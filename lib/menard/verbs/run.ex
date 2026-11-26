defmodule Menard.Verbs.Run do
  @moduledoc """
  The `run` verbs (`Menard.Verbs`): `check`, `test`, `format`, `compile`, `credo`, with `args` for
  the mix task behind them, in the project at `dir` (default: the root, else the caller's
  directory), under `timeout` ms when a door gives one. The reply is `Menard.Run.lean/1`'s: `ok`
  false is an answer, never a refusal.
  """

  alias Menard.Run.Committed

  import Menard.Verbs

  @verbs ~w(check test format compile credo e2e)

  @doc "The noun, as both doors are made from it (`Menard.Verbs.Noun`)."
  @spec noun() :: Menard.Verbs.Noun.t()
  def noun do
    %{
      name: "run",
      doc: """
      In a directory with no mix.exs, `check`, `test` and `compile` run its mise task of that name
      and answer with its tail; with a build.zig and no such task, `zig build` (`test`, and for `check`
      `install test`), its compile errors and failed tests as `failures`. In a mix project, run a verb and get ONE structured answer: `check` (the
      project formatted first, `formatted` naming what changed, then its `mix precommit`: format,
      warnings-as-errors, tests), `test` (args: files, file:line,
      and any `mix test` flag), `format` (args: files), `compile`, `credo` (args: files, `--strict`,
      `--changed` for the lines changed since the last commit). `dir` defaults to the root; a `test`
      given no `dir` runs in the project above its files (a `demo/` with its own mix.exs).

      `e2e` runs the repo's own `e2e` mise task alone (a mix project or not), with `run check`'s
      process-group handling: a failing step is a `failures` entry `{kind: "e2e", name, screen}` from
      the task's `FAIL  name` lines and the `      | ` screen under each. With no `e2e` task it
      refuses at once and says so.

      While you work, `test` with the test files of what you changed: seconds, and their failures
      alone. `check` once, when the change is done: it is the whole suite and more (a session that
      ran it after every edit spent twice the suite runs of one that did not).

      A `test` of FILE:LINE names what the line ran in `ran`: ExUnit takes the closest test at or
      before it. Every verb answers `failures` in one shape: `{kind, message, at}` — `kind` is `test`, `error`,
      `warning`, `format` or `credo`, `message` says why, `at` is `file:line`. A test failure adds `name`,
      `module`, `source` (the test as written) and, for an assertion, `code`, `left`, `right`; past
      the third, a failure is `{kind, name, at, message}` and the `log` has the rest. A failed test
      runs once more: one that passes is in `flaky`, not `failures`. A run whose tests were all
      excluded by the project's tags is not ok, and says which to `--include`.

      Every reply's `dir` is where it ran, from the repository's root (`.` is the root). `outer: "."`
      says that was a project nested in a repository whose root is a mix project too: not its gate.

      `committed: true` (`--committed`) runs `check`, `test` or `compile` on the last commit, in a
      worktree menard keeps: the files can be edited while it runs. The reply's `committed` is the
      commit, `uncommitted` how many changed paths it did not see.
      """,
      deadline: 600_000,
      fields: [
        {:verb, :enum, [values: ["check", "test", "format", "compile", "credo", "e2e"], required: true]},
        {:args, {:list, :string}, []},
        {:dir, :string, []},
        {:committed, :boolean, []}
      ]
    }
  end

  @spec run(Menard.Verbs.params()) :: Menard.Verbs.result()
  def run(%{verb: verb} = p) when verb in @verbs do
    with {:ok, base} <- resolve(p[:dir] || ".", p),
         {:ok, dir, args} <- project(verb, p[:dir], base, p[:args] || []),
         {:ok, dir, said} <- at(dir, verb, p[:committed]) do
      opts = if ms = p[:timeout], do: [timeout: ms], else: []
      reply = Menard.Run.lean(Menard.Run.result(dir, verb, args, opts))
      {:ok, reply |> Map.merge(said) |> Map.merge(where(dir))}
    end
  end

  def run(%{verb: verb}), do: {:error, "run has no verb #{inspect(verb)}: one of #{Enum.join(@verbs, ", ")}"}
  def run(_params), do: {:error, "run needs verb: one of #{Enum.join(@verbs, ", ")}"}

  # Test files run in the project above them, wherever the caller stands.
  defp project("test", nil, base, args) do
    files =
      for arg <- args,
          path = Path.expand(arg, base),
          File.exists?(bare(path)),
          into: %{},
          do: {arg, path}

    case files |> Map.values() |> Enum.map(&mix_root(bare(&1))) |> Enum.uniq() do
      [project] when is_binary(project) ->
        {:ok, project, Enum.map(args, &if(path = files[&1], do: Path.relative_to(path, project), else: &1))}

      [_, _ | _] ->
        {:error, "run test was given files of two projects: run each project's on its own"}

      _none ->
        {:ok, base, args}
    end
  end

  defp project(_verb, _dir, base, args), do: {:ok, base, args}

  defp bare(path), do: Regex.replace(~r/(:\d+)+$/, path, "")

  defp mix_root("/"), do: nil

  defp mix_root(path),
    do: if(File.regular?(Path.join(path, "mix.exs")), do: path, else: mix_root(Path.dirname(path)))

  defp at(dir, verb, true) when verb in ~w(check test compile) do
    with {:ok, %{dir: dir, sha: sha, uncommitted: n}} <- Committed.at_head(dir) do
      {:ok, dir, if(n > 0, do: %{committed: sha, uncommitted: n}, else: %{committed: sha})}
    end
  end

  defp at(_dir, verb, true),
    do: {:error, "run #{verb} is of the working tree: --committed is for check, test and compile"}

  defp at(dir, _verb, _committed), do: {:ok, dir, %{}}

  # From the repository's root, so a check of a nested project is not read as the repository's gate.
  defp where(dir) do
    case System.cmd("git", ["-C", dir, "rev-parse", "--show-toplevel", "--show-prefix"],
           stderr_to_stdout: true
         ) do
      {out, 0} -> out |> String.split("\n") |> below()
      _outside -> %{dir: dir}
    end
  end

  defp below([_top, "" | _]), do: %{dir: "."}

  defp below([top, prefix | _]) do
    dir = String.trim_trailing(prefix, "/")
    if File.regular?(Path.join(top, "mix.exs")), do: %{dir: dir, outer: "."}, else: %{dir: dir}
  end
end
