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

  @doc """
  `range` with its end corrected on its last line. Sourceror ends a node that closes a line — a
  heredoc, a bare literal like `false` — a column past the line's end, and a patch over that eats
  the newline; it ends an INTERPOLATED heredoc inside its closing quotes, and a patch over that
  leaves quotes behind.
  """
  def clamp(%{end: [line: b, column: c]} = range, source) do
    line = source |> String.split("\n") |> Enum.at(b - 1, "")

    c =
      case Regex.run(~r/^\s*("""|''')/, line) do
        [closing, _delimiter] -> max(c, String.length(closing) + 1)
        nil -> c
      end

    %{range | end: [line: b, column: line |> String.length() |> Kernel.+(1) |> min(c) |> off_blanks(line)]}
  end

  # A literal before `end` (`fn -> nil end`) ends one past itself in Sourceror, on the space: a patch
  # over it ate the space, `nilend`. No node ends on whitespace.
  defp off_blanks(c, line) when c > 1 do
    if String.at(line, c - 2) in [" ", "\t"], do: off_blanks(c - 1, line), else: c
  end

  defp off_blanks(c, _line), do: c

  @doc """
  `code` placed at `indent`: its first line bare (a patch starts at the column), every later line
  at `indent` — after dropping the indent those lines already share, so code sliced from a file
  (first line bare, the rest still indented) is not indented twice. Blank lines stay blank.
  """
  def reindent(code, indent) do
    case code |> String.trim() |> String.split("\n") do
      [one] ->
        one

      [first | rest] ->
        # Already at or past `indent`: placed for here, and left as it is. Dropping the indent they
        # share assumed the shallowest sat at the base, and pulled a sigil's words or a heredoc's
        # lines left when every line, the closing too, sat deeper.
        rest =
          if shared_indent(rest) >= String.length(indent),
            do: rest,
            else:
              rest
              |> Enum.join("\n")
              |> dedent()
              |> String.split("\n")
              |> Enum.map(&if(String.trim(&1) == "", do: "", else: indent <> &1))

        Enum.join([first | rest], "\n")
    end
  end

  defp shared_indent(lines) do
    lines
    |> Enum.reject(&(String.trim(&1) == ""))
    |> Enum.map(&(String.length(&1) - String.length(String.trim_leading(&1))))
    |> Enum.min(fn -> 0 end)
  end

  @doc """
  `source` parsed by Sourceror, or `{:error, "not parseable — …"}`. The last result is kept in the
  process dictionary: one verb finds a clause, then a statement in it, then patches — all over the
  same bytes — and the parse was most of each call's cost.
  """
  def parse(source) do
    case Process.get(__MODULE__) do
      {^source, result} ->
        result

      _ ->
        result =
          case Sourceror.parse_string(source) do
            {:ok, ast} -> {:ok, ast}
            {:error, reason} -> {:error, "not parseable — #{inspect(reason)}"}
          end

        Process.put(__MODULE__, {source, result})
        result
    end
  end

  @doc "How many `#` comment lines sit directly above zero-based line `i` — the why glued to what follows."
  def comment_lines_above(lines, i) do
    lines
    |> Enum.take(i)
    |> Enum.reverse()
    |> Enum.take_while(&String.starts_with?(String.trim_leading(&1), "#"))
    |> length()
  end

  @doc """
  `range` grown upward over the `#` comment lines directly above it, when `code` opens with a
  comment of its own: a new body that restates the comment above the old body's first statement
  replaces it, where a body's range alone left it and wrote it twice. Otherwise `range` as it is.
  """
  def with_leading_comments(%{start: [line: line, column: _]} = range, source, code) do
    lines = String.split(source, "\n")

    above =
      lines
      |> Enum.take(line - 1)
      |> Enum.reverse()
      |> Enum.take_while(&String.starts_with?(String.trim_leading(&1), "#"))

    if above != [] and code |> String.trim_leading() |> String.starts_with?("#") do
      first = line - length(above)
      text = Enum.at(lines, first - 1)

      %{
        range
        | start: [line: first, column: String.length(text) - String.length(String.trim_leading(text)) + 1]
      }
    else
      range
    end
  end

  @doc """
  `node`'s range as the verbs patch it: Sourceror's, corrected where it is wrong, then `clamp/2`ed.
  It starts `__MODULE__.Docs.go()` after the `__MODULE__`, which left `__MODULE__` behind a patch
  and made the statement unreachable by what is written: the true start is the earliest position
  any node inside carries. nil where Sourceror has no range.
  """
  def range(node, source) do
    case Sourceror.get_range(node) do
      nil -> nil
      range -> range |> earliest_start(node) |> clamp(source)
    end
  end

  defp earliest_start(%{start: [line: line, column: col]} = range, node) do
    {_node, {line, col}} =
      Macro.prewalk(node, {line, col}, fn
        {_, meta, _} = inner, earliest when is_list(meta) ->
          here = {meta[:line], meta[:column]}

          if is_integer(elem(here, 0)) and is_integer(elem(here, 1)) and here < earliest,
            do: {inner, here},
            else: {inner, earliest}

        inner, earliest ->
          {inner, earliest}
      end)

    %{range | start: [line: line, column: col]}
  end
end
