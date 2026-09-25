# Vendored from github.com/bryanjos/diff (MIT, v1.1.0) — the LCS diff engine.
# Renamed from Diff to Menard.Diff.Engine so menard-as-a-library does not pollute the host's
# top-level namespace. Matrix is nested (it is internal). Dict.get → Keyword.get (Dict is
# deprecated). Mix.env removed (no mix.exs of our own).

defmodule Menard.Diff.Engine do
  @moduledoc false
  alias Menard.Diff.Diffable

  defmodule Matrix do
    def new(rows, columns), do: List.duplicate(List.duplicate(0, columns), rows)

    def get(matrix, i, j) do
      matrix |> Enum.fetch!(i) |> Enum.fetch!(j)
    end

    def put(matrix, i, j, value) do
      list = Enum.fetch!(matrix, i) |> List.update_at(j, fn _ -> value end)
      List.update_at(matrix, i, fn _ -> list end)
    end
  end

  defmodule Insert do
    defstruct [:element, :index, :length]
  end

  defmodule Delete do
    defstruct [:element, :index, :length]
  end

  defmodule Modified do
    defstruct [:element, :old_element, :index, :length]
  end

  defmodule Unchanged do
    defstruct [:element, :index, :length]
  end

  defmodule Ignored do
    defstruct [:element, :index, :length]
  end

  def diff(original, changed, options \\ []) do
    original = Diffable.to_list(original)
    changed = Diffable.to_list(changed)

    original_length = length(original)
    changed_length = length(changed)

    longest_common_subsequence(original, changed, original_length, changed_length)
    |> build_diff(original, changed, original_length, changed_length, [], options)
    |> build_changes(options)
  end

  defp longest_common_subsequence(x, y, x_length, y_length) do
    matrix = Matrix.new(x_length + 1, y_length + 1)

    rowreduction = fn i, matrix ->
      columnreduction = fn j, matrix ->
        if Enum.fetch!(x, i - 1) == Enum.fetch!(y, j - 1) do
          Matrix.put(matrix, i, j, Matrix.get(matrix, i - 1, j - 1) + 1)
        else
          Matrix.put(matrix, i, j, max(Matrix.get(matrix, i, j - 1), Matrix.get(matrix, i - 1, j)))
        end
      end

      Enum.reduce(1..y_length, matrix, columnreduction)
    end

    Enum.reduce(1..x_length, matrix, rowreduction)
  end

  defp build_diff(matrix, x, y, i, j, edits, options) do
    cond do
      i > 0 and j > 0 and Enum.fetch!(x, i - 1) == Enum.fetch!(y, j - 1) ->
        newedits =
          if Keyword.get(options, :keep_unchanged, false) do
            edits ++ [{:unchanged, Enum.fetch!(x, i - 1), i - 1}]
          else
            edits
          end

        build_diff(matrix, x, y, i - 1, j - 1, newedits, options)

      j > 0 and (i == 0 or Matrix.get(matrix, i, j - 1) >= Matrix.get(matrix, i - 1, j)) ->
        build_diff(matrix, x, y, i, j - 1, edits ++ [{:insert, Enum.fetch!(y, j - 1), j - 1}], options)

      i > 0 and (j == 0 or Matrix.get(matrix, i, j - 1) < Matrix.get(matrix, i - 1, j)) ->
        build_diff(matrix, x, y, i - 1, j, edits ++ [{:delete, Enum.fetch!(x, i - 1), j}], options)

      true ->
        edits |> Enum.reverse()
    end
  end

  defp build_changes(edits, options) do
    merge = fn {type, char, index}, changes ->
      if changes == [] do
        [make_change(type, char, index)]
      else
        change = List.last(changes)
        regex = Keyword.get(options, :ignore)

        cond do
          regex && Regex.match?(regex, char) ->
            changes ++ [make_change(:ignored, char, index)]

          is_type(change, type) && type == :delete && index == change.index ->
            change = %{change | element: change.element ++ [char], length: change.length + 1}
            List.replace_at(changes, length(changes) - 1, change)

          is_type(change, type) && type != :delete && index == change.index + change.length ->
            change = %{change | element: change.element ++ [char], length: change.length + 1}
            List.replace_at(changes, length(changes) - 1, change)

          true ->
            changes ++ [make_change(type, char, index)]
        end
      end
    end

    makemodified = fn x, changes ->
      if changes == [] do
        [x]
      else
        last = List.last(changes)

        if is_type(last, :delete) and is_type(x, :insert) and
             last.index == x.index and last.length == x.length do
          modified = %Modified{
            element: x.element,
            old_element: last.element,
            index: x.index,
            length: x.length
          }

          List.replace_at(changes, length(changes) - 1, modified)
        else
          changes ++ [x]
        end
      end
    end

    Enum.reduce(edits, [], merge) |> Enum.reduce([], makemodified)
  end

  defp make_change(:insert, char, index), do: %Insert{element: [char], index: index, length: 1}
  defp make_change(:delete, char, index), do: %Delete{element: [char], index: index, length: 1}
  defp make_change(:unchanged, char, index), do: %Unchanged{element: [char], index: index, length: 1}
  defp make_change(:ignored, char, index), do: %Ignored{element: [char], index: index, length: 1}

  defp is_type(%Insert{}, :insert), do: true
  defp is_type(%Delete{}, :delete), do: true
  defp is_type(%Unchanged{}, :unchanged), do: true
  defp is_type(%Ignored{}, :ignored), do: true
  defp is_type(_, _), do: false
end
