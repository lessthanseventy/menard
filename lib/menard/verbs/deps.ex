defmodule Menard.Verbs.Deps do
  @moduledoc """
  The `deps` verbs (`Menard.Verbs`): `refs` (the default: what `name_arity` in `file` references),
  `add` (`spec`, in the project at `dir`) and `upgrade` (`apps`, `to`, in `dir`). `add` and
  `upgrade` answer the way `run` does: `ok` false is an answer, with `error` or the compile's
  failures, not a refusal.
  """

  import Menard.Verbs

  @verbs ~w(refs add upgrade)

  @doc "The noun, as both doors are made from it (`Menard.Verbs.Noun`)."
  @spec noun() :: Menard.Verbs.Noun.t()
  def noun do
    %{
      name: "deps",
      doc: """
      Dependencies, both kinds. `verb` is:

      - `refs` (the default): what one function references — the read before a move. Give `file` and
        `name_arity`. Returns the local calls it makes (each with `shared_with`: the OTHER functions
        here that also call it, so a helper with an empty list can travel and one with entries cannot),
        the remote calls, the modules whose aliases must travel, and the attributes it reads.
      - `add`: a project dependency, `spec` as written in mix.exs (`{:req, "~> 0.5"}`) or a bare name
        looked up on Hex. Written into the deps list, fetched and compiled; the answer carries the lock
        diff and the compile, `ok` false when either failed. A fetch that fails puts mix.exs back.
      - `upgrade`: `apps` updated (all when none are named), through the host's own
        `mix igniter.upgrade` when it has Igniter. `to` rewrites one app's requirement first.

      `dir` is the mix project, under the root (default: the root).
      """,
      deadline: 600_000,
      fields: [
        {:verb, :enum, [values: ["refs", "add", "upgrade"]]},
        {:file, :string, []},
        {:name_arity, :string, []},
        {:module, :string, []},
        {:spec, :string, []},
        {:apps, {:list, :string}, []},
        {:to, :string, []},
        {:dir, :string, []}
      ]
    }
  end

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
