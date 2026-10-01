defmodule Menard.Block do
  @moduledoc """
  The body of a macro's `do` block — `schema do … end`, `describe "…" do`, `test "…" do`,
  `setup do`. Not a clause, so no clause verb reaches one.

  Addressed by the macro's NAME, and by its `label` when the macro takes a string first — which is
  what makes `describe "the retired leader"` and `test "…"` addressable at all. Several blocks
  sharing a name and no label given is refused with their labels, never guessed at.
  """

  import Menard.Source, only: [indented: 2, parse: 1, patch: 3, reindent: 2]
  alias Menard.Tree
  alias Sourceror.Zipper

  @def_kinds Tree.def_kinds()

  @doc "Replace the block's body with `code`, keeping the `name … do` line and the `end`."
  @spec replace(String.t(), String.t() | atom(), String.t(), keyword()) :: String.t() | {:error, String.t()}
  def replace(source, name, code, opts \\ []) do
    {code, tags} = own_tags(code)
    name = named(name, code)

    with :ok <- tags_over_whole(name, code, tags),
         {:ok, _label, code, unwrapped_opts} <- unwrapped(name, opts[:label], code, opts),
         :ok <- body_only(name, code),
         {:ok, node} <- one(source, name, opts) do
      {_name, meta, args} = node
      %{start: [line: line, column: col]} = Sourceror.get_range(node)
      indent = String.duplicate(" ", col + 1)

      out =
        case {body_range(node), meta[:do]} do
          # `test "x" do end` has no body to take a range from: write between the `do` and the `end`
          {nil, [line: line, column: column]} ->
            at = %{start: [line: line, column: column + 2], end: meta[:end]}

            patch(
              source,
              at,
              "\n" <> indent <> reindent(code, indent) <> "\n" <> String.duplicate(" ", col - 1)
            )

          {body, _do} ->
            range = body |> Menard.Source.clamp(source) |> Menard.Source.with_leading_comments(source, code)
            patch_body(source, range, code, meta, args, col)
        end

      # the body is patched first: it sits after the args, so their range still holds; the tags
      # sit above the block, where neither moves a line
      if is_binary(out),
        do: out |> with_args(args, unwrapped_opts[:args]) |> retag(line, col, tags),
        else: out
    end
  end

  # `@tag` lines above a whole block are that block's own (found 2026-09-26: taken for a body, the
  # tagged test came out nested in the old one). nil when there are none.
  defp own_tags(code) do
    {rest, opts} = tagged(code, [])
    {rest, opts[:tag]}
  end

  defp tags_over_whole(_name, _code, nil), do: :ok

  defp tags_over_whole(name, code, _tags) do
    if match?({:whole, _, _, _}, unwrap(name, code)),
      do: :ok,
      else: {:error, "an @tag goes above a whole `#{name}` block: give the whole block after it, not a body"}
  end

  # the block's `@tag` lines, right above its first line, become `tags`
  defp retag(out, _line, _col, nil), do: out

  defp retag(out, line, col, tags) do
    {above, rest} = out |> String.split("\n") |> Enum.split(line - 1)
    kept = above |> Enum.reverse() |> Enum.drop_while(&(&1 =~ ~r/^\s*@tag\b/)) |> Enum.reverse()
    indent = String.duplicate(" ", col - 1)
    Enum.join(kept ++ Enum.map(tags, &(indent <> "@tag " <> &1)) ++ rest, "\n")
  end

  defp patch_body(source, range, code, meta, args, col) do
    cond do
      meta[:do] -> patch(source, range, reindent(code, String.duplicate(" ", col + 1)))
      not String.contains?(String.trim(code), "\n") -> patch(source, range, String.trim(code))
      true -> to_do_block(source, args, range, code, col)
    end
  end

  # A whole `test "x", %{tmp_dir: dir} do … end` given for a test written with other args, or none,
  # carries its args too: only the body taken, `dir` was an undefined variable in it
  defp with_args(out, _args, nil), do: out

  defp with_args(out, [label | rest], ctx) do
    %{end: from} = Sourceror.get_range(label)

    to =
      case rest do
        [current, _do] -> Sourceror.get_range(current).end
        _no_args -> from
      end

    at = %{start: from, end: to}
    if Menard.Source.slice(out, at) == ", " <> ctx, do: out, else: patch(out, at, ", " <> ctx)
  end

  # Several lines cannot sit in a `do:` keyword, so the block becomes `do … end`: from the end of
  # the argument before `, do:` to the end of the body.
  defp to_do_block(source, args, range, code, col) do
    case Enum.drop(args, -1) do
      [] ->
        {:error, "this block is written `do:` with no argument before it — give one expression"}

      before ->
        %{end: from} = Sourceror.get_range(List.last(before))
        indent = String.duplicate(" ", col + 1)
        text = " do\n" <> indent <> reindent(code, indent) <> "\n" <> String.duplicate(" ", col - 1) <> "end"
        patch(source, %{start: from, end: range.end}, text)
    end
  end

  @doc """
  Add a new `name "label" do … end` block. Placement, in order: at the END of the block named by
  `in:` (a `describe`, matched by its label) — which is where a new test goes; else after the last
  sibling block of the same name; else at the end of the module.
  """
  @spec add(String.t(), String.t() | atom(), String.t() | nil, String.t(), keyword()) ::
          String.t() | {:error, String.t()}
  # `defmodule` is not a block to add — a module with a `--label` renders `defmodule "Name"`, which
  # parses and then dies at compile with "invalid module name". `module add` is the verb for that.
  def add(source, name, label, body, opts \\ []) do
    {body, opts} = tagged(body, opts)

    name = named(name, body)

    cond do
      # an MCP call may leave `name` out; `"label" do … end` is what that would write, and it doesn't parse
      name in [nil, ""] ->
        {:error,
         "add needs the macro to write — `test`, `describe`, `setup` — as `name`; the label alone is not one"}

      to_string(name) == "defmodule" ->
        {:error,
         "add a module with `menard.module add`, not `block add defmodule` (a --label would become a string module name)"}

      wholes = several(name, label, body) ->
        add_each(source, name, wholes, opts)

      true ->
        with {:ok, label, body, opts} <- unwrapped(name, add_label(name, label, body), body, opts),
             :ok <- body_only(name, body),
             {:ok, ast} <- parse(source),
             {:ok, module} <- Tree.module_scope(ast, opts[:module]),
             {:ok, all} <- blocks(source, opts),
             {:ok, where, anchor} <- placement(all, ast, module, name, opts[:in]) do
          # `tag:` — `":tmp_dir"`, `"timeout: 5_000"` — each an `@tag` line right above the new block
          tags = opts[:tag] |> List.wrap() |> Enum.map_join(&"@tag #{tag(&1)}\n")
          place(source, where, anchor, tags <> render(name, label, body, opts[:args]))
        end
    end
  end

  defp add_each(source, name, wholes, opts) do
    Enum.reduce_while(wholes, source, fn whole, source ->
      case add(source, name, nil, whole, opts) do
        {:error, _} = error -> {:halt, error}
        out -> {:cont, out}
      end
    end)
  end

  # A whole block being added is named by its own label: there is nothing to tell it apart from, and
  # long1 cart-refactor.B.sonnet was refused over "…no placeholders" against "…leaves no placeholders"
  defp add_label(name, label, body) do
    if match?({:whole, _, _, _}, unwrap(name, body)), do: nil, else: label
  end

  # `@tag :tmp_dir` above a whole test is how a test is written, and was taken for a body: the block
  # came out wrapped in a bare `test do`. The tags go to `tag:`, which writes them above the block.
  # `tmp_dir` is the tag `:tmp_dir`; `:tmp_dir` and `timeout: 5_000` are as written
  defp tag(tag) do
    if Regex.match?(~r/^[a-z_][a-zA-Z0-9_]*[?!]?$/, tag), do: ":" <> tag, else: tag
  end

  defp tagged(code, opts) do
    case Regex.run(~r/\A((?:\s*@tag\s+[^\n]+\n)+)(.*)\z/s, code || "") do
      [_, lines, rest] ->
        tags =
          for [tag] <- Regex.scan(~r/@tag\s+([^\n]+)/, lines, capture: :all_but_first), do: String.trim(tag)

        {rest, Keyword.update(opts, :tag, tags, &(List.wrap(&1) ++ tags))}

      nil ->
        {code, opts}
    end
  end

  # No name given and a whole block as the code: the block says which macro (long2
  # cart-refactor.B.haiku was refused as "a whole `` block")
  defp named(name, code) when name in [nil, ""] do
    case Sourceror.parse_string(code || "") do
      # a do-block is the last argument, a keyword list: anything else is a body, not a whole block
      {:ok, {call, _, [_ | _] = args} = node} when is_atom(call) and call != :__block__ ->
        if is_list(List.last(args)) and body_range(node), do: to_string(call), else: name

      _ ->
        name
    end
  end

  defp named(name, _code), do: name

  # Inside: on the line before the block's own `end`, one level in. After: below the anchor, at the
  # anchor's own column. Both leave a blank line, the way blocks are separated everywhere else.
  defp place(source, :inside, node, text) do
    %{start: [line: _, column: col], end: [line: last, column: _]} = Sourceror.get_range(node)
    at = %{start: [line: last, column: 1], end: [line: last, column: 1]}
    patch(source, at, "\n" <> indented(text, col + 2) <> "\n")
  end

  defp place(source, :after, node, text) do
    %{start: [line: _, column: col], end: [line: last, column: last_col]} = Sourceror.get_range(node)
    at = %{start: [line: last, column: last_col], end: [line: last, column: last_col]}
    patch(source, at, "\n\n" <> indented(text, col))
  end

  @doc "The block's body exactly as written."
  @spec get(String.t(), String.t() | atom(), keyword()) :: String.t() | {:error, String.t()}
  def get(source, name, opts \\ []) do
    with {:ok, node} <- one(source, name, opts) do
      {_name, meta, _args} = node
      %{start: [line: a, column: _], end: [line: b, column: _]} = range = body_range(node)

      # a `do:` body shares its line with the call, so only its own range is the body
      if meta[:do] do
        source
        |> String.split("\n")
        |> Enum.slice((a - 1)..(b - 1))
        |> Enum.join("\n")
        |> Menard.Source.dedent()
      else
        Menard.Source.slice(source, range)
      end
    end
  end

  @doc "Every block named `name`, as `%{label, line, code}` in source order: what a get with no label, among several, means."
  @spec get_all(String.t(), String.t() | atom(), keyword()) :: [map()] | {:error, String.t()}
  def get_all(source, name, opts \\ []) do
    with {:ok, blocks} <- blocks(source, opts) do
      for node <- blocks, same?(call_name(node), name) do
        %{
          label: label(node),
          line: Tree.start_line(node),
          code: get(source, name, Keyword.put(opts, :label, label(node)))
        }
      end
    end
  end

  @doc "Every `do`-block macro call in the module, as `{name, label | nil, line}` in source order."
  @spec list(String.t(), keyword()) :: [{atom(), String.t() | nil, pos_integer()}] | {:error, String.t()}
  def list(source, opts \\ []) do
    with {:ok, blocks} <- blocks(source, opts) do
      Enum.map(blocks, fn node -> {call_name(node), label(node), Tree.start_line(node)} end)
    end
  end

  @doc "The one do-block (`test`, `describe`, …) labelled `label`, as its node, or why not."
  @spec labelled(String.t(), String.t()) :: {:ok, Macro.t()} | {:error, String.t()}
  def labelled(source, label) do
    with {:ok, blocks} <- blocks(source, []) do
      case Enum.filter(blocks, &(label(&1) == label)) do
        [node] -> {:ok, node}
        [] -> {:error, "no block labelled #{inspect(label)}"}
        many -> {:error, "#{length(many)} blocks labelled #{inspect(label)}"}
      end
    end
  end

  # -- locating ------------------------------------------------------------

  defp one(source, name, opts) do
    wanted_label = opts[:label]

    with {:ok, blocks} <- blocks(source, opts) do
      blocks
      # no name, a label: the label alone says which (bench3 new-component.B.sonnet)
      |> Enum.filter(fn node ->
        (name in [nil, ""] or same?(call_name(node), name)) and
          (is_nil(wanted_label) or label(node) == wanted_label)
      end)
      |> pick(name, wanted_label)
    end
  end

  defp pick([node], _want, _label), do: {:ok, node}

  # a test's label where the macro's name goes
  defp pick([], want, nil) do
    if to_string(want) =~ ~r/^[a-z_]\w*[?!]?$/,
      do: {:error, "no `#{want} do` block here"},
      else:
        {:error,
         "no `#{want} do` block here: a test is `test --label #{inspect(to_string(want))}` (a describe, `describe --label`)"}
  end

  defp pick([], want, label), do: {:error, "no `#{want} #{inspect(label)} do` block here"}

  defp pick(many, want, _label) do
    labels =
      Enum.map_join(many, " · ", fn node -> inspect(label(node)) <> " (line #{Tree.start_line(node)})" end)

    {:error, "#{length(many)} `#{want}` blocks here — name one with a label: #{labels}"}
  end

  # Every macro call in the module that carries a `do` block, at any depth: a `test` lives inside a
  # `describe`, so a top-level-only walk would miss most of them.
  defp blocks(source, opts) do
    with {:ok, ast} <- parse(source),
         {:ok, scopes} <- scopes(ast, opts) do
      found =
        scopes
        |> Enum.flat_map(fn module ->
          module |> Zipper.zip() |> Zipper.traverse_while([], &collect_block/2) |> elem(1) |> Enum.reverse()
        end)
        # a nested module is walked in its parent's walk as well
        |> Enum.uniq_by(&Tree.start_line/1)

      {:ok, found}
    end
  end

  # a label says which block wherever it is: with one and no module named, every module is looked in
  defp scopes(ast, opts) do
    label = opts[:label]

    case Tree.module_scope(ast, opts[:module]) do
      {:ok, module} ->
        {:ok, [module]}

      {:error, "several modules" <> _} when is_binary(label) ->
        {:ok, Enum.map(Tree.modules(ast), &elem(&1, 1))}

      error ->
        error
    end
  end

  # into a describe, but not into a function or a test: an `if` in a def body, a `for` in a test,
  # is a statement, not a block (`block list` named every `for` in a test file's tests)
  defp collect_block(zipper, acc) do
    case Zipper.node(zipper) do
      {kind, _, _} when kind in @def_kinds -> {:skip, zipper, acc}
      {kind, _, [_ | _]} = node when kind in [:test, :setup, :setup_all] -> {:skip, zipper, [node | acc]}
      # prepended, and reversed once at the end: appending copied the list at every block found
      node -> {:cont, zipper, if(block?(node), do: [node | acc], else: acc)}
    end
  end

  # -- shapes --------------------------------------------------------------

  # A macro call whose last argument is a `do` keyword list. `defmodule` and the def kinds are
  # excluded: those have their own verbs, and a module is not a block you replace the body of.
  defp block?({name, _meta, args}) when is_atom(name) and is_list(args) and args != [] do
    name not in [:defmodule | @def_kinds] and has_do?(List.last(args))
  end

  defp block?(_node), do: false

  defp has_do?(args) when is_list(args), do: Enum.any?(args, &do_key?/1)
  defp has_do?(_args), do: false

  defp do_key?({{:__block__, _meta, [:do]}, _body}), do: true
  defp do_key?({:do, _body}), do: true
  defp do_key?(_pair), do: false

  defp call_name({name, _meta, _args}), do: name

  # The first string argument, which is how `describe "…"` and `test "…"` are told apart.
  defp label({_name, _meta, args}) do
    Enum.find_value(args, fn
      {:__block__, _meta, [text]} when is_binary(text) -> text
      text when is_binary(text) -> text
      _other -> nil
    end)
  end

  defp body_range({_name, _meta, args}) do
    args
    |> List.last()
    |> Enum.find_value(fn
      {{:__block__, _meta, [:do]}, body} -> Sourceror.get_range(body)
      {:do, body} -> Sourceror.get_range(body)
      _pair -> nil
    end)
  end

  # A name is matched as text: String.to_atom on every name asked for made an atom per call, and the
  # VM never collects one
  defp same?(call, name), do: is_atom(call) and Atom.to_string(call) == to_string(name)

  @doc """
  Rename a block's label — `test "old"` to `test "new"`, or a `describe`. The label is a string
  literal, so no other verb reaches it. Only the label moves; the body is untouched.
  """
  @spec relabel(String.t(), String.t(), String.t(), String.t(), keyword()) ::
          String.t() | {:error, String.t()}
  def relabel(source, name, label, new_label, opts \\ []) do
    with {:ok, node} <- one(source, name, Keyword.put(opts, :label, label)),
         {:ok, range} <- label_range(node) do
      patch(source, range, inspect(new_label))
    end
  end

  @doc """
  Delete one block — a `test`, a `describe` — with the comment glued above it, and the blank line
  it leaves when it stood between blank lines.
  """
  @spec delete(String.t(), String.t() | atom(), keyword()) :: String.t() | {:error, String.t()}
  def delete(source, name, opts \\ []) do
    with {:ok, node} <- one(source, name, opts) do
      %{start: [line: a, column: _], end: [line: b, column: _]} = Sourceror.get_range(node)
      lines = String.split(source, "\n")
      first = a - Menard.Source.comment_lines_above(lines, a - 1)
      blank_after? = Enum.at(lines, b) == "" and (first == 1 or Enum.at(lines, first - 2) == "")
      last = if blank_after?, do: b + 1, else: b
      Menard.Source.delete_lines(source, first, last)
    end
  end

  # The range of the label STRING itself, quotes included — patching a wider range would reflow the
  # `do` and the first body line with it.
  defp label_range({_name, _meta, args}) do
    args
    |> Enum.find_value(fn
      {:__block__, _meta, [text]} = node when is_binary(text) -> Sourceror.get_range(node)
      _other -> nil
    end)
    |> case do
      nil -> {:error, "that block has no string label to rename"}
      range -> {:ok, range}
    end
  end

  defp placement(all, ast, _module, _name, parent) when is_binary(parent) do
    case Enum.filter(all, &(label(&1) == parent)) do
      [node] ->
        {:ok, :inside, node}

      many when many != [] ->
        {:error, "#{length(many)} blocks labelled #{inspect(parent)} — cannot tell which"}

      [] ->
        # A parent can be a MODULE as well as a labelled block: appending into a defmodule is the obvious
        # reading of `--in Console.KeymapTest`.
        case Tree.module_scope(ast, parent) do
          {:ok, node} -> {:ok, :inside, node}
          _error -> {:error, "no block or module #{inspect(parent)} here"}
        end
    end
  end

  defp placement(all, _ast, module, name, _none) do
    case Enum.filter(all, &same?(call_name(&1), name)) do
      [] -> {:ok, :inside, module}
      siblings -> {:ok, :after, List.last(siblings)}
    end
  end

  # `name "label", ARGS do` — ARGS is the rest of the head as written: a test's context
  # (`%{conn: conn}`), a setup's. Without a label it follows the name bare: `setup ctx do`.
  defp render(name, label, body, args) do
    parts = Enum.reject([label && inspect(label), args], &(&1 in [nil, ""]))
    head = if parts == [], do: "#{name}", else: "#{name} " <> Enum.join(parts, ", ")
    head <> " do\n" <> indented(body, 3) <> "\nend"
  end

  # A whole `name "label", ARGS do … end` where its body was asked for — the eval's agents wrote it
  # that way more often than not. `{:whole, label, args, body}` with the texts as written, or `:body`.
  defp unwrap(name, code) do
    with {:ok, {call, meta, [_ | _] = args} = node} <- Sourceror.parse_string(code),
         true <- same?(call, name),
         %{} = range <- body_range(node) do
      ctx =
        case args do
          [_label, ctx, _do] -> code |> Menard.Source.slice(Sourceror.get_range(ctx)) |> String.trim()
          _ -> nil
        end

      {:whole, label(node), ctx, body_text(code, meta, range)}
    else
      _ -> :body
    end
  end

  # Every line between the `do` and the `end`: the body's range starts at its first expression, and a
  # comment above that is not in it
  defp body_text(code, meta, range) do
    case {meta[:do], meta[:end]} do
      {[line: d, column: _], [line: e, column: _]} when e > d ->
        code |> String.split("\n") |> Enum.slice(d..(e - 2)//1) |> Enum.join("\n") |> Menard.Source.dedent()

      _keyword_do ->
        # from the start of the body's first line, so every line keeps the indent `dedent` removes
        %{start: [line: first, column: _]} = range = Menard.Source.clamp(range, code)
        code |> Menard.Source.slice(%{range | start: [line: first, column: 1]}) |> Menard.Source.dedent()
    end
  end

  # A whole block that is the one asked for (same macro, and the label given or none) stands for its
  # body, its label and its args; anything else is passed on as written, for `body_only` to judge
  defp unwrapped(name, label, code, opts) do
    case unwrap(name, code) do
      {:whole, whole_label, ctx, body} when label in [nil, whole_label] ->
        {:ok, whole_label, body, Keyword.put(opts, :args, opts[:args] || ctx)}

      # the same macro under another label: a rename in disguise, which `relabel` is for
      {:whole, whole_label, _ctx, _body} when is_binary(label) and is_binary(whole_label) ->
        {:error,
         "CODE is a whole `#{name} #{inspect(whole_label)}` block, for `#{name} #{inspect(label)}`: " <>
           "to rename it, `block relabel` first, then replace; to change only what is inside, pass its body"}

      _ ->
        {:ok, label, code, opts}
    end
  end

  # `describe "x" do … end` handed to `replace describe` is valid Elixir as a body — a block nested in
  # itself — so only the reader would notice
  defp body_only(name, code) do
    if Regex.match?(~r/\A\s*#{Regex.escape(to_string(name))}[\s(].*\bdo\b/s, code) do
      case Code.string_to_quoted(code, emit_warnings: false) do
        # a whole block with a typo reads as one here: the parse error is the answer
        {:error, {meta, message, token}} ->
          {:error, "CODE does not parse (line #{meta[:line]}): #{parse_message(message, token)}"}

        _ ->
          {:error,
           "CODE is the block's BODY here, and this looks like a whole `#{name}` block — pass what goes inside it"}
      end
    else
      :ok
    end
  end

  defp parse_message(message, token) when is_tuple(message), do: elem(message, 0) <> token <> elem(message, 1)
  defp parse_message(message, token), do: message <> token

  # Several whole blocks of the macro named, the first labelled as asked (or no label asked): each is
  # added in turn, as its own whole block. The texts as written, or nil.
  defp several(name, label, code) do
    with {:ok, {:__block__, _, [_, _ | _] = nodes}} <- Sourceror.parse_string(code),
         true <- Enum.all?(nodes, &match?({call, _, [_ | _]} when is_atom(call), &1)),
         true <- Enum.all?(nodes, &same?(elem(&1, 0), name)),
         true <- label in [nil, label(hd(nodes))] do
      Enum.map(nodes, &Menard.Source.slice(code, Sourceror.get_range(&1)))
    else
      _ -> nil
    end
  end
end
