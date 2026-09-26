defmodule Menard.Format do
  @moduledoc """
  The HOST project's formatter — its `.formatter.exs`, plugins and `import_deps` — run as an OS
  process on the host's own toolchain (`priv/format.exs`), never in menard's VM: a host's beams
  built by another OTP, a plugin's `:persistent_term` config, a plugin reading its config from the
  cwd, all stay in the host's own process, which lives for one call.

  It works while the host is as broken as it gets: `elixir`, not `mix format`, so the host's
  `mix.exs` is never evaluated and its config never loaded. Plugins load from the host's last build
  (`_build/*/lib/*/ebin`), and each `import_deps` entry from `deps/`, else from the copy cached by
  the last format that found it (`cache:` overrides the cache directory). A dep with neither leaves
  the file UNformatted with Mix's own reason: without its exports the formatter would add parens to
  every DSL call in the file.

  Every call is bounded (over stdio an unbounded wait is an MCP tool that never answers), and past
  its deadline the host's process is killed, not abandoned: it never writes the real file, so
  nothing it did can land after menard handed out its version. `{:error, reason}` means "written
  but not formatted", never "not written".
  """

  # Under load a host's own toolchain through mise took past 30s; 60s still leaves the MCP door's
  # 90s deadline room
  @timeout 60_000

  @doc "Format `file` in place. `:ok`, or `{:error, reason}` with the file left as it was."
  @spec file(String.t(), keyword()) :: :ok | {:error, String.t()}
  def file(file, opts \\ []) do
    [{^file, result}] = files([file], opts)
    result
  end

  @doc """
  Format `files` in place, every file of one formatter root by one host process: `[{file, :ok |
  {:error, reason}}]` in the order given.
  """
  @spec files([String.t()], keyword()) :: [{String.t(), :ok | {:error, String.t()}}]
  def files(files, opts \\ []) do
    pairs = Enum.map(files, &{&1, File.read!(&1)})
    results = run(pairs, opts)
    for {file, content} <- pairs, do: {file, written(file, content, results[file])}
  end

  defp written(_file, _content, {:error, reason}), do: {:error, reason}

  defp written(file, content, {:ok, formatted, _split}) do
    if formatted != content, do: File.write!(file, formatted)
    :ok
  end

  @doc """
  Format `content` for `file` without touching disk, and where the host's `.formatter.exs` has
  plugins, what the formatter alone made of it: `{:ok, formatted, {plain, plugins}}`, so a caller
  can tell a plugin's rewrites (Styler's) from the formatter's. `formatted` is always the host's
  full formatter, so its `format --check-formatted` agrees. The split is `nil` with no plugins.
  """
  @spec staged(String.t(), String.t(), keyword()) ::
          {:ok, String.t(), {String.t(), [String.t()]} | nil} | {:error, String.t()}
  def staged(file, content, opts \\ []) do
    %{^file => result} = run([{file, content}], opts)
    result
  end

  @doc """
  The files among `files` that are formatted already by their project's formatter with the plugins
  left out: the check for a file `files/2` could not format (a plugin the host never built), where
  it is checked instead of refused. Nothing is written; a file whose check fails is not formatted.
  """
  @spec formatted_without_plugins([String.t()]) :: [String.t()]
  def formatted_without_plugins(files) do
    pairs = Enum.map(files, &{&1, File.read!(&1)})
    results = run(pairs, plugins: false)
    for {file, content} <- pairs, match?({:ok, ^content, _}, results[file]), do: file
  end

  # `{file, content}` pairs to results, one host process per formatter root
  defp run(pairs, opts) do
    pairs
    |> Enum.group_by(fn {file, _content} -> root(file) end)
    |> Enum.flat_map(fn {root, pairs} -> Map.to_list(run_in(root, pairs, opts)) end)
    |> Map.new()
  end

  defp run_in(root, pairs, opts) do
    project = find_up(root, "mix.exs") || root
    ms = opts[:timeout] || @timeout
    dir = Path.join(System.tmp_dir!(), "menard-format-#{System.pid()}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    input = Path.join(dir, "in")
    output = Path.join(dir, "out")

    File.write!(
      input,
      :erlang.term_to_binary(%{
        root: root,
        project: project,
        cache: opts[:cache] || cache_dir(project),
        plugins: Keyword.get(opts, :plugins, true),
        files: pairs
      })
    )

    script = Application.app_dir(:menard, "priv/format.exs")

    {out, status} =
      Menard.host_cmd(project, ["elixir", script, input, output], timeout: ms, label: "the host's formatter")

    try do
      cond do
        status in [124, 137] ->
          secs = max(div(ms + 500, 1000), 1)

          all(
            pairs,
            {:error, "format did not finish in #{secs}s, and was stopped — file written UNFORMATTED"}
          )

        File.regular?(output) ->
          output |> File.read!() |> :erlang.binary_to_term()

        true ->
          all(pairs, {:error, "the host's formatter failed: " <> said(out)})
      end
    after
      File.rm_rf!(dir)
    end
  end

  defp all(pairs, result), do: Map.new(pairs, fn {file, _content} -> {file, result} end)

  # the last lines that say why: mise ends every refusal (an untrusted config) with its version
  # and a pointer to --verbose, which were all the reply kept
  defp said(out) do
    out
    |> String.split("\n")
    |> Enum.reject(&(String.trim(&1) == "" or &1 =~ ~r/^mise ERROR (Version:|Run with --verbose)/))
    |> Enum.take(-3)
    |> Enum.join(" ")
  end

  defp cache_dir(project),
    do: Path.join([Menard.cache_dir(), "formatter", Integer.to_string(:erlang.phash2(project))])

  defp root(file) do
    dir = file |> Path.expand() |> Path.dirname()
    find_up(dir, ".formatter.exs") || find_up(dir, "mix.exs") || dir
  end

  defp find_up("/", _name), do: nil

  defp find_up(dir, name) do
    if File.exists?(Path.join(dir, name)), do: dir, else: find_up(Path.dirname(dir), name)
  end
end
