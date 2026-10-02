defmodule Menard.Tree do
  @moduledoc """
  The parsed file as modules and definitions: which `defmodule` a verb acts in, what that module's
  body holds, and what a definition's head says. Every verb walks this before it edits, and every
  verb walks it the same way, so `Foo.go/1` names the same node to `clause`, `deps` and `outline`.

  `Menard.Source` owns the bytes and the ranges (`parse/1`, `range/2`, `patch/3`); this owns the
  tree those give. Line numbers here are Sourceror's own, read for a report or a whole-line edit:
  a range a verb PATCHES comes from `Menard.Source.range/2`, which corrects Sourceror's columns.
  """

  @def_kinds [:def, :defp, :defmacro, :defmacrop, :defguard, :defguardp, :defdelegate]

  @doc """
  The kinds a definition is written as. One list for every verb: `clause` addresses these,
  `outline` lists them, `attr` places a table above the first of them, `block` does not walk into
  them, `find`, `deps` and `rename` know a head by them. A `defdelegate` is one: it defines a
  function of the module, which a call resolves to and an outline lists; the kinds without a body
  (`defguard`, `defguardp`, `defdelegate`) are what `clause replace` refuses toward `rewrite`.
  """
  @spec def_kinds() :: [atom()]
  def def_kinds, do: @def_kinds

  @doc "True for a `def`-family node, usable in a guard: `when is_def(kind)`."
  defguard is_def(kind) when kind in @def_kinds

  @doc """
  Every `defmodule` in the file as `{"Full.Name", node}`, in source order — a nested one by the
  name Elixir gives it (`Outer.Inner`), the name `outline` shows.
  """
  @spec modules(Macro.t()) :: [{String.t(), Macro.t()}]
  def modules(ast), do: modules_in(ast, nil)

  @doc """
  The module to act in: `name`d, or — nil — the file's one module. Several unnamed is refused,
  the same discipline as an unqualified name/arity two modules define: an edit must never land
  in the wrong module silently.
  """
  @spec module_scope(Macro.t(), String.t() | nil) :: {:ok, Macro.t()} | {:error, String.t()}
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

      # named by its last parts (`Tracker` for SymphonyElixir.Config.Schema.Tracker, up4 Symphony
      # 01): the one whose name ends so, where one does; several are named, not guessed between
      [] ->
        by_suffix(ast, module)

      # `if Code.ensure_loaded?(X) do defmodule M … else defmodule M … end`: an edit went to the first
      # whichever was meant
      many ->
        lines = Enum.map_join(many, ", ", &"line #{start_line(&1)}")

        {:error,
         "#{module} is defined #{length(many)} times here (#{lines}), which no verb can tell apart — `write` the file whole"}
    end
  end

  @doc "A module's top-level statements, in source order; `[]` for anything that is not a `defmodule`."
  @spec module_body(Macro.t()) :: [Macro.t()]
  def module_body({:defmodule, _, [_alias, [{_do, {:__block__, _, statements}}]]}), do: statements
  def module_body({:defmodule, _, [_alias, [{_do, statement}]]}), do: [statement]
  def module_body(_node), do: []

  @doc "The top-level statements of each module in the file: what `stmt`'s module fallback may reach."
  @spec module_bodies(Macro.t()) :: [[Macro.t()]]
  def module_bodies(ast), do: Enum.map(modules(ast), fn {_name, node} -> module_body(node) end)

  @doc "The module's own top-level definitions, in source order — a def nested inside another is not one."
  @spec definitions(Macro.t()) :: [Macro.t()]
  def definitions(node) do
    node |> module_body() |> Enum.filter(&match?({kind, _meta, _args} when is_def(kind), &1))
  end

  @doc """
  What a definition's head names: `{name, arity}`, the guard looked through (`def go(x) when …`)
  and `def go` (no parens) arity 0. The name is what the AST holds — an atom, or the node of
  `def unquote(name)(…)`, which names nothing a caller can ask for.
  """
  @spec name_arity(Macro.t()) :: {atom() | Macro.t(), non_neg_integer()}
  def name_arity({:when, _, [call | _]}), do: name_arity(call)
  def name_arity({name, _, args}) when is_list(args), do: {name, length(args)}
  def name_arity({name, _, _}), do: {name, 0}

  @doc "The line a node starts on, or nil where Sourceror has no range for it."
  @spec start_line(Macro.t()) :: pos_integer() | nil
  def start_line(node) do
    case line_span(node) do
      {line, _last} -> line
      nil -> nil
    end
  end

  @doc """
  The first and last LINE a node spans, or nil where Sourceror has no range for it. For whole-line
  edits (an attribute deleted, a block's lines) and reports: a heredoc's closing quotes end on the
  same line whatever column Sourceror gives them, so none of `Menard.Source.range/2`'s column
  fixes bear on it.
  """
  @spec line_span(Macro.t()) :: {pos_integer(), pos_integer()} | nil
  def line_span(node) do
    case Sourceror.get_range(node) do
      %{start: [line: a, column: _], end: [line: b, column: _]} -> {a, b}
      _ -> nil
    end
  end

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

  defp by_suffix(ast, module) do
    case for {name, _} <- modules(ast), String.ends_with?(name, "." <> module), uniq: true, do: name do
      [full] ->
        module_scope(ast, full)

      [_, _ | _] = ends ->
        {:error, "#{module} could be any of #{Enum.join(ends, ", ")}: name one"}

      [] ->
        {:error,
         "no module #{module} in this file — have: #{Enum.map_join(modules(ast), ", ", &elem(&1, 0))}"}
    end
  end
end
