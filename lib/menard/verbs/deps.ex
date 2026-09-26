defmodule Menard.Verbs.Deps do
  @moduledoc """
  The `deps` verbs (`Menard.Verbs`): `refs` (the default: what `name_arity` in `file` references),
  `add` (`spec`, in the project at `dir`) and `upgrade` (`apps`, `to`, in `dir`). `add` and
  `upgrade` answer the way `run` does: `ok` false is an answer, with `error` or the compile's
  failures, not a refusal.
  """

  import Menard.Verbs

  @verbs ~w(refs add upgrade)

  @spec run(Menard.Verbs.params()) :: Menard.Verbs.result()
  def run(%{verb: "add"} = p) do
    with :ok <- need(p, [:spec], "deps add"),
         {:ok, dir} <- resolve(p[:dir] || ".", p) do
      {:ok, Menard.MixDeps.add_in(dir, p.spec)}
    end
  end

  def run(%{verb: "upgrade"} = p) do
    with {:ok, dir} <- resolve(p[:dir] || ".", p) do
      {:ok, Menard.MixDeps.upgrade_in(dir, p[:apps] || [], p[:to])}
    end
  end

  def run(%{verb: verb} = p) when verb in [nil, "refs"] do
    with :ok <- need(p, [:file, :name_arity], "deps refs"),
         {:ok, file} <- resolve(p.file, p),
         {:ok, source} <- read(file),
         %{} = report <- Menard.Deps.of(source, p.name_arity, module: p[:module]) do
      {:ok, report}
    end
  end

  def run(%{verb: verb}), do: {:error, "deps has no verb #{inspect(verb)}: one of #{Enum.join(@verbs, ", ")}"}
  def run(p), do: run(Map.put(p, :verb, "refs"))
end
