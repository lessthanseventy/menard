defmodule Menard.Diff do
  @moduledoc """
  Line-level diffs for the staged reply (docs/live.md). `hunks/2` compares two source strings
  and returns the changed regions as `%{start, removed, added}` — `start` is the 1-based line in
  the BEFORE file where the change begins, `removed` and `added` are the lines that went and came.

  The diff is the stdlib's `List.myers_difference/2` over lines: O(ND), where the LCS table it
  replaced took 12s on a 1000-line file, twice per verb.
  """

  @doc """
  What changed between two source strings: a list of hunks, or `[]` when they match. `start` is the
  1-based line in the BEFORE file where the change begins; `removed` and `added` are the lines that
  went and came.

      iex> Menard.Diff.hunks("a\\nb\\nc", "a\\nb\\nc")
      []

      iex> Menard.Diff.hunks("a\\nb\\nc\\nd\\ne", "a\\nB\\nc\\nd\\ne")
      [%{start: 2, removed: ["b"], added: ["B"]}]

  A line inserted at the end, at the start, or deleted:

      iex> Menard.Diff.hunks("a\\nb\\nc", "a\\nb\\nc\\nd")
      [%{start: 4, removed: [], added: ["d"]}]

      iex> Menard.Diff.hunks("b\\nc", "a\\nb\\nc")
      [%{start: 1, removed: [], added: ["a"]}]

      iex> Menard.Diff.hunks("a\\nb\\nc\\nd", "a\\nc\\nd")
      [%{start: 2, removed: ["b"], added: []}]

      iex> Menard.Diff.hunks("x\\ny\\nz", "y\\nz")
      [%{start: 1, removed: ["x"], added: []}]

  Two changes apart are two hunks; lines removed and the lines put in their place are one:

      iex> Menard.Diff.hunks("a\\nb\\nc\\nd\\ne\\nf\\ng\\nh", "a\\nB\\nc\\nd\\ne\\nf\\nG\\nh")
      [%{start: 2, removed: ["b"], added: ["B"]}, %{start: 7, removed: ["g"], added: ["G"]}]

      iex> Menard.Diff.hunks("def go do\\n  :a\\n  :b\\nend", "def go do\\n  :c\\n  :d\\n  :e\\nend")
      [%{start: 2, removed: ["  :a", "  :b"], added: ["  :c", "  :d", "  :e"]}]

  A new file is one insert, and a trailing newline added is an inserted empty line:

      iex> Menard.Diff.hunks("", "a\\nb\\nc")
      [%{start: 1, removed: [], added: ["a", "b", "c"]}]

      iex> Menard.Diff.hunks("a\\nb", "a\\nb\\n")
      [%{start: 3, removed: [], added: [""]}]
  """
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
