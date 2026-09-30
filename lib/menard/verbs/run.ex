defmodule Menard.Verbs.Run do
  @moduledoc """
  The `run` verbs (`Menard.Verbs`): `check`, `test`, `format`, `compile`, `credo`, with `args` for
  the mix task behind them, in the project at `dir` (default: the root, else the caller's
  directory), under `timeout` ms when a door gives one. The reply is `Menard.Run.lean/1`'s: `ok`
  false is an answer, never a refusal.
  """

  import Menard.Verbs

  @verbs ~w(check test format compile credo)

  @doc "The noun, as both doors are made from it (`Menard.Verbs.Noun`)."
  @spec noun() :: Menard.Verbs.Noun.t()
  def noun do
    %{
      name: "run",
      doc: """
      Run a verb in a mix project under the root and get ONE structured answer: `check` (the
      project's `mix precommit`: format, warnings-as-errors, tests), `test` (args: files, file:line,
      and any `mix test` flag), `format` (args: files), `compile`, `credo` (args: files, `--strict`,
      `--changed` for the lines changed since the last commit). `dir` defaults to the root.

      While you work, `test` with the test files of what you changed: seconds, and their failures
      alone. `check` once, when the change is done: it is the whole suite and more (a session that
      ran it after every edit spent twice the suite runs of one that did not).

      Every verb answers `failures` in one shape: `{kind, message, at}` — `kind` is `test`, `error`,
      `warning`, `format` or `credo`, `message` says why, `at` is `file:line`. A test failure adds `name`,
      `module`, `source` (the test as written) and, for an assertion, `code`, `left`, `right`.
      """,
      deadline: 600_000,
      fields: [
        {:verb, :enum, [values: ["check", "test", "format", "compile", "credo"], required: true]},
        {:args, {:list, :string}, []},
        {:dir, :string, []}
      ]
    }
  end

  @spec run(Menard.Verbs.params()) :: Menard.Verbs.result()
  def run(%{verb: verb} = p) when verb in @verbs do
    with {:ok, dir} <- resolve(p[:dir] || ".", p) do
      opts = if ms = p[:timeout], do: [timeout: ms], else: []
      {:ok, Menard.Run.lean(Menard.Run.result(dir, verb, p[:args] || [], opts))}
    end
  end

  def run(%{verb: verb}), do: {:error, "run has no verb #{inspect(verb)}: one of #{Enum.join(@verbs, ", ")}"}
  def run(_params), do: {:error, "run needs verb: one of #{Enum.join(@verbs, ", ")}"}
end
