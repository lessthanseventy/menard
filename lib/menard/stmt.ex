defmodule Menard.Stmt do
  @moduledoc """
  ONE statement inside a clause body.

  Addressed the way a clause is: you name the clause (`name_arity` + `head`), then the statement
  by what is WRITTEN (`Bus.subscribe_habits()`), whitespace-insensitive. A miss lists the
  statements that are there; a match that is ambiguous is refused with line numbers and `nth`,
  never guessed at.

  "Statement" is any addressable node inside the clause, so this reaches a line in a `do` block, a
  step in a `with`, and a `case` arm (`match -> body`) alike — the smallest node whose text
  matches wins, so naming a call does not accidentally select the block containing it.
  """
  import Menard.Source, only: [reindent: 2]
  alias Menard.Clause
  alias Sourceror.Zipper

  @doc "Insert `code` as a new statement directly after the matched one."
  @spec insert_after(String.t(), String.t(), String.t(), String.t(), String.t(), keyword()) ::
          String.t() | {:error, String.t()}
  def insert_after(source, name_arity, head, match, code, opts \\ []) do
    with {:ok, stmt} <- locate(source, name_arity, head, match, opts) do
      %{end: [line: line, column: col]} = stmt.range
      at = %{start: [line: line, column: col], end: [line: line, column: col]}
      patch(source, at, "\n\n" <> indent_block(code, stmt.indent))
    end
  end

  @doc "Insert `code` as a new statement directly before the matched one."
  @spec insert_before(String.t(), String.t(), String.t(), String.t(), String.t(), keyword()) ::
          String.t() | {:error, String.t()}
  def insert_before(source, name_arity, head, match, code, opts \\ []) do
    with {:ok, stmt} <- locate(source, name_arity, head, match, opts) do
      %{start: [line: line, column: _]} = stmt.range
      at = %{start: [line: line, column: 1], end: [line: line, column: 1]}
      patch(source, at, indent_block(code, stmt.indent) <> "\n\n")
    end
  end

  @doc "Replace the matched statement with `code`."
  @spec replace(String.t(), String.t(), String.t(), String.t(), String.t(), keyword()) ::
          String.t() | {:error, String.t()}
  def replace(source, name_arity, head, match, code, opts \\ []) do
    case locate(source, name_arity, head, match, opts) do
      {:ok, stmt} ->
        out = patch(source, stmt.range, reindent(code, stmt.indent))
        if whole_by_start?(stmt, match, out), do: {:error, by_start(stmt, match)}, else: out

      # not a statement: maybe an expression in the clause's ~H, which agents reach for here first
      {:error, _} = miss ->
        case in_template(source, name_arity, head, match, opts) do
          {:ok, expr} -> patch(source, expr.range, reindent(code, expr.indent))
          {:error, _} = refused -> refused
          :none -> miss
        end
    end
  end

  # `case x do` matches the whole case by its start, and code for that one line leaves one that does
  # not parse: say what was matched, where the write would only have said "missing terminator"
  defp whole_by_start?(stmt, match, out),
    do: key(stmt.text) != key(match) and match?({:error, _}, Code.string_to_quoted(out))

  defp by_start(%{range: %{start: [line: a, column: _], end: [line: b, column: _]}}, match),
    do:
      "`#{match}` matched, by its start, the whole statement on lines #{a}-#{b}, and `code` replaces all of " <>
        "it: what is left does not parse. Give `code` for the whole statement, or add a line with insert_before/insert_after"

  # The `{…}` and `<%= … %>` expressions of the ~H templates in the clause, matched as a statement
  # is: whitespace-insensitive, the whole expression or its start
  defp in_template(source, name_arity, head, match, opts) do
    with {:ok, clause} <- scope(source, name_arity, head, opts) do
      all =
        for {:sigil_H, _meta, _args} = node <- clause.node |> Macro.prewalker() |> Enum.to_list(),
            {line, column, code} <- Menard.Source.heex_expressions(source, node),
            text = String.trim(code),
            text != "" do
          [lead | _] = String.split(code, text, parts: 2)
          {sl, sc} = Menard.Source.advance({line, column}, lead)
          {el, ec} = Menard.Source.advance({sl, sc}, text)

          %{
            range: %{start: [line: sl, column: sc], end: [line: el, column: ec]},
            text: text,
            indent: String.duplicate(" ", sc - 1),
            span: el - sl
          }
        end

      case matching(all, key(match)) do
        [] -> template_text(source, clause, match)
        [one] -> {:ok, one}
        many -> nth(many, match, opts[:nth])
      end
    end
  end

  # Not one expression: any text of a template, a whole line of markup and all, found once as written
  defp template_text(source, clause, match) do
    want = String.trim(match)

    found =
      for {:sigil_H, _meta, _args} = node <- clause.node |> Macro.prewalker() |> Enum.to_list(),
          %{start: [line: a, column: ca]} = range = Sourceror.get_range(node),
          text = Menard.Source.slice(source, range),
          want != "",
          {at, _len} <- :binary.matches(text, want) do
        {sl, sc} = Menard.Source.advance({a, ca}, binary_part(text, 0, at))
        {el, ec} = Menard.Source.advance({sl, sc}, want)

        %{
          range: %{start: [line: sl, column: sc], end: [line: el, column: ec]},
          text: want,
          indent: String.duplicate(" ", sc - 1),
          span: el - sl
        }
      end

    case found do
      [] -> :none
      [one] -> {:ok, one}
      many -> nth(many, match, nil)
    end
  end

  @doc "Delete the matched statement, the comment lines glued above it, and a blank line left behind."
  @spec delete(String.t(), String.t(), String.t(), String.t(), keyword()) :: String.t() | {:error, String.t()}
  def delete(source, name_arity, head, match, opts \\ []) do
    with {:ok, stmt} <- locate(source, name_arity, head, match, opts) do
      lines = String.split(source, "\n")
      %{start: [line: a, column: _], end: [line: b, column: _]} = stmt.range
      first = a - 1 - comments_above(lines, a - 1)
      last = if Enum.at(lines, b) == "", do: b, else: b - 1

      lines
      |> Enum.with_index()
      |> Enum.reject(fn {_text, i} -> i >= first and i <= last end)
      |> Enum.map_join("\n", &elem(&1, 0))
    end
  end

  @doc """
  The statements this clause holds, as written — what a miss prints, and useful on its own before
  editing one.
  """
  @spec list(String.t(), String.t(), String.t(), keyword()) :: [String.t()] | {:error, String.t()}
  def list(source, name_arity, head, opts \\ []) do
    # the module is a scope to match in, not one to list: a clause that is not there stays a miss
    with {:ok, clause} <- scope(source, name_arity, head, opts),
         nil <- clause[:miss] do
      source |> candidates(clause) |> Enum.map(& &1.text)
    end
  end

  @doc """
  The `#` comment block above the matched statement — the why inside a body — set, replaced, or with
  `text` nil removed. The statement twin of `Menard.Clause.comment/5`.
  """
  @spec comment(String.t(), String.t(), String.t(), String.t(), String.t() | nil, keyword()) ::
          String.t() | {:error, String.t()}
  def comment(source, name_arity, head, match, text, opts \\ []) do
    with {:ok, stmt} <- locate(source, name_arity, head, match, opts) do
      %{start: [line: line, column: _]} = stmt.range
      Clause.comment_at(source, line, stmt.indent, text)
    end
  end

  # -- locating a statement -------------------------------------------------

  # The clause named, or, when that names none, the test or describe whose label is in `head`: an
  # agent reaches for a line of a test the way it reaches for one of a function
  defp scope(source, name_arity, head, opts) do
    with {:error, _} = miss <- Clause.find(source, name_arity, head, opts) do
      # the label where the head goes, or where the name goes: agents have written both
      labels =
        for text <- [head, name_arity |> to_string() |> String.replace(~r{/\d+\z}, "")],
            label = text |> to_string() |> String.trim() |> String.trim(~s(")),
            label != "",
            do: label

      case Enum.find_value(labels, &ok_block(source, &1)) do
        {:ok, node} -> {:ok, %{node: node, range: Menard.Source.range(node, source)}}
        # neither: the module itself, for `defstruct` or `@type t ::`; a miss there is the clause miss
        nil -> module_scope(source, miss, to_string(name_arity) in ["", "-"] and to_string(head) == "")
      end
    end
  end

  # The module when no clause or test is named. Something named that is not there reaches only the
  # module's own statements: reaching into a function or a test from there put a test inside a test
  # (bench4 bug-receipt-total.B.haiku, which named the function under test). Nothing named at all
  # ("" or "-") searches the whole file for the one statement written (bench5 move-function.B.haiku).
  defp module_scope(source, miss, anywhere?) do
    case Menard.Source.parse(source) do
      {:ok, ast} when anywhere? ->
        {:ok, %{node: ast, range: Menard.Source.range(ast, source)}}

      {:ok, ast} ->
        {:ok,
         %{
           node: ast,
           range: Menard.Source.range(ast, source),
           miss: miss,
           top: List.flatten(Clause.module_bodies(ast))
         }}

      _ ->
        miss
    end
  end

  defp ok_block(source, label) do
    with {:ok, _node} = found <- Menard.Block.labelled(source, label), do: found, else: (_ -> nil)
  end

  defp locate(source, name_arity, head, match, opts) do
    with {:ok, clause} <- scope(source, name_arity, head, opts) do
      want = key(match)
      all = candidates(source, clause)

      case matching(all, want) do
        [] ->
          clause[:miss] ||
            {:error,
             "no statement `#{match}` in #{name_arity} — have: #{have(all)}" <> inside_string(all, match)}

        [one] ->
          {:ok, one}

        many ->
          nth(many, match, opts[:nth])
      end
    end
  end

  # What a miss shows: the statement each line starts with, its first line only, and 20 at most.
  # Every nested node in full ran a miss in a long case to thousands of characters.
  defp have(all) do
    lines =
      all
      |> Enum.group_by(&line_of/1)
      |> Enum.sort()
      |> Enum.map(fn {_line, here} ->
        here |> Enum.min_by(&column_of/1) |> Map.fetch!(:text) |> String.split("\n") |> hd()
      end)

    {shown, rest} = Enum.split(lines, 20)
    more = if rest == [], do: "", else: " · … #{length(rest)} more: `list` shows them"
    Enum.map_join(shown, " · ", &"`#{&1}`") <> more
  end

  # A line of a ~H template or a heredoc is text, not a statement, and no verb reaches into it: an
  # agent that tried says so here, where it will look next
  defp inside_string(all, match) do
    if Enum.any?(all, &(&1.text =~ ~r/\A\s*(~[a-zA-Z]|")/ and String.contains?(&1.text, String.trim(match)))),
      do:
        " — that text is inside a string or sigil: `replace` reaches an expression in a ~H template's `{…}`, " <>
          "and anything else there is Edit's, which passes the guard when only text inside a string changes",
      else: ""
  end

  # The whole statement as written, or, when none is, the ones that start with it: `elixir_files =`
  # reaches a multi-line assignment without restating its pipeline.
  defp matching(all, want) do
    case Enum.filter(all, &(key(&1.text) == want)) do
      [] when want != "" -> Enum.filter(all, &String.starts_with?(key(&1.text), want))
      exact -> exact
    end
  end

  # What a statement is matched by: its text squashed, its comments left out. An agent writes the
  # statement as it means it, and a `# why` between a map's keys is not part of that (Tlön ticket 8).
  # The parser finds the comments, so a `#` in a string stays.
  defp key(text), do: text |> uncommented() |> Clause.squash()

  defp uncommented(text) do
    case Code.string_to_quoted_with_comments(text) do
      {:ok, _ast, [_ | _] = comments} ->
        at = Map.new(comments, &{&1.line, &1.column})

        text
        |> String.split("\n")
        |> Enum.with_index(1)
        |> Enum.map_join("\n", fn {line, i} -> if at[i], do: String.slice(line, 0, at[i] - 1), else: line end)

      _ ->
        text
    end
  end

  defp nth(many, match, nil) do
    # each by its first line as written, not a line number alone: which is which is the question
    found = Enum.map_join(many, ", ", &"`#{&1.text |> String.split("\n") |> hd()}` (line #{line_of(&1)})")

    {:error,
     "#{length(many)} statements match `#{match}`: #{found} — say which with --nth 1..#{length(many)}"}
  end

  defp nth(many, match, n) do
    case Enum.at(many, n - 1) do
      nil -> {:error, "--nth #{n} is past the #{length(many)} statements matching `#{match}`"}
      stmt -> {:ok, stmt}
    end
  end

  defp line_of(%{range: %{start: [line: line, column: _]}}), do: line

  defp column_of(%{range: %{start: [line: _, column: column]}}), do: column

  # Every node inside the clause that carries a range, smallest first — so naming a call selects
  # the call, not the block around it.
  defp candidates(source, clause) do
    # the module fallback: its own statements, not what they hold
    nodes =
      if top = clause[:top],
        do: top,
        else:
          clause.node
          # only the clause's own subtree: walking the whole file per call made stmt linear in the file
          |> Zipper.zip()
          |> Zipper.traverse([], fn z, acc -> {z, statement_nodes(Zipper.node(z)) ++ acc} end)
          |> elem(1)

    nodes
    |> Enum.flat_map(&describe(&1, source, clause))
    |> Enum.uniq_by(& &1.range)
    |> Enum.sort_by(&{line_of(&1), &1.span, column_of(&1)})
  end

  defp describe(node, source, clause) do
    case Menard.Source.range(node, source) do
      %{start: [line: a, column: col], end: [line: b, column: _]} = range ->
        if within?(range, clause.range) and not same_as?(range, clause.range) do
          [%{range: range, text: slice(source, range), indent: String.duplicate(" ", col - 1), span: b - a}]
        else
          []
        end

      _no_range ->
        []
    end
  end

  defp within?(%{start: [line: a, column: _], end: [line: b, column: _]}, %{
         start: [line: ca, column: _],
         end: [line: cb, column: _]
       }),
       do: a >= ca and b <= cb

  defp same_as?(%{start: s, end: e}, %{start: s2, end: e2}), do: s == s2 and e == e2

  defp slice(source, %{start: [line: a, column: ca], end: [line: b, column: cb]}) do
    lines = source |> String.split("\n") |> Enum.slice((a - 1)..(b - 1))

    case lines do
      [] ->
        ""

      [one] ->
        String.slice(one, ca - 1, cb - ca)

      many ->
        [first | rest] = many
        {mid, [last]} = Enum.split(rest, length(rest) - 1)
        Enum.join([String.slice(first, (ca - 1)..-1//1) | mid] ++ [String.slice(last, 0, cb - 1)], "\n")
    end
  end

  defp comments_above(lines, i) do
    lines
    |> Enum.take(i)
    |> Enum.reverse()
    |> Enum.take_while(&String.starts_with?(String.trim_leading(&1), "#"))
    |> length()
  end

  defp indent_block(code, indent), do: indent <> reindent(code, indent)

  defp patch(source, range, change),
    do: Sourceror.patch_string(source, [%{range: range, change: change, preserve_indentation: false}])

  # 2+ children means a SEQUENCE of statements. Sourceror also wraps literals in `__block__`, and a
  # one-child block is one of those (`{:ok, :up}`) — a body holding a single statement is reached
  # through its do-block instead.
  defp statement_nodes({:__block__, _meta, children}) when length(children) > 1, do: children
  # An anonymous fn is a list of `->` arms, not a do-block, so its body was unreachable — a call
  # inside `Enum.each(fn … -> … end)` had no verb. Its arms are statements, and so are theirs.
  defp statement_nodes({:fn, _meta, arms}) when is_list(arms), do: arms

  defp statement_nodes({:->, _meta, [_pattern, body]}), do: body_statements(body)

  defp statement_nodes({call, _meta, args}) when is_list(args) do
    case List.last(args) do
      [{{:__block__, _m, [key]}, _body} | _rest] = blocks when key in [:do, :else, :after, :catch, :rescue] ->
        # a `with`'s steps are statements too, and every block's body is, not the first alone: an
        # `else` arm or a `rescue` was unreachable
        steps = if call == :with, do: Enum.drop(args, -1), else: []
        steps ++ Enum.flat_map(blocks, fn {_key, body} -> body_statements(body) end)

      _other ->
        []
    end
  end

  defp statement_nodes(_node), do: []

  # A do-block holds either a `__block__` (many lines, collected above), a list of `->` arms, or one
  # bare expression.
  defp body_statements(arms) when is_list(arms), do: arms
  # One child is a literal Sourceror wrapped (`{:ok, x}`, `:error`) — a statement, not a sequence.
  defp body_statements({:__block__, _meta, [_one]} = literal), do: [literal]
  defp body_statements({:__block__, _meta, _children}), do: []
  defp body_statements(one), do: [one]
end
