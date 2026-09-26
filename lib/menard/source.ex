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
        # A line inside a multi-line string, sigil or heredoc is part of its value: moving it changes
        # the program. Only the lines of code around them move.
        content = code |> String.trim() |> literal_lines()
        lines = Enum.with_index(rest, 2)
        movable = for {line, i} <- lines, i not in content, do: line

        # Already at or past `indent`: placed for here, and left as it is. Dropping the indent they
        # share assumed the shallowest sat at the base, and pulled lines left when every one sat deeper.
        shift = shared_indent(movable)

        rest =
          if shift >= String.length(indent),
            do: rest,
            else: Enum.map(lines, &move_code(&1, content, shift, indent))

        Enum.join([first | rest], "\n")
    end
  end

  defp move_code({line, i}, content, shift, indent) do
    if i in content, do: line, else: move(line, shift, indent)
  end

  defp move(line, shift, indent) do
    if String.trim(line) == "", do: "", else: indent <> String.slice(line, shift..-1//1)
  end

  # The lines of `code` (1-based) inside a literal that spans several: after the line it opens on,
  # through the line it closes on. A `->` arm (a statement `stmt` reaches) parses only inside a
  # `fn`, which opens on the arm's own first line, so the numbers hold. Code that parses neither way
  # has none found, and moves whole.
  defp literal_lines(code) do
    parsed =
      with {:error, _} <- Sourceror.parse_string(code),
           do: Sourceror.parse_string("fn " <> code <> "\nend")

    case parsed do
      {:ok, ast} -> ast |> Macro.prewalker() |> Enum.flat_map(&inner_lines/1) |> MapSet.new()
      {:error, _} -> MapSet.new()
    end
  end

  defp inner_lines(node) do
    if literal?(node), do: lines_after_first(Sourceror.get_range(node)), else: []
  end

  defp lines_after_first(%{start: [line: a, column: _], end: [line: b, column: _]}) when b > a,
    do: Enum.to_list((a + 1)..b)

  defp lines_after_first(_range), do: []

  defp literal?({:__block__, meta, [value]}) when is_binary(value) or is_list(value),
    do: meta[:delimiter] != nil

  defp literal?({:<<>>, meta, _parts}), do: meta[:delimiter] != nil

  defp literal?({sigil, _meta, _args}) when is_atom(sigil),
    do: String.starts_with?(Atom.to_string(sigil), "sigil_")

  defp literal?(_node), do: false

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
      range -> range |> earliest_start(node) |> clamp(source) |> past_strings(node, source)
    end
  end

  # Sourceror ends an interpolated string with escaped quotes (`"n: \"#{x}\"} y"`) one column short
  # of its closing quote, and every node that ends in one inherits it: an insert after such a
  # statement went INSIDE the string, where it still parsed. The true end is the string's own
  # closing quote, found by reading it from its opening one.
  defp past_strings(range, node, source) do
    lines = String.split(source, "\n")
    now = {range.end[:line], range.end[:column]}

    ends =
      for {:<<>>, meta, _parts} = string <- node |> Macro.prewalker() |> Enum.to_list(),
          meta[:delimiter] == "\"",
          %{start: start} <- [Sourceror.get_range(string)],
          stop = string_end(lines, start),
          stop != nil,
          do: stop

    case Enum.max(ends, fn -> nil end) do
      {line, column} = stop when stop > now -> %{range | end: [line: line, column: column]}
      _ -> range
    end
  end

  # `{line, column}` just past the closing quote of the string opening at `line:column`, honoring
  # `\` escapes and `#{…}` interpolations (a string inside one is skipped whole); nil if unclosed.
  # Read lazily, up to the closing quote: read to the end of the file, a node with many strings in
  # it cost the rest of the file once per string.
  defp string_end(lines, line: line, column: column) do
    lines
    |> Enum.drop(line - 1)
    |> Stream.with_index(line)
    |> Stream.flat_map(fn {text, no} ->
      text
      |> String.graphemes()
      |> Stream.with_index(1)
      |> Stream.map(fn {g, c} -> {g, no, c} end)
      |> Stream.concat([{"\n", no, String.length(text) + 1}])
    end)
    |> Stream.drop(column - 1)
    |> Enum.reduce_while(:open, &scan_string/2)
    |> case do
      {:closed, stop} -> stop
      _unclosed -> nil
    end
  end

  # The state is `{depths, pending}`: the interpolation depth of each string open, innermost first
  # (a `"` inside `#{…}` opens another), and whether the last grapheme was a `\` or a `#`.
  defp scan_string({"\"", _, _}, :open), do: {:cont, {[0], nil}}
  defp scan_string(_g, :open), do: {:halt, nil}
  defp scan_string(_escaped, {depths, :escape}), do: {:cont, {depths, nil}}
  defp scan_string({"{", _, _}, {[0 | outer], :hash}), do: {:cont, {[1 | outer], nil}}
  defp scan_string(g, {depths, :hash}), do: scan_string(g, {depths, nil})
  defp scan_string({"\\", _, _}, {depths, nil}), do: {:cont, {depths, :escape}}
  defp scan_string({"\"", no, c}, {[0], nil}), do: {:halt, {:closed, {no, c + 1}}}
  defp scan_string({"\"", _, _}, {[0 | outer], nil}), do: {:cont, {outer, nil}}
  defp scan_string({"\"", _, _}, {depths, nil}), do: {:cont, {[0 | depths], nil}}
  defp scan_string({"#", _, _}, {[0 | _] = depths, nil}), do: {:cont, {depths, :hash}}
  defp scan_string({"{", _, _}, {[d | outer], nil}) when d > 0, do: {:cont, {[d + 1 | outer], nil}}
  defp scan_string({"}", _, _}, {[d | outer], nil}) when d > 0, do: {:cont, {[d - 1 | outer], nil}}
  defp scan_string(_g, state), do: {:cont, state}

  @doc """
  The Elixir in a `~H` sigil node: each `{…}` (braces counted) and `<%… %>`, as `{line, column,
  text}`, the text exactly as written between the delimiters. ~H is a string to the AST, so this
  is the only way into what its expressions call.
  """
  def heex_expressions(source, node) do
    %{start: [line: a, column: ca], end: [line: b, column: _]} = Sourceror.get_range(node)

    gs =
      source
      |> String.split("\n")
      |> Enum.slice((a - 1)..(b - 1)//1)
      |> Enum.join("\n")
      |> String.graphemes()
      |> Enum.drop(ca - 1)

    for {from, to} <- heex_regions(Enum.with_index(gs), :markup, nil, []) do
      {line, column} = advance({a, ca}, gs |> Enum.take(from) |> Enum.join())
      {line, column, gs |> Enum.slice(from, to - from) |> Enum.join()}
    end
  end

  @doc "The `{line, column}` just past `text`, written from `{line, column}`."
  def advance({line, column}, text) do
    case String.split(text, "\n") do
      [one] -> {line, column + String.length(one)}
      many -> {line + length(many) - 1, String.length(List.last(many)) + 1}
    end
  end

  defp heex_regions([], _state, _start, acc), do: Enum.reverse(acc)
  defp heex_regions([{"<", i}, {"%", _} | rest], :markup, _, acc), do: heex_regions(rest, :eex, i + 2, acc)
  defp heex_regions([{"{", i} | rest], :markup, _, acc), do: heex_regions(rest, {:brace, 1}, i + 1, acc)

  defp heex_regions([{"%", i}, {">", _} | rest], :eex, s, acc),
    do: heex_regions(rest, :markup, nil, [{s, i} | acc])

  defp heex_regions([{"{", _} | rest], {:brace, d}, s, acc), do: heex_regions(rest, {:brace, d + 1}, s, acc)

  defp heex_regions([{"}", i} | rest], {:brace, 1}, s, acc),
    do: heex_regions(rest, :markup, nil, [{s, i} | acc])

  defp heex_regions([{"}", _} | rest], {:brace, d}, s, acc), do: heex_regions(rest, {:brace, d - 1}, s, acc)
  defp heex_regions([_ | rest], state, s, acc), do: heex_regions(rest, state, s, acc)

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
