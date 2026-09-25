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

  @spec run(String.t(), String.t(), String.t(), keyword()) :: String.t() | {:error, term()}
  def run(source, old, new, opts \\ []) when is_binary(source) do
    case Sourceror.parse_string(source) do
      {:ok, ast} ->
        from = String.to_atom(old)
        functions = function_positions(ast, from)

        patches =
          ast
          |> patches(from, new, Keyword.get(opts, :atoms, false))
          |> Enum.filter(&wanted?(&1, opts[:only], functions))
          |> Enum.map(&elem(&1, 1))

        apply_patches(
          source,
          patches ++ comment_patches(source, old, new, Keyword.get(opts, :comments, false))
        )

      {:error, reason} ->
        {:error, reason}
    end
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
        {kind, _, [head | _]} when kind in [:def, :defp, :defmacro, :defmacrop, :defguard, :defguardp] ->
          {z, bare_start(strip_when(head), from) ++ acc}

        {:&, _, [{:/, _, [name, _arity]}]} ->
          {z, bare_start(name, from) ++ acc}

        _ ->
          {z, acc}
      end
    end)
    |> elem(1)
  end

  defp strip_when({:when, _, [head | _]}), do: head
  defp strip_when(head), do: head

  defp bare_start({from, _meta, ctx} = node, from) when is_atom(ctx), do: [Sourceror.get_range(node).start]
  defp bare_start(_node, _from), do: []

  # Comments are not AST: a whole-word mention (`\bold\b`) inside a `#` comment is patched by its
  # own range. The word boundary keeps `old_extra` and the like alone; strings never match here
  # because only the comment's text is searched.
  defp comment_patches(_source, _old, _new, false), do: []

  defp comment_patches(source, old, new, true) do
    word = ~r/(?<![A-Za-z0-9_])#{Regex.escape(old)}(?![A-Za-z0-9_])/

    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, no} -> line_comment_patches(line, no, word, new) end)
  end

  defp line_comment_patches(line, no, word, new) do
    case comment_start(line) do
      nil -> []
      col0 -> line |> String.split_at(col0) |> elem(1) |> mention_patches(no, col0, word, new)
    end
  end

  # ranges are 1-based columns, in graphemes
  defp mention_patches(comment, no, col0, word, new) do
    for [{off, len}] <- Regex.scan(word, comment, return: :index) do
      c = String.length(binary_part(comment, 0, off)) + col0 + 1
      %{range: %{start: [line: no, column: c], end: [line: no, column: c + len]}, change: new}
    end
  end

  # Where a line's comment begins, ignoring a `#` inside a string — a good-enough scan: the
  # first `#` not inside double quotes on that line.
  defp comment_start(line), do: comment_start(String.graphemes(line), 0, false)
  defp comment_start([], _i, _in_str), do: nil
  defp comment_start(["\"" | rest], i, in_str), do: comment_start(rest, i + 1, not in_str)
  defp comment_start(["#" | _rest], i, false), do: i
  defp comment_start([_g | rest], i, in_str), do: comment_start(rest, i + 1, in_str)

  defp apply_patches(source, []), do: source
  defp apply_patches(source, patches), do: Sourceror.patch_string(source, patches)

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
end
