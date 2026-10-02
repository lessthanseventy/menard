defmodule Menard.Layout do
  @moduledoc """
  Where a write puts what it adds: a new clause beside its function's others, and a new private
  function below the module's public ones, with the comment and `@spec` above it. Every write goes
  through it (`Menard.write/3`), so it holds whichever verb wrote the code and wherever the agent
  put it.
  """

  alias Menard.Tree

  @private [:defp, :defmacrop]

  # attributes a function or the module's head owns, or whose place is their meaning: credo's own
  # list (StrictModuleLayout), and a test's tags
  @bound ~w(moduledoc shortdoc behaviour type typep opaque callback macrocallback optional_callbacks
            after_compile before_compile compile impl deprecated doc typedoc dialyzer external_resource
            file on_definition on_load vsn spec enforce_keys tag moduletag describetag)a

  @doc """
  `content` laid out against `original`, and a note for each thing moved:

    * a function with more clauses than it had, now apart from each other: the new clause joins
      the others, before them where it was written above them (a catch-all last stays last), else
      after them. Public or private, split clauses do not build with warnings as errors.
    * a module with more private functions than it had: each new one with a public definition
      below it goes to the module's end. A rename, or an arity changed, adds none and moves none.
    * a module attribute it did not have, set once, below the first function: up above it, with
      its comment. Set twice, its place is its meaning; reading one set below the first
      function, it cannot go above it.

  Code that does not parse comes back as it is, for the parse check to refuse.
  """
  @spec private_last(String.t(), String.t()) :: {String.t(), [String.t()]}
  def private_last(original, content) do
    was = shape(original)
    attrs = attributes(original)
    {content, joined} = loop(content, &next_join(&1, was), [])
    {content, unsplit} = loop(content, &next_split(&1, was), [])
    {content, moved} = loop(content, &next_private(&1, was), [])
    {content, lifted} = loop(content, &next_attribute(&1, attrs), [])
    {content, joined ++ unsplit ++ moved ++ lifted}
  end

  # A function whose clauses were together, apart now by a definition it did not have: that goes
  # after its last clause. up4 Symphony 01: a `clause rewrite`, a new helper written under the
  # clause, refused where edit's own writes moved it.
  defp next_split({{mod, node}, content}, was) do
    defs = defs(node)
    before = Map.get(was, mod, [])
    old = MapSet.new(before, &elem(&1, 1))
    indexed = Enum.with_index(defs)

    indexed
    |> Enum.group_by(fn {{_kind, na}, _i} -> na end, fn {_def, i} -> i end)
    |> Enum.find_value(fn {na, at} ->
      new =
        for {{_, other}, i} <- indexed,
            i > Enum.min(at),
            i < Enum.max(at),
            other != na,
            other not in old,
            uniq: true,
            do: other

      if apart?(at) and together?(before, na) and new != [], do: unsplit(content, mod, na, hd(new))
    end)
  end

  defp together?(defs, na) do
    case for({{_kind, ^na}, i} <- Enum.with_index(defs), do: i) do
      [] -> false
      at -> not apart?(at)
    end
  end

  defp unsplit(content, mod, na, intruder) do
    {:ok, spans} = Menard.Clause.spans(content, "#{mod}.#{na}")
    {:ok, taken} = Menard.Clause.spans(content, "#{mod}.#{intruder}")
    {_, last} = List.last(spans)

    {"#{intruder} after the last clause of #{na}, not between its clauses",
     place(content, taken, {:after, last}, true)}
  end

  # each module's attribute names, as `shape/1` its definitions
  defp attributes(original) do
    case Menard.Source.parse(original) do
      {:ok, ast} -> Map.new(Tree.modules(ast), fn {mod, node} -> {mod, set(Tree.module_body(node))} end)
      _ -> %{}
    end
  end

  defp set(forms), do: for({:@, _, [{name, _, _}]} <- forms, do: name)

  # a new attribute, set once, below the module's first function: above it
  defp next_attribute({{mod, node}, content}, attrs) do
    forms = Tree.module_body(node)
    was = Map.get(attrs, mod, [])

    with first when is_integer(first) <- Enum.find_index(forms, &definition?/1),
         below = set(Enum.drop(forms, first)),
         attribute when attribute != nil <-
           forms |> Enum.drop(first) |> Enum.find(&movable?(&1, set(forms), below, was)),
         {:ok, spans} <- Menard.Clause.spans(content, "#{mod}.#{na(head(Enum.at(forms, first)))}") do
      {a, b} = Tree.line_span(attribute)
      lines = List.to_tuple(String.split(content, "\n"))
      span = {a - 1 - comments_above(lines, a - 2), b - 1}
      to = spans |> Enum.map(&elem(&1, 0)) |> Enum.min()
      {:@, _, [{name, _, _}]} = attribute
      {"@#{name} to the module's top, above its functions", place(content, [span], {:before, to})}
    else
      _ -> nil
    end
  end

  defp definition?({kind, _, [_ | _]}), do: kind in Tree.def_kinds()
  defp definition?(_form), do: false

  defp head({_kind, _, [head | _]}), do: head

  defp movable?({:@, _, [{name, _, value}]}, names, below, was) do
    name not in @bound and name not in was and Enum.count(names, &(&1 == name)) == 1 and
      not Enum.any?(reads(value), &(&1 in below))
  end

  defp movable?(_form, _names, _below, _was), do: false

  # the attributes a value reads (`@b @a + 1`)
  defp reads(value) do
    {_, names} =
      Macro.prewalk(value, [], fn
        {:@, _, [{name, _, _}]} = node, acc -> {node, [name | acc]}
        node, acc -> {node, acc}
      end)

    names
  end

  defp comments_above(lines, i) do
    if i >= 0 and String.starts_with?(String.trim(elem(lines, i)), "#"),
      do: 1 + comments_above(lines, i - 1),
      else: 0
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
  defp place(content, spans, to, close \\ false) do
    lines = List.to_tuple(String.split(content, "\n"))

    taken =
      Enum.flat_map(spans, fn {a, b} ->
        for(i <- a..b, do: elem(lines, i)) ++ if(blank?(lines, b + 1), do: [""], else: [])
      end)
      |> drop_last_blank()

    gone = MapSet.new(Enum.flat_map(spans, &gone(lines, &1, close)))

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

  # a span's lines, and a blank line beside it: one goes where it had one on each side; taken from
  # between clauses (`close`), the one above goes too, and they come back together with none between
  defp gone(lines, {a, b}, close) do
    cond do
      blank?(lines, a - 1) and blank?(lines, b + 1) -> a..(b + 1)
      close and blank?(lines, a - 1) -> (a - 1)..b
      true -> a..b
    end
  end

  defp blank?(lines, i), do: i >= 0 and i < tuple_size(lines) and String.trim(elem(lines, i)) == ""

  defp drop_last_blank(lines), do: if(List.last(lines) == "", do: List.delete_at(lines, -1), else: lines)
end
