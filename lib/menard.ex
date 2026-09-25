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
    work = fn ->
      in_vm? =
        Code.ensure_loaded?(Mix.Tasks.Format) and function_exported?(Mix.Tasks.Format, :formatter_for_file, 2)

      case if(in_vm?, do: in_process(file, opts), else: {:fallback, "Mix is not loaded here"}) do
        {:fallback, why} ->
          case shell_format(file) do
            :ok -> :ok
            {:error, shell} -> {:error, "not formatted — #{why}; #{shell}"}
          end

        result ->
          result
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

  defp in_process(file, opts) do
    root = formatter_root(file)
    project = find_up(root, "mix.exs") || root
    dot = Path.join(root, ".formatter.exs")

    with {:ok, deps_paths} <- import_deps(dot, project, opts[:cache] || cache_dir(project)) do
      {formatter, _opts} =
        Mix.Tasks.Format.formatter_for_file(file,
          root: root,
          dot_formatter: dot,
          deps_paths: deps_paths,
          plugin_loader: &load_plugins(&1, project)
        )

      content = File.read!(file)
      formatted = formatter.(content)

      # without one of its plugins the formatter writes code the host's own would rewrite — a diff
      # on lines nobody touched — so a missing plugin means not here, never "format without it"
      case Process.get(:menard_skipped_plugins, []) do
        [] ->
          if formatted != content, do: File.write!(file, formatted)
          :ok

        skipped ->
          {:fallback, "#{inspect(skipped)} will not load from #{project}/_build in this VM"}
      end
    end
  rescue
    e -> {:fallback, Exception.message(e)}
  end

  # The host's last build: appended, so menard's own modules win any name both have.
  defp load_plugins(plugins, project) do
    for ebin <- Path.wildcard(Path.join(project, "_build/*/lib/*/ebin")),
        to_charlist(ebin) not in :code.get_path(),
        do: Code.append_path(ebin)

    {loaded, skipped} = Enum.split_with(plugins, &Code.ensure_loaded?/1)
    Process.put(:menard_skipped_plugins, skipped)
    loaded
  end

  defp import_deps(dot, project, cache) do
    wanted = if File.regular?(dot), do: Keyword.get(elem(Code.eval_file(dot), 0), :import_deps, []), else: []

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

  @doc """
  Write `content` to `file`, but only if it still parses as Elixir, then format it. Every edit verb
  goes through here: an AST patch that lands unparseable bytes locks the file out of every other
  verb, and text editing is then the only door back.
  """
  @spec checked_write(String.t(), String.t()) :: :ok | {:error, String.t()}
  def checked_write(file, content) do
    case Menard.Write.checked(file, content) do
      {:ok, checked} ->
        File.write!(file, checked)
        # A format timeout is NOT a write failure: the bytes are on disk and correct, just not
        # reformatted. Say so rather than failing an edit that actually landed.
        case format(file) do
          :ok -> :ok
          {:error, reason} -> Mix.shell().error("menard: " <> reason)
        end

        :ok

      {:error, reason} ->
        {:error, "refusing to write #{Path.relative_to_cwd(file)} — #{reason}"}
    end
  end

  @doc """
  The HOST project's `mix`, run in `dir` on the host's own toolchain. menard's toolchain is first on
  its PATH, so a bare `mix` built the host with the wrong Elixir: every dep rebuilt, and nothing the
  host's toolchain built would load. With mise installed, `mise exec` picks the host's pins.
  """
  def host_mix(dir, args, opts \\ []) do
    opts = Keyword.merge([cd: dir, stderr_to_stdout: true], opts)

    case System.find_executable("mise") do
      nil -> System.cmd("mix", args, opts)
      mise -> System.cmd(mise, ["exec", "-C", dir, "--", "mix" | args], opts)
    end
  end
end
