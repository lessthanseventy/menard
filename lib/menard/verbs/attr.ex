defmodule Menard.Verbs.Attr do
  @moduledoc "The `attr` verbs (`Menard.Verbs`): `get`, `set`, `delete`, `list`."

  import Menard.Verbs
  alias Menard.Attr

  @verbs ~w(get set delete list)

  @spec run(Menard.Verbs.params()) :: Menard.Verbs.result()
  def run(%{verb: "list"} = p) do
    with :ok <- need(p, [:file], "attr list"),
         {:ok, file} <- resolve(p.file, p),
         {:ok, source} <- read(file),
         found when is_list(found) <- Attr.list(source, module: p[:module]) do
      {:ok, %{attributes: Enum.map(found, fn {name, line} -> "@#{name} (line #{line})" end)}}
    end
  end

  def run(%{verb: "get"} = p) do
    with :ok <- need(p, [:file, :name], "attr get"),
         {:ok, file} <- resolve(p.file, p),
         {:ok, source} <- read(file),
         text when is_binary(text) <- Attr.get(source, p.name, module: p[:module]) do
      {:ok, %{value: text}}
    end
  end

  def run(%{verb: verb} = p) when verb in @verbs do
    with :ok <- need(p, [:file, :name], "attr #{verb}") do
      # the name may come with its `@` or without; the reply names it once either way
      at = "@" <> String.trim_leading(p.name, "@")
      edit(p, &"#{verb} #{at} in #{&1}", &change(verb, &1, p))
    end
  end

  def run(%{verb: verb}), do: {:error, "attr has no verb #{inspect(verb)}: one of #{Enum.join(@verbs, ", ")}"}
  def run(_params), do: {:error, "attr needs verb: one of #{Enum.join(@verbs, ", ")}"}

  defp change("set", source, p), do: Attr.set(source, p.name, p[:value] || "", module: p[:module])
  defp change("delete", source, p), do: Attr.delete(source, p.name, module: p[:module])
end
