defmodule Menard.Diff do
  @moduledoc """
  Line-level diffs for the staged reply (docs/live.md). `hunks/2` compares two source strings
  and returns the changed regions as `%{start, removed, added}` — `start` is the 1-based line in
  the BEFORE file where the change begins, `removed` and `added` are the lines that went and came.

  The diff is the stdlib's `List.myers_difference/2` over lines: O(ND), where the LCS table it
  replaced took 12s on a 1000-line file, twice per verb.
  """

  @doc "What changed between two source strings: a list of hunks, or `[]` when they match."
  @spec hunks(String.t(), String.t()) :: [map()]
  def hunks(before, after_) do
    cond do
      before == after_ ->
        []

      before == "" ->
        [%{start: 1, removed: [], added: String.split(after_, "\n")}]

      true ->
        String.split(before, "\n")
        |> List.myers_difference(String.split(after_, "\n"))
        |> collect(1, [])
    end
  end

  # A :del and the :ins that follows it are one change, so they are one hunk.
  defp collect([], _line, acc), do: Enum.reverse(acc)
  defp collect([{:eq, lines} | rest], line, acc), do: collect(rest, line + length(lines), acc)

  defp collect([{:del, removed}, {:ins, added} | rest], line, acc),
    do: collect(rest, line + length(removed), [%{start: line, removed: removed, added: added} | acc])

  defp collect([{:del, removed} | rest], line, acc),
    do: collect(rest, line + length(removed), [%{start: line, removed: removed, added: []} | acc])

  defp collect([{:ins, added} | rest], line, acc),
    do: collect(rest, line, [%{start: line, removed: [], added: added} | acc])
end
