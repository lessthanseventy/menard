defmodule Menard.Verbs.Run do
  @moduledoc """
  The `run` verbs (`Menard.Verbs`): `check`, `test`, `format`, `compile`, `credo`, with `args` for
  the mix task behind them, in the project at `dir` (default: the root, else the caller's
  directory), under `timeout` ms when a door gives one. The reply is `Menard.Run.lean/1`'s: `ok`
  false is an answer, never a refusal.
  """

  alias Menard.Run.Committed

  import Menard.Verbs

  @verbs ~w(check test format compile credo)

  @doc "The noun, as both doors are made from it (`Menard.Verbs.Noun`)."
  @spec noun() :: Menard.Verbs.Noun.t()
  def noun do
    %{
      name: "run",
      doc: """
      In a directory with no mix.exs, `check`, `test` and `compile` run its mise task of that name
      and answer with its tail. In a mix project, run a verb and get ONE structured answer: `check` (the
      project formatted first, `formatted` naming what changed, then its `mix precommit`: format,
      warnings-as-errors, tests), `test` (args: files, file:line,
      and any `mix test` flag), `format` (args: files), `compile`, `credo` (args: files, `--strict`,
      `--changed` for the lines changed since the last commit). `dir` defaults to the root.

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

      `committed: true` (`--committed`) runs `check`, `test` or `compile` on the last commit, in a
      worktree menard keeps: the files can be edited while it runs. The reply's `committed` is the
      commit, `uncommitted` how many changed paths it did not see.
      """,
      deadline: 600_000,
      fields: [
        {:verb, :enum, [values: ["check", "test", "format", "compile", "credo"], required: true]},
        {:args, {:list, :string}, []},
        {:dir, :string, []},
        {:committed, :boolean, []}
      ]
    }
  end

  @spec run(Menard.Verbs.params()) :: Menard.Verbs.result()
  def run(%{verb: verb} = p) when verb in @verbs do
    with {:ok, dir} <- resolve(p[:dir] || ".", p),
         {:ok, dir, said} <- at(dir, verb, p[:committed]) do
      opts = if ms = p[:timeout], do: [timeout: ms], else: []
      {:ok, Map.merge(Menard.Run.lean(Menard.Run.result(dir, verb, p[:args] || [], opts)), said)}
    end
  end

  def run(%{verb: verb}), do: {:error, "run has no verb #{inspect(verb)}: one of #{Enum.join(@verbs, ", ")}"}
  def run(_params), do: {:error, "run needs verb: one of #{Enum.join(@verbs, ", ")}"}

  defp at(dir, verb, true) when verb in ~w(check test compile) do
    with {:ok, %{dir: dir, sha: sha, uncommitted: n}} <- Committed.at_head(dir) do
      {:ok, dir, if(n > 0, do: %{committed: sha, uncommitted: n}, else: %{committed: sha})}
    end
  end

  defp at(_dir, verb, true),
    do: {:error, "run #{verb} is of the working tree: --committed is for check, test and compile"}

  defp at(dir, _verb, _committed), do: {:ok, dir, %{}}
end
