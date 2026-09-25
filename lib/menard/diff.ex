defmodule Menard.Diff do
  @moduledoc """
  Line-level diffs for the staged reply (docs/live.md). `hunks/2` compares two source strings
  and returns the changed regions as `%{start, removed, added}` — `start` is the 1-based line in
  the BEFORE file where the change begins, `removed` and `added` are the lines that went and came.

  The engine is vendored from github.com/bryanjos/diff (MIT, v1.1.0) — an LCS diff, pure Elixir,
  no deps. Menard only needs the diff (not the patch), and it works on line lists, not graphemes,
  so the hunks are line-granular.
  """

  alias Menard.Diff.Engine

  @doc "What changed between two source strings: a list of hunks, or `[]` when they match."
  @spec hunks(String.t(), String.t()) :: [map()]
  def hunks(before, after_) do
    cond do
      before == after_ ->
        []

      before == "" ->
        [%{start: 1, removed: [], added: String.split(after_, "\n")}]

      true ->
        diff_lines(String.split(before, "\n"), String.split(after_, "\n"))
    end
  end

  defp diff_lines(before_lines, after_lines) do
    # The engine's index is relative to the CHANGED list. To get the line in the BEFORE file,
    # track an offset: after each change it grows by (removed - added), so the next change's
    # before-line is its changed-index + offset. Verified: a modify at index 1 with old=[B,C]
    # new=[X] in a 5-line file lands at before-line 2 (index 1 + offset 0 + 1); a second modify
    # at changed-index 3 lands at before-line 5 (3 + offset 1 + 1).
    {hunks, _offset} =
      Engine.diff(before_lines, after_lines)
      |> Enum.reduce({[], 0}, fn change, {hunks, offset} ->
        case to_hunk(change, offset) do
          nil -> {hunks, offset}
          {hunk, delta} -> {hunks ++ [hunk], offset + delta}
        end
      end)

    hunks
  end

  defp to_hunk(%Engine.Insert{element: added, index: i}, offset) do
    {%{start: i + offset + 1, removed: [], added: added}, 0 - length(added)}
  end

  defp to_hunk(%Engine.Delete{element: removed, index: i}, offset) do
    {%{start: i + offset + 1, removed: removed, added: []}, length(removed)}
  end

  defp to_hunk(%Engine.Modified{element: added, old_element: removed, index: i}, offset) do
    {%{start: i + offset + 1, removed: removed, added: added}, length(removed) - length(added)}
  end

  defp to_hunk(_unchanged_or_ignored, _offset), do: nil
end
