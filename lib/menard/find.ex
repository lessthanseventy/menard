defmodule Menard.Find do
  @moduledoc """
  Search that knows what a call, a def or an alias is — grep for code. Every hit is
  `%{line, column, kind, text}` from the node's own source range; strings and comments never
  match. `calls/2` takes a bare local name or `Mod.fun`, and resolves the file's aliases so an
  aliased call (`Channels.general`) is found by its full name (`Server.Channels.general`).
  """

  alias Sourceror.Zipper

  @def_kinds [:def, :defp, :defmacro, :defmacrop, :defguard, :defguardp]

  @type hit :: %{line: pos_integer(), column: pos_integer(), kind: atom(), text: String.t()}

  @doc ~s|Call sites of `target`: `"fun"` (local) or `"Mod.Sub.fun"` (remote, alias-aware).|
  @spec calls(String.t(), String.t()) :: [hit()]
  def calls(source, target) do
    {mod, fun} = split_target(target)

    # a def head looks exactly like a local call — those positions are excluded
    heads = source |> walk(&def_head/2) |> MapSet.new(&{&1.line, &1.column})

    source
    |> walk(&call_to(&1, &2, mod, fun))
    |> Enum.reject(&MapSet.member?(heads, {&1.line, &1.column}))
    |> Kernel.++(heex_calls(source, mod, fun))
    |> Enum.sort_by(&{&1.line, &1.column})
  end

  defp call_to({name, _meta, args} = node, _aliases, nil, fun) when is_atom(name) and is_list(args),
    do: if(Atom.to_string(name) == fun, do: {:call, node})

  defp call_to({{:., _, [{:__aliases__, _, parts}, name]}, _meta, args} = node, aliases, mod, fun)
       when is_atom(name) and is_list(args) and not is_nil(mod) do
    if Atom.to_string(name) == fun and expand(parts, aliases) == mod, do: {:call, node}, else: nil
  end

  defp call_to(_node, _aliases, _mod, _fun), do: nil

  @doc """
  The calls to `name_arity` left in `root`'s lib/ and test/ once it is deleted from `file` (whose
  source before the delete is `source`), as `file:line: call`, one inside a test with its label: the
  file's own local calls, and every file's remote ones by the module's full name. What a
  whole-function delete answers with, so the agent fixes or deletes those on purpose.
  """
  def left(root, file, source, name_arity) do
    [spec | _] = String.split(name_arity, "/")

    {mod, fun} =
      case String.split(spec, ".") do
        [fun] -> {own_module(source), fun}
        parts -> {parts |> Enum.drop(-1) |> Enum.join("."), List.last(parts)}
      end

    # Never raises: the delete this answers for is already written, and a raise lost its reply. An
    # empty lib/ holds no calls (files/1 calls it an error), and a file that cannot be read says so.
    files = for dir <- ["lib", "test"], f <- Path.wildcard(Path.join([root, dir, "**/*.{ex,exs}"])), do: f

    for f <- Enum.uniq([file | files]), line <- left_in(f, root, f == file, mod, fun), do: line
  end

  defp left_in(f, root, own?, mod, fun) do
    case File.read(f) do
      {:ok, text} ->
        text |> left_hits(own?, mod, fun) |> Enum.map(&left_line(f, root, text, &1))

      {:error, reason} ->
        ["#{Path.relative_to(f, root)}: not read (#{:file.format_error(reason)})"]
    end
  end

  # every file's remote calls by the module's full name, and the file's own local ones
  defp left_hits(text, own?, mod, fun) do
    remote = if mod, do: calls(text, "#{mod}.#{fun}"), else: []
    local = if own?, do: calls(text, fun), else: []
    remote ++ local
  end

  defp left_line(f, root, text, hit) do
    test =
      text
      |> Menard.Block.list()
      |> List.wrap()
      |> Enum.filter(&match?({:test, _label, line} when line <= hit.line, &1))
      |> List.last()

    where = Path.relative_to(f, root) <> ":#{hit.line}"
    if test, do: ~s(#{where}, in test "#{elem(test, 1)}": #{hit.text}), else: "#{where}: #{hit.text}"
  end

  defp own_module(source) do
    with {:ok, ast} <- Menard.Source.parse(source),
         [{name, _node} | _] <- Menard.Clause.modules(ast),
         do: name,
         else: (_ -> nil)
  end

  # ~H is a string to the AST, so a call in its `{…}` or `<%= … %>` was never found: explore-callers
  # answered two callers of four. Those are Elixir, matched as written (`Alias.fun(` or `fun(`);
  # the markup around them is not.
  defp heex_calls(source, mod, fun) do
    case Sourceror.parse_string(source) do
      {:ok, ast} ->
        aliases = collect_aliases(ast)
        name = Regex.escape(to_string(fun))

        call =
          if mod,
            do: ~r/(?<![\w.@:])((?:[A-Z]\w*\.)+)#{name}\(/,
            else: ~r/(?<![\w.@:?!])()#{name}\(/

        for {:sigil_H, _meta, _args} = node <- ast |> Macro.prewalker() |> Enum.to_list(),
            {line, column, code} <- Menard.Source.heex_expressions(source, node),
            [{at, _}, {m, ml}] <- Regex.scan(call, code, return: :index),
            is_nil(mod) or expand(module_parts(binary_part(code, m, ml)), aliases) == mod do
          {line, column} = Menard.Source.advance({line, column}, binary_part(code, 0, at))
          rest = binary_part(code, at, byte_size(code) - at)

          %{
            line: line,
            column: column,
            kind: :call,
            text: rest |> String.split("\n") |> hd() |> String.trim()
          }
        end

      _ ->
        []
    end
  end

  defp module_parts(prefix),
    do: prefix |> String.trim_trailing(".") |> String.split(".")

  defp def_head({kind, _meta, [head | _]}, _aliases) when kind in @def_kinds, do: {:head, strip_guard(head)}
  defp def_head(_node, _aliases), do: nil

  defp strip_guard({:when, _, [call | _]}), do: call
  defp strip_guard(call), do: call

  @doc "Definitions of `name` or `name/arity`, any def kind."
  @spec defs(String.t(), String.t()) :: [hit()]
  def defs(source, name_arity) do
    {name, arity} = split_name_arity(name_arity)
    walk(source, &def_of(&1, &2, name, arity))
  end

  defp def_of({kind, _meta, [head | _]} = node, _aliases, name, arity) when kind in @def_kinds do
    case def_name_arity(head) do
      {n, a} when is_atom(n) and (is_nil(arity) or a == arity) ->
        if Atom.to_string(n) == name, do: {kind, node, head_only(kind, head)}

      _ ->
        nil
    end
  end

  defp def_of(_node, _aliases, _name, _arity), do: nil

  @doc "Where module `mod` is aliased (`alias A.B` or `alias A.{B, C}`)."
  @spec aliases(String.t(), String.t()) :: [hit()]
  def aliases(source, mod) do
    walk(source, &alias_of(&1, &2, mod))
  end

  defp alias_of({:alias, _meta, [{:__aliases__, _, parts}]} = node, _aliases, mod) do
    if Menard.Source.alias_name(parts) == mod, do: {:alias, node}, else: nil
  end

  defp alias_of({:alias, _meta, [{{:., _, [{:__aliases__, _, base}, :{}]}, _, subs}]} = node, _aliases, mod) do
    if Enum.any?(subs, fn {:__aliases__, _, p} -> Menard.Source.alias_name(base ++ p) == mod end),
      do: {:alias, node},
      else: nil
  end

  defp alias_of(_node, _aliases, _mod), do: nil

  @doc """
  The files `paths` name, for either door: a directory is its Elixir files, a glob its matches. A
  path that matches nothing is an error, not an empty answer that reads as "no references".
  """
  @spec files([String.t()]) :: {:ok, [String.t()]} | {:error, String.t()}
  def files(paths) do
    Enum.reduce_while(paths, {:ok, []}, fn path, {:ok, acc} ->
      found =
        if File.dir?(path), do: Path.wildcard(Path.join(path, "**/*.{ex,exs}")), else: Path.wildcard(path)

      if found == [], do: {:halt, {:error, "#{path} matches no file"}}, else: {:cont, {:ok, acc ++ found}}
    end)
  end

  # -- walking ---------------------------------------------------------------

  # Walk every node with the aliases seen so far (a flat, file-wide map — good enough for a
  # module's worth of `alias` lines); `match.(node, aliases)` answers `{kind, node_to_report}`.
  defp walk(source, match) do
    case Sourceror.parse_string(source) do
      {:ok, ast} ->
        aliases = collect_aliases(ast)

        ast
        |> Zipper.zip()
        |> Zipper.traverse([], &add_hit(&1, &2, match.(Zipper.node(&1), aliases)))
        |> elem(1)
        |> Enum.reverse()

      {:error, _} ->
        []
    end
  end

  defp add_hit(z, acc, {kind, report}), do: {z, [hit(kind, report, nil) | acc]}
  defp add_hit(z, acc, {kind, report, text}), do: {z, [hit(kind, report, text) | acc]}
  defp add_hit(z, acc, nil), do: {z, acc}

  defp hit(kind, node, text) do
    text = text || one_line(node)

    case Sourceror.get_range(node) do
      %{start: [line: l, column: c]} -> %{line: l, column: c, kind: kind, text: text}
      _ -> %{line: 0, column: 0, kind: kind, text: text}
    end
  end

  defp one_line(node), do: node |> Sourceror.to_string() |> String.split("\n") |> List.first()

  # `def name(args)` as text, without the body — the head is what a search shows.
  defp head_only(kind, head), do: "#{kind} " <> Sourceror.to_string(head)

  # `alias __MODULE__.X` means the module it is written in, so each module's aliases are read with its name.
  defp collect_aliases(ast) do
    ast
    |> Menard.Clause.modules()
    |> Enum.reduce(aliases_in(ast, nil), fn {mod, node}, acc -> Map.merge(acc, aliases_in(node, mod)) end)
  end

  defp aliases_in(ast, current) do
    ast
    |> Zipper.zip()
    |> Zipper.traverse(%{}, fn z, acc ->
      case Zipper.node(z) do
        {:alias, _, [{:__aliases__, _, parts}]} ->
          {z, Map.put(acc, to_string(List.last(parts)), Menard.Source.alias_name(parts, current))}

        {:alias, _, [{{:., _, [{:__aliases__, _, base}, :{}]}, _, subs}]} ->
          {z,
           Enum.reduce(subs, acc, fn {:__aliases__, _, p}, a ->
             Map.put(a, to_string(List.last(p)), Menard.Source.alias_name(base ++ p, current))
           end)}

        _ ->
          {z, acc}
      end
    end)
    |> elem(1)
  end

  # A module reference's full name: the first segment may be an alias. Names are text, the aliases'
  # and the target's alike: String.to_atom on every target asked for made an atom per call, and the
  # VM never collects one
  defp expand([first | rest], aliases) do
    case Map.fetch(aliases, Menard.Source.alias_name([first])) do
      {:ok, full} -> Enum.join([full | Enum.map(rest, &to_string/1)], ".")
      :error -> Menard.Source.alias_name([first | rest])
    end
  end

  defp split_target(target) do
    case String.split(target, ".") do
      [fun] -> {nil, fun}
      parts -> {parts |> Enum.drop(-1) |> Enum.join("."), List.last(parts)}
    end
  end

  defp split_name_arity(spec) do
    case String.split(spec, "/") do
      [name, arity] -> {name, String.to_integer(arity)}
      [name] -> {name, nil}
    end
  end

  defp def_name_arity({:when, _, [call | _]}), do: def_name_arity(call)
  defp def_name_arity({name, _, args}) when is_list(args), do: {name, length(args)}
  defp def_name_arity({name, _, _}), do: {name, 0}
end
