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
        {same, was, now} = unshared(String.split(before, "\n"), String.split(after_, "\n"), 0)
        {now, was} = now |> Enum.reverse() |> unshared(Enum.reverse(was), 0) |> ends()

        if rewritten?(was, now),
          do: [%{start: same + 1, removed: was, added: now}],
          else: was |> List.myers_difference(now) |> collect(same + 1, [])
    end
  end

  # the lines two lists start with alike, counted, and each list's rest
  defp unshared([line | a], [line | b], n), do: unshared(a, b, n + 1)
  defp unshared(a, b, n), do: {n, a, b}

  defp ends({_n, a, b}), do: {Enum.reverse(a), Enum.reverse(b)}

  # Myers' work grows with the lines that differ times the lines there are: 3000 lines each changed
  # took 15 s, to say what one hunk says. Counted by the lines one side has and the other has not.
  defp rewritten?(was, now) do
    differ = length(was -- now) + length(now -- was)
    differ * (length(was) + length(now)) > 4_000_000
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
