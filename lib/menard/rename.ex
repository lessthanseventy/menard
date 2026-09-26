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

  @spec run(String.t(), String.t(), String.t(), keyword()) :: String.t() | {:error, String.t()}
  def run(source, old, new, opts \\ []) when is_binary(source) do
    with {:ok, ast} <- Menard.Source.parse(source) do
      apply_patches(
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
  defp import_patches(ast, from, new) do
    for {:import, _, [_module, opts]} <- ast |> Macro.prewalker() |> Enum.to_list(),
        is_list(opts),
        {{:__block__, _, [key]}, {:__block__, _, [names]}} <- opts,
        key in [:only, :except] and is_list(names),
        {{:__block__, _, [^from]} = name, _arity} <- names,
        do: {:function, %{range: Sourceror.get_range(name), change: "#{new}:"}}
  end

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
  # left `old/1` there (long1 cart-refactor.B.haiku) or `iex> A.old(1)` (a doctest that no longer
  # runs) is half done. Only mentions that read as code: before `(` or `/arity`, or inside backticks;
  # "the old way" is a word, not the function.
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
