defmodule Menard.Deps do
  @moduledoc """
  What one function actually references — the read before `clause move`.

  A moved function's body resolves against the SOURCE module's aliases, it may call private helpers
  other functions also need, and it may read the module's attributes. `clause move` carries what
  only it needs and refuses a helper it shares (`graph/1` is its read); this is the same answer for
  one function, asked before.

  `of/3` returns `%{locals, remotes, modules, attributes}`. `locals` is the part that decides the
  question: each is a function of THIS module that the queried one calls, with `shared_with` —
  every other function here that also calls it. A local with an empty `shared_with` can travel; one
  with entries cannot, and the source module has to keep (and probably publicise) it.
  """

  import Menard.Source, only: [parse: 1]
  alias Menard.Tree
  alias Sourceror.Zipper

  @kinds Tree.def_kinds()

  @type report :: %{
          locals: [%{call: String.t(), shared_with: [String.t()]}],
          remotes: [String.t()],
          modules: [String.t()],
          attributes: [atom()]
        }

  @doc "What `name/arity` references. `module` names which module in a file that has several."
  @spec of(String.t(), String.t(), keyword()) :: report() | {:error, String.t()}
  def of(source, name_arity, opts \\ []) do
    with {:ok, want} <- split(name_arity),
         {:ok, ast} <- parse(source),
         {:ok, module} <- Tree.module_scope(ast, opts[:module]) do
      defs = definitions(module)

      case Enum.filter(defs, &(key(&1) == want)) do
        [] ->
          {:error,
           "no #{name(want)} in this module — have: #{Enum.map_join(Enum.uniq(Enum.map(defs, &name(key(&1)))), ", ", & &1)}"}

        mine ->
          report(mine, defs, want)
      end
    end
  end

  @doc """
  Every function the module node defines, by `{name, arity}`: its `kind`, its clauses (`nodes`) and
  the `calls` they make to functions of the module — what `clause move` decides from which helpers
  travel with a function and which are shared with one that stays.
  """
  @spec graph(Macro.t()) :: %{{atom(), arity()} => %{kind: atom(), nodes: [Macro.t()], calls: MapSet.t()}}
  def graph(module) do
    defs = definitions(module)
    defined = defined(defs)

    defs
    |> Enum.group_by(&key/1, fn {_key, node} -> node end)
    |> Map.new(fn {key, [{kind, _, _} | _] = nodes} ->
      calls = Enum.reduce(nodes, empty(), &collect/2).calls
      {key, %{kind: kind, nodes: nodes, calls: own(calls, defined)}}
    end)
  end

  @doc """
  The function of `graph` that a call to `name/arity` reaches: the one of that arity, else one with
  more arguments whose defaults make up the difference (`record(a, b, c \\\\ :x)` called as
  record/2). nil when the module defines neither.
  """
  @spec reached(%{{atom(), arity()} => map()}, {atom(), arity()}) :: {atom(), arity()} | nil
  def reached(graph, call),
    do: resolve(call, defined(for {key, %{nodes: nodes}} <- graph, n <- nodes, do: {key, n}))

  # every function defined, with how few arguments a call to it may give
  defp defined(defs) do
    defs
    |> Enum.group_by(&key/1, fn {_key, {_kind, _meta, [head | _]}} -> defaults(head) end)
    |> Map.new(fn {{_name, arity} = key, defaults} -> {key, arity - Enum.max(defaults)} end)
  end

  defp defaults({:when, _meta, [call | _guard]}), do: defaults(call)
  defp defaults({_name, _meta, args}) when is_list(args), do: Enum.count(args, &match?({:\\, _, [_, _]}, &1))
  defp defaults(_head), do: 0

  defp resolve({name, arity} = call, defined) do
    if is_map_key(defined, call) do
      call
    else
      Enum.find(Map.keys(defined), fn {n, a} = key -> n == name and a > arity and defined[key] <= arity end)
    end
  end

  # the calls that are to this module's own functions, each as the function it reaches
  defp own(calls, defined) do
    for call <- calls, key = resolve(call, defined), into: MapSet.new(), do: key
  end

  defp report(mine, defs, want) do
    refs = Enum.reduce(mine, empty(), fn {_key, node}, acc -> collect(node, acc) end)

    locals =
      refs.calls
      |> own(defined(defs))
      |> Enum.reject(&(&1 == want))
      |> Enum.sort()
      |> Enum.map(fn call -> %{call: name(call), shared_with: shared_with(defs, call, want)} end)

    %{
      locals: locals,
      remotes: refs.remotes |> Enum.uniq() |> Enum.sort(),
      modules: refs.modules |> Enum.uniq() |> Enum.sort(),
      attributes: refs.attributes |> Enum.uniq() |> Enum.sort()
    }
  end

  # Which OTHER functions of this module call `target` — the reason a helper cannot simply travel
  # with the function being moved.
  defp shared_with(defs, target, want) do
    defs
    |> Enum.reject(&(key(&1) == want))
    |> Enum.filter(fn {_key, node} -> target in own(collect(node, empty()).calls, defined(defs)) end)
    |> Enum.map(&name(key(&1)))
    |> Enum.uniq()
    |> Enum.sort()
  end

  # -- walking a body -------------------------------------------------------

  # The body, and the head's arguments and guard, but not the head's own name: walking the whole def
  # node counted its head as a call, so every function came back "shared with" itself and nothing
  # ever looked free to move. A default (`at \\ now()`) and a guard (`when k in @kinds`) are calls
  # and reads as much as the body's, and they travel with the function.
  defp collect({_kind, _meta, [head | rest]}, acc) do
    [head_parts(head) | rest]
    |> Macro.prewalk(&as_call/1)
    |> Zipper.zip()
    |> Zipper.traverse(acc, fn zipper, found -> {zipper, absorb(Zipper.node(zipper), found)} end)
    |> elem(1)
  end

  defp collect(_node, acc), do: acc

  defp head_parts({:when, _meta, [call, guard]}), do: [head_parts(call), guard]
  defp head_parts({_name, _meta, args}) when is_list(args), do: args
  defp head_parts(_head), do: []

  # A pipeline step and a capture, written as the call they make: `x |> step()` is step/1, not
  # step/0, and `&step/1` calls step/1. Read as written, a helper two functions share looked free
  # to move.
  def as_call({:|>, _meta, [lhs, {fun, meta, args}]}) when is_list(args) or is_nil(args),
    do: {fun, meta, [lhs | List.wrap(args)]}

  def as_call({:&, _meta, [{:/, _, [{fun, meta, args}, {:__block__, _, [arity]}]}]})
      when is_integer(arity) and (is_nil(args) or args == []),
      do: {fun, meta, List.duplicate(:_, arity)}

  def as_call(node), do: node

  # A remote call: `Mod.fun(args)`. Its module counts as a reference too — that is the alias that
  # has to travel with the code.
  defp absorb({{:., _dot, [{:__aliases__, _am, parts}, fun]}, _meta, args}, acc)
       when is_atom(fun) and is_list(args) do
    name = Menard.Source.alias_name(parts)
    %{acc | remotes: ["#{name}.#{fun}/#{length(args)}" | acc.remotes], modules: [name | acc.modules]}
  end

  # A bare module mention (`alias`-resolved, a struct, a behaviour).
  defp absorb({:__aliases__, _meta, parts}, acc),
    do: %{acc | modules: [Menard.Source.alias_name(parts) | acc.modules]}

  # An attribute READ (`@kinds`), which is what does NOT travel with a moved function.
  defp absorb({:@, _meta, [{name, _inner, args}]}, acc) when is_atom(name) and not is_list(args),
    do: %{acc | attributes: [name | acc.attributes]}

  # A local call. Every one is collected here and intersected with the module's own definitions
  # later, which is what keeps `if`, `case`, `|>` and the rest of Kernel out of the answer.
  defp absorb({fun, _meta, args}, acc) when is_atom(fun) and is_list(args),
    do: %{acc | calls: [{fun, length(args)} | acc.calls]}

  defp absorb(_node, acc), do: acc

  defp empty, do: %{calls: [], remotes: [], modules: [], attributes: []}

  # -- shapes ---------------------------------------------------------------

  defp definitions(module) do
    module
    |> Tree.module_body()
    |> Enum.flat_map(fn
      {kind, _meta, [head | _rest]} = node when kind in @kinds -> [{Tree.name_arity(head), node}]
      _other -> []
    end)
  end

  defp key({key, _node}), do: key
  defp name({fun, arity}), do: "#{fun}/#{arity}"

  defp split(name_arity) do
    with [fun, arity] <- String.split(name_arity, "/"),
         {arity, ""} <- Integer.parse(arity) do
      {:ok, {String.to_atom(fun), arity}}
    else
      _ -> {:error, "expected name/arity, got #{inspect(name_arity)}"}
    end
  end
end
