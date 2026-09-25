defmodule Menard.Attr do
  @moduledoc """
  Module attributes — `@hints`, `@colors`, `@panes`, `@kinds`. The tables a module keeps at the
  top, which every clause verb walks straight past because an attribute is not a clause.

  Addressed by NAME. A name several attributes share is refused with their lines rather than
  guessed at — `@doc`, `@impl` and `@spec` repeat per clause by design, and those belong to the
  clause verbs (`Menard.Clause.delete/4` takes them with the clause; `visibility/3` drops a `@doc`
  when it privatises).
  """

  import Menard.Source, only: [parse: 1, reindent: 2]
  alias Menard.Clause

  # written above one def and belonging to it, as Menard.Clause's @attached
  @per_definition [:doc, :spec, :impl, :deprecated, :dialyzer]

  @doc "The attribute's value exactly as written, or `{:error, …}` if it is missing or ambiguous."
  @spec get(String.t(), String.t() | atom(), keyword()) :: String.t() | {:error, String.t()}
  def get(source, name, opts \\ []) do
    with {:ok, node} <- one(source, name, opts), do: value_text(node)
  end

  @doc """
  Set `@name` to `value` (the value as you would write it). Replaces the existing attribute's
  value, or adds the attribute when it isn't there yet — at the TOP of the module's tables, above
  the first attribute or definition, since an attribute another attribute reads must precede it.
  """
  @spec set(String.t(), String.t() | atom(), String.t(), keyword()) :: String.t() | {:error, String.t()}
  def set(source, name, value, opts \\ []) do
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
         {:ok, node} <- one(source, name, opts) do
      %{start: [line: a, column: _], end: [line: b, column: _]} = Sourceror.get_range(node)
      # Under a def's own @doc or @spec, the blank line after it would part them from the def they
      # belong to: it goes too. Anywhere else a blank on each side is the formatter's to fold.
      above = body |> Enum.take_while(&(&1 != node)) |> List.last()
      next_blank? = source |> String.split("\n") |> Enum.at(b) |> Kernel.==("")
      b = if attr_name(above) in @per_definition and next_blank?, do: b + 1, else: b
      drop_lines(source, a, b)
    end
  end

  @doc """
  The `#` comment above `@name`: prose in, `#` added; no `text` removes it. The attribute twin of
  `Menard.Clause.comment/5`.
  """
  @spec comment(String.t(), String.t() | atom(), String.t() | nil, keyword()) ::
          String.t() | {:error, String.t()}
  def comment(source, name, text, opts \\ []) do
    with {:ok, node} <- one(source, name, opts) do
      %{start: [line: line, column: col]} = Sourceror.get_range(node)
      Clause.comment_at(source, line, col - 1, text)
    end
  end

  @doc "Every attribute the module sets, as `{name, line}` in source order — the read half."
  @spec list(String.t(), keyword()) :: [{atom(), pos_integer()}] | {:error, String.t()}
  def list(source, opts \\ []) do
    with {:ok, body} <- body(source, opts) do
      body
      |> Enum.flat_map(fn node ->
        case attr_name(node) do
          nil -> []
          name -> [{name, start_line(node)}]
        end
      end)
    end
  end

  # -- locating ------------------------------------------------------------

  defp one(source, name, opts) do
    want = to_atom(name)

    with {:ok, body} <- body(source, opts) do
      case Enum.filter(body, &(attr_name(&1) == want)) do
        [node] ->
          {:ok, node}

        [] ->
          {:error, :missing}

        many ->
          lines = Enum.map_join(many, ", ", &to_string(start_line(&1)))

          {:error,
           "@#{want} is set #{length(many)} times (lines #{lines}) — attributes that repeat per clause belong to the clause verbs"}
      end
    end
  end

  defp body(source, opts) do
    with {:ok, ast} <- parse(source),
         {:ok, node} <- Clause.module_scope(ast, opts[:module]) do
      {:ok, Clause.module_body(node)}
    end
  end

  # -- editing -------------------------------------------------------------

  defp replace(source, node, name, value) do
    %{start: [line: _, column: col]} = range = Menard.Source.range(node, source)
    written = "@#{to_atom(name)} " <> reindent(value, String.duplicate(" ", col - 1))
    Sourceror.patch_string(source, [%{range: range, change: written, preserve_indentation: false}])
  end

  # Above the first TABLE or definition, whichever comes first — not merely above the first def:
  # an attribute another attribute reads has to precede it, and Elixir only warns when it does not.
  defp add(source, name, value, opts) do
    with {:ok, ast} <- parse(source),
         {:ok, module} <- Clause.module_scope(ast, opts[:module]) do
      body = Clause.module_body(module)
      atom = to_atom(name)

      case Enum.find_index(body, &(anchor?(&1) or reads?(&1, atom))) do
        nil -> {:error, "nothing to place @#{atom} above — the module has no definitions"}
        i -> insert_before(source, owner_start(body, i), name, value)
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
    written = indent <> "@#{to_atom(name)} " <> reindent(value, indent) <> "\n\n"
    # above the comment glued to what it goes before, too: that comment explains the node, not this
    line = line - comment_lines_above(source, line)
    at = %{start: [line: line, column: 1], end: [line: line, column: 1]}
    Sourceror.patch_string(source, [%{range: at, change: written, preserve_indentation: false}])
  end

  defp comment_lines_above(source, line) do
    source
    |> String.split("\n")
    |> Enum.take(line - 1)
    |> Enum.reverse()
    |> Enum.take_while(&String.starts_with?(String.trim_leading(&1), "#"))
    |> length()
  end

  defp drop_lines(source, a, b) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.reject(fn {_text, line} -> line >= a and line <= b end)
    |> Enum.map_join("\n", &elem(&1, 0))
  end

  # -- shapes --------------------------------------------------------------

  # `@name value`. An attribute READ (`@name` with no argument) is not a set and never matches.
  defp attr_name({:@, _meta, [{name, _inner, args}]}) when is_atom(name) and is_list(args) and args != [],
    do: name

  defp attr_name(_node), do: nil

  defp value_text({:@, _meta, [{_name, _inner, [value]}]}), do: Sourceror.to_string(value)
  defp value_text(_node), do: {:error, "not an attribute with a value"}

  defp definition?({kind, _meta, _args})
       when kind in [:def, :defp, :defmacro, :defmacrop, :defguard, :defguardp],
       do: true

  defp definition?(_node), do: false
  defp anchor?(node), do: definition?(node) or table?(node)

  # `@name` read anywhere under the node: a `use Foo, from: @name`, a moduledoc interpolating it. A
  # read above its definition is nil, so a new attribute goes above its first reader, too.
  defp reads?(node, name) do
    node |> Macro.prewalker() |> Enum.any?(&match?({:@, _, [{^name, _, ctx}]} when ctx in [nil, []], &1))
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

  defp start_line(node) do
    %{start: [line: line, column: _]} = Sourceror.get_range(node)
    line
  end

  defp to_atom(name) when is_atom(name), do: name
  defp to_atom(name) when is_binary(name), do: String.to_atom(String.trim_leading(name, "@"))
end
