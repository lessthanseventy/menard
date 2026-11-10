defmodule Menard.Rename do
  @moduledoc """
  Rename an identifier in Elixir source by walking its AST (Sourceror), so a rename lands on
  every def/defp head, call, capture and variable and never on a string or a comment. The file is
  PATCHED, not reprinted: each matched node's source range is replaced in place, so every other
  byte — comments, blank lines, the project's own formatting — is untouched. `atoms: true` also
  renames the bare atom `:old` and the keyword/map key `old:`; `comments: true` the whole-word
  mentions inside `#` comments. The operator's door is
  `mix menard.rename`; a coworker's is the same function behind an MCP verb.
  """

  alias Sourceror.Zipper

  @def_kinds Menard.Tree.def_kinds()

  @module ~r/^[A-Z][A-Za-z0-9_]*(\.[A-Z][A-Za-z0-9_]*)*$/
  @name ~r/^[a-z_][A-Za-z0-9_]*[?!]?$/
  @reserved ~w(do end fn true false nil when and or not in after else catch rescue)

  @spec run(String.t(), String.t(), String.t(), keyword()) :: String.t() | {:error, String.t()}
  def run(source, old, new, opts \\ [])

  def run(source, old, new, opts) when is_binary(source) and is_binary(old) and old != "" do
    with :ok <- check(old, new) do
      cond do
        old =~ @module -> module(source, old, new)
        String.contains?(old, ".") -> qualified(source, old, new)
        true -> by_name(source, old, new, opts)
      end
    end
  end

  @doc """
  `:ok`, or why `old` cannot become `new`: a new name that is not one (written as given, `bad name(`
  parsed as a call of `bad`), a module renamed to a function's name or the other way, or an arity
  on `old`, where a rename is of the name, every arity of it.
  """
  @spec check(String.t(), String.t()) :: :ok | {:error, String.t()}
  def check(old, new) do
    cond do
      String.contains?(old, "/") ->
        {:error,
         "rename takes a name and renames every arity of it: #{old} names one. Give it without the arity"}

      old =~ @module and new =~ @module ->
        :ok

      old =~ @module ->
        {:error, "rename: #{old} is a module, and #{inspect(new)} is no module's name (Shop.Cart)"}

      new =~ @name and new not in @reserved ->
        :ok

      true ->
        {:error,
         "rename: #{inspect(new)} is no name for a function or a variable (the new name alone, as `total` or `valid?`, " <>
           "not `Mod.total`)"}
    end
  end

  # `old` as a module: every alias that spells it — its defmodule, `alias Old`, `Old.fun` calls and
  # captures, and the modules nested under it (`Old.Error`), whose names change with it. A bare
  # `Last` that an `alias Old` or `alias Base.{Last}` binds still reaches it unless the last segment
  # changed, when those take the new last segment. Code only: strings, docs and comments stay
  defp module(source, old, new) do
    with {:ok, ast} <- Menard.Source.parse(source),
         {:ok, inside} <- defined_inside(ast, old, new),
         do: Menard.Source.patch(source, module_patches(ast, source, old, new, inside))
  end

  # `old` where it is defined inside its parent (`defmodule Cart` in `defmodule Shop`): the
  # `defmodule`s, which spell only its last segment. Renamed there when the new name stays under the
  # same parent; moved to another, it is not a rename of names
  defp defined_inside(ast, old, new) do
    {parent, last} = old |> String.split(".") |> Enum.split(-1)
    parent = Enum.join(parent, ".")

    inside =
      for {^old, {:defmodule, _, [name | _]} = node} <- Menard.Tree.modules(ast),
          spelled(name) != old,
          do: node

    cond do
      inside == [] ->
        {:ok, []}

      String.starts_with?(new, parent <> ".") and
          Enum.all?(inside, fn {:defmodule, _, [name | _]} -> [spelled(name)] == last end) ->
        {:ok, inside}

      true ->
        {:error,
         "rename: #{old} is defined inside #{parent} (a `defmodule` in its body), so it is renamed " <>
           "under #{parent} (#{parent}.New), or moved out of it by hand first"}
    end
  end

  defp module_patches(ast, source, old, new, inside) do
    {last_old, last_new} =
      {old |> String.split(".") |> List.last(), new |> String.split(".") |> List.last()}

    defined = MapSet.new(inside, fn {:defmodule, meta, _} -> {meta[:line], meta[:column]} end)
    scopes = if last_old == last_new, do: MapSet.new(), else: binding_scopes(ast, old, defined)
    moved = Enum.flat_map(Macro.prewalker(ast), &List.wrap(leaving_patch(&1, source, old, new)))

    patches =
      ast
      |> Zipper.zip()
      |> Zipper.traverse([], fn z, acc ->
        short? = bound?(z, scopes)
        {z, List.wrap(module_patch(Zipper.node(z), source, {old, new}, {last_old, last_new, short?})) ++ acc}
      end)
      |> elem(1)
      |> Enum.reject(fn %{range: %{start: at}} ->
        Enum.any?(moved, &(at >= &1.range.start and at <= &1.range.end))
      end)

    moved ++ patches
  end

  # the scopes where an `alias` binds the bare last segment: `:root` for the file's own top level,
  # else the `defmodule`s, by position. A scope's own body counts, not a module nested in it, which
  # inherits the binding from where it sits
  defp binding_scopes(ast, old, defined \\ MapSet.new()) do
    for {:defmodule, meta, [_name, body]} <- Macro.prewalker(ast),
        scope_binds?(body, old, defined),
        into: if(scope_binds?(ast, old, defined), do: MapSet.new([:root]), else: MapSet.new()),
        do: {meta[:line], meta[:column]}
  end

  # a module defined here by its last segment is named by it here, as one aliased is
  defp scope_binds?({:defmodule, meta, _}, _old, defined), do: {meta[:line], meta[:column]} in defined

  defp scope_binds?(node, old, defined) do
    cond do
      binds?(node, old) ->
        true

      match?({_, _, args} when is_list(args), node) ->
        Enum.any?([elem(node, 0) | elem(node, 2)], &scope_binds?(&1, old, defined))

      is_tuple(node) and tuple_size(node) == 2 ->
        Enum.any?(Tuple.to_list(node), &scope_binds?(&1, old, defined))

      is_list(node) ->
        Enum.any?(node, &scope_binds?(&1, old, defined))

      true ->
        false
    end
  end

  defp bound?(z, scopes), do: :root in scopes or inside_bound?(z, scopes)

  defp inside_bound?(nil, _scopes), do: false

  defp inside_bound?(z, scopes) do
    case Zipper.node(z) do
      {:defmodule, meta, _} -> {meta[:line], meta[:column]} in scopes or inside_bound?(Zipper.up(z), scopes)
      _ -> inside_bound?(Zipper.up(z), scopes)
    end
  end

  # `alias Acme.{Billing, X}` renamed to another base cannot keep the entry in the braces: it
  # becomes its own `alias New`, and the braces keep the rest
  defp leaving_patch({:alias, meta, [{{:., _, [base, :{}]}, _, entries}]} = node, source, old, new) do
    prefix = spelled(base)
    new_base = new |> String.split(".") |> Enum.drop(-1) |> Enum.join(".")

    {gone, rest} =
      Enum.split_with(
        entries,
        &(is_binary(prefix) and spelled(&1) != nil and prefix <> "." <> spelled(&1) == old)
      )

    if gone != [] and new_base != prefix do
      kept =
        case Enum.map(rest, &Sourceror.to_string/1) do
          [] -> []
          [one] -> ["alias #{prefix}.#{one}"]
          many -> ["alias #{prefix}.{#{Enum.join(many, ", ")}}"]
        end

      change = Enum.join(kept ++ ["alias #{new}"], "\n" <> String.duplicate(" ", meta[:column] - 1))
      %{range: Menard.Source.range(node, source), change: change}
    end
  end

  defp leaving_patch(_node, _source, _old, _new), do: nil

  defp module_patch(node, source, {old, new}, {last_old, last_new, short?}) do
    name = spelled(node)

    case renamed(name, old, new) || (short? && renamed(name, last_old, last_new)) do
      change when is_binary(change) -> %{range: Menard.Source.range(node, source), change: change}
      _ -> nil
    end
  end

  defp renamed(nil, _old, _new), do: nil
  defp renamed(old, old, new), do: new

  defp renamed(name, old, new) do
    if String.starts_with?(name, old <> "."),
      do: new <> binary_part(name, byte_size(old), byte_size(name) - byte_size(old))
  end

  # an alias that makes the module's last segment name it: `alias Old` with no `as:`, or an entry
  # of `alias Base.{…}`
  defp binds?({:alias, _meta, [{{:., _, [base, :{}]}, _, entries} | _]}, old) do
    prefix = spelled(base)
    is_binary(prefix) and Enum.any?(entries, &(spelled(&1) != nil and prefix <> "." <> spelled(&1) == old))
  end

  defp binds?({:alias, _meta, [target]}, old), do: spelled(target) == old
  defp binds?({:alias, _meta, [target, opts]}, old), do: spelled(target) == old and not as?(opts)
  defp binds?(_node, _old), do: false

  defp as?(opts) when is_list(opts), do: Enum.any?(opts, &match?({{:__block__, _, [:as]}, _}, &1))
  defp as?(_opts), do: false

  defp spelled({:__aliases__, _meta, parts}) when is_list(parts) do
    if Enum.all?(parts, &is_atom/1), do: Enum.map_join(parts, ".", &Atom.to_string/1)
  end

  defp spelled(_node), do: nil

  # `old` as `Mod.fun`: that module's function alone, by what `find calls` resolves to it: its def
  # heads in `Mod` (a nested module's are its own), calls through an alias or an import,
  # `__MODULE__.fun` and bare calls inside `Mod`, and the captures of each. Code only: docs and
  # comments stay
  defp qualified(source, old, new) do
    [spec | _] = String.split(old, "/")
    parts = String.split(spec, ".")
    {mod, fun} = {parts |> Enum.drop(-1) |> Enum.join("."), List.last(parts)}

    with {:ok, ast} <- Menard.Source.parse(source),
         :ok <- apart(source, fun, new, &(&1 == mod)) do
      own = own_lines(ast, source, mod)
      at = fn %{line: l, column: c, text: text} -> {l, c + name_offset(text, fun)} end
      remote = Enum.map(Menard.Find.calls(source, spec), at)
      local = for hit <- Menard.Find.calls(source, fun), hit.line in own, do: at.(hit)

      patches =
        for {l, c} <- Enum.uniq(Menard.Find.def_sites(source, mod, fun) ++ remote ++ local),
            do: %{
              range: %{start: [line: l, column: c], end: [line: l, column: c + String.length(fun)]},
              change: new
            }

      Menard.Source.patch(source, patches ++ imported(ast, mod, fun, new))
    end
  end

  # the function in the `only:`/`except:` of an import of `mod`, by its full name or the last
  # segment an alias of it binds
  defp imported(ast, mod, fun, new) do
    last = mod |> String.split(".") |> List.last()
    short? = MapSet.size(binding_scopes(ast, mod)) > 0

    case existing_atom(fun) do
      nil ->
        []

      from ->
        for {:function, patch} <-
              import_patches(ast, from, new, &(spelled(&1) == mod or (short? and spelled(&1) == last))),
            do: patch
    end
  end

  # where the name is in a hit's text: `Channels.general(ws.id)`, `&general/1`, `general(1)`
  defp name_offset(text, fun) do
    case Regex.run(~r/(?<![\w])#{Regex.escape(fun)}(?![\w?!])/, text, return: :index) do
      [{at, _}] -> at
      nil -> 0
    end
  end

  # the lines of module `mod`, its nested modules' left out
  defp own_lines(ast, source, mod) do
    modules = Menard.Tree.modules(ast)

    span = fn node ->
      %{start: [{:line, a} | _], end: [{:line, b} | _]} = Menard.Source.range(node, source)
      MapSet.new(a..b//1)
    end

    case List.keyfind(modules, mod, 0) do
      nil ->
        MapSet.new()

      {_mod, node} ->
        nested = for {name, n} <- modules, String.starts_with?(name, mod <> "."), do: span.(n)
        Enum.reduce(nested, span.(node), &MapSet.difference(&2, &1))
    end
  end

  # A module that defines `old/n` and `new/n` both: renamed, the two are one function, its clauses
  # whichever came first, and it compiles. Refused, where the outline names both.
  defp apart(source, old, new, of?) do
    with {:ok, modules} <- Menard.Outline.run(source) do
      modules
      |> flat()
      |> Enum.filter(&of?.(&1.module))
      |> Enum.find_value(:ok, fn m ->
        arities = fn name -> for d <- m.defs, Atom.to_string(d.name) == name, uniq: true, do: d.arity end

        case arities.(old) -- (arities.(old) -- arities.(new)) do
          [] ->
            nil

          [n | _] ->
            {:error,
             "rename: #{m.module} already has #{new}/#{n}, and #{old}/#{n} would become more of its clauses"}
        end
      end)
    end
  end

  defp flat(modules), do: Enum.flat_map(modules, &[&1 | flat(&1.modules)])

  defp by_name(source, old, new, opts) do
    with {:ok, ast} <- Menard.Source.parse(source),
         :ok <- if(opts[:only] == :variables, do: :ok, else: apart(source, old, new, fn _ -> true end)) do
      Menard.Source.patch(
        source,
        code_patches(ast, old, new, opts) ++
          comment_patches(source, old, new, Keyword.get(opts, :comments, false)) ++
          heex_patches(ast, source, old, new, opts[:only]) ++
          doc_patches(ast, source, old, new, Keyword.get(opts, :docs, true) and opts[:only] != :variables)
      )
    end
  end

  # The name is an atom only once the source is parsed, and only if that parse made it: a name the
  # source never mentions has nothing to rename in the AST, and String.to_atom made an atom per call
  # that the VM never collects
  defp code_patches(ast, old, new, opts) do
    case existing_atom(old) do
      nil ->
        []

      from ->
        functions = function_positions(ast, from)
        attributes = if opts[:only], do: attribute_starts(ast, from), else: []

        ast
        |> patches(from, new, Keyword.get(opts, :atoms, false))
        |> Kernel.++(import_patches(ast, from, new))
        |> Kernel.++(keyed_patches(ast, from, new))
        |> Enum.filter(&wanted?(&1, opts[:only], functions))
        |> Enum.map(&elem(&1, 1))
        |> Enum.reject(&(&1.range.start in attributes))
        # `atoms: true` renames the import's key as an atom too
        |> Enum.uniq_by(& &1.range)
    end
  end

  defp existing_atom(name) do
    String.to_existing_atom(name)
  rescue
    ArgumentError -> nil
  end

  # `only:` narrows by what a name IS. A call with args, a remote call and a def head with args are
  # functions; a bare name is a variable unless it sits where only a function can — a zero-arity def
  # head, or `&name/arity`. A zero-arity call written without parens stays ambiguous, read as a variable.
  defp wanted?({:atom, _patch}, _only, _functions), do: true
  defp wanted?(_tagged, nil, _functions), do: true
  defp wanted?({:function, _patch}, only, _functions), do: only == :functions
  defp wanted?({{:bare, at}, _patch}, only, functions), do: at in functions == (only == :functions)

  defp function_positions(ast, from) do
    ast
    |> Zipper.zip()
    |> Zipper.traverse([], fn z, acc ->
      case Zipper.node(z) do
        {kind, _, [head | _]} when kind in @def_kinds ->
          {z, bare_start(strip_when(head), from) ++ acc}

        {:&, _, [{:/, _, [name, _arity]}]} ->
          {z, bare_start(name, from) ++ acc}

        _ ->
          {z, acc}
      end
    end)
    |> elem(1)
  end

  # `@old` is an attribute, neither a function nor a variable: under `only:` its name stays, where
  # `only: :functions` renamed `@old 1` and left every `@old` read, and the module stopped compiling
  defp attribute_starts(ast, from) do
    for {:@, _, [{^from, _, _} = name]} <- ast |> Macro.prewalker() |> Enum.to_list(),
        do: Sourceror.get_range(name).start
  end

  # `import B, only: [old: 1]` names the function by a key: left as it was, it asks B for a function
  # the rename took away
  defp import_patches(ast, from, new, of? \\ fn _module -> true end) do
    for {:import, _, [module, opts]} <- ast |> Macro.prewalker() |> Enum.to_list(),
        is_list(opts) and of?.(module),
        {{:__block__, _, [key]}, {:__block__, _, [names]}} <- opts,
        key in [:only, :except] and is_list(names),
        {{:__block__, _, [^from]} = name, _arity} <- names,
        do: {:function, %{range: Sourceror.get_range(name), change: "#{new}:"}}
  end

  # `defoverridable old: 1` and `@compile {:inline, old: 1}` name the function by a key too
  defp keyed_patches(ast, from, new) do
    for node <- ast |> Macro.prewalker() |> Enum.to_list(),
        keyed?(node),
        {{:__block__, _, [^from]} = name, {:__block__, _, [arity]}} <- Macro.prewalker(node),
        is_integer(arity),
        do: {:function, %{range: Sourceror.get_range(name), change: "#{new}:"}}
  end

  defp keyed?({:defoverridable, _, [_ | _]}), do: true
  defp keyed?({:@, _, [{attribute, _, [_ | _]}]}), do: attribute in [:compile, :dialyzer]
  defp keyed?(_node), do: false

  defp strip_when({:when, _, [head | _]}), do: head
  defp strip_when(head), do: head

  defp bare_start({from, _meta, ctx} = node, from) when is_atom(ctx), do: [Sourceror.get_range(node).start]
  defp bare_start(_node, _from), do: []

  # Comments are not AST: a whole-word mention (`\bold\b`) inside a `#` comment is patched by its
  # own range. The word boundary keeps `old_extra` and the like alone. The comments are the
  # parser's, so a `#` line of a heredoc or of ~H markup is text, not one: a scan of each line for
  # its first `#` renamed inside both.
  defp comment_patches(_source, _old, _new, false), do: []

  defp comment_patches(source, old, new, true) do
    word = ~r/(?<![A-Za-z0-9_])#{Regex.escape(old)}(?![A-Za-z0-9_])/
    {:ok, _ast, comments} = Code.string_to_quoted_with_comments(source, emit_warnings: false)

    Enum.flat_map(comments, fn %{line: no, column: c, text: text} ->
      mention_patches(text, no, c - 1, word, new)
    end)
  end

  # @doc/@moduledoc/@typedoc text is prose ABOUT the code, and a doctest in it is code: a rename that
  # left `old/1` there or `iex> A.old(1)` (a doctest that no longer runs) is half done. Only
  # mentions that read as code: before `(` or `/arity`, or inside backticks; "the old way" is a
  # word, not the function.
  defp doc_patches(_ast, _source, _old, _new, false), do: []

  defp doc_patches(ast, source, old, new, true) do
    lines = String.split(source, "\n")
    name = Regex.escape(old)
    code_like = ~r/(?<![A-Za-z0-9_])#{name}(?=\(|\/\d)/
    in_ticks = ~r/`[^`\n]*`/
    word = ~r/(?<![A-Za-z0-9_])#{name}(?![A-Za-z0-9_?!])/

    for {:@, _, [{doc, _, [value]}]} <- ast |> Macro.prewalker() |> Enum.to_list(),
        doc in [:doc, :moduledoc, :typedoc],
        %{start: [line: a, column: _], end: [line: b, column: _]} <- [Sourceror.get_range(value)],
        no <- a..b,
        line = Enum.at(lines, no - 1, ""),
        offset <- doc_mentions(line, code_like, in_ticks, word),
        uniq: true do
      c = String.length(binary_part(line, 0, offset)) + 1
      %{range: %{start: [line: no, column: c], end: [line: no, column: c + String.length(old)]}, change: new}
    end
  end

  defp doc_mentions(line, code_like, in_ticks, word) do
    calls = for [{off, _}] <- Regex.scan(code_like, line, return: :index), do: off

    ticked =
      for [{t, len}] <- Regex.scan(in_ticks, line, return: :index),
          [{off, _}] <- Regex.scan(word, binary_part(line, t, len), return: :index),
          do: t + off

    Enum.uniq(calls ++ ticked)
  end

  # ranges are 1-based columns, in graphemes
  defp mention_patches(comment, no, col0, word, new) do
    for [{off, len}] <- Regex.scan(word, comment, return: :index) do
      c = String.length(binary_part(comment, 0, off)) + col0 + 1
      %{range: %{start: [line: no, column: c], end: [line: no, column: c + len]}, change: new}
    end
  end

  defp patches(ast, from, new, atoms?) do
    ast
    |> Zipper.zip()
    |> Zipper.traverse([], fn z, acc ->
      case patch_for(Zipper.node(z), from, new, atoms?) do
        nil -> {z, acc}
        patch -> {z, [patch | acc]}
      end
    end)
    |> elem(1)
  end

  # A local call / def head / variable: `{name, meta, args_or_context}` — the identifier is the
  # first `String.length(old)` bytes of the node's range.
  defp patch_for({from, _meta, args} = node, from, new, _atoms?) when is_list(args) or is_atom(args) do
    with %{} = patch <- ident_patch(node, from, new),
         do: {if(is_list(args), do: :function, else: {:bare, patch.range.start}), patch}
  end

  # A bare atom or a keyword key is a literal Sourceror wraps: `{:__block__, meta, [:old]}`.
  # `:old` → `:new`; the key form `old:` → `new:` (Sourceror marks it `format: :keyword`).
  defp patch_for({:__block__, meta, [from]} = node, from, new, true) do
    case Sourceror.get_range(node) do
      nil -> nil
      range -> {:atom, %{range: range, change: if(meta[:format] == :keyword, do: "#{new}:", else: ":#{new}")}}
    end
  end

  # A remote call or capture on a module (`B.old(1)`, `&B.old/1`, `__MODULE__.old()`): the call's own
  # meta points at the name. On a variable (`map.old`) it is a field access, and stays.
  defp patch_for({{:., _dot, [receiver, from]}, meta, _args}, from, new, _atoms?) do
    if module_ref?(receiver) and meta[:line] do
      len = String.length(Atom.to_string(from))

      {:function,
       %{
         range: %{
           start: [line: meta[:line], column: meta[:column]],
           end: [line: meta[:line], column: meta[:column] + len]
         },
         change: new
       }}
    end
  end

  defp patch_for(_node, _from, _new, _atoms?), do: nil

  defp module_ref?({:__aliases__, _meta, _parts}), do: true
  defp module_ref?({:__MODULE__, _meta, _ctx}), do: true
  defp module_ref?({:__block__, _meta, [mod]}) when is_atom(mod), do: true
  defp module_ref?(_receiver), do: false

  defp ident_patch(node, from, new) do
    case Sourceror.get_range(node) do
      %{start: [line: l, column: c]} ->
        len = String.length(Atom.to_string(from))
        %{range: %{start: [line: l, column: c], end: [line: l, column: c + len]}, change: new}

      _ ->
        nil
    end
  end

  # ~H is a string to the AST, so the calls in its `{…}` and `<%= %>` kept the old name: the rename
  # said the file was done, and the project stopped compiling. A call written there, `old(` alone or
  # after a module's dot, is patched too; an assign `@old` or an atom `:old` is not a call.
  defp heex_patches(_ast, _source, _old, _new, :variables), do: []

  defp heex_patches(ast, source, old, new, _only) do
    call = ~r/(?<![A-Za-z0-9_@:?!])#{Regex.escape(old)}(?=\()/
    lines = String.split(source, "\n")

    ast
    |> Macro.prewalker()
    |> Enum.flat_map(fn
      {:sigil_H, _meta, _args} = node -> sigil_patches(node, lines, call, new)
      _node -> []
    end)
  end

  defp sigil_patches(node, lines, call, new) do
    %{start: [line: a, column: ca], end: [line: b, column: cb]} = Sourceror.get_range(node)

    Enum.flat_map(a..b, fn no ->
      line = Enum.at(lines, no - 1, "")
      from = if no == a, do: ca, else: 1
      to = if no == b, do: cb, else: String.length(line) + 1
      line |> String.slice(from - 1, to - from) |> mention_patches(no, from - 1, call, new)
    end)
  end
end
