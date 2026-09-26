defmodule Menard.Verbs.Module do
  @moduledoc "The `module` verbs (`Menard.Verbs`): `add`, `replace`, `list`."

  import Menard.Verbs

  @verbs ~w(add replace list)

  @spec run(Menard.Verbs.params()) :: Menard.Verbs.result()
  def run(%{verb: "list"} = p) do
    with :ok <- need(p, [:file], "module list"),
         {:ok, file} <- resolve(p.file, p),
         {:ok, source} <- read(file),
         names when is_list(names) <- Menard.Module.list(source) do
      {:ok, %{modules: names}}
    end
  end

  def run(%{verb: "add"} = p) do
    with :ok <- need(p, [:file, :code], "module add") do
      edit(p, &"add a module in #{&1}", &Menard.Module.add(&1, p.code))
    end
  end

  def run(%{verb: "replace"} = p) do
    with :ok <- need(p, [:file, :module, :code], "module replace") do
      edit(p, &"replace #{p.module} in #{&1}", &Menard.Module.replace(&1, p.module, p.code))
    end
  end

  def run(%{verb: verb}),
    do: {:error, "module has no verb #{inspect(verb)}: one of #{Enum.join(@verbs, ", ")}"}

  def run(_params), do: {:error, "module needs verb: one of #{Enum.join(@verbs, ", ")}"}
end
