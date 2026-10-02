defmodule Menard.Verbs do
  @moduledoc """
  The one verb layer both doors call. Every noun has a `Menard.Verbs.<Noun>.run/1`: a params map
  in — the fields as the MCP schema names them (`verb`, `file`, `name_arity`, …), string values,
  atom keys — and `{:ok, reply} | {:error, reason}` out, `reply` the one JSON-able map a caller
  sees and `reason` a string. A verb owns resolve → read → change → `Menard.write/3` → the `did`
  text → the reply, and the check that the fields it cannot do without are there. A door (a mix
  task, an MCP tool) only turns its input into the params and the result into its own answer:
  the CLI prints the reply as one JSON line and raises the reason, the MCP tool returns each.

  `root` in the params is the MCP door's launch directory: a path resolves under it and one that
  escapes it is refused. Without it a path resolves against the caller's directory, as the CLI
  means it.
  """

  alias Menard.Verbs.Noun
  alias Menard.Verbs.Run
  @type params :: %{optional(atom()) => term()}
  @type result :: {:ok, map()} | {:error, String.t()}

  @doc """
  A path as the door meant it: under `params[:root]`, as written and as the OS follows it (a
  symlink under the root that points outside it passed the first test alone), or against the
  caller's directory when no root is given.
  """
  @spec resolve(String.t(), params()) :: {:ok, String.t()} | {:error, String.t()}
  def resolve(path, params) do
    case params[:root] do
      nil -> {:ok, Menard.resolve(path)}
      root -> resolve_under(path, Path.expand(root), real(Path.expand(root)))
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
      _ -> resolve_each(expanded, params[:root])
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
    if then in Noun.thens(),
      do: with({:ok, reply} <- verbs.run(params), do: {:ok, then_run(reply, params)}),
      else: {:error, "no then #{inspect(then)}: one of #{Enum.join(Noun.thens(), ", ")}"}
  end

  def call(verbs, params), do: verbs.run(params)

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

  # the root's own real path once, not per file: resolving 20,000 paths is a rename's first step
  defp resolve_each(paths, nil), do: {:ok, Enum.map(paths, &Menard.resolve/1)}

  defp resolve_each(paths, root) do
    root = Path.expand(root)
    real_root = real(root)

    resolved =
      Enum.reduce_while(paths, {:ok, []}, fn p, {:ok, acc} ->
        case resolve_under(p, root, real_root) do
          {:ok, abs} -> {:cont, {:ok, [abs | acc]}}
          {:error, _} = refused -> {:halt, refused}
        end
      end)

    with {:ok, reversed} <- resolved, do: {:ok, Enum.reverse(reversed)}
  end

  defp resolve_under(path, root, real_root) do
    abs = Path.expand(path, root)

    if under?(abs, root) and under?(real_below(abs, root, real_root), real_root),
      do: {:ok, abs},
      else: {:error, "refused: #{path} is outside #{root}"}
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
  # root, a repo whose project is server/ (tlon's) mapped no test file, and --stale ran where there
  # was no mix.exs (Fable's review, 2026-10-01). Several projects, a run each, its `dir` named.
  defp then_run(reply, %{then: verb} = p) do
    root = p[:root] || Menard.caller_dir()

    runs =
      for {dir, files} <- by_project(written(reply), root) do
        args = if verb == "test", do: tests_of(files, dir), else: []
        {:ok, run} = Run.run(Map.merge(Map.take(p, [:root, :timeout]), %{verb: verb, args: args, dir: dir}))
        if dir == root, do: run, else: Map.put(run, :dir, Path.relative_to(dir, root))
      end

    run = with [one] <- runs, do: one
    reply |> Map.update(:did, "then run #{verb}", &(&1 <> ", then run #{verb}")) |> Map.put(:run, run)
  end

  defp by_project([], root), do: [{root, []}]

  defp by_project(files, root),
    do: files |> Enum.group_by(&project_of(Path.dirname(&1), root)) |> Enum.to_list()

  defp project_of(dir, root) do
    cond do
      File.regular?(Path.join(dir, "mix.exs")) -> dir
      dir == root or not String.starts_with?(dir, root <> "/") -> root
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
  defp tests_of(files, root) do
    tests =
      for file <- files,
          test = test_of(Path.relative_to(file, root)),
          test && File.regular?(Path.join(root, test)),
          uniq: true,
          do: test

    if tests == [], do: ["--stale"], else: tests
  end

  defp test_of("test/" <> _ = rel), do: if(String.ends_with?(rel, "_test.exs"), do: rel)
  defp test_of("lib/" <> rest), do: "test/" <> Path.rootname(rest) <> "_test.exs"
  defp test_of(_rel), do: nil
end
