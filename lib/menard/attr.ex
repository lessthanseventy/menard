defmodule Menard.Attr do
  @moduledoc """
  Module attributes — `@hints`, `@colors`, `@panes`, `@kinds`. The tables a module keeps at the
  top, which every clause verb walks straight past because an attribute is not a clause.

  Addressed by NAME. A name several attributes share is refused with their lines rather than
  guessed at — `@doc`, `@impl` and `@spec` repeat per clause by design, and those belong to the
  clause verbs (`Menard.Clause.delete/4` takes them with the clause; `visibility/3` drops a `@doc`
  when it privatises).
  """

  import Menard.Source, only: [delete_lines: 3, parse: 1, patch: 3, reindent: 2]
  alias Menard.Tree

  @def_kinds Tree.def_kinds()

  # written above one def and belonging to it, as Menard.Clause's @attached
  @per_definition [:doc, :spec, :impl, :deprecated, :dialyzer]

  @doc "The attribute's value exactly as written, or `{:error, …}` if it is missing or ambiguous."
  @spec get(String.t(), String.t() | atom(), keyword()) :: String.t() | {:error, String.t()}
  def get(source, name, opts \\ []) do
    with {:ok, node} <- located(source, name, opts), do: value_text(node, source)
  end

  @doc """
  Set `@name` to `value` (the value as you would write it). Replaces the existing attribute's
  value, or adds the attribute when it isn't there yet — at the TOP of the module's tables, above
  the first attribute or definition, since an attribute another attribute reads must precede it.
  """
  @spec set(String.t(), String.t() | atom(), String.t(), keyword()) :: String.t() | {:error, String.t()}
  def set(source, name, value, opts \\ []) do
    value = own_value(name, value)

    case one(source, name, opts) do
      {:ok, node} -> replace(source, node, name, value)
      {:error, :missing} -> add(source, name, value, opts)
      {:error, message} -> {:error, message}
    end
  end

  @doc "Remove the attribute and the lines it occupies."
  @spec delete(String.t(), String.t() | atom(), keyword()) :: String.t() | {:error, String.t()}
  def delete(source, name, opts \\ []) do
    with {:ok, body} <- body(source, opts),
         {:ok, node} <- located(source, name, opts) do
      %{start: [line: a, column: _], end: [line: b, column: _]} = Sourceror.get_range(node)
      # Under a def's own @doc or @spec, the blank line after it would part them from the def they
      # belong to: it goes too. Anywhere else a blank on each side is the formatter's to fold.
      above = body |> Enum.take_while(&(&1 != node)) |> List.last()
      next_blank? = source |> String.split("\n") |> Enum.at(b) |> Kernel.==("")
      b = if attr_name(above) in @per_definition and next_blank?, do: b + 1, else: b
      delete_lines(source, a, b)
    end
  end

  @doc "Every attribute the module sets, as `{name, line}` in source order — the read half."
  @spec list(String.t(), keyword()) :: [{atom(), pos_integer()}] | {:error, String.t()}
  def list(source, opts \\ []) do
    with {:ok, body} <- body(source, opts) do
      for node <- body, name = attr_name(node), not is_nil(name), do: {name, Tree.start_line(node)}
    end
  end

  # -- locating ------------------------------------------------------------

  # `one/3` with a missing attribute named: `set` adds one instead, and is the only caller that
  # wants the bare `:missing`.
  defp located(source, name, opts) do
    with {:error, :missing} <- one(source, name, opts), do: {:error, missing(source, name)}
  end

  # `attr :product, …` in a component is Phoenix's declaration, not a module attribute: bench4
  # new-component.B.haiku tried to delete one here and was told only that there was no @product
  defp missing(source, name) do
    name = name |> to_string() |> String.trim_leading("@")

    if source =~ ~r/^\s*(attr|slot)\s+:#{Regex.escape(name)}\b/m,
      do:
        "no @#{name} in this module; `attr :#{name}` here is a Phoenix component declaration, which goes " <>
          "with the def below it (clause get/delete/move carry it), and stmt reaches it as a statement of the module",
      else: "no @#{name} in this module"
  end

  defp one(source, name, opts) do
    want = key(name)

    with {:ok, body} <- body(source, opts) do
      case Enum.filter(body, &named?(&1, want)) do
        [node] ->
          {:ok, node}

        [] ->
          {:error, :missing}

        many ->
          lines = Enum.map_join(many, ", ", &to_string(Tree.start_line(&1)))

          {:error,
           "@#{want} is set #{length(many)} times (lines #{lines}) — attributes that repeat per clause belong to the clause verbs"}
      end
    end
  end

  defp body(source, opts) do
    with {:ok, ast} <- parse(source),
         {:ok, node} <- Tree.module_scope(ast, opts[:module]) do
      {:ok, Tree.module_body(node)}
    end
  end

  # -- editing -------------------------------------------------------------

  defp replace(source, node, name, value) do
    %{start: [line: _, column: col]} = range = Menard.Source.range(node, source)
    written = "@#{key(name)} " <> reindent(value, String.duplicate(" ", col - 1))
    patch(source, range, written)
  end

  # Above the first TABLE or definition, whichever comes first — not merely above the first def:
  # an attribute another attribute reads has to precede it, and Elixir only warns when it does not.
  defp add(source, name, value, opts) do
    with {:ok, ast} <- parse(source),
         {:ok, module} <- Tree.module_scope(ast, opts[:module]) do
      body = Tree.module_body(module)
      want = key(name)
      # below every attribute the value reads (`@open @statuses -- […]`), which is nil above its set
      deps = reads_in(value)

      last_dep =
        body
        |> Enum.with_index()
        |> Enum.reduce(-1, &if(attr_name(elem(&1, 0)) in deps, do: elem(&1, 1), else: &2))

      found =
        body
        |> Enum.with_index()
        |> Enum.find(fn {n, i} -> i > last_dep and (anchor?(n) or reads?(n, want)) end)

      case found do
        nil -> {:error, "nothing to place @#{want} above — the module has no definitions"}
        {_node, i} -> insert_before(source, owner_start(body, i), name, value)
      end
    end
  end

  # A definition's @doc, @spec and @impl are its own, written directly above it: a new attribute goes
  # above that run, not between it and the def, where the @doc was left belonging to nothing.
  defp owner_start(body, i) do
    body
    |> Enum.take(i)
    |> Enum.reverse()
    |> Enum.take_while(&(attr_name(&1) in @per_definition))
    |> List.last(Enum.at(body, i))
  end

  defp insert_before(source, node, name, value) do
    %{start: [line: line, column: col]} = Sourceror.get_range(node)
    indent = String.duplicate(" ", col - 1)
    written = indent <> "@#{key(name)} " <> reindent(value, indent) <> "\n\n"
    # above the comment glued to what it goes before, too: that comment explains the node, not this
    line = line - Menard.Source.comment_lines_above(String.split(source, "\n"), line - 1)
    at = %{start: [line: line, column: 1], end: [line: line, column: 1]}
    patch(source, at, written)
  end

  # -- shapes --------------------------------------------------------------

  # `@name value`. An attribute READ (`@name` with no argument) is not a set and never matches.
  defp attr_name({:@, _meta, [{name, _inner, args}]}) when is_atom(name) and is_list(args) and args != [],
    do: name

  defp attr_name(_node), do: nil

  # The value's own bytes, its continuation lines taken back to the attribute's column as `set` takes
  # them. A reprint (Sourceror.to_string) broke up a line the project's own formatter keeps whole.
  defp value_text({:@, _meta, [{_name, _inner, [value]}]} = node, source) do
    %{start: [line: _, column: col]} = Sourceror.get_range(node)
    [first | rest] = source |> Menard.Source.slice(Menard.Source.range(value, source)) |> String.split("\n")
    Enum.join([first | Enum.map(rest, &drop_indent(&1, col - 1))], "\n")
  end

  defp value_text(_node, _source), do: {:error, "not an attribute with a value"}

  defp definition?({kind, _meta, _args}) when kind in @def_kinds, do: true
  defp definition?(_node), do: false
  defp anchor?(node), do: definition?(node) or table?(node)

  # `@name` read anywhere under the node: a `use Foo, from: @name`, a moduledoc interpolating it. A
  # read above its definition is nil, so a new attribute goes above its first reader, too.
  defp reads?(node, name) do
    node
    |> Macro.prewalker()
    |> Enum.any?(fn
      {:@, _, [{read, _, ctx}]} when is_atom(read) and ctx in [nil, []] -> Atom.to_string(read) == name
      _ -> false
    end)
  end

  # the attributes a value (as written) reads; a value that doesn't parse reads none, and the write's
  # own parse check says so
  defp reads_in(value) do
    case Sourceror.parse_string(value) do
      {:ok, ast} ->
        for {:@, _, [{n, _, ctx}]} <- ast |> Macro.prewalker() |> Enum.to_list(),
            ctx in [nil, []],
            uniq: true,
            do: n

      {:error, _} ->
        []
    end
  end

  # An attribute holding a value the module reads. Not @moduledoc and friends: above those is also
  # above the `alias` the value depends on. Nor a definition's own @spec or @impl: those belong to
  # the def below them.
  defp table?(node) do
    case attr_name(node) do
      nil -> false
      name -> name not in ([:moduledoc, :doc, :shortdoc, :typedoc] ++ @per_definition)
    end
  end

  # A name is matched as text: String.to_atom on every name asked for made an atom per call, and the
  # VM never collects one
  defp key(name), do: name |> to_string() |> String.trim_leading("@")

  defp named?(node, key) do
    case attr_name(node) do
      nil -> false
      name -> Atom.to_string(name) == key
    end
  end

  # The whole attribute, `@name value`, where its value was asked for: agents write it that way, and
  # `@receipt @receipt """…` parsed, so nothing refused it. The indent it was written at comes off
  # its continuation lines too, so a heredoc's text is unchanged.
  defp own_value(name, value) do
    at = "@" <> String.trim_leading(to_string(name), "@")
    [first | rest] = String.split(value, "\n")
    lead = String.length(first) - String.length(String.trim_leading(first))

    case String.split(String.trim_leading(first), at, parts: 2) do
      ["", after_name] when after_name == "" or binary_part(after_name, 0, 1) in [" ", "("] ->
        Enum.join([String.trim_leading(after_name) | Enum.map(rest, &drop_indent(&1, lead))], "\n")

      _ ->
        value
    end
  end

  defp drop_indent(line, n) do
    pad = String.length(line) - String.length(String.trim_leading(line, " "))
    String.slice(line, min(pad, n)..-1//1)
  end
end
