defmodule Menard.Block do
  @moduledoc """
  The body of a macro's `do` block — `schema do … end`, `describe "…" do`, `test "…" do`,
  `setup do`. Not a clause, so no clause verb reaches one.

  Addressed by the macro's NAME, and by its `label` when the macro takes a string first — which is
  what makes `describe "the retired leader"` and `test "…"` addressable at all. Several blocks
  sharing a name and no label given is refused with their labels, never guessed at.
  """

  import Menard.Source, only: [parse: 1, reindent: 2]
  alias Menard.Clause
  alias Sourceror.Zipper

  @doc "Replace the block's body with `code`, keeping the `name … do` line and the `end`."
  @spec replace(String.t(), String.t() | atom(), String.t(), keyword()) :: String.t() | {:error, String.t()}
  def replace(source, name, code, opts \\ []) do
    with :ok <- body_only(name, code),
         {:ok, node} <- one(source, name, opts) do
      {_name, meta, args} = node
      %{start: [line: _, column: col]} = Sourceror.get_range(node)
      indent = String.duplicate(" ", col + 1)
      range = node |> body_range() |> Menard.Source.clamp(source)

      cond do
        meta[:do] -> patch(source, range, reindent(code, indent))
        not String.contains?(String.trim(code), "\n") -> patch(source, range, String.trim(code))
        true -> to_do_block(source, args, range, code, col)
      end
    end
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
    if to_atom(name) == :defmodule do
      {:error,
       "add a module with `menard.module add`, not `block add defmodule` (a --label would become a string module name)"}
    else
      with {:ok, ast} <- parse(source),
           {:ok, module} <- Clause.module_scope(ast, opts[:module]),
           {:ok, all} <- blocks(source, opts),
           {:ok, where, anchor} <- placement(all, ast, module, to_atom(name), opts[:in]) do
        place(source, where, anchor, render(to_atom(name), label, body, opts[:args]))
      end
    end
  end

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

  defp indented(text, col) do
    indent = String.duplicate(" ", col - 1)
    text |> String.trim() |> String.split("\n") |> Enum.map_join("\n", &(indent <> &1))
  end

  defp patch(source, range, change),
    do: Sourceror.patch_string(source, [%{range: range, change: change, preserve_indentation: false}])

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

  @doc "Every `do`-block macro call in the module, as `{name, label | nil, line}` in source order."
  @spec list(String.t(), keyword()) :: [{atom(), String.t() | nil, pos_integer()}] | {:error, String.t()}
  def list(source, opts \\ []) do
    with {:ok, blocks} <- blocks(source, opts) do
      Enum.map(blocks, fn node -> {call_name(node), label(node), start_line(node)} end)
    end
  end

  # -- locating ------------------------------------------------------------

  defp one(source, name, opts) do
    want = to_atom(name)
    wanted_label = opts[:label]

    with {:ok, blocks} <- blocks(source, opts) do
      blocks
      |> Enum.filter(&(call_name(&1) == want))
      |> Enum.filter(fn node -> is_nil(wanted_label) or label(node) == wanted_label end)
      |> pick(want, wanted_label)
    end
  end

  defp pick([node], _want, _label), do: {:ok, node}

  defp pick([], want, nil), do: {:error, "no `#{want} do` block here"}
  defp pick([], want, label), do: {:error, "no `#{want} #{inspect(label)} do` block here"}

  defp pick(many, want, _label) do
    labels = Enum.map_join(many, " · ", fn node -> inspect(label(node)) <> " (line #{start_line(node)})" end)
    {:error, "#{length(many)} `#{want}` blocks here — name one with a label: #{labels}"}
  end

  # Every macro call in the module that carries a `do` block, at any depth: a `test` lives inside a
  # `describe`, so a top-level-only walk would miss most of them.
  defp blocks(source, opts) do
    with {:ok, ast} <- parse(source),
         {:ok, module} <- Clause.module_scope(ast, opts[:module]) do
      # into a describe, but not into a function: an `if` in a def body is a statement, not a block
      found =
        module
        |> Zipper.zip()
        |> Zipper.traverse_while([], fn zipper, acc ->
          case Zipper.node(zipper) do
            {kind, _, _} when kind in [:def, :defp, :defmacro, :defmacrop] -> {:skip, zipper, acc}
            node -> {:cont, zipper, if(block?(node), do: acc ++ [node], else: acc)}
          end
        end)
        |> elem(1)

      {:ok, found}
    end
  end

  # -- shapes --------------------------------------------------------------

  # A macro call whose last argument is a `do` keyword list. `defmodule` and the def kinds are
  # excluded: those have their own verbs, and a module is not a block you replace the body of.
  defp block?({name, _meta, args}) when is_atom(name) and is_list(args) and args != [] do
    name not in [:defmodule, :def, :defp, :defmacro, :defmacrop, :defguard, :defguardp] and
      has_do?(List.last(args))
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

  defp start_line(node) do
    %{start: [line: line, column: _]} = Sourceror.get_range(node)
    line
  end

  defp to_atom(name) when is_atom(name), do: name
  defp to_atom(name) when is_binary(name), do: String.to_atom(name)

  @doc """
  Rename a block's label — `test "old"` to `test "new"`, or a `describe`. The label is a string
  literal, so no other verb reaches it. Only the label moves; the body is untouched.
  """
  @spec relabel(String.t(), String.t(), String.t(), String.t(), keyword()) ::
          String.t() | {:error, String.t()}
  def relabel(source, name, label, new_label, opts \\ []) do
    with {:ok, node} <- one(source, name, Keyword.put(opts, :label, label)),
         {:ok, range} <- label_range(node) do
      Sourceror.patch_string(source, [
        %{range: range, change: inspect(new_label), preserve_indentation: false}
      ])
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
      first = a - 1 - Menard.Source.comment_lines_above(lines, a - 1)
      blank_after? = Enum.at(lines, b) == "" and (first == 0 or Enum.at(lines, first - 1) == "")
      last = if blank_after?, do: b, else: b - 1

      lines
      |> Enum.with_index()
      |> Enum.reject(fn {_text, i} -> i >= first and i <= last end)
      |> Enum.map_join("\n", &elem(&1, 0))
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
        case Clause.module_scope(ast, parent) do
          {:ok, node} -> {:ok, :inside, node}
          _error -> {:error, "no block or module #{inspect(parent)} here"}
        end
    end
  end

  defp placement(all, _ast, module, name, _none) do
    case Enum.filter(all, &(call_name(&1) == name)) do
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

  # `describe "x" do … end` handed to `replace describe` is valid Elixir as a body — a block nested in
  # itself — so only the reader would notice
  defp body_only(name, code) do
    if Regex.match?(~r/\A\s*#{Regex.escape(to_string(name))}[\s(].*\bdo\b/s, code) do
      {:error,
       "CODE is the block's BODY here, and this looks like a whole `#{name}` block — pass what goes inside it"}
    else
      :ok
    end
  end
end
