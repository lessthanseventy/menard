defmodule Menard.Verbs.Run do
  @moduledoc """
  The `run` verbs (`Menard.Verbs`): `check`, `test`, `format`, `compile`, `credo`, with `args` for
  the mix task behind them, in the project at `dir` (default: the root, else the caller's
  directory), under `timeout` ms when a door gives one. The reply is `Menard.Run.lean/1`'s: `ok`
  false is an answer, never a refusal.
  """

  import Menard.Verbs

  @verbs ~w(check test format compile credo)

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
