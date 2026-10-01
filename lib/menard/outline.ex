defmodule Menard.Outline do
  @moduledoc """
  A source file as data: every module (nested ones under `modules`) with its moduledoc's first
  line, the lines it spans, and its defs — name, arity, kind (`def`/`defp`/`defmacro`/…), the head the clause verbs address, the
  `@doc` first line and `@spec` text that precede it, and the lines the clause spans. What an
  agent reads before it edits; the outline door is `mix menard.outline FILE`.
  """

  @kinds Menard.Tree.def_kinds()

  # A test file's content: its setups, tests and describes (each describe's tests under it), with
  # their lines. A module-level `for` that makes tests is looked through; nothing inside a test is
  # one: a `for` in a test body is a statement, which `stmt` reaches.
  @blocks [:setup, :setup_all, :test, :describe]

  @spec run(String.t()) :: {:ok, [map()]} | {:error, String.t()}
  def run(source) when is_binary(source) do
    with {:ok, ast} <- Menard.Source.parse(source), do: {:ok, modules(ast)}
  end

  # Top-level modules; a `defmodule` nested in a body lands under its parent's `modules`, with
  # the full name Elixir gives it (`Parent.Inner`).
  defp modules(ast, parent \\ nil)
  defp modules({:__block__, _, forms}, parent), do: Enum.flat_map(forms, &modules(&1, parent))

  defp modules({:defmodule, _, [name, [{_do, body}]]} = node, parent),
    do: [module(full_name(name, parent), body, node)]

  defp modules(_other, _parent), do: []

  defp full_name(name, nil), do: Macro.to_string(name)
  defp full_name(name, parent), do: parent <> "." <> Macro.to_string(name)

  defp module(name, body, node) do
    forms = body_forms(body)

    %{
      module: name,
      doc: attr_first_line(forms, :moduledoc),
      lines: lines(node),
      defs: defs(forms),
      tests: tests(forms),
      modules: Enum.flat_map(forms, &modules(&1, name))
    }
  end

  defp tests(forms), do: Enum.flat_map(forms, &test_entry/1)

  defp test_entry({:for, _, args}) when is_list(args) do
    case List.last(args) do
      [{{:__block__, _, [:do]}, body}] -> tests(body_forms(body))
      _ -> []
    end
  end

  defp test_entry({kind, _, [_ | _] = args} = node) when kind in @blocks do
    entry = %{kind: kind, label: test_label(kind, args), lines: lines(node)}
    if kind == :describe, do: [Map.put(entry, :tests, tests(block_body(args)))], else: [entry]
  end

  defp test_entry(_form), do: []

  defp test_label(kind, _args) when kind in [:setup, :setup_all], do: nil
  defp test_label(_kind, [{:__block__, _, [label]} | _]) when is_binary(label), do: label
  defp test_label(_kind, [label | _]), do: Sourceror.to_string(label)

  defp block_body(args) do
    case List.last(args) do
      [{{:__block__, _, [:do]}, body} | _] -> body_forms(body)
      _ -> []
    end
  end

  defp body_forms({:__block__, _, forms}), do: forms
  defp body_forms(form), do: [form]

  # Walk the body keeping the @doc/@spec, and a component's attr/slot lines, that precede each def; a
  # def consumes them.
  defp defs(forms) do
    forms
    |> Enum.reduce({[], nil, nil, []}, fn form, {acc, doc, spec, attrs} ->
      case form do
        {:@, _, [{:doc, _, [text]}]} ->
          {acc, string_first_line(text), spec, attrs}

        {:@, _, [{:spec, _, [expr]}]} ->
          {acc, doc, Sourceror.to_string(expr), attrs}

        {kind, _, [_ | _]} when kind in [:attr, :slot] ->
          # as written: without parens, as Phoenix's formatter plugin keeps them
          text = Sourceror.to_string(form, locals_without_parens: [attr: :*, slot: :*])
          {acc, doc, spec, attrs ++ [text |> String.split("\n") |> hd()]}

        {kind, _, [head | _]} = node when kind in @kinds ->
          {[def_entry(kind, head, doc, spec, node) |> Map.put(:attrs, attrs) | acc], nil, nil, []}

        _ ->
          {acc, doc, spec, attrs}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp def_entry(kind, head, doc, spec, node) do
    {name, arity} = name_arity(head)

    %{
      name: name,
      arity: arity,
      # the address the clause verbs take, so an edit needs no Read of the def line
      head: Menard.Clause.bare_head(head),
      kind: kind,
      doc: doc,
      spec: spec,
      lines: lines(node)
    }
  end

  defp name_arity(head), do: Menard.Tree.name_arity(head)

  defp attr_first_line(forms, attr) do
    Enum.find_value(forms, fn
      {:@, _, [{^attr, _, [text]}]} -> string_first_line(text)
      _ -> nil
    end)
  end

  # A doc is a string literal Sourceror wraps in a `:__block__`; `false` (no doc) reads as nil.
  defp string_first_line({:__block__, _, [text]}) when is_binary(text), do: text |> String.split("\n") |> hd()
  defp string_first_line(_other), do: nil

  defp lines(node), do: Menard.Tree.line_span(node)
end
