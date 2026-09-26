defmodule Menard.Directive do
  @moduledoc """
  `alias` / `import` / `require` / `use` — added and removed where they belong.

  The insert is trivial; the PLACEMENT is the reason this exists. Elixir has one conventional
  order for a module's directives — `use`, then `import`, then `alias`, then `require`, each
  alphabetised — and Styler enforces it in projects that run it. Dropping a new `alias` at a guessed
  line means the next format pass moves it, so the diff never matches what was written. `add/3`
  puts it in its own block in sorted position, or opens the block in the right place when there
  isn't one: after the `@moduledoc` and after every kind that outranks it.

  An `alias` that is already there is left exactly as written — adding twice is not an error and
  never duplicates a line. One that is there with other options is refused: `replace` changes those.
  """

  import Menard.Source, only: [parse: 1]
  # in the order they are written; a test module's doctest line comes last, as Quokka places it
  @kinds [:use, :import, :alias, :require, :doctest]

  @doc """
  Add `alias Mod` (or `import`/`require`/`use`) to the module. `opts` is the rest of the directive
  as written — `"as: Thing"`, `"only: [pad: 3]"` — or nil. `module` names which module in a file
  that has several; nil takes the only one.
  """
  @spec add(String.t(), atom(), String.t(), keyword()) :: String.t() | {:error, String.t()}
  def add(source, kind, target, opts \\ [])

  def add(_source, kind, _target, _opts) when kind not in @kinds,
    do: {:error, "kind must be one of #{Enum.map_join(@kinds, ", ", &to_string/1)}"}

  def add(source, kind, target, opts) do
    line = directive_line(kind, target, opts[:args])

    with {:ok, ast} <- parse(source),
         {:ok, node} <- Menard.Tree.module_scope(ast, opts[:module]) do
      body = Menard.Tree.module_body(node)

      case Enum.find(body, &({kind, target} in directives(&1))) do
        nil ->
          insert(source, node, body, kind, target, line)

        found ->
          already(source, found, line, directive_line(kind, target, nil))
      end
    end
  end

  @doc "Remove `alias Mod` (or import/require/use) and the line it sits on. A miss leaves the source alone."
  @spec remove(String.t(), atom(), String.t(), keyword()) :: String.t() | {:error, String.t()}
  def remove(source, kind, target, opts \\ []) do
    with {:ok, ast} <- parse(source),
         {:ok, node} <- Menard.Tree.module_scope(ast, opts[:module]) do
      body = Menard.Tree.module_body(node)

      cond do
        found = Enum.find(body, &match(&1, kind, target)) ->
          drop_lines(source, Sourceror.get_range(found))

        # dropping the line would take its siblings with it
        multi = Enum.find(body, &({kind, target} in directives(&1))) ->
          {:error, "#{kind} #{target} is part of `#{Sourceror.to_string(multi)}` — rewrite that line"}

        true ->
          source
      end
    end
  end

  @doc "Every directive in the module, as `{kind, \"Mod.Name\"}` in source order — the read half."
  @spec list(String.t(), keyword()) :: [{atom(), String.t()}] | {:error, String.t()}
  def list(source, opts \\ []) do
    with {:ok, ast} <- parse(source),
         {:ok, node} <- Menard.Tree.module_scope(ast, opts[:module]) do
      node |> Menard.Tree.module_body() |> Enum.flat_map(&directives/1)
    end
  end

  @doc """
  Replace `alias Mod` (or import/require/use) with the same directive and new `args` — `use X,
  opts` changed in one step, in place, where a remove and an add would leave the module broken in
  between and the block reshuffled.
  """
  @spec replace(String.t(), atom(), String.t(), keyword()) :: String.t() | {:error, String.t()}
  def replace(source, kind, target, opts) do
    with {:ok, ast} <- parse(source),
         {:ok, node} <- Menard.Tree.module_scope(ast, opts[:module]) do
      case Enum.find(Menard.Tree.module_body(node), &match(&1, kind, target)) do
        nil -> {:error, "no #{kind} #{target} in this module"}
        found -> patch(source, Sourceror.get_range(found), directive_line(kind, target, opts[:args]))
      end
    end
  end

  # -- placement ------------------------------------------------------------

  # In its own block, alphabetically. With no block of this kind yet, after the last directive that
  # outranks it (use > import > alias > require) — and failing that, after the @moduledoc, which is
  # the one thing that is always above every directive.
  defp insert(source, module_node, body, kind, target, line) do
    case Enum.filter(body, &(kind_of(&1) == kind)) do
      [] -> insert_at_block_start(source, module_node, body, kind, line)
      peers -> insert_among(source, peers, target, line)
    end
  end

  defp insert_among(source, peers, target, line) do
    # case-insensitive, as Styler and Credo sort: `App.Zb` goes before `App.ZZ`
    case Enum.find(peers, fn peer -> String.downcase(target_of(peer)) > String.downcase(target) end) do
      nil -> after_line(source, List.last(peers), line)
      later -> before_line(source, later, line)
    end
  end

  defp insert_at_block_start(source, module_node, body, kind, line) do
    # Only DIRECTIVES rank against each other: a `def` or a `@moduledoc` is not something an alias
    # goes below, and counting them as "outranked" put the alias above the moduledoc.
    directives = Enum.filter(body, &(kind_of(&1) != nil))
    above = Enum.filter(directives, &(rank(kind_of(&1)) < rank(kind)))
    below = Enum.filter(directives, &(rank(kind_of(&1)) > rank(kind)))

    cond do
      above != [] -> after_line(source, List.last(above), line)
      below != [] -> before_line(source, hd(below), line)
      true -> after_preamble(source, module_node, body, line)
    end
  end

  # No directives at all: under the @moduledoc if there is one, else as the module's first line.
  defp after_preamble(source, module_node, body, line) do
    case Enum.find(body, &moduledoc?/1) do
      nil -> open_block(source, module_node, line)
      doc -> after_line(source, doc, line, "\n")
    end
  end

  defp open_block(source, module_node, line) do
    %{start: [line: start, column: col]} = Sourceror.get_range(module_node)
    indent = String.duplicate(" ", col + 1)
    at = %{start: [line: start + 1, column: 1], end: [line: start + 1, column: 1]}
    patch(source, at, indent <> line <> "\n\n")
  end

  defp after_line(source, node, line, gap \\ "") do
    %{start: [line: _, column: col], end: [line: last, column: last_col]} = Sourceror.get_range(node)
    at = %{start: [line: last, column: last_col], end: [line: last, column: last_col]}
    patch(source, at, gap <> "\n" <> String.duplicate(" ", col - 1) <> line)
  end

  defp before_line(source, node, line) do
    %{start: [line: first, column: col]} = Sourceror.get_range(node)
    at = %{start: [line: first, column: 1], end: [line: first, column: 1]}
    patch(source, at, String.duplicate(" ", col - 1) <> line <> "\n")
  end

  defp drop_lines(source, %{start: [line: a, column: _], end: [line: b, column: _]}) do
    source
    |> String.split("\n")
    |> Enum.with_index()
    |> Enum.reject(fn {_text, i} -> i >= a - 1 and i <= b - 1 end)
    |> Enum.map_join("\n", &elem(&1, 0))
  end

  # -- reading directives ---------------------------------------------------

  defp directive({kind, _meta, [{:__aliases__, _alias_meta, parts} | _rest]}) when kind in @kinds,
    do: {kind, Menard.Source.alias_name(parts)}

  defp directive(_statement), do: nil

  # Every {kind, target} a statement names — `alias Foo.{Bar, Baz}` names two.
  defp directives({kind, _meta, [{{:., _, [{:__aliases__, _, base}, :{}]}, _, subs} | _rest]})
       when kind in @kinds,
       do: for({:__aliases__, _, p} <- subs, do: {kind, Menard.Source.alias_name(base ++ p)})

  defp directives(statement), do: List.wrap(directive(statement))

  defp kind_of(statement) do
    case directives(statement) do
      [{kind, _target} | _] -> kind
      [] -> nil
    end
  end

  defp target_of(statement) do
    case directives(statement) do
      [{_kind, target} | _] -> target
      [] -> ""
    end
  end

  defp match(statement, kind, target), do: directive(statement) == {kind, target}

  # Already there means the same directive, options and all: `import Foo, only: [b: 1]` beside an
  # `import Foo, only: [a: 1]` was taken for there and dropped without a word. A multi-alias names
  # its targets bare, so it is the same only as one added without options.
  defp already(source, found, line, bare) do
    same? =
      case found do
        {_kind, _meta, [{:__aliases__, _, _} | _]} -> plain(written(source, found)) == plain(line)
        _multi -> line == bare
      end

    if same?,
      do: source,
      else: {:error, "`#{written(source, found)}` is already here — `replace` changes its options"}
  end

  defp written(source, node), do: Menard.Source.slice(source, Sourceror.get_range(node))

  defp plain(code) do
    case Code.string_to_quoted(code) do
      {:ok, ast} -> Macro.prewalk(ast, &Macro.update_meta(&1, fn _meta -> [] end))
      {:error, _} -> code
    end
  end

  defp moduledoc?({:@, _meta, [{:moduledoc, _inner, _args}]}), do: true
  defp moduledoc?(_statement), do: false

  # The conventional order. A nil kind (anything that is not a directive) sorts after all of them,
  # so a def never counts as something an alias should go below.
  defp rank(kind), do: Enum.find_index(@kinds, &(&1 == kind)) || 99

  defp directive_line(kind, target, nil), do: "#{kind} #{target}"
  defp directive_line(kind, target, ""), do: "#{kind} #{target}"
  defp directive_line(kind, target, args), do: "#{kind} #{target}, #{args}"

  defp patch(source, range, change),
    do: Sourceror.patch_string(source, [%{range: range, change: change, preserve_indentation: false}])
end
