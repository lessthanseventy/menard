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

    %{range | end: [line: b, column: min(c, String.length(line) + 1)]}
  end

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
        rest =
          rest
          |> Enum.join("\n")
          |> dedent()
          |> String.split("\n")
          |> Enum.map(&if(String.trim(&1) == "", do: "", else: indent <> &1))

        Enum.join([first | rest], "\n")
    end
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
end
