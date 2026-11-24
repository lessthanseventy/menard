defmodule Menard.Format do
  @moduledoc """
  The HOST project's formatter — its `.formatter.exs`, plugins and `import_deps` — run as an OS
  process on the host's own toolchain (`priv/format.exs`), never in menard's VM: a host's beams
  built by another OTP, a plugin's `:persistent_term` config, a plugin reading its config from the
  cwd, all stay in the host's own process, which lives for one call.

  It works while the host is as broken as it gets: `elixir`, not `mix format`, so the host's
  `mix.exs` is never evaluated and its config never loaded. Plugins load from the host's last build
  (`_build/*/lib/*/ebin`), and each `import_deps` entry from `deps/`, else from the copy cached by
  the last format that found it (`cache:` overrides the cache directory), else, in a git worktree
  with no `deps/`, from the main checkout's (as are plugins its `_build` lacks). A dep with none of them leaves
  the file UNformatted with Mix's own reason: without its exports the formatter would add parens to
  every DSL call in the file.

  Every call is bounded (over stdio an unbounded wait is an MCP tool that never answers), and past
  its deadline the host's process is killed, not abandoned: it never writes the real file, so
  nothing it did can land after menard handed out its version. `{:error, reason}` means "written
  but not formatted", never "not written".
  """

  alias Menard.Format.Worker
  # Under load a host's own toolchain through mise takes past 30s; 60s still leaves the MCP door's
  # 90s deadline room
  @timeout 60_000
  @not_taken "no project's .formatter.exs takes this file"

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

  @doc """
  Format `content` for `file` without touching disk, and where the host's `.formatter.exs` has
  plugins, what the formatter alone made of it: `{:ok, formatted, {plain, plugins}}`, so a caller
  can tell a plugin's rewrites (Styler's) from the formatter's. `formatted` is always the host's
  full formatter, so its `format --check-formatted` agrees. The split is `nil` with no plugins.
  """
  @spec staged(String.t(), String.t(), keyword()) ::
          {:ok, String.t(), {String.t(), [String.t()]} | nil} | {:error, String.t()}
  def staged(file, content, opts \\ []) do
    if Menard.Lang.known?(file, content) do
      {:ok, Menard.Lang.format(file, content), nil}
    else
      %{^file => result} = run([{file, content}], opts)
      result
    end
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

  @doc """
  Whether the project's own `mix format` takes `file`: it is among the `.formatter.exs` inputs of
  the nearest mix project above it, or that project has no `.formatter.exs` to go by. A file with
  no mix project above it is no project's to format. `{:error, why}` is why not, a
  `.formatter.exs` that does not evaluate with the error it raised.
  """
  @spec taken(String.t()) :: :ok | {:error, String.t()}
  def taken(file) do
    file = Path.expand(file)
    project = find_up(Path.dirname(file), "mix.exs")

    cond do
      project == nil -> {:error, @not_taken}
      not File.regular?(Path.join(project, ".formatter.exs")) -> :ok
      true -> among(Menard.Run.formatter_takes(project, file))
    end
  end

  defp among({:error, why}), do: {:error, "its project's .formatter.exs does not evaluate (#{why})"}
  defp among({:ok, true}), do: :ok
  defp among({:ok, false}), do: {:error, @not_taken}

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

    request = %{
      root: root,
      project: project,
      cache: opts[:cache] || cache_dir(project),
      behind: main_checkout_deps(project),
      built_behind: main_checkout_build(project),
      plugins: Keyword.get(opts, :plugins, true),
      files: pairs
    }

    case warm(request, ms, Keyword.get(opts, :warm, true)) do
      {:ok, results} -> results
      :timeout -> all(pairs, stopped(ms))
      {:error, out} -> all(pairs, {:error, "the host's formatter failed: " <> said(out)})
      :unavailable -> once(project, request, ms)
    end
  end

  # the warm worker holds the host's plugins on its path, so a format without them is a process of
  # its own, as is every format where nothing supervises a worker (`warm: false` asks for that)
  defp warm(%{plugins: true, project: project} = request, ms, true), do: Worker.format(project, request, ms)
  defp warm(_request, _ms, _warm), do: :unavailable

  defp once(project, %{files: pairs} = request, ms) do
    dir = Path.join(System.tmp_dir!(), "menard-format-#{System.pid()}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    input = Path.join(dir, "in")
    output = Path.join(dir, "out")
    File.write!(input, :erlang.term_to_binary(request))
    script = Application.app_dir(:menard, "priv/format.exs")

    {out, status} =
      Menard.host_cmd(project, ["elixir", script, input, output], timeout: ms, label: "the host's formatter")

    try do
      cond do
        status in [124, 137] -> all(pairs, stopped(ms))
        File.regular?(output) -> output |> File.read!() |> :erlang.binary_to_term()
        true -> all(pairs, {:error, "the host's formatter failed: " <> said(out)})
      end
    after
      File.rm_rf!(dir)
    end
  end

  defp stopped(ms) do
    secs = max(div(ms + 500, 1000), 1)
    {:error, "format did not finish in #{secs}s, and was stopped — file written UNFORMATTED"}
  end

  defp all(pairs, result), do: Map.new(pairs, fn {file, _content} -> {file, result} end)

  # the lines that say why: mise ends every refusal with its version and a pointer to --verbose,
  # which were all the reply kept, and draws the file under a parse error's `×` line
  defp said(out) do
    lines =
      out
      # uncoloured: under the gate mise coloured its `×` line, and nothing matched it
      |> String.replace(~r/\e\[[0-9;]*m/, "")
      |> String.split("\n")
      |> Enum.reject(&(String.trim(&1) == "" or &1 =~ ~r/^mise ERROR (Version:|Run with --verbose)/))

    case Enum.filter(lines, &(&1 =~ ~r/^\s*(×|mise ERROR)/)) do
      [] -> lines |> Enum.take(-3) |> Enum.join(" ")
      why -> Enum.map_join(why, " ", &String.trim/1)
    end
  end

  defp cache_dir(project),
    do: Path.join([Menard.cache_dir(), "formatter", Integer.to_string(:erlang.phash2(project))])

  # `deps/` of the same project in the main checkout, where `project` is in a linked git worktree
  # and has no `deps/` of its own: a new worktree is written to before anything fetches its deps
  defp main_checkout_deps(project) do
    with false <- File.dir?(Path.join(project, "deps")),
         main when main != nil <- main_checkout(project),
         deps = Path.join(main, "deps"),
         true <- File.dir?(deps) do
      deps
    else
      _ -> nil
    end
  end

  # `_build/` of the same project in the main checkout, behind the worktree's own: a plugin the
  # worktree has not built yet is the main checkout's last build of it
  defp main_checkout_build(project) do
    with main when main != nil <- main_checkout(project),
         build = Path.join(main, "_build"),
         true <- File.dir?(build) do
      build
    else
      _ -> nil
    end
  end

  defp main_checkout(project) do
    with {out, 0} <-
           System.cmd("git", ~w(rev-parse --path-format=absolute --git-common-dir --show-toplevel),
             cd: project,
             stderr_to_stdout: true
           ),
         [common, top] <- String.split(out, "\n", trim: true),
         main = Path.dirname(common),
         true <- Path.basename(common) == ".git" and main != top do
      Path.join(main, Path.relative_to(project, top))
    else
      _ -> nil
    end
  end

  defp root(file) do
    dir = file |> Path.expand() |> Path.dirname()
    find_up(dir, ".formatter.exs") || find_up(dir, "mix.exs") || dir
  end

  defp find_up("/", _name), do: nil

  defp find_up(dir, name) do
    if File.exists?(Path.join(dir, name)), do: dir, else: find_up(Path.dirname(dir), name)
  end

  defp written(_file, _content, {:error, reason}), do: {:error, reason}

  defp written(file, content, {:ok, formatted, _split}) do
    if formatted != content, do: File.write!(file, formatted)
    :ok
  end
end
