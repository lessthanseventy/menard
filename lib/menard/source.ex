defmodule Menard.Source do
  @moduledoc false

  @doc """
  The dotted name an `{:__aliases__, _, parts}` spells. `__MODULE__` is an AST node, not an atom,
  so it becomes `current` when the enclosing module is known and stays `__MODULE__` when not.
  """
  def alias_name(parts, current \\ nil) do
    Enum.map_join(parts, ".", fn
      {:__MODULE__, _meta, _ctx} -> current || "__MODULE__"
      part -> to_string(part)
    end)
  end

  @doc "The source text a range covers."
  def slice(source, %{start: [line: a, column: ca], end: [line: b, column: cb]}) do
    case source |> String.split("\n") |> Enum.slice((a - 1)..(b - 1)) do
      [] ->
        ""

      [one] ->
        String.slice(one, ca - 1, cb - ca)

      [first | rest] ->
        {mid, [last]} = Enum.split(rest, -1)
        Enum.join([String.slice(first, (ca - 1)..-1//1) | mid] ++ [String.slice(last, 0, cb - 1)], "\n")
    end
  end

  @doc "`text` with the indent its lines share removed."
  def dedent(text) do
    pad =
      text
      |> String.split("\n")
      |> Enum.reject(&(String.trim(&1) == ""))
      |> Enum.map(&(String.length(&1) - String.length(String.trim_leading(&1))))
      |> Enum.min(fn -> 0 end)

    text |> String.split("\n") |> Enum.map_join("\n", &String.slice(&1, pad..-1//1))
  end
end
