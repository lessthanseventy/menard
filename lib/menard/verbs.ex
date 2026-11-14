defmodule Menard.Verbs do
  @moduledoc """
  The one verb layer both doors call. Every noun has a `Menard.Verbs.<Noun>.run/1`: a params map
  in — the fields as the MCP schema names them (`verb`, `file`, `name_arity`, …), string values,
  atom keys — and `{:ok, reply} | {:error, reason}` out, `reply` the one JSON-able map a caller
  sees and `reason` a string. A verb owns resolve → read → change → `Menard.write/3` → the `did`
  text → the reply, and the check that the fields it cannot do without are there. A door (a mix
  task, an MCP tool) only turns its input into the params and the result into its own answer:
  the CLI prints the reply as one JSON line and raises the reason, the MCP tool returns each.

  `root` in the params is the MCP door's launch directory: a path resolves under it, or in another
  git checkout under the user's home (`home`, else `System.user_home/0`), and any other is refused.
  Without it a path resolves against the caller's directory, as the CLI means it.
  """

  alias Menard.Run.Lint
  alias Menard.Verbs.Noun
  alias Menard.Verbs.Run
  @type params :: %{optional(atom()) => term()}
  @type result :: {:ok, map()} | {:error, String.t()}

  @doc """
  A path as the door meant it: under `params[:root]`, as written and as the OS follows it (a
  symlink under the root that points outside it passed the first test alone), or in another git
  checkout under the user's home; against the caller's directory when no root is given.
  """
  @spec resolve(String.t(), params()) :: {:ok, String.t()} | {:error, String.t()}
  def resolve(path, params) do
    case params[:root] do
      nil -> {:ok, Menard.resolve(path)}
      root -> resolve_under(path, Path.expand(root), real(Path.expand(root)), home(params))
    end
  end

  @doc """
  Every path resolved, or the first refusal, so no verb edits some of its files. A glob
  (`lib/**/*.ex`) is expanded — agents pass them, and no shell is there to expand them; one that
  matches nothing beside others that do is dropped, and only an empty whole is refused.
  """
  @spec resolve_all([String.t()], params()) :: {:ok, [String.t()]} | {:error, String.t()}
  def resolve_all(paths, params) do
    base = if root = params[:root], do: Path.expand(root), else: Menard.caller_dir()
    glob? = &String.contains?(&1, ["*", "?", "[", "{"])

    expanded =
      Enum.flat_map(paths, fn p ->
        if glob?.(p), do: Path.wildcard(Path.expand(p, base)), else: [p]
      end)

    case expanded do
      [] -> {:error, "no file matches #{paths |> Enum.filter(glob?) |> Enum.join(", ")}"}
      _ -> resolve_each(expanded, params[:root], params)
    end
  end

  @doc """
  The fields a verb cannot do without, where the schema leaves them optional for the noun's other
  verbs: a path left out was `params[:to] || ""`, which resolved to the root directory itself.
  """
  @spec need(params(), [atom()], String.t()) :: :ok | {:error, String.t()}
  def need(params, keys, what) do
    case for(key <- keys, params[key] in [nil, ""], do: key) do
      [] -> :ok
      missing -> {:error, "#{what} needs #{Enum.join(missing, ", ")}"}
    end
  end

  @doc "The file's content, or why it could not be read — a door never sees a File.Error."
  @spec read(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def read(file) do
    case File.read(file) do
      {:ok, source} -> {:ok, source}
      {:error, reason} -> {:error, "cannot read #{file}: #{:file.format_error(reason)}"}
    end
  end

  @doc """
  A verb as both doors run it: the noun's `run`, and then, when the params ask, a `run` verb after
  it (`test`, `check`, `compile`), its answer in the reply's `run`. Every writing verb takes `then`
  (`Menard.Verbs.Noun.of/1`), not `edit` alone: a test added with `block add` was run by a second
  call, as an edit's need not be.
  """
  @spec call(module(), params()) :: result()
  def call(verbs, %{then: then} = params) when is_binary(then) and then != "" do
    # `test FILE…`: the test files to run, where a change's tests are not its files' mirror (a
    # formatter in priv/, its tests in run_test.exs): named, they were run by a second call
    case String.split(then) do
      [verb | _] when verb not in ["test", "check", "compile"] ->
        {:error, "no then #{inspect(verb)}: one of #{Enum.join(Noun.thens(), ", ")}"}

      [verb, _ | _] when verb != "test" ->
        {:error, "then #{verb} takes no files: only test takes files"}

      [verb | files] ->
        with {:ok, reply} <- verbs.run(params),
             do: {:ok, reply |> then_run(params, verb, files) |> credo(params) |> from_root(params)}
    end
  end

  def call(verbs, params), do: with({:ok, reply} <- verbs.run(params), do: {:ok, from_root(reply, params)})

  @doc """
  The pipeline every writing verb is: `params.file` resolved and read, `change.(source)` (the new
  source, or `{:error, reason}`), written through `Menard.write/3` under the `version` and `force`
  the params carry, and the staged reply, its `did` from `did.(file)`.
  """
  @spec edit(params(), (String.t() -> String.t()), (String.t() -> String.t() | {:error, String.t()})) ::
          result()
  def edit(params, did, change) do
    with {:ok, file} <- resolve(params.file, params),
         {:ok, source} <- read(file),
         out when is_binary(out) <- change.(source) do
      Menard.write(file, out, [did: did.(Path.basename(file))] ++ stale(params))
    end
  end

  @doc "The `version` and `force` a writing verb hands `Menard.write/3`, from the params."
  @spec stale(params()) :: keyword()
  def stale(params), do: [version: params[:version], force: params[:force] == true]

  @doc "The `nth` option, when the params pick one of two clauses that share a head."
  @spec nth(params()) :: keyword()
  def nth(params), do: if(n = params[:nth], do: [nth: n], else: [])

  @doc "`\"-\"` or an empty module name means the file's one module: nothing to name."
  @spec module(String.t() | nil) :: String.t() | nil
  def module(m) when m in [nil, "-", ""], do: nil
  def module(m), do: m

  @doc "`path` with every symlink in it followed, as far as it exists: macOS's /var is /private/var."
  @spec real_path(String.t()) :: String.t()
  def real_path(path), do: real(Path.expand(path))

  # the root's own real path once, not per file: resolving 20,000 paths is a rename's first step
  defp resolve_each(paths, nil, _params), do: {:ok, Enum.map(paths, &Menard.resolve/1)}

  defp resolve_each(paths, root, params) do
    root = Path.expand(root)
    real_root = real(root)
    home = home(params)

    resolved =
      Enum.reduce_while(paths, {:ok, []}, fn p, {:ok, acc} ->
        case resolve_under(p, root, real_root, home) do
          {:ok, abs} -> {:cont, {:ok, [abs | acc]}}
          {:error, _} = refused -> {:halt, refused}
        end
      end)

    with {:ok, reversed} <- resolved, do: {:ok, Enum.reverse(reversed)}
  end

  defp resolve_under(path, root, real_root, home) do
    abs = Path.expand(path, root)

    cond do
      under?(abs, root) and under?(real_below(abs, root, real_root), real_root) -> {:ok, abs}
      in_a_checkout?(real(abs), home) -> {:ok, abs}
      in_the_scratchpad?(real(abs)) -> {:ok, abs}
      true -> {:error, "refused: #{path} is outside #{root}, and in no git checkout under the user's home"}
    end
  end

  defp home(params) do
    case params[:home] || System.user_home() do
      home when is_binary(home) -> real(Path.expand(home))
      nil -> nil
    end
  end

  # A sibling repo is the session's too: a file, as the OS follows it, in a git checkout under the
  # home. Not the home's own repo (dotfiles), one under a dot-directory of it (~/.claude, ~/.ssh), or
  # a checkout's .git.
  defp in_a_checkout?(_real, nil), do: false

  defp in_a_checkout?(real, home) do
    with true <- under?(real, home) and real != home,
         [top | _] <- Path.split(Path.relative_to(real, home)),
         false <- String.starts_with?(top, "."),
         repo when is_binary(repo) <- checkout(real, home) do
      ".git" not in Path.split(Path.relative_to(real, repo))
    else
      _ -> false
    end
  end

  # Claude Code's scratchpad is under /tmp/claude-UID, made by the harness for that user alone: the
  # name's UID owns it and this process may write it, so it is not another user's.
  defp in_the_scratchpad?(real) do
    tmp = real("/tmp")

    with true <- under?(real, tmp) and real != tmp,
         [top, _ | _] <- Path.split(Path.relative_to(real, tmp)),
         "claude-" <> uid <- top,
         {uid, ""} <- Integer.parse(uid),
         {:ok, %File.Stat{type: :directory, uid: ^uid, access: :read_write}} <- File.stat(Path.join(tmp, top)) do
      true
    else
      _ -> false
    end
  end

  defp checkout(dir, home) do
    cond do
      dir == home or not under?(dir, home) -> nil
      File.exists?(Path.join(dir, ".git")) -> dir
      true -> checkout(Path.dirname(dir), home)
    end
  end

  # only the part below the root is walked, from the root's own real path: each link looked up is a
  # call to the file server, and resolve_all makes these for every file it is given
  defp real_below(abs, root, real_root) do
    abs |> Path.relative_to(root) |> Path.split() |> Enum.reduce(real_root, &follow(Path.join(&2, &1), 0))
  end

  defp under?(path, dir), do: path == dir or String.starts_with?(path, dir <> "/")

  # `path` with each symlink in it followed, as far as it exists: a file about to be created is
  # taken as written. A link loop stops following after 40 links, as the OS does.
  defp real(path, hops \\ 0) do
    path |> Path.split() |> Enum.reduce(&follow(Path.join(&2, &1), hops))
  end

  defp follow(path, hops) when hops > 40, do: path

  defp follow(path, hops) do
    case :file.read_link(path) do
      {:ok, target} -> real(Path.expand(to_string(target), Path.dirname(path)), hops + 1)
      {:error, _} -> path
    end
  end

  # In the mix project of each file it wrote: the nearest mix.exs above it, the root at most. From the
  # root, a repo whose project is a subdirectory would map no test file. Several projects, a run
  # each, its `dir` named.
  # the files named: those, in the root
  defp then_run(reply, p, "test", [_ | _] = files) do
    run =
      ran(Map.merge(Map.take(p, [:root, :timeout]), %{verb: "test", args: files, dir: named_dir(reply, p)}))

    reply |> Map.update(:did, "then run test", &(&1 <> ", then run test")) |> Map.put(:run, run)
  end

  defp then_run(reply, p, verb, []) do
    root = p[:root] || Menard.caller_dir()

    runs =
      for {dir, files} <- by_project(written(reply), root) do
        # the mirror of a file's tests is mix's layout: a repo's own task takes what it takes
        args =
          if verb == "test" and File.regular?(Path.join(dir, "mix.exs")), do: tests_of(files, dir), else: []

        run =
          case args do
            {:none, why} ->
              %{skipped: why}

            args ->
              ran(Map.merge(Map.take(p, [:root, :timeout]), %{verb: verb, args: args, dir: dir}))
          end

        if dir == root, do: run, else: Map.put(run, :dir, Path.relative_to(dir, root))
      end

    run = with [one] <- runs, do: one
    reply |> Map.update(:did, "then run #{verb}", &(&1 <> ", then run #{verb}")) |> Map.put(:run, run)
  end

  # credo on the Elixir lines the write changed: with the check the agent reads, not a call later
  defp credo(reply, p) do
    root = p[:root] || Menard.caller_dir()
    run = p[:run] || (&Menard.Run.result/3)

    found =
      for {dir, files} <- by_project(written(reply), root),
          rels = for(f <- files, Path.extname(f) in [".ex", ".exs"], do: Path.relative_to(f, dir)),
          failure <- Lint.credo_changed(dir, rels, run),
          do: "#{finding_at(failure[:at], dir, root)} #{failure.message}"

    if found == [], do: reply, else: Map.put(reply, :credo, found)
  end

  defp finding_at(nil, _dir, _root), do: ""
  defp finding_at(at, root, root), do: at
  defp finding_at(at, dir, root), do: Path.join(Path.relative_to(dir, root), at)

  defp by_project([], root), do: [{root, []}]

  defp by_project(files, root),
    do: files |> Enum.group_by(&project_of(Path.dirname(&1), root)) |> Enum.to_list()

  # a run refused (its directory out of reach) is said in the reply, the write it follows kept
  defp ran(params) do
    case Run.run(params) do
      {:ok, run} -> run
      {:error, why} -> %{ok: false, failures: [%{kind: "error", message: why}]}
    end
  end

  # where named test files run: the root, or a sibling checkout's own project when the write was there
  defp named_dir(reply, p) do
    root = Path.expand(p[:root] || Menard.caller_dir())

    case written(reply) do
      [file | _] -> if under?(file, root), do: root, else: project_of(Path.dirname(file), root)
      [] -> root
    end
  end

  defp project_of(dir, root) do
    cond do
      File.regular?(Path.join(dir, "mix.exs")) -> dir
      # a file in a sibling checkout is walked up to its own project, past where the root would stop
      dir == root or dir == Path.dirname(dir) -> root
      true -> project_of(Path.dirname(dir), root)
    end
  end

  # the files a write's reply names: one (`file`), or each it changed (`changed`, edit's and rename's)
  defp written(reply) do
    changed = for %{file: file} <- List.wrap(reply[:changed]), do: file
    Enum.uniq(List.wrap(reply[:file]) ++ changed)
  end

  # a run while working, not the gate: an edited test file, and the test file of an edited lib file
  # (lib/a/b.ex, test/a/b_test.exs); none of those, the tests stale since the last run
  # Each file's mirror test, or, for a file with none (a helper, a test support module), the tests
  # that name its modules. Never the suite: `--stale` with no manifest, as in a fresh worktree, ran
  # all of it, and with one ran every test touched since the last `--stale`
  defp tests_of(files, root) do
    {mirrored, bare} =
      Enum.split_with(files, fn file ->
        test = test_of(Path.relative_to(file, root))
        test != nil and File.regular?(Path.join(root, test))
      end)

    mods = Enum.flat_map(bare, &modules_of/1)

    tests =
      Enum.map(mirrored, &test_of(Path.relative_to(&1, root))) ++ naming(mods, root)

    case Enum.uniq(tests) do
      [] ->
        {:none, "no test is the mirror of what changed, or names #{names(mods)}: `run test` runs the suite"}

      tests ->
        tests
    end
  end

  defp modules_of(file) do
    with true <- Path.extname(file) in [".ex", ".exs"],
         {:ok, source} <- File.read(file),
         [_ | _] = mods <- Menard.Module.list(source) do
      mods
    else
      _ -> []
    end
  end

  defp naming([], _root), do: []

  # by the whole name: `C` is not named by `ExUnit.Case`
  defp naming(mods, root) do
    named = ~r/(?<![\w.])(?:#{Enum.map_join(mods, "|", &Regex.escape/1)})(?![\w])/

    for test <- Path.wildcard(Path.join(root, "test/**/*_test.exs")),
        Regex.match?(named, File.read!(test)),
        do: Path.relative_to(test, root)
  end

  defp names([]), do: "a module"
  defp names(mods), do: Enum.join(mods, ", ")

  defp test_of("test/" <> _ = rel), do: if(String.ends_with?(rel, "_test.exs"), do: rel)
  defp test_of("lib/" <> rest), do: "test/" <> Path.rootname(rest) <> "_test.exs"
  defp test_of(_rel), do: nil

  # A file under the root named from it, not by an absolute path. After `then`, which finds each
  # file's project.
  defp from_root(reply, params), do: relative(reply, Path.expand(params[:root] || Menard.caller_dir()))

  # a value that is a path under the root, wherever it is (a `file`, a list of the unchanged, a line
  # `path:12: text`); a sentence that names one in its middle, or code, starts otherwise
  defp relative(%{} = map, root) when not is_struct(map),
    do: Map.new(map, fn {k, v} -> {k, relative(v, root)} end)

  defp relative(list, root) when is_list(list), do: Enum.map(list, &relative(&1, root))
  defp relative("/" <> _ = path, root), do: under(path, root)
  defp relative(other, _root), do: other

  defp under(path, root),
    do:
      if(String.starts_with?(path, root <> "/"), do: String.replace_prefix(path, root <> "/", ""), else: path)
end
