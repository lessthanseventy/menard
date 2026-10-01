defmodule Menard.Layout do
  @moduledoc """
  Where a write puts what it adds: a new clause beside its function's others, and a new private
  function below the module's public ones, with the comment and `@spec` above it. Every write goes
  through it (`Menard.write/3`), so it holds whichever verb wrote the code and wherever the agent
  put it.
  """

  alias Menard.Tree

  @private [:defp, :defmacrop]

  @doc """
  `content` laid out against `original`, and a note for each thing moved:

    * a function with more clauses than it had, now apart from each other: the new clause joins
      the others, before them where it was written above them (a catch-all last stays last), else
      after them. Public or private, split clauses do not build with warnings as errors.
    * a module with more private functions than it had: each new one with a public definition
      below it goes to the module's end. A rename, or an arity changed, adds none and moves none.

  Code that does not parse comes back as it is, for the parse check to refuse.
  """
  @spec private_last(String.t(), String.t()) :: {String.t(), [String.t()]}
  def private_last(original, content) do
    was = shape(original)
    {content, joined} = loop(content, &next_join(&1, was), [])
    {content, moved} = loop(content, &next_private(&1, was), [])
    {content, joined ++ moved}
  end

  # one move at a time, the file parsed again after each, until there is none to make
  defp loop(content, next, notes) do
    with {:ok, ast} <- Menard.Source.parse(content),
         {note, moved} <- Enum.find_value(Tree.modules(ast), &next.({&1, content})) do
      loop(moved, next, [note | notes])
    else
      _ -> {content, Enum.reverse(notes)}
    end
  end

  # each module's definitions in source order, `{kind, "name/arity"}`, and its clause counts
  defp shape(original) do
    case Menard.Source.parse(original) do
      {:ok, ast} -> Map.new(Tree.modules(ast), fn {mod, node} -> {mod, defs(node)} end)
      _ -> %{}
    end
  end

  defp defs(node), do: for({kind, _, [head | _]} <- Tree.definitions(node), do: {kind, na(head)})

  defp na(head) do
    {name, arity} = Tree.name_arity(head)
    "#{name}/#{arity}"
  end

  # a function whose clauses are apart, with more of them than it had: its first stray clause
  defp next_join({{mod, node}, content}, was) do
    defs = defs(node)
    before = Map.get(was, mod, [])

    defs
    |> Enum.with_index()
    |> Enum.group_by(fn {{_kind, na}, _i} -> na end, fn {_def, i} -> i end)
    |> Enum.find_value(fn {na, at} ->
      if apart?(at) and length(at) > Enum.count(before, &(elem(&1, 1) == na)), do: join(content, mod, na, at)
    end)
  end

  defp apart?(at), do: Enum.max(at) - Enum.min(at) + 1 != length(at)

  # the longest run of the clauses stays; the first clause outside it goes before or after it
  defp join(content, mod, na, at) do
    {:ok, spans} = Menard.Clause.spans(content, "#{mod}.#{na}")
    runs = at |> Enum.zip(spans) |> Enum.chunk_while([], &run/2, &{:cont, Enum.reverse(&1), []})
    home = Enum.max_by(runs, &length/1)
    {_i, stray} = runs |> Enum.reject(&(&1 == home)) |> hd() |> hd()
    {_, {first, _}} = hd(home)
    {_, {_, last}} = List.last(home)

    to = if elem(stray, 0) < first, do: {:before, first}, else: {:after, last}
    {"#{na}: the new clause beside its others", place(content, [stray], to)}
  end

  defp run({i, _} = clause, [{j, _} | _] = acc) when i == j + 1, do: {:cont, [clause | acc]}
  defp run(clause, []), do: {:cont, [clause]}
  defp run(clause, acc), do: {:cont, Enum.reverse(acc), [clause]}

  # a new private function with a public definition below it, to the module's end
  defp next_private({{mod, node}, content}, was) do
    defs = defs(node)
    before = Map.get(was, mod, [])
    privates = fn defs -> for({kind, na} <- defs, kind in @private, uniq: true, do: na) end
    old = privates.(before)

    last_public =
      defs |> Enum.with_index() |> Enum.reject(fn {{kind, _}, _} -> kind in @private end) |> List.last()

    with true <- length(privates.(defs)) > length(old),
         {_, last} <- last_public,
         {{_kind, na}, _i} <-
           Enum.find(Enum.with_index(defs), fn {{kind, na}, i} ->
             kind in @private and na not in old and i < last
           end) do
      {:ok, spans} = Menard.Clause.spans(content, "#{mod}.#{na}")
      {_first, end_line} = Tree.line_span(node)
      # after the line before the module's `end` (1-based `end_line`)
      {"#{na} to the module's end, below its public functions", place(content, spans, {:after, end_line - 2})}
    else
      _ -> nil
    end
  end

  # the lines of `spans` (0-based `{a, b}`) taken out and put back before line `to`, or after it, a
  # blank line between them and their new neighbour, and between two where one was; where a span
  # leaves a blank line on each side, one goes
  defp place(content, spans, to) do
    lines = List.to_tuple(String.split(content, "\n"))

    taken =
      Enum.flat_map(spans, fn {a, b} ->
        for(i <- a..b, do: elem(lines, i)) ++ if(blank?(lines, b + 1), do: [""], else: [])
      end)
      |> drop_last_blank()

    gone =
      MapSet.new(
        Enum.flat_map(spans, fn {a, b} ->
          if blank?(lines, a - 1) and blank?(lines, b + 1), do: a..(b + 1), else: a..b
        end)
      )

    Enum.flat_map(0..(tuple_size(lines) - 1), fn i ->
      line = if i in gone, do: [], else: [elem(lines, i)]

      case to do
        {:before, ^i} -> taken ++ [""] ++ line
        {:after, ^i} -> line ++ [""] ++ taken
        _ -> line
      end
    end)
    |> Enum.join("\n")
  end

  defp blank?(lines, i), do: i >= 0 and i < tuple_size(lines) and String.trim(elem(lines, i)) == ""

  defp drop_last_blank(lines), do: if(List.last(lines) == "", do: List.delete_at(lines, -1), else: lines)
end
