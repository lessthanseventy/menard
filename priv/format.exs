# The HOST's formatter, run on the host's own toolchain as an OS process (`elixir THIS IN OUT`):
# its `.formatter.exs`, its plugins from its last build in `_build`, its `import_deps` from `deps/`
# or from the copy cached by the last format that found them. Never `mix format`: mix evaluates
# `mix.exs` and the config first, and a host whose `mix.exs` does not parse, whose deps are not
# fetched or whose config wants an env var is the host menard must still format. It runs on
# whatever Elixir the host pins, so nothing here is newer than what 1.18 has (`:deps_paths` and
# `:plugin_loader` on `formatter_for_file/2`).
#
# IN is `term_to_binary` of `%{root, project, cache, plugins, files: [{path, content}]}`; OUT is
# written as `%{path => {:ok, formatted, split} | {:error, reason}}`, where `split` is
# `{formatter_alone, plugin_names}` when the file's formatter has plugins, else nil. The real files
# are never touched: a caller killed past its deadline has nothing to fear from this process
# finishing later.
#
# `elixir THIS serve` is the same formatter kept warm (`Menard.Format.Worker`): a request per
# 4-byte-framed message on fd 3, its results on fd 4, until the caller closes them. The host's VM
# takes 0.4s to start, which a session paid on every write. stdout is not the channel: a plugin
# may print.

Mix.start()
# The deadline's TERM ends this process at once. The VM's own handler is `init:stop`, an orderly
# shutdown a plugin mid-format can hold up, and the caller has already answered "unformatted".
:os.set_signal(:sigterm, :default)

format = fn %{root: root, project: project, cache: cache, plugins: plugins?, files: files} ->
  # The host's last build, whatever env built it: a plugin lives in `_build/*/lib/*/ebin`. Left off
  # the path when the caller asks for no plugins, so a plugin that is there is not found either.
  if plugins? do
    for ebin <- Path.wildcard(Path.join(project, "_build/*/lib/*/ebin")), do: Code.append_path(ebin)
  end

  # every dep fetched, whatever any `.formatter.exs` here imports (a subdirectory's own too), and
  # behind them the cache: each dep's `.formatter.exs` as the last format found it, for a host whose
  # deps are gone. A dep with neither is Mix's own "Unknown dependency" refusal.
  fetched =
    for dir <- Path.wildcard(Path.join(project, "deps/*")),
        File.dir?(dir),
        dot = Path.join(dir, ".formatter.exs"),
        File.regular?(dot),
        dep = Path.basename(dir),
        kept = Path.join([cache, dep, ".formatter.exs"]),
        into: %{} do
      if not File.regular?(kept) or File.read!(kept) != File.read!(dot) do
        File.mkdir_p!(Path.dirname(kept))
        File.cp!(dot, kept)
      end

      {String.to_atom(dep), dir}
    end

  cached =
    for dir <- Path.wildcard(Path.join(cache, "*")),
        File.regular?(Path.join(dir, ".formatter.exs")),
        into: %{},
        do: {String.to_atom(Path.basename(dir)), dir}

  deps_paths = Map.merge(cached, fetched)
  dot = Path.join(root, ".formatter.exs")
  dot = if File.regular?(dot), do: dot

  # A caller that asked for no plugins gets none: the loader answers with an empty list, and with
  # `_build` off the path no plugin can be found by extension either.
  loader = if plugins?, do: & &1, else: fn _plugins -> [] end

  for {path, content} <- files, into: %{} do
    result =
      try do
        opts = [root: root, deps_paths: deps_paths, plugin_loader: loader]
        opts = if dot, do: [{:dot_formatter, dot} | opts], else: opts
        {formatter, formatter_opts} = Mix.Tasks.Format.formatter_for_file(path, opts)
        formatted = formatter.(content)

        # The formatter alone, with the host's options, so what the plugins changed after it is
        # theirs to answer for. A pass that fails (a .heex file) loses the split, not the format.
        split =
          case formatter_opts[:plugins] do
            plugins when plugins? and is_list(plugins) and plugins != [] ->
              try do
                plain = Code.format_string!(content, Keyword.put(formatter_opts, :file, path))
                {IO.iodata_to_binary([plain, ?\n]), Enum.map(plugins, &inspect/1)}
              rescue
                _ -> nil
              end

            _ ->
              nil
          end

        {:ok, formatted, split}
      rescue
        e -> {:error, Exception.message(e)}
      catch
        kind, reason -> {:error, Exception.format_banner(kind, reason)}
      end

    {path, result}
  end
end

case System.argv() do
  [input, output] ->
    results = input |> File.read!() |> :erlang.binary_to_term() |> format.()
    # written whole, then named: a reader never sees half a result
    File.write!(output <> ".part", :erlang.term_to_binary(results))
    File.rename!(output <> ".part", output)

  ["serve"] ->
    port = :erlang.open_port({:fd, 3, 4}, [:binary, :eof, {:packet, 4}])
    # the VM's own pid, first: what the caller kills at a deadline (mise does not exec into it)
    Port.command(port, :erlang.term_to_binary({:pid, System.pid()}))

    serve = fn serve ->
      receive do
        {^port, {:data, request}} ->
          Port.command(port, :erlang.term_to_binary(format.(:erlang.binary_to_term(request))))
          serve.(serve)

        # the caller is gone, or closed the worker
        {^port, :eof} ->
          :ok
      end
    end

    serve.(serve)
end
