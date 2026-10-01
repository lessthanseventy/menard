defmodule Menard.Move do
  @moduledoc """
  `clause move`: functions out of one module and into another, as many as a call names — the tool
  for splitting a module, one call per new module. What the moved code needs goes with it rather
  than being left broken:

  - a private helper only the moved functions call travels with them; one that a function staying
    behind also calls stays, made public, and the moved code calls it there (`published`); one the
    caller named in the move is refused, naming it (it was asked to go, and something needs it here);
  - the module attributes it reads are copied, and leave the source when nothing there reads them;
  - the `alias`, `import` and `require` lines it uses are added to the destination, and only those:
    an unused one fails a `--warnings-as-errors` build, so the source loses the ones it stops using;
  - a call back to a public function that stays, and `__MODULE__`, now name the source module;
  - with `delegate`, each public function moved leaves a `defdelegate` where it was, its defaults
    kept, so every caller keeps working. Without, the reply names the calls left pointing at nothing.

  Both files are parse-checked before either is written — a move that half lands is worse than one
  that does not. A missing destination is created, named after its path the way a generator would
  (`as:` overrides).
  """

  import Menard.Source, only: [parse: 1]
  alias Menard.Attr
  alias Menard.Clause
  alias Menard.Deps
  alias Menard.Directive
  alias Menard.Tree

  @private [:defp, :defmacrop, :defguardp]
  @macros [:defmacro, :defguard]
  @typespecs [:spec, :type, :typep, :opaque, :callback, :macrocallback]
  @directives [:import, :require, :alias]
  # what a local call resolves to with nothing defined or imported
  @builtin for m <- [Kernel, Kernel.SpecialForms],
               kind <- [:functions, :macros],
               {name, _arity} <- m.__info__(kind),
               into: MapSet.new([:when]),
               do: name

  @tests [:test, :describe]

  @setups [:setup, :setup_all]

  # what moved by its label, the helpers that came along; no delegate stands in for a test
  @exunit for m <- [ExUnit.Assertions, ExUnit.Callbacks, ExUnit.Case],
              Code.ensure_loaded?(m),
              kind <- [:functions, :macros],
              {name, _} <- m.__info__(kind),
              into: MapSet.new(),
              do: Atom.to_string(name)

  @doc """
  Move `names` (`"name/arity"`: a list, or comma-separated) from `file` to `dest`, absolute paths.
  `module:` picks the destination module in a file with several, `as:` names a created one and
  `moduledoc:` gives it its `@moduledoc`; `delegate: true` leaves a `defdelegate` for each public
  function moved; `root:` is where the calls left behind are looked for, without `delegate`.

  Returns `{:ok, reply}`: `created` (the new module's name, else nil), `moved`, `carried` (the
  private helpers that came along), `attributes` and `directives` (what the destination gained),
  `unresolved` (each call only a `use` or an import without `only:` may answer, with those: not
  copied, as the AST cannot say which), `qualified` (the calls back to the source, and its types,
  that now name it), `delegated`, `left` (each call still naming a moved function, without
  `delegate`), and `to` and `from`, each file's `Menard.write/3` reply, its version and stages.
  """
  @spec run(String.t(), String.t(), String.t() | [String.t()], keyword()) ::
          {:ok, map()} | {:error, String.t()}
  def run(file, dest, names, opts \\ []) do
    names = names(names)
    listed = Enum.join(names, ", ")

    with :ok <- apart(file, dest),
         {:ok, dest_source, created} <- dest_source(dest, opts[:as], opts[:moduledoc]),
         {:ok, plan} <- plan(File.read!(file), dest_source, names, opts),
         dest_out = with_moduledoc(plan.dest, opts[:moduledoc]),
         {:ok, _} <- Menard.Write.checked(dest, dest_out),
         {:ok, _} <- Menard.Write.checked(file, plan.source),
         :ok <- File.mkdir_p!(Path.dirname(dest)),
         {:ok, to} <- Menard.write(dest, dest_out, did: "move #{listed} into #{Path.basename(dest)}"),
         {:ok, from} <- Menard.write(file, plan.source, did: "move #{listed} out of #{Path.basename(file)}") do
      left =
        if opts[:delegate], do: [], else: left(opts[:root] || Menard.caller_dir(), file, plan.report.moved)

      {:ok, Map.merge(plan.report, %{created: created, left: left, to: to, from: from})}
    end
  end

  @doc """
  `block move`: tests out of one test module into another, as `run/4` moves functions. `labels`
  name the module's own `test`s and `describe`s (not a test inside a describe). What they need goes
  with them: the private helpers only they call, the attributes they read and the alias, import and
  require lines they use; each one's `@tag` lines and the comment above it. A destination the move
  creates gets the source's `use` lines and its `setup` blocks, copied: the tests ran under them.

  A private helper a test that stays calls too is refused, naming it. A function's move makes such
  a helper public where it is; a test that called into another test module would fail whenever its
  own file ran alone, which does not load that one. Such a helper belongs in `test/support`.
  """
  @spec blocks(String.t(), String.t(), [String.t()], keyword()) :: {:ok, map()} | {:error, String.t()}
  def blocks(file, dest, labels, opts \\ []) do
    listed = Enum.map_join(labels, ", ", &inspect/1)

    with :ok <- apart(file, dest),
         {:ok, dest_source, created} <- dest_source(dest, opts[:as], nil),
         {:ok, plan} <- plan_blocks(File.read!(file), dest_source, labels, created != nil),
         {:ok, _} <- Menard.Write.checked(dest, plan.dest),
         {:ok, _} <- Menard.Write.checked(file, plan.source),
         :ok <- File.mkdir_p!(Path.dirname(dest)),
         {:ok, to} <- Menard.write(dest, plan.dest, did: "move #{listed} into #{Path.basename(dest)}"),
         {:ok, from} <- Menard.write(file, plan.source, did: "move #{listed} out of #{Path.basename(file)}") do
      {:ok, Map.merge(plan.report, %{created: created, to: to, from: from})}
    end
  end

  @doc "`\"a/1,b/2\"` or a list of those: the names a move takes, trimmed, each once."
  @spec names(String.t() | [String.t()]) :: [String.t()]
  def names(names) when is_list(names), do: names |> Enum.flat_map(&names/1) |> Enum.uniq()

  def names(names) when is_binary(names),
    do: names |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == "")) |> Enum.uniq()

  @doc """
  The move on sources, nothing written: `{:ok, %{source, dest, report}}`, `report` being `run/4`'s
  reply without what only the files give (`created`, `left`, `to`, `from`).
  """
  @spec plan(String.t(), String.t(), [String.t()], keyword()) :: {:ok, map()} | {:error, String.t()}
  def plan(source, dest_source, names, opts \\ []) do
    case plan_once(source, dest_source, names, opts) do
      # a helper the move takes that what stays calls too: made public where it is, and the move made
      # again, the moved code now calling it there (riverside2: the refusal and two `visibility`
      # calls every split made by hand)
      {:publish, keys, mod} ->
        with {:ok, source} <- publish(source, mod, keys),
             {:ok, plan} <- plan(source, dest_source, names, opts) do
          {:ok, update_in(plan.report.published, &(Enum.map(keys, fn key -> na(key) end) ++ &1))}
        end

      planned ->
        planned
    end
  end

  defp publish(source, mod, keys) do
    Enum.reduce_while(keys, {:ok, source}, fn key, {:ok, source} ->
      case Clause.visibility(source, "#{mod}.#{na(key)}", :public) do
        out when is_binary(out) -> {:cont, {:ok, out}}
        error -> {:halt, error}
      end
    end)
  end

  defp plan_once(source, dest_source, names, opts) do
    with {:ok, ast} <- parse(source),
         {:ok, mod, module} <- source_module(ast, names),
         graph = Deps.graph(module),
         {:ok, named} <- named(names, graph, mod),
         taking = taking(named, graph),
         :ok <- unshared(taking, named, graph, mod),
         :ok <- delegable(named, graph, opts[:delegate]),
         {:ok, dest_ast} <- parse(dest_source),
         {:ok, dest_module} <- Tree.module_scope(dest_ast, opts[:module]),
         :ok <- not_in(dest_module, taking),
         {:ok, spans} <- spans(source, mod, taking) do
      lines = String.split(source, "\n")
      # at the source's indent, as the insert takes it: a dedent pulled a heredoc's text left too,
      # and the insert (rightly) leaves a string's lines where they are
      code = Enum.map_join(taking, "\n\n", &function_text(lines, spans[&1]))

      src = %{
        source: source,
        mod: mod,
        module: module,
        graph: graph,
        named: named,
        taking: taking,
        spans: spans
      }

      move(src, %{code: code, dest: dest_source, module: dest_module}, opts)
    end
  end

  defp move(src, dest, opts) do
    with {:ok, needs} <- needs(src, dest.code),
         {:ok, ref, qualified, code} <- qualify(src, needs, dest),
         {:ok, dest_out, directives} <- dest(src, dest, code, needs, ref, opts[:module]),
         {:ok, out, delegated} <- source_after(src, dest, needs, opts[:delegate]) do
      report = %{
        moved: Enum.map(src.named, &na/1),
        carried: src.taking |> Enum.reject(&(&1 in src.named)) |> Enum.map(&na/1),
        attributes: Enum.map(needs.values, &"@#{elem(&1, 0)}"),
        directives: directives,
        unresolved:
          Enum.map(needs.answered.open, &"#{na(&1)} (one of: #{Enum.join(needs.answered.from, "; ")})"),
        qualified: qualified,
        delegated: Enum.map(delegated, &na/1),
        published: []
      }

      {:ok, %{source: out, dest: dest_out, report: report}}
    end
  end

  # -- what moves -----------------------------------------------------------

  # The module the names are in: the file's one, or the one a qualified name (`Mod.fun/1`) names.
  defp source_module(ast, names) do
    qualified =
      Enum.find_value(names, fn name ->
        case name |> String.split("/") |> hd() |> String.split(".") do
          [_fun] -> nil
          parts -> parts |> Enum.drop(-1) |> Enum.join(".")
        end
      end)

    case {Tree.modules(ast), qualified} do
      {[], _} ->
        {:error, "no module in this file"}

      {[{mod, node}], nil} ->
        {:ok, mod, node}

      {modules, nil} ->
        {:error, "several modules here — qualify the names: #{Enum.map_join(modules, ", ", &elem(&1, 0))}"}

      {modules, mod} ->
        case List.keyfind(modules, mod, 0) do
          {^mod, node} -> {:ok, mod, node}
          nil -> {:error, "no module #{mod} in this file"}
        end
    end
  end

  defp named(names, graph, mod) do
    Enum.reduce_while(names, {:ok, []}, fn name, {:ok, acc} ->
      bare = name |> String.split(".") |> List.last()

      case Enum.find(Map.keys(graph), &(na(&1) == bare)) do
        nil ->
          {:halt,
           {:error, "no #{bare} in #{mod} — have: #{graph |> in_order() |> Enum.map_join(", ", &na/1)}"}}

        key ->
          {:cont, {:ok, acc ++ [key]}}
      end
    end)
  end

  # The named functions and every private helper they reach, in source order.
  defp taking(named, graph) do
    reached = reach(named, graph, MapSet.new(named))
    graph |> in_order() |> Enum.filter(&MapSet.member?(reached, &1))
  end

  defp reach([], _graph, seen), do: seen

  defp reach(frontier, graph, seen) do
    next =
      for key <- frontier,
          call <- graph[key].calls,
          graph[call].kind in @private,
          not MapSet.member?(seen, call),
          uniq: true,
          do: call

    reach(next, graph, MapSet.union(seen, MapSet.new(next)))
  end

  # A private function the moved code takes that a function staying behind also calls cannot go
  # without breaking that one, nor stay private without breaking the moved code. A helper the move
  # only carried stays and goes public (`plan/4`); one the caller named was asked to go, so that one
  # is refused with both ways out.
  defp unshared(taking, named, graph, mod) do
    shared =
      for key <- taking,
          graph[key].kind in @private,
          by = for({k, %{calls: calls}} <- graph, k not in taking, MapSet.member?(calls, key), do: k),
          by != [],
          do: {key, by |> Enum.sort_by(&line(graph, &1)) |> Enum.map(&na/1)}

    case Enum.split_with(shared, fn {key, _by} -> key in named end) do
      {[], []} -> :ok
      {[], carried} -> {:publish, Enum.map(carried, &elem(&1, 0)), mod}
      {asked, _carried} -> {:error, shared_refusal(asked, mod)}
    end
  end

  defp shared_refusal(shared, mod) do
    helpers = Enum.map(shared, &na(elem(&1, 0)))
    callers = shared |> Enum.flat_map(&elem(&1, 1)) |> Enum.uniq()

    why =
      Enum.map_join(shared, "; ", fn {key, by} ->
        verb = if match?([_], by), do: "stays and calls", else: "stay and call"
        "#{na(key)} is private, and #{Enum.join(by, ", ")} #{verb} it too"
      end)

    one = if match?([_], helpers), do: hd(helpers), else: "NAME/ARITY"
    calls = Enum.map_join(shared, ", ", fn {{name, _}, _} -> "#{mod}.#{name}" end)

    "refused, nothing written: #{why}. Move #{Enum.join(callers, ", ")} as well, or make " <>
      "#{Enum.join(helpers, ", ")} public first (clause visibility FILE #{one} public): the moved code then calls #{calls}"
  end

  defp delegable(named, graph, true) do
    case Enum.filter(named, &(graph[&1].kind in @macros)) do
      [] ->
        :ok

      macros ->
        {:error,
         "#{Enum.map_join(macros, ", ", &na/1)} is a macro, which no defdelegate stands in for — move it without delegate, or leave it"}
    end
  end

  defp delegable(_named, _graph, _delegate), do: :ok

  defp not_in(dest_module, taking) do
    there =
      dest_module |> Tree.definitions() |> Enum.map(fn {_kind, _, [head | _]} -> Tree.name_arity(head) end)

    case Enum.filter(taking, &(&1 in there)) do
      [] -> :ok
      clash -> {:error, "the destination already defines #{Enum.map_join(clash, ", ", &na/1)}"}
    end
  end

  defp spans(source, mod, taking) do
    Enum.reduce_while(taking, {:ok, %{}}, fn key, {:ok, acc} ->
      case Clause.spans(source, "#{mod}.#{na(key)}") do
        {:ok, spans} -> {:cont, {:ok, Map.put(acc, key, spans)}}
        error -> {:halt, error}
      end
    end)
  end

  # A function's clauses as written, a blank line between two of them kept.
  defp function_text(lines, spans) do
    spans
    |> Enum.chunk_every(2, 1)
    |> Enum.flat_map(fn
      [{a, b}, {next, _}] ->
        gap = Enum.slice(lines, (b + 1)..(next - 1)//1)
        Enum.slice(lines, a..b) ++ if(Enum.all?(gap, &(String.trim(&1) == "")), do: gap, else: [])

      [{a, b}] ->
        Enum.slice(lines, a..b)
    end)
    |> Enum.join("\n")
  end

  # -- what the moved code needs --------------------------------------------

  # What code reads from its module: the aliases (by first segment), the attributes, each local call
  # with where it is written, and where it says `__MODULE__`. A typespec is read for its aliases and
  # `__MODULE__` only: `list(t())` there is a type, not a call to `list/1`.
  defp scan(code) do
    empty = %{aliases: MapSet.new(), attributes: MapSet.new(), calls: [], modules: [], types: []}

    case Sourceror.parse_string(code) do
      {:ok, ast} ->
        {:ok, ast |> Macro.prewalk(&Deps.as_call/1) |> Macro.prewalk(empty, &scan_node/2) |> elem(1)}

      {:error, reason} ->
        {:error, "the moved code does not parse — #{inspect(reason)}"}
    end
  end

  defp scan_node({:@, _, [{kind, _, [_ | _] = args}]}, acc) when kind in @typespecs do
    {_, inner} = Macro.prewalk(typespec_body(kind, args), %{acc | calls: []}, &scan_node/2)
    {:typespec, %{inner | calls: acc.calls, types: inner.calls ++ acc.types}}
  end

  # an attribute SET: its value is read, its name is not a call
  defp scan_node({:@, meta, [{name, _, args}]}, acc) when is_atom(name) and is_list(args),
    do: {{:__block__, meta, args}, acc}

  defp scan_node({:@, _, [{name, _, ctx}]} = node, acc) when is_atom(name) and is_atom(ctx),
    do: {node, %{acc | attributes: MapSet.put(acc.attributes, name)}}

  defp scan_node({:__aliases__, _, [first | _]} = node, acc) when is_atom(first),
    do: {node, %{acc | aliases: MapSet.put(acc.aliases, first)}}

  defp scan_node({:__MODULE__, meta, ctx} = node, acc) when is_atom(ctx),
    do: {node, %{acc | modules: [meta | acc.modules]}}

  defp scan_node({fun, meta, args} = node, acc) when is_atom(fun) and is_list(args),
    do: {node, %{acc | calls: [{{fun, length(args)}, meta} | acc.calls]}}

  defp scan_node(node, acc), do: {node, acc}

  # What a spec's types are read from: its head's arguments, its return and its guard, not the head's
  # name, which is the function's own.
  defp typespec_body(kind, [{:when, _, [spec, guard]}]) when kind in [:spec, :callback, :macrocallback],
    do: [typespec_body(kind, [spec]), guard]

  defp typespec_body(kind, [{:"::", _, [head, return]}]) when kind in [:spec, :callback, :macrocallback],
    do: [head_args(head), return]

  defp typespec_body(_kind, args), do: args

  # The calls neither the module nor Kernel answers: an import's.
  defp unresolved(calls, graph) do
    own = graph |> Map.keys() |> MapSet.new(&elem(&1, 0))

    for {{fun, _arity} = key, _meta} <- calls,
        not MapSet.member?(own, fun),
        not MapSet.member?(@builtin, fun),
        Regex.match?(~r/^[a-z][a-zA-Z0-9_]*[?!]?$/, Atom.to_string(fun)),
        uniq: true,
        do: key
  end

  defp needs(src, code) do
    with {:ok, scan} <- scan(code),
         {:ok, values} <- attributes(src, MapSet.to_list(scan.attributes)),
         {:ok, from_values} <- scan(Enum.map_join(values, "\n", &elem(&1, 1))) do
      {:ok,
       %{
         scan: scan,
         values: values,
         aliases: MapSet.union(scan.aliases, from_values.aliases),
         answered: answering(src.source, src.mod, unresolved(scan.calls ++ from_values.calls, src.graph))
       }}
    end
  end

  # The attributes the code reads that the module sets, and those their values read, in source
  # order: each with its value as written and the comment lines glued above it, which explain it.
  defp attributes(src, reads) do
    listed = Attr.list(src.source, module: src.mod)
    set = listed |> Enum.map(&elem(&1, 0)) |> Enum.uniq()
    wanted = wanted(src, set, reads, MapSet.new())
    lines = String.split(src.source, "\n")

    set
    |> Enum.filter(&MapSet.member?(wanted, &1))
    |> Enum.reduce_while({:ok, []}, fn name, {:ok, acc} ->
      case Attr.get(src.source, name, module: src.mod) do
        value when is_binary(value) ->
          {:cont, {:ok, acc ++ [{name, value, comment_above(lines, listed[name])}]}}

        {:error, why} ->
          {:halt, {:error, "the moved code reads @#{name}: #{why}"}}
      end
    end)
  end

  defp comment_above(lines, line) do
    n = Menard.Source.comment_lines_above(lines, line - 1)
    lines |> Enum.slice(line - 1 - n, n) |> Enum.map(&String.trim_leading/1)
  end

  defp wanted(_src, _set, [], seen), do: seen

  defp wanted(src, set, [name | rest], seen) do
    if name in set and not MapSet.member?(seen, name) do
      more =
        with value when is_binary(value) <- Attr.get(src.source, name, module: src.mod),
             {:ok, scan} <- scan(value),
             do: MapSet.to_list(scan.attributes),
             else: (_ -> [])

      wanted(src, set, rest ++ more, MapSet.put(seen, name))
    else
      wanted(src, set, rest, seen)
    end
  end

  # -- the destination ------------------------------------------------------

  # A call back to a public function that stays, a public type the source defines, and `__MODULE__`
  # now name the source module: by its last segment, aliased, unless that name already means
  # something else where the code lands. A type is named, not delegated: no stand-in exists for one.
  defp qualify(src, needs, dest) do
    staying = Map.drop(src.graph, src.taking)
    # as the function it reaches: a call that leaves a default out names a smaller arity
    back =
      for {call, meta} <- needs.scan.calls,
          key = Deps.reached(src.graph, call),
          Map.has_key?(staying, key),
          do: {key, meta}

    defined = types(src.module)
    types = for {key, meta} <- needs.scan.types, Map.has_key?(defined, key), do: {key, meta}
    macros = for {key, _} <- back, staying[key].kind in @macros, uniq: true, do: na(key)
    private = for {key, _} <- types, defined[key] == :typep, uniq: true, do: key

    cond do
      macros != [] ->
        {:error,
         "the moved code calls #{Enum.join(macros, ", ")}, a macro that stays in #{src.mod} — move it too"}

      private != [] ->
        {:error, typep_refusal(private, src.mod)}

      true ->
        name_source(src.mod, needs, dest, back, types)
    end
  end

  defp name_source(mod, needs, dest, back, types) do
    ref = source_ref(mod, needs, dest.module)

    patches =
      for({{fun, _}, meta} <- back ++ types, do: name_patch(meta, fun, "#{ref.name}.#{fun}")) ++
        for(meta <- needs.scan.modules, do: name_patch(meta, :__MODULE__, ref.name))

    qualified =
      (back |> Enum.map(&na(elem(&1, 0))) |> Enum.uniq() |> Enum.sort()) ++
        (types |> Enum.map(&"@type #{na(elem(&1, 0))}") |> Enum.uniq() |> Enum.sort()) ++
        if(needs.scan.modules == [], do: [], else: ["__MODULE__"])

    {:ok, if(patches == [], do: nil, else: ref), qualified, Menard.Source.patch(dest.code, patches)}
  end

  # The types a module defines: `{name, arity} => :type | :typep | :opaque`.
  defp types(module) do
    for {:@, _, [{kind, _, [{:"::", _, [{name, _, args}, _]}]}]} <- Tree.module_body(module),
        kind in [:type, :typep, :opaque],
        into: %{},
        do: {{name, length(List.wrap(args))}, kind}
  end

  # A private type is named nowhere else, so a spec naming it cannot move as written; making it
  # public, or rewriting the spec, is the caller's call.
  defp typep_refusal(private, mod) do
    names = Enum.map_join(private, ", ", &na/1)
    statements = Enum.map_join(private, ", ", fn {name, _} -> "`@typep #{name}`" end)
    them = Enum.map_join(private, ", ", fn {name, _} -> "#{mod}.#{name}()" end)

    "refused, nothing written: the moved @spec names #{names}, a @typep of #{mod}, which no other module " <>
      "can name. Make it a @type first (stmt replace of the module's #{statements}): the spec then names #{them}"
  end

  defp name_patch(meta, name, to) do
    {line, column} = {meta[:line], meta[:column]}
    width = name |> Atom.to_string() |> String.length()
    %{range: %{start: [line: line, column: column], end: [line: line, column: column + width]}, change: to}
  end

  defp source_ref(mod, needs, dest_module) do
    parts = String.split(mod, ".")
    short = List.last(parts)
    there = dest_aliases(dest_module)

    cond do
      match?([_], parts) -> %{name: mod, alias: nil}
      {short, mod} in there -> %{name: short, alias: nil}
      Enum.any?(there, &(elem(&1, 0) == short)) -> %{name: mod, alias: nil}
      String.to_atom(short) in needs.aliases -> %{name: mod, alias: nil}
      true -> %{name: short, alias: mod}
    end
  end

  defp dest(src, dest, code, needs, ref, module) do
    own = if ref && ref.alias, do: [{:alias, ref.alias, nil}], else: []

    adds =
      src.source
      |> directives(src.mod)
      |> used(needs)
      |> Kernel.++(own)
      |> Enum.sort_by(fn {kind, target, _} -> {Enum.find_index(@directives, &(&1 == kind)), target} end)

    with {:ok, out} <- reduce([code], dest.dest, &Clause.insert_at(&2, module, nil, &1)),
         {:ok, out} <-
           reduce(adds, out, fn {kind, target, args}, acc ->
             Directive.add(acc, kind, target, args: args, module: module)
           end),
         {:ok, out} <-
           reduce(needs.values, out, fn {name, value, _}, acc ->
             Attr.set(acc, name, value, module: module)
           end),
         {:ok, out} <-
           reduce(needs.values, out, fn {name, _, comment}, acc -> commented(acc, name, comment, module) end) do
      {:ok, out, Enum.map(adds, &directive_text/1)}
    end
  end

  # The source's directives the moved code uses: an alias by its name, a require by its module's
  # first or last segment, an import by a call it answers (`answering/3`).
  defp used(directives, needs) do
    Enum.filter(directives, fn
      {:alias, target, args} ->
        short_atom(target, args) in needs.aliases

      {:require, target, _} ->
        parts = String.split(target, ".")
        Enum.any?([hd(parts), List.last(parts)], &(String.to_atom(&1) in needs.aliases))

      {:import, _, _} = import ->
        import in needs.answered.imports
    end)
  end

  # -- the source after -----------------------------------------------------

  defp source_after(src, dest, needs, delegate) do
    delegated = if delegate, do: Enum.filter(src.named, &(src.graph[&1].kind == :def)), else: []
    ref = dest_ref(src, module_name(dest.module))
    lines = String.split(src.source, "\n")

    replace =
      Map.new(delegated, fn key ->
        [{a, _} = first | _] = src.spans[key]
        line = Enum.at(lines, a)
        indent = String.duplicate(" ", String.length(line) - String.length(String.trim_leading(line)))

        {first,
         Enum.map_join(delegate(key, src.graph[key].nodes, ref.name, src.taking), "\n\n", &(indent <> &1))}
      end)

    out = Clause.cut(src.source, Enum.flat_map(src.taking, &src.spans[&1]), replace)
    alias_it = if delegated != [] and ref.alias, do: [ref.alias], else: []

    with {:ok, out} <- reduce(alias_it, out, &Directive.add(&2, :alias, &1, module: src.mod)),
         {:ok, out} <- unread(out, src, needs),
         {:ok, out} <- unaliased(out, src),
         {:ok, out} <- unimported(out, src, needs) do
      {:ok, out, delegated}
    end
  end

  defp dest_ref(src, dest_mod) do
    parts = String.split(dest_mod, ".")
    short = List.last(parts)

    mine =
      src.source
      |> directives(src.mod)
      |> Enum.find(fn {kind, target, args} -> kind == :alias and short_of(target, args) == short end)

    cond do
      match?([_], parts) -> %{name: dest_mod, alias: nil}
      match?({:alias, ^dest_mod, _}, mine) -> %{name: short, alias: nil}
      mine != nil -> %{name: dest_mod, alias: nil}
      String.to_atom(short) in module_aliases(src.module) -> %{name: dest_mod, alias: nil}
      true -> %{name: short, alias: dest_mod}
    end
  end

  # `defdelegate name(args), to: Dest`: each argument named from a clause that names it — a variable,
  # else a struct's module (`%User{}` is `user`), else `argN` — with the default the function gave
  # it: a delegate's head carries defaults, and its one head covers every arity they make. A default
  # is evaluated where the delegate is, so one calling code that moved (`opts \\ defaults()`, a
  # helper that may be private there) cannot be copied: each arity delegates to the same arity
  # instead, whose default is evaluated in the destination.
  defp delegate({name, 0}, _nodes, to, _taking), do: ["defdelegate #{name}, to: #{to}"]

  defp delegate({name, arity}, nodes, to, taking) do
    heads = Enum.map(nodes, fn {_kind, _, [head | _]} -> head_args(head) end)

    args =
      0..(arity - 1)//1
      |> Enum.map(fn i ->
        at = Enum.map(heads, &Enum.at(&1, i))
        default = Enum.find_value(at, &default/1)
        {Enum.find_value(at, &var_name/1) || Enum.find_value(at, &struct_name/1) || "arg#{i + 1}", default}
      end)
      |> unique()

    if Enum.any?(args, fn {_var, default} -> default && calls_any?(default, taking) end) do
      per_arity(name, args, to)
    else
      args =
        Enum.map_join(args, ", ", fn
          {var, nil} -> var
          {var, default} -> "#{var} \\\\ #{Sourceror.to_string(default)}"
        end)

      ["defdelegate #{name}(#{args}), to: #{to}"]
    end
  end

  defp head_args({:when, _, [call | _]}), do: head_args(call)
  defp head_args({_name, _, args}) when is_list(args), do: args
  defp head_args(_head), do: []

  defp default({:\\, _, [_arg, default]}), do: default
  defp default(_arg), do: nil

  # One delegate per arity the defaults make, each passing what it is given: every argument without
  # a default, and the defaulted ones from the left as the arity has room, as Elixir fills them.
  defp per_arity(name, args, to) do
    required = Enum.count(args, &(elem(&1, 1) == nil))

    for k <- required..length(args) do
      {kept, _} =
        Enum.flat_map_reduce(args, k - required, fn
          {var, nil}, left -> {[var], left}
          {var, _default}, left when left > 0 -> {[var], left - 1}
          _arg, 0 -> {[], 0}
        end)

      if kept == [],
        do: "defdelegate #{name}, to: #{to}",
        else: "defdelegate #{name}(#{Enum.join(kept, ", ")}), to: #{to}"
    end
  end

  defp calls_any?(ast, keys) do
    ast
    |> Macro.prewalk(&Deps.as_call/1)
    |> Macro.prewalker()
    |> Enum.any?(fn
      {fun, _, args} when is_atom(fun) and is_list(args) -> {fun, length(args)} in keys
      _node -> false
    end)
  end

  defp var_name({:\\, _, [arg, _]}), do: var_name(arg)
  defp var_name({:=, _, [left, right]}), do: var_name(left) || var_name(right)

  defp var_name({name, _, ctx}) when is_atom(name) and is_atom(ctx) do
    text = Atom.to_string(name)
    if String.starts_with?(text, "_"), do: nil, else: text
  end

  defp var_name(_arg), do: nil

  defp struct_name({:\\, _, [arg, _]}), do: struct_name(arg)
  defp struct_name({:=, _, [left, right]}), do: struct_name(left) || struct_name(right)

  defp struct_name({:%, _, [{:__aliases__, _, parts}, _]}) do
    case List.last(parts) do
      last when is_atom(last) -> last |> Atom.to_string() |> Macro.underscore()
      _ -> nil
    end
  end

  defp struct_name(_arg), do: nil

  # two positions one name would be one variable twice: the later one is numbered
  defp unique(args) do
    args
    |> Enum.with_index(1)
    |> Enum.map_reduce(MapSet.new(), fn {{var, default}, i}, seen ->
      var = if MapSet.member?(seen, var), do: "#{var}#{i}", else: var
      {{var, default}, MapSet.put(seen, var)}
    end)
    |> elem(0)
  end

  # An attribute the moved code took that the source no longer reads goes, and the comment glued
  # above it with it: set and never used warns, and the comment would explain nothing.
  defp unread(out, src, needs) do
    with {:ok, module} <- scope(out, src.mod) do
      reads =
        module
        |> Macro.prewalker()
        |> Enum.flat_map(fn
          {:@, _, [{name, _, ctx}]} when is_atom(name) and is_atom(ctx) -> [name]
          _ -> []
        end)

      needs.values
      |> Enum.map(&elem(&1, 0))
      |> Enum.reject(&(&1 in reads))
      |> reduce(out, &drop_attribute(&2, &1, src.mod))
    end
  end

  defp drop_attribute(source, name, mod) do
    line = source |> Attr.list(module: mod) |> Keyword.fetch!(name)
    n = Menard.Source.comment_lines_above(String.split(source, "\n"), line - 1)

    with out when is_binary(out) <- Attr.delete(source, name, module: mod) do
      if n > 0, do: Menard.Source.delete_lines(out, line - n, line - 1), else: out
    end
  end

  # the attribute's comment, above it where it lands
  defp commented(source, _name, [], _module), do: source

  defp commented(source, name, comment, module) do
    line = source |> Attr.list(module: module) |> Keyword.fetch!(name)
    {head, tail} = source |> String.split("\n") |> Enum.split(line - 1)
    [at | _] = tail
    indent = String.duplicate(" ", String.length(at) - String.length(String.trim_leading(at)))
    Enum.join(head ++ Enum.map(comment, &(indent <> &1)) ++ tail, "\n")
  end

  # An alias the source used before the move and does not after goes: an unused alias warns.
  defp unaliased(out, src) do
    with {:ok, module} <- scope(out, src.mod) do
      before = module_aliases(src.module)
      now = module_aliases(module)

      out
      |> directives(src.mod)
      |> Enum.filter(fn {kind, target, args} ->
        kind == :alias and short_atom(target, args) in before and short_atom(target, args) not in now
      end)
      |> reduce(out, fn {:alias, target, _}, acc -> unalias(acc, target, src.mod) end)
    end
  end

  # one of an `alias A.{B, C}` leaves its line; one of an `alias A.{B, C}, opts` stays, as the
  # options speak for every member
  defp unalias(source, target, mod) do
    with {:error, _} <- Directive.remove(source, :alias, target, module: mod), do: source
  end

  # An import the moved code used that nothing left calls into goes: an unused import warns, unless
  # it says `warn: false`. Which import answers a call is decided as for the move (`answering/3`):
  # one the AST cannot tie to a call stays, as the call may be its.
  defp unimported(out, src, needs) do
    with {:ok, module} <- scope(out, src.mod) do
      {_, calls} =
        module
        |> Macro.prewalk(&Deps.as_call/1)
        |> Macro.prewalk([], fn
          {fun, meta, args} = node, acc when is_atom(fun) and is_list(args) ->
            {node, [{{fun, length(args)}, meta} | acc]}

          node, acc ->
            {node, acc}
        end)

      kept = answering(out, src.mod, unresolved(calls, Deps.graph(module))).imports

      out
      |> directives(src.mod)
      |> Enum.filter(fn {kind, _, args} = import ->
        kind == :import and import in needs.answered.imports and import not in kept and not quiet?(args)
      end)
      |> reduce(out, fn {:import, target, _}, acc ->
        Directive.remove(acc, :import, target, module: src.mod)
      end)
    end
  end

  # -- directives -----------------------------------------------------------

  # The module's alias/import/require lines, one per target: `{kind, "Full.Name", args_as_written}`.
  defp directives(source, mod) do
    case scope(source, mod) do
      {:ok, module} -> module |> Tree.module_body() |> Enum.flat_map(&directive_of(&1, source, mod))
      _ -> []
    end
  end

  defp directive_of({kind, _, [{{:., _, [{:__aliases__, _, base}, :{}]}, _, subs}]}, _source, mod)
       when kind in @directives,
       do: for({:__aliases__, _, p} <- subs, do: {kind, Menard.Source.alias_name(base ++ p, mod), nil})

  defp directive_of({kind, _, [{:__aliases__, _, parts} | rest]} = node, source, mod)
       when kind in @directives do
    args =
      if rest != [] do
        source
        |> Menard.Source.slice(Sourceror.get_range(node))
        |> String.split(",", parts: 2)
        |> List.last()
        |> String.trim()
      end

    [{kind, Menard.Source.alias_name(parts, mod), args}]
  end

  defp directive_of(_node, _source, _mod), do: []

  # Which imports answer `calls`, the calls neither the module nor Kernel does. An `only:` import
  # answers its list, exactly. What an import without one brings, or a `use`, the AST cannot say:
  # such an import is taken to answer the rest only when it is the one directive that could, and
  # otherwise none is, and the rest is `open`, with the directives it may come from.
  defp answering(source, mod, calls) do
    {bare, listed} =
      source
      |> directives(mod)
      |> Enum.filter(&(elem(&1, 0) == :import))
      |> Enum.split_with(&(only(elem(&1, 2)) == nil))

    answers? = fn {:import, _, args}, call -> call in only(args) end
    by_list = Enum.filter(listed, fn import -> Enum.any?(calls, &answers?.(import, &1)) end)
    open = Enum.reject(calls, fn call -> Enum.any?(listed, &answers?.(&1, call)) end)
    uses = uses(source, mod)

    case {open, bare, uses} do
      {[], _, _} -> %{imports: by_list, open: [], from: []}
      {_, [one], []} -> %{imports: by_list ++ [one], open: [], from: []}
      _ -> %{imports: by_list, open: open, from: uses ++ Enum.map(bare, &directive_text/1)}
    end
  end

  # The module's `use` lines, as written.
  defp uses(source, mod) do
    case scope(source, mod) do
      {:ok, module} ->
        for {:use, _, [_ | _]} = node <- Tree.module_body(module),
            do: Menard.Source.slice(source, Sourceror.get_range(node))

      _ ->
        []
    end
  end

  defp only(nil), do: nil

  defp only(args) do
    case Code.string_to_quoted("[#{args}]") do
      {:ok, opts} when is_list(opts) -> if Keyword.keyword?(opts) and is_list(opts[:only]), do: opts[:only]
      _ -> nil
    end
  end

  defp quiet?(nil), do: false
  defp quiet?(args), do: args |> String.replace(" ", "") |> String.contains?("warn:false")

  # the destination's aliases as `{name, "Full.Name"}`
  defp dest_aliases(module) do
    for {:alias, _, [{:__aliases__, _, parts} | rest]} <- Tree.module_body(module) do
      full = Menard.Source.alias_name(parts)
      {short_of(full, if(rest != [], do: Sourceror.to_string(hd(rest)))), full}
    end
  end

  # Every first segment a module's body names outside its alias lines: what its aliases are used for.
  defp module_aliases(module) do
    module
    |> Tree.module_body()
    |> Enum.reject(&match?({:alias, _, _}, &1))
    |> Macro.prewalker()
    |> Enum.flat_map(fn
      {:__aliases__, _, [first | _]} when is_atom(first) -> [first]
      _ -> []
    end)
    |> Enum.uniq()
  end

  defp short_atom(target, args), do: String.to_atom(short_of(target, args))

  defp short_of(target, args) when is_binary(args) do
    case Regex.run(~r/as:\s*([A-Z][\w.]*)/, args) do
      [_, as] -> as
      nil -> short_of(target, nil)
    end
  end

  defp short_of(target, _args), do: target |> String.split(".") |> List.last()

  defp directive_text({kind, target, nil}), do: "#{kind} #{target}"
  defp directive_text({kind, target, args}), do: "#{kind} #{target}, #{args}"

  # -- shapes ---------------------------------------------------------------

  defp scope(source, mod) do
    with {:ok, ast} <- parse(source), do: Tree.module_scope(ast, mod)
  end

  defp in_order(graph), do: graph |> Map.keys() |> Enum.sort_by(&line(graph, &1))
  defp line(graph, key), do: graph[key].nodes |> hd() |> Tree.start_line()
  defp na({name, arity}), do: "#{name}/#{arity}"

  defp module_name({:defmodule, _, [{:__aliases__, _, parts} | _]}), do: Menard.Source.alias_name(parts)

  defp reduce(items, source, fun) do
    Enum.reduce_while(items, {:ok, source}, fn item, {:ok, acc} ->
      case fun.(item, acc) do
        out when is_binary(out) -> {:cont, {:ok, out}}
        error -> {:halt, error}
      end
    end)
  end

  # -- files ----------------------------------------------------------------

  defp apart(file, file), do: {:error, "the destination is the file itself — name another"}
  defp apart(_file, _dest), do: :ok

  defp with_moduledoc(dest, doc) when doc in [nil, ""], do: dest

  defp with_moduledoc(dest, doc) do
    [first, rest] = String.split(dest, "\n", parts: 2)
    "#{first}\n  @moduledoc #{inspect(doc)}\n\n#{rest}"
  end

  # Each call still naming a moved function: in the source, where nothing stands in for it now, and
  # in lib/ and test/ by the source module's name.
  defp left(root, file, moved) do
    source = File.read!(file)

    case scope(source, nil) do
      {:ok, {:defmodule, _, [{:__aliases__, _, parts} | _]}} ->
        mod = Menard.Source.alias_name(parts)
        Enum.flat_map(moved, &Menard.Find.left(root, file, source, "#{mod}.#{&1}"))

      _ ->
        []
    end
  end

  defp dest_source(dest, as, moduledoc) do
    cond do
      File.exists?(dest) and moduledoc not in [nil, ""] ->
        {:error,
         "#{dest} exists: moduledoc is for a module the move creates — attr set changes its @moduledoc"}

      File.exists?(dest) ->
        {:ok, File.read!(dest), nil}

      as not in [nil, ""] ->
        {:ok, "defmodule #{as} do\nend\n", as}

      true ->
        case derive_module(dest) do
          {:ok, mod} ->
            {:ok, "defmodule #{mod} do\nend\n", mod}

          :error ->
            {:error, "#{dest} does not exist and is not inside a mix project — name it with --as Mod.Name"}
        end
    end
  end

  # What a generator would have called it: `lib/my_app/foo/bar.ex` is `MyApp.Foo.Bar`, relative to
  # the nearest mix.exs, with `lib/` or `test/` dropped.
  defp derive_module(path) do
    with {:ok, root} <- project_root(Path.dirname(path)) do
      path
      |> Path.relative_to(root)
      |> String.replace(~r{^(lib|test)/}, "")
      |> String.replace(~r{\.exs?$}, "")
      |> Path.split()
      |> Enum.map_join(".", &Macro.camelize/1)
      |> then(&{:ok, &1})
    end
  end

  defp project_root("/"), do: :error
  defp project_root("."), do: :error

  defp project_root(dir) do
    if File.exists?(Path.join(dir, "mix.exs")),
      do: {:ok, dir},
      else: dir |> Path.dirname() |> project_root()
  end

  defp plan_blocks(source, dest_source, labels, created?) do
    with {:ok, ast} <- parse(source),
         {:ok, mod, module} <- source_module(ast, []),
         body = Tree.module_body(module),
         blocks = for({kind, _, [_ | _]} = n <- body, kind in (@tests ++ @setups), do: {block_key(n), n}),
         {:ok, named} <- labelled(blocks, labels),
         graph = Deps.graph(module, blocks),
         setups = setups(blocks, created?),
         taking = taking(named ++ setups, graph) -- setups,
         :ok <- helpers_unshared(taking, graph),
         dest_source = with_uses(dest_source, body, source, created?),
         {:ok, dest_ast} <- parse(dest_source),
         {:ok, dest_module} <- Tree.module_scope(dest_ast, nil),
         :ok <- not_in(dest_module, Enum.reject(taking, &block_key?/1)),
         {:ok, spans} <- block_spans(source, ast, mod, taking ++ setups),
         lines = String.split(source, "\n"),
         code = Enum.map_join(setups ++ taking, "\n\n", &function_text(lines, spans[&1])),
         src = %{
           source: source,
           mod: mod,
           module: module,
           graph: graph,
           named: named,
           taking: taking,
           spans: spans
         },
         {:ok, plan} <- move(src, %{code: code, dest: dest_source, module: dest_module}, []) do
      {:ok, %{plan | report: block_report(plan.report, named, taking, graph)}}
    end
  end

  # a block's key in the graph: no function's, as no function is named `#block`
  defp block_key(node), do: {:"#block", Tree.start_line(node)}

  defp block_key?(key), do: match?({:"#block", _}, key)

  defp labelled(blocks, labels) do
    Enum.reduce_while(labels, {:ok, []}, fn label, {:ok, acc} ->
      case label_key(blocks, label) do
        {:ok, key} -> {:cont, {:ok, acc ++ [key]}}
        error -> {:halt, error}
      end
    end)
  end

  defp label_key(blocks, label) do
    case for({key, {kind, _, [l | _]}} <- blocks, kind in @tests, text(l) == label, do: key) do
      [key] ->
        {:ok, key}

      [] ->
        there = for {_, {kind, _, [l | _]}} <- blocks, kind in @tests, do: inspect(text(l))

        {:error,
         "no test or describe #{inspect(label)} in this module — there are: #{Enum.join(there, ", ")}"}

      _ ->
        {:error, "#{inspect(label)} labels several tests of this module: relabel one first"}
    end
  end

  defp text({:__block__, _, [label]}) when is_binary(label), do: label
  defp text(label), do: Sourceror.to_string(label)

  defp helpers_unshared(taking, graph) do
    shared =
      for key <- taking,
          not block_key?(key),
          by = for({k, %{calls: calls}} <- graph, k not in taking, MapSet.member?(calls, key), do: k),
          by != [],
          do: {key, by}

    case shared do
      [] ->
        :ok

      shared ->
        why =
          Enum.map_join(shared, "; ", fn {key, by} ->
            "#{na(key)} by #{Enum.map_join(by, ", ", &what(graph, &1))}"
          end)

        {:error,
         "refused, nothing written: the moved tests call private helpers that stay called here too (#{why}). " <>
           "Move those tests as well, or put the helpers in a test/support module both files import"}
    end
  end

  # a key as a reader knows it: `test "a"`, `setup`, or `name/arity`
  defp what(graph, key) do
    case graph[key].nodes do
      [{kind, _, [label | _]}] when kind in @tests -> "#{kind} #{inspect(text(label))}"
      [{kind, _, _}] when kind in @setups -> "#{kind}"
      _ -> na(key)
    end
  end

  # the setups a created destination copies: the moved tests ran under them
  defp setups(_blocks, false), do: []
  defp setups(blocks, true), do: for({key, {kind, _, _}} <- blocks, kind in @setups, do: key)

  # the source's `use` lines, as written, into the module the move creates
  defp with_uses(dest_source, _body, _source, false), do: dest_source

  defp with_uses(dest_source, body, source, true) do
    lines = String.split(source, "\n")

    uses =
      for {:use, _, _} = node <- body do
        {a, b} = Tree.line_span(node)
        lines |> Enum.slice((a - 1)..(b - 1)) |> Enum.join("\n")
      end

    [first, rest] = String.split(dest_source, "\n", parts: 2)
    Enum.join([first | uses], "\n") <> "\n" <> rest
  end

  # a block with the `@tag` and comment lines above it; a helper as `clause move` takes it
  defp block_spans(source, ast, mod, keys) do
    lines = String.split(source, "\n")

    Enum.reduce_while(keys, {:ok, %{}}, fn key, {:ok, acc} ->
      case span_of(key, source, ast, lines, mod) do
        {:ok, spans} -> {:cont, {:ok, Map.put(acc, key, spans)}}
        error -> {:halt, error}
      end
    end)
  end

  defp span_of({:"#block", first}, _source, ast, lines, _mod) do
    {_, last} = ast |> Tree.modules() |> find_block(first) |> Tree.line_span()
    above = lines |> Enum.take(first - 1) |> Enum.reverse() |> Enum.take_while(&attached?/1) |> length()
    {:ok, [{first - 1 - above, last - 1}]}
  end

  defp span_of(key, source, _ast, _lines, mod), do: Clause.spans(source, "#{mod}.#{na(key)}")

  defp find_block(modules, line) do
    Enum.find_value(modules, fn {_, module} ->
      Enum.find(Tree.module_body(module), &(Tree.start_line(&1) == line))
    end)
  end

  defp attached?(line) do
    line = String.trim_leading(line)
    String.starts_with?(line, ["#", "@tag ", "@describetag "])
  end

  defp block_report(report, named, taking, graph) do
    %{
      report
      | moved: Enum.map(named, &what(graph, &1)),
        carried: taking |> Enum.reject(&block_key?/1) |> Enum.map(&na/1),
        unresolved:
          Enum.reject(report.unresolved, &(&1 |> String.split("/") |> hd() |> then(fn n -> n in @exunit end)))
    }
    |> Map.drop([:delegated, :published, :qualified])
  end
end
