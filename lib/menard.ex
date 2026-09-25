defmodule Menard do
  @moduledoc """
  Menard — Pierre Menard, author of the Quixote: rewrite a text word for word and have it come
  out different. AST-aware edits and introspection for Elixir repos (Sourceror patches: only the
  bytes a verb names move), as a project of its own so `mix menard.*` runs even while the app
  being edited does not compile.

  The tasks run from THIS project (`bin/menard VERB …` from anywhere), so a path is resolved
  against the caller's directory (`MENARD_CWD`, else the cwd), and the run verbs act in
  `--in DIR` (default: the caller's directory).
  """
  @doc "The directory the caller stood in."
  @format_timeout 30_000

  def caller_dir, do: System.get_env("MENARD_CWD") || File.cwd!()

  @doc "A path as the caller meant it: absolute stays, relative joins the caller's directory."
  def resolve(path), do: Path.expand(path, caller_dir())

  @doc """
  Format `file` with the TARGET project's formatter — its `.formatter.exs`, plugins and `import_deps` —
  while that project is as broken as it gets. Run in THIS VM through
  `Mix.Tasks.Format.formatter_for_file/2`, so the host's `mix.exs` is never evaluated and its deps
  never checked: plugins load from the host's last build (`_build/*/lib/*/ebin`), and each
  `import_deps` entry from `deps/`, else from the copy cached by the last format that found it
  (`cache:` overrides the cache directory). A dep with neither leaves the file UNformatted with the
  reason: without its exports the formatter would add parens to every DSL call in the file.

  Where Mix is not loaded (a release), it shells out to the host's `mix format` instead. Either way it
  is bounded — over stdio an unbounded wait is an MCP tool that never answers — and `{:error, reason}`
  means "written but not formatted", never "not written".
  """
  def format(file, opts \\ []) do
    content = File.read!(file)

    case format_content(file, content, opts) do
      {:ok, formatted} ->
        if formatted != content, do: File.write!(file, formatted)
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Format `content` for `file` in-memory — the host's `.formatter.exs`, plugins and `import_deps`,
  without writing to disk. Returns `{:ok, formatted}` or `{:error, reason}`. The fallback path
  (shell out to the host's `mix format`) writes to disk and reads back, since `mix format` works on
  a file path; the caller's write is then a no-op.
  """
  def format_content(file, content, opts \\ []) do
    with {:ok, formatted, _split} <- format_staged(file, content, opts), do: {:ok, formatted}
  end

  @doc """
  `format_content/3`, and where the host's `.formatter.exs` has plugins, what the formatter alone
  made of `content`: `{:ok, formatted, {plain, plugins}}`, so a caller can tell a plugin's rewrites
  (Styler's) from the formatter's. `formatted` is always the host's full formatter, so its
  `format --check-formatted` agrees. The split is `nil` with no plugins, or on the shell fallback,
  which runs both in one pass.
  """
  def format_staged(file, content, opts \\ []) do
    work = fn ->
      in_vm? =
        Code.ensure_loaded?(Mix.Tasks.Format) and
          function_exported?(Mix.Tasks.Format, :formatter_for_file, 2)

      case if(in_vm?, do: in_process(file, content, opts), else: {:fallback, "Mix is not loaded here"}) do
        {:ok, formatted, split} ->
          {:ok, formatted, split}

        {:fallback, why} ->
          File.write!(file, content)

          case shell_format(file) do
            :ok -> {:ok, File.read!(file), nil}
            {:error, shell} -> {:error, "not formatted — #{why}; #{shell}"}
          end
      end
    end

    task = Task.async(work)

    case Task.yield(task, @format_timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} ->
        result

      _timeout ->
        {:error, "format did not finish in #{div(@format_timeout, 1000)}s — file written UNFORMATTED"}
    end
  end

  defp in_process(file, content, opts) do
    root = formatter_root(file)
    project = find_up(root, "mix.exs") || root
    dot = Path.join(root, ".formatter.exs")
    dot_opts = if File.regular?(dot), do: elem(Code.eval_file(dot), 0), else: []
    plugins = dot_opts[:plugins] || []

    with {:ok, deps_paths} <-
           import_deps(dot_opts[:import_deps] || [], project, opts[:cache] || cache_dir(project)),
         :ok <- plugins_here(plugins, project) do
      forget_plugin_state(plugins)

      in_host_dir(plugins, project, fn ->
        {formatter, formatter_opts} =
          Mix.Tasks.Format.formatter_for_file(file,
            root: root,
            dot_formatter: dot,
            deps_paths: deps_paths,
            plugin_loader: & &1
          )

        split = if plugins != [], do: split(content, formatter_opts, file, plugins)
        {:ok, formatter.(content), split}
      end)
    end
  rescue
    e -> {:fallback, Exception.message(e)}
  end

  # Every plugin must load here, or none is used: without one of them the formatter writes code the
  # host's own would rewrite, a diff on lines nobody touched. Decided BEFORE Mix sees the file, since
  # it loads every plugin .formatter.exs names when it picks one by extension, whatever a
  # plugin_loader returned. The host's last build is appended, so menard's own modules win any name
  # both have.
  defp plugins_here(plugins, project) do
    for ebin <- Path.wildcard(Path.join(project, "_build/*/lib/*/ebin")),
        to_charlist(ebin) not in :code.get_path(),
        do: Code.append_path(ebin)

    case Enum.reject(plugins, &(loadable?(&1) and Code.ensure_loaded?(&1))) do
      [] -> :ok
      skipped -> {:fallback, "#{inspect(skipped)} will not load from #{project}/_build in this VM"}
    end
  end

  # A beam a newer compiler built will not load in this VM, and trying makes the VM log an error per
  # attempt. Its compile_info chunk names the compiler, and reading a chunk loads nothing.
  defp loadable?(module) do
    with path when is_list(path) <- :code.which(module),
         {:ok, {_, [compile_info: info]}} <- :beam_lib.chunks(path, [:compile_info]),
         built when is_list(built) <- info[:version] do
      Application.load(:compiler)
      vsn_parts(built) <= vsn_parts(Application.spec(:compiler, :vsn))
    else
      # loaded already, preloaded, not on the path, or unreadable: loading it is the test
      _ -> true
    end
  end

  defp vsn_parts(vsn) do
    vsn |> to_string() |> String.split(".") |> Enum.map(&(Integer.parse(&1) |> elem_or_zero()))
  end

  defp elem_or_zero({n, _rest}), do: n
  defp elem_or_zero(:error), do: 0

  defp import_deps(wanted, project, cache) do
    Enum.reduce_while(wanted, {:ok, %{}}, fn dep, {:ok, acc} ->
      real = Path.join([project, "deps", to_string(dep)])
      cached = Path.join(cache, to_string(dep))

      cond do
        File.regular?(Path.join(real, ".formatter.exs")) ->
          File.mkdir_p!(cached)
          File.cp!(Path.join(real, ".formatter.exs"), Path.join(cached, ".formatter.exs"))
          {:cont, {:ok, Map.put(acc, dep, real)}}

        File.dir?(real) ->
          {:cont, {:ok, Map.put(acc, dep, real)}}

        File.regular?(Path.join(cached, ".formatter.exs")) ->
          {:cont, {:ok, Map.put(acc, dep, cached)}}

        true ->
          {:halt,
           {:fallback, "import_deps names #{inspect(dep)}, not fetched in #{project} and never cached"}}
      end
    end)
  end

  defp cache_dir(project),
    do:
      Path.join([
        :filename.basedir(:user_cache, "menard"),
        "formatter",
        Integer.to_string(:erlang.phash2(project))
      ])

  defp shell_format(file) do
    # the host's own toolchain — a plugin built by a newer OTP loads there and not here. `loadpaths
    # --no-deps-check` first puts its last build on the path without checking deps, so the `format`
    # after it finds its plugins loaded and neither checks nor compiles anything.
    args = ["do", "loadpaths", "--no-deps-check", "+", "format", file]

    case host_mix(formatter_root(file), args) do
      {_out, 0} ->
        :ok

      {out, _status} ->
        {:error, "mix format failed: " <> (out |> String.split("\n") |> Enum.take(-3) |> Enum.join(" "))}
    end
  end

  defp formatter_root(file) do
    dir = file |> Path.expand() |> Path.dirname()
    find_up(dir, ".formatter.exs") || find_up(dir, "mix.exs") || dir
  end

  defp find_up("/", _name), do: nil

  defp find_up(dir, name) do
    if File.exists?(Path.join(dir, name)), do: dir, else: find_up(Path.dirname(dir), name)
  end

  # The formatter alone, with the host's options (import_deps' locals included), so whatever the
  # plugins changed after it is theirs to answer for. A pass that fails loses the split, not the
  # format: the plugins' changes are then billed to the formatter, as before.
  defp split(content, formatter_opts, file, plugins) do
    plain = Code.format_string!(content, Keyword.put(formatter_opts, :file, file))
    {IO.iodata_to_binary([plain, ?\n]), Enum.map(plugins, &inspect/1)}
  rescue
    _ -> nil
  end

  # :formatter is what `mix format` alone changed; :plugins, when the host has any, what they
  # (Styler) rewrote after it — so an agent can tell a rewrite it did not ask for from its own edit
  defp stages(original, patched, formatted, nil),
    do: [
      %{stage: :patch, hunks: Menard.Diff.hunks(original, patched)},
      %{stage: :formatter, hunks: Menard.Diff.hunks(patched, formatted)}
    ]

  defp stages(original, patched, formatted, {plain, plugins}) do
    [
      %{stage: :patch, hunks: Menard.Diff.hunks(original, patched)},
      %{stage: :formatter, hunks: Menard.Diff.hunks(patched, plain)},
      %{stage: :plugins, plugins: plugins, hunks: Menard.Diff.hunks(plain, formatted)}
    ]
  end

  defp checked(file, content) do
    case Menard.Write.checked(file, content) do
      {:ok, patched} -> {:ok, patched}
      {:error, reason} -> {:error, "refusing to write #{Path.relative_to_cwd(file)} — #{reason}"}
    end
  end

  # An edit computed against a version the file no longer has would overwrite whatever changed it
  # since, so a version given is a version checked (docs/live.md, phase 3). The refusal carries
  # what changed, when menard still has the version it handed out, so the agent can re-sync.
  defp fresh(file, original, opts) do
    expected = opts[:version]
    current = version_of(original)

    if is_nil(expected) or opts[:force] == true or expected == current do
      :ok
    else
      since =
        case File.read(version_path(expected)) do
          {:ok, old} -> "changed since: " <> JSON.encode!(Menard.Diff.hunks(old, original))
          {:error, _} -> "menard has no copy of #{expected} to diff against"
        end

      {:error,
       "stale: #{Path.relative_to_cwd(file)} is no longer #{expected} but #{current}; #{since}. " <>
         "Re-read it and redo the edit, or pass force to write anyway"}
    end
  end

  defp version_of(content), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, content), case: :lower)

  # Every version handed out is kept, so a stale edit can be answered with the diff since it. A
  # week is longer than any session holds a version; older copies go when the next one is kept.
  @doc """
  The version of `content` (`sha256:` + hex), with a copy kept, so a stale edit made against it
  can be answered with the diff since. What every writing verb and `outline` hand out.
  """
  def remember(content) do
    version = version_of(content)
    path = version_path(version)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, content)
    week_ago = System.os_time(:second) - 7 * 24 * 3600

    for old <- Path.wildcard(Path.join(Path.dirname(path), "*")),
        File.stat!(old, time: :posix).mtime < week_ago,
        do: File.rm(old)

    version
  end

  defp version_path(version) do
    hex = version |> String.replace_prefix("sha256:", "") |> Path.basename()
    Path.join([:filename.basedir(:user_cache, "menard"), "versions", hex])
  end

  # Quokka and Styler keep their config in :persistent_term under their own modules and read it only
  # when it is unset, which in one VM is once: the MCP server formatted every host with the first
  # host's config. What a host's plugins cached is forgotten before each format.
  defp forget_plugin_state(plugins) do
    prefixes = Enum.map(plugins, &(inspect(&1) <> "."))

    for {key, _value} <- :persistent_term.get(),
        is_atom(key),
        name = inspect(key),
        Enum.any?(prefixes, &String.starts_with?(name, &1)),
        do: :persistent_term.erase(key)
  end

  # From the host's directory, as its own `mix format` runs: Quokka reads .credo.exs from the cwd,
  # and from menard's it found none and rewrapped whole files at its default line length. Only a
  # plugin reads the cwd, so only then; and the cwd is the whole VM's, so one format at a time.
  defp in_host_dir([], _project, fun), do: fun.()

  defp in_host_dir(_plugins, project, fun),
    do: :global.trans({{__MODULE__, :cwd}, self()}, fn -> File.cd!(project, fun) end, [node()], :infinity)

  @doc """
  Write `content` to `file` through the staged pipeline: parse-check, format in-memory, diff each
  stage, write the result. Returns `{:ok, reply}` where reply is `%{did, file, version, stages}` —
  the LiveView reply (docs/live.md). `stages` has `:patch` (what the verb changed) and `:formatter`
  (what `mix format` changed after it), each as a list of `%{start, removed, added}` hunks.

  `did` is a human-readable one-liner (`opts[:did]`), `version` is `sha256:` + the hex digest of the
  file after every stage. A format failure is NOT a write failure: the bytes are on disk and
  correct, just not reformatted — the reason goes to stderr and the `:formatter` stage is empty.
  """
  @spec write(String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, String.t()}
  def write(file, content, opts \\ []) do
    did = opts[:did] || "edit #{Path.relative_to_cwd(file)}"
    original = if File.regular?(file), do: File.read!(file), else: ""

    with :ok <- fresh(file, original, opts),
         {:ok, patched} <- checked(file, content) do
      {formatted, split, format_error} =
        case format_staged(file, patched) do
          {:ok, f, split} -> {f, split, nil}
          {:error, reason} -> {patched, nil, reason}
        end

      File.write!(file, formatted)

      if format_error, do: Mix.shell().error("menard: " <> format_error)

      version = remember(formatted)
      {:ok, %{did: did, file: file, version: version, stages: stages(original, patched, formatted, split)}}
    end
  end

  @doc """
  Write `content` to `file`, but only if it still parses as Elixir, then format it. The thin
  wrapper over `write/3` for callers that don't need the reply yet. Every edit verb goes through
  here: an AST patch that lands unparseable bytes locks the file out of every other verb.
  """
  @spec checked_write(String.t(), String.t()) :: :ok | {:error, String.t()}
  def checked_write(file, content) do
    case write(file, content) do
      {:ok, _reply} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  The HOST project's `mix`, run in `dir` on the host's own toolchain. menard's toolchain is first on
  its PATH, so a bare `mix` built the host with the wrong Elixir: every dep rebuilt, and nothing the
  host's toolchain built would load. With mise installed, `mise exec` picks the host's pins.
  """
  def host_mix(dir, args, opts \\ []) do
    opts = Keyword.merge([cd: dir, stderr_to_stdout: true], opts)

    case host_toolchain(dir) do
      {:mise, mise} ->
        System.cmd(mise, ["exec", "-C", dir, "--", "mix" | args], opts)

      {:path, nil} ->
        System.cmd("mix", args, opts)

      {:path, why} ->
        {out, status} = System.cmd("mix", args, opts)
        {"menard: #{why}\n" <> out, status}
    end
  end

  # `mise exec` installs a pinned tool that is missing, and for Erlang that is a source build: minutes
  # of kerl, which fail on a machine without its build deps, before the verb answered ok:false with no
  # reason. MISE_EXEC_AUTO_INSTALL=false did not stop it (mise 2026.8). So ask first: a host that pins
  # a toolchain that is not installed gets the mix on PATH, and is told why.
  defp host_toolchain(dir) do
    with mise when is_binary(mise) <- System.find_executable("mise"),
         {out, 0} <- System.cmd(mise, ["ls", "--current", "--missing", "-C", dir], stderr_to_stdout: true) do
      missing =
        for line <- String.split(out, "\n"),
            [tool, version | _] <- [String.split(line)],
            tool in ["erlang", "elixir"],
            do: "#{tool} #{version}"

      if missing == [],
        do: {:mise, mise},
        else: {:path, "#{Enum.join(missing, ", ")} pinned here is not installed, so this ran the mix on PATH"}
    else
      nil -> {:path, nil}
      # mise could not say: let `exec` decide, as before
      _ -> {:mise, System.find_executable("mise")}
    end
  end

  @doc """
  `term` as JSON can carry it. JSON has no tuple, and the library answers with them (`lines: {3, 9}`):
  encoding one crashed the MCP tool call and `outline --json` alike.

      iex> Menard.jsonable(%{module: "A", lines: {1, 3}, defs: [%{lines: {2, 2}}]})
      %{module: "A", lines: [1, 3], defs: [%{lines: [2, 2]}]}
  """
  def jsonable(%{__struct__: _} = struct), do: struct
  def jsonable(map) when is_map(map), do: Map.new(map, fn {k, v} -> {k, jsonable(v)} end)
  def jsonable(list) when is_list(list), do: Enum.map(list, &jsonable/1)
  def jsonable(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> jsonable()
  def jsonable(other), do: other
end
