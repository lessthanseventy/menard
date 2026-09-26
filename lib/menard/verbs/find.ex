defmodule Menard.Verbs.Find do
  @moduledoc "The `find` verb (`Menard.Verbs`): `kind` (`calls`, `defs`, `aliases`) of `target` in `files` (paths, directories or globs); the reply is `hits`."

  import Menard.Verbs
  alias Menard.Find

  @kinds ~w(calls defs aliases)

  @spec run(Menard.Verbs.params()) :: Menard.Verbs.result()
  def run(p) do
    with :ok <- need(p, [:kind, :target], "find"),
         {:ok, finder} <- finder(p.kind, p.target),
         {:ok, patterns} <- patterns(p),
         {:ok, files} <- Find.files(patterns) do
      hits =
        Enum.flat_map(files, fn file ->
          file |> File.read!() |> finder.() |> Enum.map(&Map.put(&1, :file, file))
        end)

      {:ok, %{hits: hits}}
    end
  end

  defp patterns(%{files: [_ | _] = files} = p), do: resolve_all(files, p)
  defp patterns(_p), do: {:error, "find needs files"}

  defp finder("calls", target), do: {:ok, &Find.calls(&1, target)}
  defp finder("defs", target), do: {:ok, &Find.defs(&1, target)}
  defp finder("aliases", target), do: {:ok, &Find.aliases(&1, target)}

  defp finder(kind, _target),
    do: {:error, "find has no kind #{inspect(kind)}: one of #{Enum.join(@kinds, ", ")}"}
end
