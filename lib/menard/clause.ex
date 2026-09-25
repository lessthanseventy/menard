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

  import Menard.Source, only: [parse: 1, reindent: 2]
  alias Sourceror.Zipper

  @kinds [:def, :defp, :defmacro, :defmacrop, :defguard, :defguardp]

  # Attributes written directly above a clause belong TO that clause, not to the file: delete the
  # clause and leave them behind and they re-attach to whatever follows — "redefining @impl
  # attribute previously set at line N", or a @spec describing a head that no longer exists.
  @attached [:doc, :impl, :spec, :deprecated, :dialyzer]

  @doc "Replace the clause's body with `code` (one line → `, do:` form; more → a `do … end` block)."
  @spec replace_body(String.t(), String.t(), String.t(), String.t(), keyword()) ::
          String.t() | {:error, String.t()}
  def replace_body(source, name_arity, head, code, opts \\ []) do
    with :ok <- body_only(code),
         {:ok, clause} <- find(source, name_arity, head, opts) do
      body_edit(source, clause, code, name_arity, opts)
    end
  end

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

        if reads_back?(inline, source, name_arity, clause, code, opts),
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

  defp reads_back?(out, source, name_arity, clause, code, opts) do
    with false <- String.contains?(String.trim(code), "\n"),
         {:ok, %{node: {_kind, _meta, [_head, [{_do, body}]]}}} <-
           find(out, name_arity, clause.head_text, opts),
         {:ok, want} <- Sourceror.parse_string(code) do
      # parsed "right" can still be parsed with a warning: an unparenthesised call in a keyword is
      # ambiguous to Elixir, which picks a reading and says so
      Sourceror.to_string(body) == Sourceror.to_string(want) and parse_warnings(out) <= parse_warnings(source)
    else
      _ -> false
    end
  end

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
         {:ok, _node} <- parse_clause(code) do
      Sourceror.patch_string(source, [
        %{
          range: with_comments_above(source, clause.range, code),
          change: reindent(code, clause.indent),
          preserve_indentation: false
        }
      ])
    end
  end

  # The lines a clause OWNS: its `def`, the @doc/@spec/@impl written above it, and the comment above
  # those. Zero-based and inclusive. Shared by `delete/4` and `move/4`, which must agree exactly —
  # a doc left behind by one re-attaches to whatever definition follows it.
  defp attached_span(ast, lines, %{range: %{end: [line: b, column: _]}} = clause) do
    a = attrs_start(ast, clause.range)
    {a - 1 - comment_lines_above(lines, a - 1), b - 1}
  end

  defp drop_spans(lines, spans) do
    lines
    |> Enum.with_index()
    |> Enum.reject(fn {_l, i} -> Enum.any?(spans, fn {a, b} -> i >= a and i <= b end) end)
    |> Enum.map_join("\n", &elem(&1, 0))
  end

  # Take the blank line after the span too, but only when the span was blank-separated above as
  # well — otherwise removing the last clause of a run closes a gap that was never there.
  defp with_trailing_blank(lines, {first, last}) do
    if Enum.at(lines, last + 1) == "" and (first == 0 or Enum.at(lines, first - 1) == ""),
      do: {first, last + 1},
      else: {first, last}
  end

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

  defp dedent(text) do
    pad =
      text
      |> String.split("\n")
      |> Enum.reject(&(String.trim(&1) == ""))
      |> Enum.map(&(String.length(&1) - String.length(String.trim_leading(&1))))
      |> Enum.min(fn -> 0 end)

    text |> String.split("\n") |> Enum.map_join("\n", &String.slice(&1, pad..-1//1))
  end

  @doc "Delete the clause, the comment lines glued above it, and one blank line left behind."
  @spec delete(String.t(), String.t(), String.t(), keyword()) :: String.t() | {:error, String.t()}
  def delete(source, name_arity, head, opts \\ []) do
    with {:ok, ast} <- parse(source),
         {:ok, clause} <- find(source, name_arity, head, opts) do
      lines = String.split(source, "\n")
      span = attached_span(ast, lines, clause)
      drop_spans(lines, [with_trailing_blank(lines, span)])
    end
  end

  @doc "Insert `code` as a new clause on the line after the addressed one, at its indent."
  @spec insert_after(String.t(), String.t(), String.t(), String.t(), keyword()) ::
          String.t() | {:error, String.t()}
  def insert_after(source, name_arity, head, code, opts \\ []) do
    with {:ok, found} <- find(source, name_arity, head, opts) do
      {clause, gap} = edge(source, name_arity, found, code, &List.last/1)
      %{range: %{end: [line: b, column: c]}, indent: indent} = clause
      body = code |> String.split("\n") |> Enum.map_join("\n", &(indent <> &1))
      at = %{start: [line: b, column: c], end: [line: b, column: c]}
      Sourceror.patch_string(source, [%{range: at, change: gap <> body, preserve_indentation: false}])
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
      body = code |> String.split("\n") |> Enum.map_join("\n", &(indent <> &1))
      at = %{start: [line: a, column: 1], end: [line: a, column: 1]}
      Sourceror.patch_string(source, [%{range: at, change: body <> gap, preserve_indentation: false}])
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
  @spec insert_at(String.t(), String.t() | nil, :top | :bottom | String.t() | nil, String.t()) ::
          String.t() | {:error, String.t()}
  def insert_at(source, module, where, code) do
    with {:ok, ast} <- parse(source),
         {:ok, node} <- module_scope(ast, module) do
      case anchor(definitions(node), normalize_where(where), code) do
        nil -> insert_inside_empty(source, node, code)
        {sibling, side} -> anchor_insert(source, sibling, side, code)
      end
    end
  end

  @doc """
  Move EVERY clause of `name/arity` out of `source` and into `dest`, carrying the `@doc`, `@spec`
  and `@impl` written above it and the comment above those.

  The whole function, never one clause — half of it in each file is the same mistake
  `visibility/3` refuses. Attachments travel because that is the half of a move that fails
  SILENTLY: a `@doc` left behind re-attaches to whatever definition follows it, and a `@spec`
  left behind describes a head that is gone.

  Returns `{:ok, source_without_it, dest_with_it}`. Aliases and call sites are deliberately NOT
  touched — `deps FILE name/arity` names them, and which of them should travel is a judgement.
  """
  @spec move(String.t(), String.t(), String.t(), keyword()) ::
          {:ok, String.t(), String.t()} | {:error, String.t()}
  def move(source, dest, name_arity, opts \\ []) do
    with {:ok, {mod, name, arity}} <- parse_name_arity(name_arity),
         {:ok, ast} <- parse(source),
         {:ok, scope} <- scope(ast, mod, name, arity),
         {:ok, dest_ast} <- parse(dest),
         {:ok, dest_module} <- module_scope(dest_ast, opts[:module]) do
      case clauses(scope, name, arity) do
        [] ->
          {:error, "no #{name}/#{arity} in this file"}

        found ->
          lines = String.split(source, "\n")
          spans = Enum.map(found, &attached_span(ast, lines, &1))

          code =
            spans
            |> Enum.map_join("\n", fn {a, b} -> lines |> Enum.slice(a..b) |> Enum.join("\n") end)
            |> dedent()

          moved =
            case anchor(definitions(dest_module), normalize_where(nil), code) do
              nil -> insert_inside_empty(dest, dest_module, code)
              {sibling, side} -> anchor_insert(dest, sibling, side, code)
            end

          {:ok, drop_spans(lines, spans |> merge_spans() |> Enum.map(&with_trailing_blank(lines, &1))), moved}
      end
    end
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
        [] -> {:error, "no #{name}/#{arity} in this file"}
        found -> source |> flip(found, want) |> drop_docs(name_arity, want)
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
  defp normalize_where("top"), do: :top
  defp normalize_where("bottom"), do: :bottom
  defp normalize_where(_none), do: nil

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
  defp anchor_insert(source, node, :top, code) do
    %{start: [line: line, column: col]} = Sourceror.get_range(node)
    at = %{start: [line: line, column: 1], end: [line: line, column: 1]}
    patch(source, at, indented(code, col) <> "\n\n")
  end

  defp anchor_insert(source, node, :bottom, code) do
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

  defp indented(code, col) do
    indent = String.duplicate(" ", col - 1)
    code |> String.trim() |> String.split("\n") |> Enum.map_join("\n", &(indent <> &1))
  end

  defp patch(source, range, change),
    do: Sourceror.patch_string(source, [%{range: range, change: change, preserve_indentation: false}])

  # -- locating a clause ----------------------------------------------------

  @doc """
  Locate one clause: `%{kind, name, args, guard, head_text, range, indent}`, or an error naming the
  heads that exist. Public so `Menard.Stmt` addresses a statement the same way — inside the clause
  you named, by what is written.
  """
  def find(source, name_arity, head, opts) do
    with {:ok, {mod, name, arity}} <- parse_name_arity(name_arity),
         {:ok, ast} <- parse(source),
         {:ok, scope} <- scope(ast, mod, name, arity) do
      clauses = clauses(scope, name, arity)
      want = wanted_head(head, name, arity)

      case Enum.filter(clauses, &(want in [squash(&1.head_text), squash(&1.bare_head)])) do
        # no head, and only one clause: nothing to tell apart
        [] when want == "" and length(clauses) == 1 -> {:ok, hd(clauses)}
        [] -> {:error, "no clause #{name}/#{arity} with head `#{head}` — have: #{heads(clauses)}"}
        [one] -> {:ok, one}
        many -> pick_nth(many, name, arity, head, opts[:nth])
      end
    end
  end

  # A zero-arity clause has no head, so the name is what a caller would write. Arity 0 only: at
  # arity 1 `style` is an ARGUMENT.
  defp wanted_head(head, name, 0) do
    n = to_string(name)

    if squash(head) in ["", squash(n), squash("#{n}()"), squash("def #{n}"), squash("def #{n}()")],
      do: "",
      else: squash(head)
  end

  # `def go(x)` and `go(x)` are what people copy off the def line; drop the name and what is left,
  # `(x)`, is the paren wrapper already tolerated. A call is not a pattern, so no head starts `go(`.
  defp wanted_head(head, name, _arity) do
    head
    |> String.replace(~r/\A\s*(?:(?:defp?|defmacrop?)\s+)?#{Regex.escape(to_string(name))}(?=\s*\()/, "")
    |> squash()
  end

  # Acting on "the first" silently is how a delete eats the clause that was just written, so an
  # ambiguous head is refused and `--nth` is the way to mean one of them.
  defp pick_nth(many, name, arity, head, nil) do
    lines = Enum.map_join(many, ", ", fn c -> "line #{start_line_of(c)}" end)

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

    case Sourceror.parse_string(body) do
      {:ok, {kind, _meta, _args} = node} when kind in @kinds ->
        {:ok, node}

      {:ok, _other} ->
        {:error, "rewrite needs a whole clause (`def …`), got: #{String.slice(String.trim(body), 0, 40)}"}

      {:error, reason} ->
        {:error, "not parseable — #{inspect(reason)}"}
    end
  end

  # Only a leading run that ENDS at the first real line counts, so a comment inside a body stays put.
  defp split_leading_comments(code) do
    lines = String.split(code, "\n")
    {lead, rest} = Enum.split_while(lines, &comment_or_blank?/1)

    {Enum.join(lead, "\n"), Enum.join(rest, "\n")}
  end

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

  # Every `defmodule` in the file as `{"Full.Name", node}` — a nested one by the name Elixir gives it
  # (`Outer.Inner`), the name `outline` shows.
  def modules(ast), do: modules_in(ast, nil)

  defp modules_in({:defmodule, _, [{:__aliases__, _, parts} | _] = args} = node, parent) do
    name =
      case {parts, parent} do
        {[{:__MODULE__, _, _} | _], _} -> Menard.Source.alias_name(parts, parent)
        {_, nil} -> Menard.Source.alias_name(parts)
        _ -> parent <> "." <> Menard.Source.alias_name(parts)
      end

    [{name, node} | modules_in(args, name)]
  end

  defp modules_in({form, _meta, args}, parent), do: modules_in(form, parent) ++ modules_in(args, parent)
  defp modules_in({a, b}, parent), do: modules_in(a, parent) ++ modules_in(b, parent)
  defp modules_in(list, parent) when is_list(list), do: Enum.flat_map(list, &modules_in(&1, parent))
  defp modules_in(_leaf, _parent), do: []

  # The module to act in: named, or — unnamed — the file's one module. Several unnamed is refused,
  # the same discipline as an unqualified name/arity two modules define.
  @doc false
  def module_scope(ast, nil) do
    case modules(ast) do
      [{_name, node}] -> {:ok, node}
      [] -> {:error, "no module in this file"}
      many -> {:error, "several modules here — name one: #{Enum.map_join(many, ", ", &elem(&1, 0))}"}
    end
  end

  def module_scope(ast, module) do
    case for {^module, node} <- modules(ast), do: node do
      [node] ->
        {:ok, node}

      [] ->
        {:error,
         "no module #{module} in this file — have: #{Enum.map_join(modules(ast), ", ", &elem(&1, 0))}"}

      # `if Code.ensure_loaded?(X) do defmodule M … else defmodule M … end`: an edit went to the first
      # whichever was meant
      many ->
        lines = Enum.map_join(many, ", ", &"line #{start_line(&1)}")

        {:error,
         "#{module} is defined #{length(many)} times here (#{lines}), which no verb can tell apart — `write` the file whole"}
    end
  end

  # The module's own top-level definitions, in source order — a def nested inside another is not one.
  defp definitions(node) do
    node |> module_body() |> Enum.filter(&match?({kind, _meta, _args} when kind in @kinds, &1))
  end

  @doc false
  def module_body({:defmodule, _, [_alias, [{_do, {:__block__, _, statements}}]]}), do: statements
  def module_body({:defmodule, _, [_alias, [{_do, statement}]]}), do: [statement]
  def module_body(_node), do: []

  defp parse_name_arity(spec) do
    with [path, arity] <- String.split(spec, "/"),
         {arity, ""} <- Integer.parse(arity) do
      # `Mod.Sub.fun/2` scopes the search to that module; `fun/2` searches the whole file
      {mod, [name]} = path |> String.split(".") |> Enum.split(-1)
      {:ok, {if(mod == [], do: nil, else: Enum.join(mod, ".")), String.to_atom(name), arity}}
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
      bare_head: with_guard.(bare_args(head)),
      range: range,
      indent: String.duplicate(" ", col - 1),
      node: node
    }
  end

  defp name_arity({:when, _, [call | _]}), do: name_arity(call)
  defp name_arity({name, _, args}) when is_list(args), do: {name, length(args)}
  defp name_arity({name, _, _}), do: {name, 0}

  # The head as written: `{args_text, guard_text | nil}`.
  defp split_head({:when, _, [call, guard]}), do: {elem(split_head(call), 0), Sourceror.to_string(guard)}

  defp split_head({_name, _, args}) when is_list(args),
    do: {Enum.map_join(args, ", ", &Sourceror.to_string/1), nil}

  defp split_head(_head), do: {"", nil}

  defp bare_args({:when, _, [call | _]}), do: bare_args(call)

  defp bare_args({_name, _, args}) when is_list(args) do
    Enum.map_join(args, ", ", fn
      {:\\, _, [arg, _default]} -> Sourceror.to_string(arg)
      arg -> Sourceror.to_string(arg)
    end)
  end

  defp bare_args(_head), do: ""

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
    if Regex.match?(~r/^\s*(def|defp|defmacro|defmacrop)\s/, code) do
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

  defp comment_lines_above(lines, i) do
    lines
    |> Enum.take(i)
    |> Enum.reverse()
    |> Enum.take_while(&String.starts_with?(String.trim_leading(&1), "#"))
    |> length()
  end

  # The line a clause really starts on: its first ATTACHED attribute, walking back over the
  # contiguous `@doc`/`@impl`/`@spec` siblings written above it, else the `def` line itself. Only
  # CONTIGUOUS ones count, so deleting the middle clause of a function takes the `@impl` written
  # above THAT clause and leaves the `@doc` written above the first one alone.
  defp attrs_start(ast, %{start: [line: line, column: _]}) do
    Enum.reduce(module_bodies(ast), line, fn statements, acc ->
      case Enum.find_index(statements, &(start_line(&1) == line)) do
        nil ->
          acc

        i ->
          statements
          |> Enum.take(i)
          |> Enum.reverse()
          |> Enum.take_while(&attached_attr?/1)
          |> Enum.map(&start_line/1)
          |> Enum.reject(&is_nil/1)
          |> Enum.min(fn -> acc end)
      end
    end)
  end

  defp module_bodies(ast), do: Enum.map(modules(ast), fn {_name, node} -> module_body(node) end)

  defp start_line(node) do
    case Sourceror.get_range(node) do
      %{start: [line: line, column: _]} -> line
      _ -> nil
    end
  end

  defp attached_attr?({:@, _meta, [{name, _inner, _args}]}) when is_atom(name), do: name in @attached
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
              change: Atom.to_string(new),
              preserve_indentation: false
            }
          ]
        end
      end)

    if patches == [], do: source, else: Sourceror.patch_string(source, patches)
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

      if Enum.empty?(doomed) do
        source
      else
        source
        |> String.split("\n")
        |> Enum.with_index(1)
        |> Enum.reject(fn {_text, line} -> MapSet.member?(doomed, line) end)
        |> Enum.map_join("\n", &elem(&1, 0))
      end
    else
      _ -> source
    end
  end

  # Every line of the `@doc` attached above this clause (a heredoc doc spans several).
  defp doc_lines(ast, %{start: [line: line, column: _]}) do
    Enum.flat_map(module_bodies(ast), fn statements ->
      case Enum.find_index(statements, &(start_line(&1) == line)) do
        nil ->
          []

        i ->
          statements
          |> Enum.take(i)
          |> Enum.reverse()
          |> Enum.take_while(&attached_attr?/1)
          |> Enum.filter(&doc_attr?/1)
          |> Enum.flat_map(fn node ->
            %{start: [line: a, column: _], end: [line: b, column: _]} = Sourceror.get_range(node)
            Enum.to_list(a..b)
          end)
      end
    end)
  end

  @doc """
  Set (or replace) the `@doc` attached to a clause. A docstring is a string literal on an
  attribute, so no other verb reaches it. `text` is the prose, not the `@doc` line: it is wrapped in
  a heredoc here. `nil` deletes the attribute.
  """
  @spec doc(String.t(), String.t(), String.t(), String.t() | nil, keyword()) ::
          String.t() | {:error, String.t()}
  def doc(source, name_arity, head, text, opts \\ []) do
    with {:ok, ast} <- parse(source),
         {:ok, clause} <- find(source, name_arity, head, opts) do
      existing = attached_lines(ast, clause.range, :doc)
      rendered = if is_nil(text), do: nil, else: clause.indent <> doc_text(text, clause.indent)

      case {existing, text} do
        {nil, nil} -> source
        {nil, _} -> insert_at_line(source, doc_start(ast, clause.range), rendered)
        {{a, b}, nil} -> delete_line_range(source, a, b)
        {{a, b}, _} -> replace_line_range(source, a, b, rendered)
      end
    end
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
        [] ->
          {:error, "no #{name}/#{arity} in this file"}

        [first | _] ->
          rendered =
            spec && first.indent <> "@spec " <> (spec |> String.trim() |> String.replace_prefix("@spec ", ""))

          %{start: [line: line, column: _]} = first.range

          case {attached_lines(ast, first.range, :spec), rendered} do
            {nil, nil} -> source
            {nil, _} -> insert_at_line(source, line, rendered)
            {{a, b}, nil} -> delete_line_range(source, a, b)
            {{a, b}, _} -> replace_line_range(source, a, b, rendered)
          end
      end
    end
  end

  # Where a NEW @doc goes: above the clause's attached attributes, so it lands over @impl/@spec
  # rather than between them and the def.
  defp doc_start(ast, range), do: attrs_start(ast, range)

  defp doc_text(text, indent) do
    pad = if is_integer(indent), do: String.duplicate(" ", indent), else: indent

    body =
      text
      |> String.trim_trailing()
      |> String.split("\n")
      |> Enum.map_join("\n", &if(&1 == "", do: "", else: pad <> &1))

    "@doc \"\"\"\n" <> body <> "\n" <> pad <> "\"\"\""
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

  @doc """
  Set, replace or delete the comment block glued above a clause — the load-bearing `why` that sits
  over a `def`. `text` is prose, one line per line; `#` is added (and an existing one tolerated, so
  pasting a block back is idempotent). A blank line becomes a bare `#`. `nil` deletes the block.

  `rewrite` can carry a comment too, but only by restating the whole clause; this changes the
  comment and nothing else.
  """
  @spec comment(String.t(), String.t(), String.t(), String.t() | nil, keyword()) ::
          String.t() | {:error, String.t()}
  def comment(source, name_arity, head, text, opts \\ []) do
    with {:ok, ast} <- parse(source),
         {:ok, clause} <- find(source, name_arity, head, opts) do
      %{start: [line: def_line, column: _]} = clause.range
      above_attrs = attrs_start(ast, clause.range)

      # Above the clause's ATTACHED attributes, not above the `def` — a `@doc` written between them
      # would orphan the comment from what it explains. But a comment already written between the
      # attributes and the def IS the clause's: replaced there, or the clause ends up with two.
      anchor =
        if above_attrs < def_line and comment_lines_above(String.split(source, "\n"), def_line - 1) > 0,
          do: def_line,
          else: above_attrs

      comment_at(source, anchor, clause.indent, text)
    end
  end

  @doc """
  The `#` comment block immediately above line `anchor`: written, replaced, or — with `text` nil —
  removed. Shared with `Menard.Attr.comment/4`, since an attribute's comment is the same edit at a
  different anchor.
  """
  @spec comment_at(String.t(), pos_integer(), non_neg_integer() | String.t(), String.t() | nil) :: String.t()
  def comment_at(source, anchor, indent, text) do
    above = source |> String.split("\n") |> comment_lines_above(anchor - 1)

    case {above, text} do
      {0, nil} -> source
      {0, _} -> insert_at_line(source, anchor, comment_text(text, indent))
      {n, nil} -> delete_line_range(source, anchor - n, anchor - 1)
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

  defp delete_line_range(source, a, b) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.reject(fn {_text, i} -> i >= a and i <= b end)
    |> Enum.map_join("\n", &elem(&1, 0))
  end

  defp replace_line_range(source, a, b, text) do
    lines = String.split(source, "\n")

    (Enum.take(lines, a - 1) ++ [text] ++ Enum.drop(lines, b))
    |> Enum.join("\n")
  end

  # The lines of the `@name` attached above the clause at `range`, or nil.
  defp attached_lines(ast, %{start: [line: line, column: _]}, name) do
    Enum.reduce(module_bodies(ast), nil, fn statements, acc ->
      case Enum.find_index(statements, &(start_line(&1) == line)) do
        nil ->
          acc

        i ->
          statements
          |> Enum.take(i)
          |> Enum.reverse()
          |> Enum.take_while(&attached_attr?/1)
          |> Enum.find(&match?({:@, _, [{^name, _, _}]}, &1))
          |> case do
            nil -> acc
            node -> line_span(node)
          end
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
