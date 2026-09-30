defmodule Menard.Clause do
  @moduledoc """
  The clause verbs: address one clause of `name/arity` by its head as written — the args, and the
  guard if any (`":b"`, `"x when is_integer(x)"`, parens optional) — then `replace_body/4`,
  `rewrite/4` (the whole clause, head included), `delete/4`, `insert_after/4` or `insert_before/4`.
  Patches from the clause's own source range (Sourceror), so the rest of the file is
  byte-identical. A miss names the clauses that exist. Whitespace in the head pattern is ignored.

  `insert_at/4` is the odd one out: it adds a whole new FUNCTION, which by definition has no
  sibling clause to address. (A new clause of an existing function is `insert_after/4` — name the
  sibling.)
  """

  import Menard.Source,
    only: [
      comment_lines_above: 2,
      dedent: 1,
      delete_lines: 3,
      indented: 2,
      parse: 1,
      patch: 2,
      patch: 3,
      reindent: 2
    ]

  import Menard.Tree,
    only: [definitions: 1, module_bodies: 1, module_scope: 2, modules: 1, start_line: 1]

  alias Sourceror.Zipper

  @kinds Menard.Tree.def_kinds()

  # A guard or a delegate has no body to replace: written as `defguard … do … end` it parses and
  # does not compile, the one thing these verbs must never leave behind.
  @bodiless [:defguard, :defguardp, :defdelegate]

  # Attributes written directly above a clause belong TO that clause, not to the file: delete the
  # clause and leave them behind and they re-attach to whatever follows — "redefining @impl
  # attribute previously set at line N", or a @spec describing a head that no longer exists.
  @attached [:doc, :impl, :spec, :deprecated, :dialyzer]

  @typedoc """
  One clause as the verbs address it: its kind and name (text), its head as written (`args`,
  `guard`, `head_text`; `bare_head` without `\\\\ default`s, `bare_args` without the guard too), where
  it sits (`range`, `indent`) and its node.
  """
  @type clause :: %{
          kind: atom(),
          name: String.t(),
          args: String.t(),
          guard: String.t() | nil,
          head_text: String.t(),
          bare_head: String.t(),
          bare_args: String.t(),
          range: Sourceror.Range.t(),
          indent: String.t(),
          node: Macro.t()
        }

  @doc "Replace the clause's body with `code` (one line → `, do:` form; more → a `do … end` block)."
  @spec replace_body(String.t(), String.t(), String.t(), String.t(), keyword()) ::
          String.t() | {:error, String.t()}
  def replace_body(source, name_arity, head, code, opts \\ []) do
    with :ok <- body_only(code),
         {:ok, clause} <- find(source, name_arity, head, opts),
         :ok <- has_body(clause) do
      body_edit(source, clause, code, name_arity, opts)
    end
  end

  defp has_body(%{kind: kind, name: name}) when kind in @bodiless,
    do: {:error, "`#{kind} #{name}` has no body to replace — `rewrite` replaces the whole #{kind}"}

  defp has_body(_clause), do: :ok

  # Only the body's bytes move, so a clause keeps its form. `do … end` holds anything. `, do:` holds
  # the new body only if it reads back as itself there — `do: if a, do: b, else: c` hands `else:` to
  # the def — so that is checked, and a body that does not fit turns the clause into `do … end`.
  # `rescue`/`after`/… beside a `do:` would need the same care, and is refused toward `rewrite`.
  defp body_edit(
         source,
         %{node: {_kind, meta, [_head, [{_do, body} | rest]]}} = clause,
         code,
         name_arity,
         opts
       ) do
    range =
      body
      |> Menard.Source.range(source)
      |> Menard.Source.with_leading_comments(source, code)

    cond do
      meta[:do] ->
        source |> patch(range, reindent(code, clause.indent <> "  ")) |> blocks_once(name_arity, clause, opts)

      rest != [] ->
        {:error, "this clause has rescue/catch/after/else in keyword form — use `rewrite`"}

      true ->
        inline = patch(source, range, String.trim(code))

        if reads_back?(inline, source, clause, code),
          do: inline,
          else: patch(source, clause.range, clause_text(clause, code))
    end
  end

  defp body_edit(source, clause, code, _name_arity, _opts),
    do: patch(source, clause.range, clause_text(clause, code))

  # A `rescue`/`after`/… in CODE joins the clause's own; given twice, it parses and does not compile.
  defp blocks_once(out, name_arity, clause, opts) do
    with {:ok, %{node: {_kind, _meta, [_head, blocks]}}} when is_list(blocks) <-
           find(out, name_arity, clause.head_text, opts),
         keys = Enum.map(blocks, fn {{:__block__, _, [key]}, _} -> key end),
         [_ | _] = twice <- Enum.uniq(keys -- Enum.uniq(keys)) do
      {:error,
       "CODE carries its own #{Enum.join(twice, ", ")}, and the clause already has one — use `rewrite`"}
    else
      _ -> out
    end
  end

  # One parse of OUT answers both questions: does the clause's body read back as CODE, and does it
  # take a warning to — an unparenthesised call in a keyword is ambiguous to Elixir, which picks a
  # reading and says so. The source is parsed for its own warnings only when OUT has some.
  defp reads_back?(out, source, clause, code) do
    %{start: [line: line, column: column]} = clause.range

    with false <- String.contains?(String.trim(code), "\n"),
         {{:ok, ast}, warnings} <- Code.with_diagnostics(fn -> Code.string_to_quoted(out, columns: true) end),
         {{:ok, want}, _} <- Code.with_diagnostics(fn -> Code.string_to_quoted(code) end),
         {_kind, _meta, [_head, [do: body]]} <- def_at(ast, line, column) do
      no_meta(body) == no_meta(want) and (warnings == [] or length(warnings) <= parse_warnings(source))
    else
      _ -> false
    end
  end

  defp def_at(ast, line, column) do
    ast
    |> Macro.prewalk(nil, fn
      {kind, meta, _args} = node, nil when kind in @kinds ->
        {node, if(meta[:line] == line and meta[:column] == column, do: node)}

      node, found ->
        {node, found}
    end)
    |> elem(1)
  end

  defp no_meta(ast), do: Macro.prewalk(ast, &Macro.update_meta(&1, fn _meta -> [] end))

  defp parse_warnings(source) do
    {_result, diagnostics} = Code.with_diagnostics(fn -> Code.string_to_quoted(source) end)
    length(diagnostics)
  end

  @doc """
  Replace the WHOLE clause — head included — with `code`, a complete `def …`. The verb for the
  edits `replace_body/4` structurally cannot make: changing the args, adding a guard,
  destructuring a parameter.
  """
  @spec rewrite(String.t(), String.t(), String.t(), String.t(), keyword()) ::
          String.t() | {:error, String.t()}
  def rewrite(source, name_arity, head, code, opts \\ []) do
    with {:ok, clause} <- find(source, name_arity, head, opts),
         {:ok, node} <- parse_clause(code),
         {:ok, ast} <- parse(source),
         :ok <- keeps_function(ast, name_arity, clause, node) do
      {lead, body} = split_leading_comments(code)
      %{start: [line: def_line, column: _]} = clause.range
      above_attrs = attrs_start(ast, clause.range)

      cond do
        # code that carries its own @doc/@spec: those replace the ones above the clause, comments and all
        leading_attrs(code) ->
          {first, _last} = attached_span(ast, String.split(source, "\n"), clause)
          range = %{clause.range | start: [line: first + 1, column: 1]}
          patch(source, range, clause.indent <> reindent(code, clause.indent))

        # A comment over a clause with @impl/@doc/@spec goes above THOSE, as `comment/5` puts it: written
        # at the `def`, it would sit between the attributes and what they describe
        String.trim(lead) != "" and above_attrs < def_line and
            comment_lines_above(String.split(source, "\n"), def_line - 1) == 0 ->
          source
          |> patch(clause.range, reindent(body, clause.indent))
          |> comment_at(above_attrs, clause.indent, String.trim(lead))

        true ->
          patch_with_comments(source, clause, code)
      end
    end
  end

  # One clause of several stays a clause of THAT function: a defp among defs does not compile, and a
  # clause of another name/arity between them splits the function. The only clause IS the function,
  # free to change.
  defp keeps_function(ast, name_arity, clause, {kind, _meta, [head | _]}) do
    {:ok, {mod, name, arity}} = parse_name_arity(name_arity)
    {:ok, scope} = scope(ast, mod, name, arity)
    {new_name, new_arity} = name_arity(head)

    if match?([_], clauses(scope, name, arity)) or {kind, new_name, new_arity} == {clause.kind, name, arity} do
      :ok
    else
      {:error,
       "#{name}/#{arity} has other clauses, so this one stays `#{clause.kind} #{name}/#{arity}`, and CODE is " <>
         "`#{kind} #{new_name}/#{new_arity}` — `visibility` flips every clause; a new function goes in with `insert_at`"}
    end
  end

  defp patch_with_comments(source, clause, code) do
    range = with_comments_above(source, clause.range, code)
    # a range widened to the comments above starts at column 1, so the text brings its own indent
    indent = if range.start[:column] == 1, do: clause.indent, else: ""
    patch(source, range, indent <> reindent(code, clause.indent))
  end

  # The lines a clause OWNS: its `def`, the @doc/@spec/@impl written above it, and the comment above
  # those. Zero-based and inclusive. Shared by `delete/4` and `spans/2` (a move), which must agree exactly —
  # a doc left behind by one re-attaches to whatever definition follows it.
  defp attached_span(ast, lines, %{range: %{end: [line: b, column: _]}} = clause) do
    a = attrs_start(ast, clause.range)
    {a - 1 - comment_lines_above(lines, a - 1), b - 1}
  end

  # spans are zero-based, as `attached_span/3` counts them
  defp drop_spans(source, spans),
    do: Menard.Source.delete_lines(source, for({a, b} <- spans, do: {a + 1, b + 1}))

  # Take the blank line after the span too, but only when the span was blank-separated above as
  # well — otherwise removing the last clause of a run closes a gap that was never there.
  defp with_trailing_blank(lines, {first, last}) do
    # a blank left against the block's own `… do` or `end` is a gap the format stage then closes:
    # the one under the span goes when a blank, the file's start or the `do` is above it, and the
    # one over it when the `end` is below
    above = trimmed_at(lines, first - 1)
    below = trimmed_at(lines, last + 1)

    cond do
      below == "" and (above == "" or String.ends_with?(above, " do")) -> {first, last + 1}
      first > 0 and above == "" and below == "end" -> {first - 1, last}
      true -> {first, last}
    end
  end

  # before the file's first line there is nothing, not its last (Enum.at counts back from the end)
  defp trimmed_at(_lines, i) when i < 0, do: ""
  defp trimmed_at(lines, i), do: lines |> Enum.at(i, "") |> String.trim()

  # A function's clauses sit together, so their spans are one block to a reader and to the
  # blank-line rule — applied per clause it never fires, and the gap the function left stays open.
  # Non-adjacent spans stay separate: merging them would take whatever sits between.
  defp merge_spans(spans) do
    spans
    |> Enum.sort()
    |> Enum.reduce([], fn
      {a, b}, [{pa, pb} | rest] when a <= pb + 1 -> [{pa, max(pb, b)} | rest]
      span, acc -> [span | acc]
    end)
    |> Enum.reverse()
  end

  @doc """
  Delete the clause, the comment lines glued above it, and one blank line left behind. The function's
  last clause takes its @doc/@spec too; one clause of several leaves them for the clauses left.
  """
  @spec delete(String.t(), String.t(), String.t(), keyword()) :: String.t() | {:error, String.t()}
  def delete(source, name_arity, head, opts \\ []) do
    with {:ok, {mod, name, arity}} <- parse_name_arity(name_arity),
         {:ok, ast} <- parse(source),
         {:ok, scope} <- scope(ast, mod, name, arity),
         {:ok, clause} <- find(source, name_arity, head, opts) do
      lines = String.split(source, "\n")

      span =
        case clauses(scope, name, arity) do
          [_only] -> with_trailing_blank(lines, attached_span(ast, lines, clause))
          _several -> own_span(ast, lines, clause)
        end

      drop_spans(source, [span])
    end
  end

  # What ONE clause of several owns: its @impl and the comment above it. @doc, @spec and a
  # component's attr/slot describe the function, so they stay — and when they stay above, the blank
  # line after goes, or they sit apart from the clause they now attach to.
  defp own_span(ast, lines, %{range: %{end: [line: b, column: _]}} = clause) do
    a = attrs_start(ast, clause.range, &match?({:@, _, [{:impl, _, _}]}, &1))
    first = a - 1 - comment_lines_above(lines, a - 1)

    if attrs_start(ast, clause.range) < a and Enum.at(lines, b) == "",
      do: {first, b},
      else: with_trailing_blank(lines, {first, b - 1})
  end

  @doc """
  Delete a whole function: every clause of `name_arity`, each with the @doc/@spec/@impl and comment
  lines that belong to it. What an agent means by deleting `f/2` with no head named.
  """
  @spec delete_function(String.t(), String.t()) :: String.t() | {:error, String.t()}
  def delete_function(source, name_arity) do
    with {:ok, {mod, name, arity}} <- parse_name_arity(name_arity),
         {:ok, ast} <- parse(source),
         {:ok, scope} <- scope(ast, mod, name, arity) do
      lines = String.split(source, "\n")

      case clauses(scope, name, arity) do
        [] ->
          {:error, "no function #{name}/#{arity} here"}

        all ->
          spans = all |> Enum.map(&attached_span(ast, lines, &1)) |> merge_spans()
          drop_spans(source, Enum.map(spans, &with_trailing_blank(lines, &1)))
      end
    end
  end

  @doc """
  The function's source as written, with the @doc/@spec/comment lines above it: every clause with no
  `head`, else the one `head` names. `%{code, lines: [first, last]}`. A function read without reading
  its file.
  """
  @spec get(String.t(), String.t(), String.t() | nil, keyword()) :: {:ok, map()} | {:error, String.t()}
  def get(source, name_arity, head, opts \\ []) do
    with {:ok, {mod, name, arity}} <- parse_name_arity(name_arity),
         {:ok, ast} <- parse(source),
         {:ok, scope} <- scope(ast, mod, name, arity),
         {:ok, clauses} <- got(source, scope, name_arity, name, arity, head, opts) do
      lines = String.split(source, "\n")

      {a, b} =
        clauses
        |> Enum.map(&attached_span(ast, lines, &1))
        |> merge_spans()
        |> Enum.reduce(fn {_, b}, {a, _} -> {a, b} end)

      {:ok, %{code: lines |> Enum.slice(a..b) |> Enum.join("\n") |> dedent(), lines: [a + 1, b + 1]}}
    end
  end

  defp got(_source, scope, _name_arity, name, arity, nil, _opts) do
    case clauses(scope, name, arity) do
      [] -> {:error, "no function #{name}/#{arity} here"}
      all -> {:ok, all}
    end
  end

  defp got(source, _scope, name_arity, _name, _arity, head, opts) do
    with {:ok, clause} <- find(source, name_arity, head, opts), do: {:ok, [clause]}
  end

  @doc "Insert `code` as a new clause on the line after the addressed one, at its indent."
  @spec insert_after(String.t(), String.t(), String.t(), String.t(), keyword()) ::
          String.t() | {:error, String.t()}
  def insert_after(source, name_arity, head, code, opts \\ []) do
    with {:ok, found} <- find(source, name_arity, head, opts) do
      {clause, gap} = edge(source, name_arity, found, code, &List.last/1)
      %{range: %{end: [line: b, column: c]}, indent: indent} = clause
      body = indent <> reindent(code, indent)
      at = %{start: [line: b, column: c], end: [line: b, column: c]}
      patch(source, at, gap <> body)
    end
  end

  @doc "Insert `code` as a new clause on the line before the addressed one, at its indent."
  @spec insert_before(String.t(), String.t(), String.t(), String.t(), keyword()) ::
          String.t() | {:error, String.t()}
  def insert_before(source, name_arity, head, code, opts \\ []) do
    with {:ok, ast} <- parse(source),
         {:ok, found} <- find(source, name_arity, head, opts) do
      {%{range: range, indent: indent}, gap} = edge(source, name_arity, found, code, &hd/1)
      lines = String.split(source, "\n")
      # Above the clause's @doc/@spec too, the block `delete/4` takes: a @doc attaches to whatever
      # definition FOLLOWS it, so landing between the two hands the doc to the new code.
      a = attrs_start(ast, range)
      a = a - comment_lines_above(lines, a - 1)
      body = indent <> reindent(code, indent)
      at = %{start: [line: a, column: 1], end: [line: a, column: 1]}
      patch(source, at, body <> gap)
    end
  end

  # A new clause of the SAME function goes beside the one named. A DIFFERENT function goes around
  # the whole of this one — after its last clause, before its first — and a blank line apart: landing
  # between two clauses splits the function, and a split function fails --warnings-as-errors.
  defp edge(source, name_arity, clause, code, pick) do
    with {:ok, {mod, name, arity}} <- parse_name_arity(name_arity),
         defined when defined not in [nil, {name, arity}] <- defines(code),
         {:ok, ast} <- parse(source),
         {:ok, scope} <- scope(ast, mod, name, arity),
         [_ | _] = all <- clauses(scope, name, arity) do
      {pick.(all), "\n\n"}
    else
      _ -> {clause, "\n"}
    end
  end

  defp defines(code) do
    case Sourceror.parse_string(code) do
      {:ok, {:__block__, _, [_ | _] = nodes}} -> nodes |> List.last() |> defined()
      {:ok, node} -> defined(node)
      _ -> nil
    end
  end

  defp defined({kind, _meta, [head | _]}) when kind in @kinds, do: name_arity(head)
  defp defined(_node), do: nil

  @doc """
  Insert `code` where there is NO sibling clause to anchor to — a whole new function, which
  `insert_after/4` cannot address because it takes an existing head. (A new *clause* of a function
  that already exists is still `insert_after/4`: name its sibling.)

  `where` is usually nil, and then the code decides: a `defp` lands after the module's last
  private function, a `def` after its last public one — where a reader goes looking for each.
  `:top`/`:bottom` override that with the module's first/last definition; an empty module takes
  the code just inside. `module` is `"Mod.Name"`, or nil in a file with exactly one module.
  """
  @spec insert_at(String.t(), String.t() | nil, :top | :bottom | nil, String.t()) ::
          String.t() | {:error, String.t()}
  def insert_at(source, module, where, code) do
    with {:ok, ast} <- parse(source),
         {:ok, node} <- module_scope(ast, module) do
      insert_into(source, ast, node, where, code)
    end
  end

  defp insert_into(source, ast, module_node, where, code) do
    case anchor(definitions(module_node), normalize_where(where), code) do
      nil -> insert_inside_empty(source, module_node, code)
      {sibling, side} -> anchor_insert(source, ast, sibling, side, code)
    end
  end

  @doc """
  The lines `name_arity` owns: every clause with the `@doc`, `@spec` and `@impl` written above it and
  the comment above those, as zero-based `{first, last}` spans in source order. What `Menard.Move`
  takes out of one file and into another — the half of a move that fails SILENTLY is an attachment
  left behind: a `@doc` re-attaches to whatever definition follows it, and a `@spec` describes a
  head that is gone.
  """
  @spec spans(String.t(), String.t()) ::
          {:ok, [{non_neg_integer(), non_neg_integer()}]} | {:error, String.t()}
  def spans(source, name_arity) do
    with {:ok, {mod, name, arity}} <- parse_name_arity(name_arity),
         {:ok, ast} <- parse(source),
         {:ok, scope} <- scope(ast, mod, name, arity) do
      case clauses(scope, name, arity) do
        [] ->
          {:error, "no #{name}/#{arity} in this file"}

        found ->
          lines = String.split(source, "\n")
          {:ok, found |> Enum.map(&attached_span(ast, lines, &1)) |> Enum.sort()}
      end
    end
  end

  @doc """
  `source` without `spans` (zero-based, as `spans/2` gives them), the gap each leaves closed as
  `delete/4` closes it — except a span `replace` maps to text, which that text stands in for: a
  moved function's `defdelegate`, where the function was.
  """
  @spec cut(String.t(), [{non_neg_integer(), non_neg_integer()}], %{
          optional({integer(), integer()}) => String.t()
        }) ::
          String.t()
  def cut(source, spans, replace \\ %{}) do
    lines = String.split(source, "\n")
    {kept, dropped} = Enum.split_with(spans, &Map.has_key?(replace, &1))
    # merged again once each has taken its blank line: two that took the same one overlapped, and
    # the second cut, made after the first, took the line under it (a module's `end`)
    drops =
      dropped
      |> merge_spans()
      |> Enum.map(&with_trailing_blank(lines, &1))
      |> merge_spans()
      |> Enum.map(&{&1, []})

    edits = drops ++ Enum.map(kept, &{&1, String.split(Map.fetch!(replace, &1), "\n")})

    edits
    |> Enum.sort_by(fn {{a, _b}, _text} -> a end, :desc)
    |> Enum.reduce(lines, fn {{a, b}, text}, acc ->
      {head, rest} = Enum.split(acc, a)
      head ++ text ++ Enum.drop(rest, b - a + 1)
    end)
    |> Enum.join("\n")
  end

  @doc """
  Flip a function's visibility — EVERY clause of it, in one patch. `def`↔`defp`, keeping the family
  (`defmacro`↔`defmacrop`, `defguard`↔`defguardp`).

  One verb rather than a rewrite per clause because a half-flipped function does not compile: the
  clauses of one name/arity must agree, so doing them one at a time leaves the module broken in
  between and unrecoverable if you stop. Going private also drops an attached `@doc` — Elixir
  discards docs on a private function and warns, which is a failed build under
  --warnings-as-errors.
  """
  @spec visibility(String.t(), String.t(), :public | :private) :: String.t() | {:error, String.t()}
  def visibility(source, name_arity, want) when want in [:public, :private] do
    with {:ok, {mod, name, arity}} <- parse_name_arity(name_arity),
         {:ok, ast} <- parse(source),
         {:ok, scope} <- scope(ast, mod, name, arity) do
      case clauses(scope, name, arity) do
        [] ->
          {:error, "no #{name}/#{arity} in this file"}

        # no defdelegatep exists: a silent no-op read as done
        [%{kind: :defdelegate} | _] ->
          {:error,
           "#{name}/#{arity} is a defdelegate, which is always public — `rewrite` it as a def to change that"}

        found ->
          source |> flip(found, want) |> drop_docs(name_arity, want)
      end
    end
  end

  # Where a new function goes. `:top`/`:bottom` are the module first/last definition, asked for
  # explicitly; with neither, the CODE says — a `defp` belongs after the last private function, a
  # `def` after the last public one, which is where a reader goes looking for it. Nothing to anchor
  # to at all is nil, and the caller puts it inside the bare module.
  defp anchor([], _where, _code), do: nil
  defp anchor(defs, :top, _code), do: {hd(defs), :top}
  defp anchor(defs, :bottom, _code), do: {List.last(defs), :bottom}

  defp anchor(defs, nil, code) do
    private? = private_kind?(kind_of(code))
    same_kind = Enum.filter(defs, &(private_kind?(node_kind(&1)) == private?))
    {List.last(same_kind) || List.last(defs), :bottom}
  end

  defp normalize_where(where) when where in [:top, :bottom], do: where
  defp normalize_where(nil), do: nil

  defp private_kind?(kind), do: kind in [:defp, :defmacrop, :defguardp]

  # The kind the code DEFINES — the last node, so a `@doc`/`@spec` written above the def is not
  # mistaken for the thing being inserted.
  defp kind_of(code) do
    case Sourceror.parse_string(code) do
      {:ok, {:__block__, _meta, nodes}} -> nodes |> List.last() |> node_kind()
      {:ok, node} -> node_kind(node)
      _ -> nil
    end
  end

  defp node_kind({kind, _meta, _args}) when is_atom(kind), do: kind
  defp node_kind(_node), do: nil

  # A new FUNCTION, unlike a new clause of an existing one, is separated from its neighbour by a
  # blank line — clauses of one function are glued, functions are not.
  # Above the definition's @doc/@spec and the comment above those, as `insert_before/5`: under them,
  # they describe the new function, and the old one is left with none (it parses, so nothing says so)
  defp anchor_insert(source, ast, node, :top, code) do
    %{start: [line: _, column: col]} = range = Sourceror.get_range(node)
    line = attrs_start(ast, range)
    line = line - comment_lines_above(String.split(source, "\n"), line - 1)
    at = %{start: [line: line, column: 1], end: [line: line, column: 1]}
    patch(source, at, indented(code, col) <> "\n\n")
  end

  defp anchor_insert(source, _ast, node, :bottom, code) do
    %{start: [line: _, column: col], end: [line: line, column: last_col]} = Sourceror.get_range(node)
    at = %{start: [line: line, column: last_col], end: [line: line, column: last_col]}
    patch(source, at, "\n\n" <> indented(code, col))
  end

  # Nothing to anchor to at all: just inside the module's own `end`, one level in from it.
  defp insert_inside_empty(source, node, code) do
    %{start: [line: _, column: col], end: [line: line, column: _]} = Sourceror.get_range(node)
    at = %{start: [line: line, column: 1], end: [line: line, column: 1]}
    patch(source, at, indented(code, col + 2) <> "\n")
  end

  # -- locating a clause ----------------------------------------------------

  @doc """
  Locate one clause (`t:clause/0`), or an error naming the heads that exist. `opts[:nth]` picks one
  of several clauses that share the head. Public so `Menard.Stmt` addresses a statement the same way
  — inside the clause you named, by what is written.
  """
  @spec find(String.t(), String.t(), String.t(), keyword()) :: {:ok, clause()} | {:error, String.t()}
  def find(source, name_arity, head, opts \\ []) do
    with {:ok, {mod, name, arity}} <- parse_name_arity(name_arity),
         {:ok, ast} <- parse(source),
         {:ok, scope} <- scope(ast, mod, name, arity) do
      clauses = scope |> clauses(name, arity) |> with_bodies()
      want = wanted_head(head, name, arity)
      exact = Enum.filter(clauses, &(want in [squash(&1.head_text), squash(&1.bare_head)]))
      # the guard left off still names a clause, when it isn't what tells the clauses apart
      unguarded = Enum.filter(clauses, &(want in [squash(&1.args), squash(&1.bare_args)]))

      candidates = if exact != [], do: exact, else: unguarded

      case candidates do
        [one] ->
          {:ok, one}

        [_ | _] = many ->
          pick_nth(many, name, arity, head, opts[:nth])

        # one clause has nothing to tell apart: any head, even the one it is about to get, means it
        [] when length(clauses) == 1 ->
          {:ok, hd(clauses)}

        [] ->
          by_part(clauses, want) || {:error, no_clause(source, name, arity, head, clauses)}
      end
    end
  end

  # A head with no body (`def run(edits, opts \\ [])`, there for its defaults) is no clause to get or
  # edit, where the function has clauses that have one: it shared their head, and was taken for one.
  defp with_bodies(clauses) do
    case Enum.filter(clauses, &match?({_kind, _meta, [_head, _body | _]}, &1.node)) do
      [] -> clauses
      bodied -> bodied
    end
  end

  # part of exactly one head, the argument that tells the clauses apart (`"TENOFF"`): that one
  defp by_part(clauses, want) do
    case Enum.filter(clauses, &(want != "" and String.contains?(squash(&1.head_text), want))) do
      [one] -> {:ok, one}
      _ -> nil
    end
  end

  # An agent reaches for a test by its label, as a name or as a head: say which call does reach it
  defp no_clause(source, name, arity, head, []) do
    guesses = [to_string(name), head |> String.trim() |> String.trim(~s("))]
    blocks = with {:error, _} <- Menard.Block.list(source), do: []

    cond do
      block = Enum.find(blocks, fn {_macro, label, _line} -> label in guesses end) ->
        {macro, label, _line} = block

        "no function #{name}/#{arity}: `#{macro} \"#{label}\"` is a macro call, not a function — " <>
          "reach it with `block replace FILE #{macro} --label \"#{label}\"` (or get, delete)"

      name in ["test", "describe", "setup", "setup_all"] ->
        "no function #{name}/#{arity}: `#{name}` is a macro, and its blocks are reached with `block` — " <>
          "`block {verb: \"get\", file, name: \"#{name}\"}` answers with every one, `label` picks one"

      # clause t/0 for `@type t ::` (bench3 and bench4 not-compiling.B.haiku)
      source =~ ~r/@(type|typep|opaque)\s+#{name}\b/ ->
        "no function #{name}/#{arity}: `@type #{name}` is a type, a statement of the module — stmt reaches it " <>
          "with no clause named: `stmt {verb: \"replace\", file, name_arity: \"-\", match: \"@type #{name} ::\", code}`"

      true ->
        "no clause #{name}/#{arity} with head `#{head}` — have: none"
    end
  end

  defp no_clause(_source, name, arity, head, clauses),
    do: "no clause #{name}/#{arity} with head `#{head}` — have: #{heads(clauses)}"

  # `def go(x) do` and `def go(x), do:` are the def line as it stands: the `do` is not the head
  defp strip_do(head), do: String.replace(head, ~r/,?\s*\bdo:?\s*\z/, "")

  # A zero-arity clause has no head, so the name is what a caller would write. Arity 0 only: at
  # arity 1 `style` is an ARGUMENT.
  defp wanted_head(head, name, 0) do
    n = to_string(name)
    head = strip_do(head)

    if squash(head) in ["", squash(n), squash("#{n}()"), squash("def #{n}"), squash("def #{n}()")],
      do: "",
      else: squash(head)
  end

  # `def go(x)` and `go(x)` are what people copy off the def line; drop the name and what is left,
  # `(x)`, is the paren wrapper already tolerated. A call is not a pattern, so no head starts `go(`.
  defp wanted_head(head, name, _arity) do
    head
    |> strip_do()
    |> String.replace(~r/\A\s*(?:(?:defp?|defmacrop?)\s+)?#{Regex.escape(to_string(name))}(?=\s*\()/, "")
    |> squash()
  end

  # Acting on "the first" silently is how a delete eats the clause that was just written, so an
  # ambiguous head is refused and `--nth` is the way to mean one of them.
  defp pick_nth(many, name, arity, head, nil) do
    lines = Enum.map_join(many, ", ", fn c -> "line #{start_line_of(c)}: `#{c.head_text}`" end)

    {:error,
     "#{length(many)} clauses of #{name}/#{arity} share the head `#{head}` (#{lines}) — " <>
       "say which with --nth 1..#{length(many)}"}
  end

  defp pick_nth(many, name, arity, head, nth) do
    case Enum.at(many, nth - 1) do
      nil ->
        {:error, "--nth #{nth} is past the #{length(many)} clauses of #{name}/#{arity} with head `#{head}`"}

      clause ->
        {:ok, clause}
    end
  end

  defp start_line_of(%{range: %{start: [line: line, column: _]}}), do: line
  defp start_line_of(_clause), do: "?"

  # `code` must BE a clause: a bare expression would silently replace a def with an expression and
  # leave the module a compile error, which is the one thing these verbs must never do.
  # A clause and the comment glued above it are one unit to a reader, so `rewrite` takes both: the
  # comment lines split off for the parse check and patch back in with the clause.
  defp parse_clause(code) do
    {_comments, body} = split_leading_comments(code)

    case clause_form(code) do
      {:ok, defn, _attrs?} ->
        {:ok, defn}

      nil ->
        case Sourceror.parse_string(body) do
          {:error, reason} ->
            {:error, "not parseable — #{inspect(reason)}"}

          _ ->
            {:error, "rewrite needs a whole clause (`def …`), got: #{String.slice(String.trim(body), 0, 40)}"}
        end
    end
  end

  # Only a leading run that ENDS at the first real line counts, so a comment inside a body stays put.
  defp split_leading_comments(code) do
    lines = String.split(code, "\n")
    {lead, rest} = Enum.split_while(lines, &comment_or_blank?/1)

    {Enum.join(lead, "\n"), Enum.join(rest, "\n")}
  end

  # What a whole clause looks like as an agent writes it: a def, maybe under @doc/@spec/@impl lines,
  # maybe followed by more of the module (a new function beside it, rewritten in the same call:
  # long1 cart-refactor.B.sonnet). `{:ok, def, carries_attrs?}`, or nil.
  defp clause_form(code) do
    {_comments, body} = split_leading_comments(code)

    case Sourceror.parse_string(body) do
      {:ok, {kind, _, _} = defn} when kind in @kinds ->
        {:ok, defn, false}

      {:ok, {:__block__, _, nodes}} ->
        case Enum.split_while(nodes, &clause_attr?/1) do
          {attrs, [{kind, _, _} = defn | _]} when kind in @kinds -> {:ok, defn, attrs != []}
          _ -> nil
        end

      _ ->
        nil
    end
  end

  # `@doc`/`@spec`/`@impl` lines and then a def, as a whole clause is written with what it carries: the
  # def, when that is the shape (long1 cart-refactor.B.haiku nested one such in the old body)
  defp leading_attrs(code) do
    case clause_form(code) do
      {:ok, defn, true} -> {:ok, defn}
      _ -> nil
    end
  end

  defp clause_attr?({:@, _, [{name, _, _}]}), do: name in [:doc, :spec, :impl, :deprecated]
  # a component written whole starts with its `attr`/`slot` declarations (long2 cart-refactor.B.haiku)
  defp clause_attr?({macro, _, [{:__block__, _, [name]} | _]}) when macro in [:attr, :slot] and is_atom(name),
    do: true

  defp clause_attr?(_node), do: false

  defp comment_or_blank?(line) do
    trimmed = String.trim(line)
    trimmed == "" or String.starts_with?(trimmed, "#")
  end

  # The subtree to search: the named module's `defmodule`, or — unqualified — the whole file,
  # refused when more than one module in it defines name/arity (an edit must never land in the
  # wrong module silently).
  defp scope(ast, nil, name, arity) do
    case Enum.filter(modules(ast), fn {_mod, node} -> clauses(node, name, arity) != [] end) do
      [_, _ | _] = many ->
        {:error,
         "#{name}/#{arity} is defined in #{Enum.map_join(many, ", ", &elem(&1, 0))} — qualify it as Mod.#{name}/#{arity}"}

      [{_mod, node}] ->
        {:ok, node}

      [] ->
        {:ok, ast}
    end
  end

  defp scope(ast, mod, _name, _arity) do
    module_scope(ast, mod)
  end

  defp parse_name_arity(spec) do
    with [path, arity] <- String.split(spec, "/"),
         {arity, ""} <- Integer.parse(arity) do
      # `Mod.Sub.fun/2` scopes the search to that module; `fun/2` searches the whole file
      {mod, [name]} = path |> String.split(".") |> Enum.split(-1)
      {:ok, {if(mod == [], do: nil, else: Enum.join(mod, ".")), name, arity}}
    else
      _ -> {:error, "expected [Mod.]name/arity, got #{inspect(spec)}"}
    end
  end

  defp clauses(ast, name, arity) do
    # A nested `defmodule` is its own scope: `Outer.foo/1` must not reach `Outer.Inner.foo/1`.
    ast
    |> Zipper.zip()
    |> Zipper.traverse_while([], fn z, acc ->
      case Zipper.node(z) do
        {:defmodule, _, _} = node when node != ast -> {:skip, z, acc}
        node -> {:cont, z, acc ++ matching(node, name, arity)}
      end
    end)
    |> elem(1)
  end

  defp matching({kind, _meta, [head | _]} = node, name, arity) when kind in @kinds do
    if name_arity(head) == {name, arity}, do: [clause(kind, name, head, node)], else: []
  end

  defp matching(_node, _name, _arity), do: []

  defp clause(kind, name, head, node) do
    %{start: [line: _, column: col]} = range = Sourceror.get_range(node)
    {args, guard} = split_head(head)
    with_guard = fn text -> if(guard, do: text <> " when " <> guard, else: text) end

    %{
      kind: kind,
      name: name,
      args: args,
      guard: guard,
      head_text: with_guard.(args),
      # the head without its `\\ default`s — what a caller types, since the arity already says which
      bare_head: bare_head(head),
      # and without its guard too, which a caller may leave off
      bare_args: bare_args(head),
      range: range,
      indent: String.duplicate(" ", col - 1),
      node: node
    }
  end

  # The name as text, as `parse_name_arity` gives it: an input name is never made an atom.
  # `def unquote(name)(…)` has no name to read, and matches no name asked for.
  defp name_arity(head) do
    case Menard.Tree.name_arity(head) do
      {name, arity} when is_atom(name) -> {Atom.to_string(name), arity}
      other -> other
    end
  end

  # The head as written: `{args_text, guard_text | nil}`.
  defp split_head({:when, _, [call, guard]}), do: {elem(split_head(call), 0), Sourceror.to_string(guard)}

  defp split_head({_name, _, args}) when is_list(args),
    do: {Enum.map_join(args, ", ", &Sourceror.to_string/1), nil}

  defp split_head(_head), do: {"", nil}

  @doc """
  A head as the clause verbs address it: the arguments without their `\\\\ default`s, the guard kept.
  What a caller passes as HEAD, and what `outline` prints for each def.
  """
  def bare_head(head) do
    case split_head(head) do
      {_args, nil} -> bare_args(head)
      {_args, guard} -> bare_args(head) <> " when " <> guard
    end
  end

  defp bare_args({:when, _, [call | _]}), do: bare_args(call)

  defp bare_args({_name, _, args}) when is_list(args) do
    Enum.map_join(args, ", ", fn
      {:\\, _, [arg, _default]} -> Sourceror.to_string(arg)
      arg -> Sourceror.to_string(arg)
    end)
  end

  defp bare_args(_head), do: ""

  @doc """
  A head reduced to what tells heads apart: trimmed, one pair of parens wrapping it dropped, and no
  whitespace. Both sides of a head match go through it; `Menard.Stmt` keys statements with it too.
  """
  @spec squash(String.t()) :: String.t()
  def squash(text), do: text |> String.trim() |> unwrap_parens() |> String.replace(~r/\s+/, "")
  # `(dir, args)` IS how a head is written, so accept the parens people copy off the def line —
  # strip one pair when it actually wraps the whole head (`(a), (b)` is two args, not a wrapper,
  # and stays as it is).
  defp unwrap_parens("(" <> _rest = text) do
    case matching_close(text) do
      {:close, i} ->
        inner = text |> String.slice(1, i - 1) |> String.trim()
        rest = text |> String.slice((i + 1)..-1//1) |> String.trim()

        cond do
          # `(dir, args)` — the parens wrap the whole head
          rest == "" -> inner
          # `(x) when is_integer(x)` — they wrap the args, and the guard follows
          String.starts_with?(rest, "when ") -> inner <> " " <> rest
          # `(a), (b)` — not a wrapper at all; leave it exactly as given
          true -> text
        end

      :unclosed ->
        text
    end
  end

  defp unwrap_parens(text), do: text

  # The index of the `)` closing the `(` at position 0 — how far the leading paren actually reaches.
  defp matching_close(text) do
    text
    |> String.graphemes()
    |> Enum.with_index()
    |> Enum.reduce_while(0, fn
      {"(", _i}, depth -> {:cont, depth + 1}
      {")", i}, 1 -> {:halt, {:close, i}}
      {")", _i}, depth -> {:cont, depth - 1}
      {_char, _i}, depth -> {:cont, depth}
    end)
    |> case do
      {:close, i} -> {:close, i}
      _depth -> :unclosed
    end
  end

  defp heads([]), do: "none"

  defp heads(clauses) do
    Enum.map_join(clauses, " · ", fn
      %{head_text: ""} -> "`` (zero-arity — pass an empty head, or the name)"
      c -> "`#{c.head_text}`"
    end)
  end

  # CODE here is the BODY, and a whole `def` nests inside itself — `def bg, do: def(bg, do: X)`
  # parses, so only the compiler would object.
  defp body_only(code) do
    # a def is a whole clause, under comments or its @doc/@spec, and with more of the module after it
    if clause_form(code) do
      {:error,
       "CODE is the clause BODY here, and this looks like a whole clause — use `rewrite`, which replaces the head too"}
    else
      :ok
    end
  end

  # -- text -----------------------------------------------------------------

  defp clause_text(%{kind: kind, name: name, args: args, guard: guard, indent: indent}, code) do
    # zero arity is written WITHOUT parens in Elixir, and rewriting `def bg` as `def bg()` is a
    # diff on a line the caller did not ask to change
    head =
      if String.trim(args) == "", do: "#{kind} #{name}", else: "#{kind} #{name}(#{args})"

    head = head <> if(guard, do: " when " <> guard, else: "")
    lines = code |> String.trim() |> String.split("\n") |> Enum.map(&(indent <> "  " <> &1))
    Enum.join([head <> " do" | lines] ++ [indent <> "end"], "\n")
  end

  # The line a clause really starts on: its first ATTACHED attribute, walking back over the
  # contiguous `@doc`/`@impl`/`@spec` siblings written above it, else the `def` line itself. Only
  # CONTIGUOUS ones count, so deleting the middle clause of a function takes the `@impl` written
  # above THAT clause and leaves the `@doc` written above the first one alone.
  defp attrs_start(ast, %{start: [line: line, column: _]}, own? \\ fn _attr -> true end) do
    Enum.reduce(module_bodies(ast), line, fn statements, acc ->
      statements
      |> attached_above(line)
      |> Enum.take_while(own?)
      |> Enum.map(&start_line/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.min(fn -> acc end)
    end)
  end

  # The attributes attached above the statement that starts on `line`, nearest first: none when no
  # statement of this module body starts there.
  defp attached_above(statements, line) do
    case Enum.find_index(statements, &(start_line(&1) == line)) do
      nil -> []
      i -> statements |> Enum.take(i) |> Enum.reverse() |> Enum.take_while(&attached_attr?/1)
    end
  end

  defp attached_attr?({:@, _meta, [{name, _inner, _args}]}) when is_atom(name), do: name in @attached
  # A Phoenix component's `attr`/`slot` declarations belong to the def below as its @doc does: a
  # clause inserted before one landed between them and it (bench4 new-component.B.haiku), and a
  # component deleted or moved left them behind
  defp attached_attr?({macro, _meta, [{:__block__, _, [name]} | _]})
       when macro in [:attr, :slot] and is_atom(name),
       do: true

  defp attached_attr?(_node), do: false

  # The `def` keyword is the first token of the clause's own range, so each flip is a patch of
  # exactly that word — every other byte of every clause is untouched.
  defp flip(source, clauses, want) do
    patches =
      Enum.flat_map(clauses, fn clause ->
        new = kind_for(clause.kind, want)
        %{start: [line: line, column: col]} = clause.range

        if new == clause.kind do
          []
        else
          [
            %{
              range: %{
                start: [line: line, column: col],
                end: [line: line, column: col + String.length(Atom.to_string(clause.kind))]
              },
              change: Atom.to_string(new)
            }
          ]
        end
      end)

    patch(source, patches)
  end

  defp kind_for(:def, :private), do: :defp
  defp kind_for(:defmacro, :private), do: :defmacrop
  defp kind_for(:defguard, :private), do: :defguardp
  defp kind_for(:defp, :public), do: :def
  defp kind_for(:defmacrop, :public), do: :defmacro
  defp kind_for(:defguardp, :public), do: :defguard
  defp kind_for(kind, _want), do: kind

  # A `@doc` above a now-private clause is discarded by Elixir with a warning, so it goes with the
  # flip. `@spec` and `@impl` stay — both are legal on a defp.
  defp drop_docs(source, _name_arity, :public), do: source

  defp drop_docs(source, name_arity, :private) do
    with {:ok, {mod, name, arity}} <- parse_name_arity(name_arity),
         {:ok, ast} <- parse(source),
         {:ok, scope} <- scope(ast, mod, name, arity) do
      doomed =
        scope
        |> clauses(name, arity)
        |> Enum.flat_map(&doc_lines(ast, &1.range))
        |> MapSet.new()

      source
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.reject(&MapSet.member?(doomed, elem(&1, 1)))
      |> Enum.map_join("\n", &elem(&1, 0))
    else
      _ -> source
    end
  end

  # Every line of the `@doc` attached above this clause (a heredoc doc spans several).
  defp doc_lines(ast, %{start: [line: line, column: _]}) do
    Enum.flat_map(module_bodies(ast), fn statements ->
      statements
      |> attached_above(line)
      |> Enum.filter(&doc_attr?/1)
      |> Enum.flat_map(fn node ->
        %{start: [line: a, column: _], end: [line: b, column: _]} = Sourceror.get_range(node)
        Enum.to_list(a..b)
      end)
    end)
  end

  @doc """
  Set, replace, or with `spec` nil remove the `@spec` of `name_arity`. A spec belongs to the
  function, not to one clause, so there is no HEAD: it sits above the first clause, below its
  `@doc`. `spec` is the signature (`go(integer()) :: atom()`); a leading `@spec ` is dropped.
  """
  @spec spec(String.t(), String.t(), String.t() | nil) :: String.t() | {:error, String.t()}
  def spec(source, name_arity, spec) do
    with {:ok, {mod, name, arity}} <- parse_name_arity(name_arity),
         {:ok, ast} <- parse(source),
         {:ok, scope} <- scope(ast, mod, name, arity) do
      case clauses(scope, name, arity) do
        [] -> {:error, "no #{name}/#{arity} in this file"}
        [first | _] -> set_spec(source, ast, first, spec)
      end
    end
  end

  defp set_spec(source, ast, first, spec) do
    rendered =
      spec && first.indent <> "@spec " <> (spec |> String.trim() |> String.replace_prefix("@spec ", ""))

    %{start: [line: line, column: _]} = first.range

    case {attached_lines(ast, first.range, :spec), rendered} do
      {nil, nil} -> source
      {nil, _} -> insert_at_line(source, line, rendered)
      {{a, b}, nil} -> delete_lines(source, a, b)
      {{a, b}, _} -> replace_line_range(source, a, b, rendered)
    end
  end

  defp insert_at_line(source, line, text) do
    lines = String.split(source, "\n")
    {before, rest} = Enum.split(lines, line - 1)

    Enum.join(before ++ [text] ++ rest, "\n")
  end

  # When the replacement carries its own leading comment, the range grows upward to swallow the
  # comment already glued above the clause — otherwise the old why and the new one both survive.
  defp with_comments_above(source, range, code) do
    case split_leading_comments(code) do
      {"", _body} ->
        range

      {_lead, _body} ->
        %{start: [line: line, column: _]} = range
        lines = String.split(source, "\n")
        above = comment_lines_above(lines, line - 1)

        put_in(range.start, line: line - above, column: 1)
    end
  end

  defp replace_line_range(source, a, b, text) do
    lines = String.split(source, "\n")

    (Enum.take(lines, a - 1) ++ [text] ++ Enum.drop(lines, b))
    |> Enum.join("\n")
  end

  # The `#` comment block immediately above line `anchor`: written, replaced, or — with `text` nil —
  # removed. Where `rewrite` puts the comment the new clause came with.
  defp comment_at(source, anchor, indent, text) do
    above = source |> String.split("\n") |> comment_lines_above(anchor - 1)

    case {above, text} do
      {0, nil} -> source
      {0, _} -> insert_at_line(source, anchor, comment_text(text, indent))
      {n, nil} -> delete_lines(source, anchor - n, anchor - 1)
      {n, _} -> replace_line_range(source, anchor - n, anchor - 1, comment_text(text, indent))
    end
  end

  defp comment_text(text, indent) do
    pad = if is_integer(indent), do: String.duplicate(" ", indent), else: indent

    text
    |> String.trim_trailing()
    |> String.split("\n")
    |> Enum.map_join("\n", fn line ->
      case line |> String.trim() |> String.replace_prefix("#", "") |> String.trim_leading() do
        "" -> pad <> "#"
        body -> pad <> "# " <> body
      end
    end)
  end

  # The lines of the `@name` attached above the clause at `range`, or nil.
  defp attached_lines(ast, %{start: [line: line, column: _]}, name) do
    Enum.reduce(module_bodies(ast), nil, fn statements, acc ->
      case statements |> attached_above(line) |> Enum.find(&match?({:@, _, [{^name, _, _}]}, &1)) do
        nil -> acc
        node -> line_span(node)
      end
    end)
  end

  # LINE numbers, not the node range: a heredoc `@doc` ends at a column Sourceror places past the
  # closing quotes, and patching that range swallowed the newline after it (`"""  @spec`). An
  # attribute owns whole lines, so whole lines are what gets replaced.
  defp line_span(node) do
    %{start: [line: a, column: _], end: [line: b, column: _]} = Sourceror.get_range(node)
    {a, b}
  end

  defp doc_attr?({:@, _meta, [{:doc, _inner, _args}]}), do: true
  defp doc_attr?(_node), do: false
end
