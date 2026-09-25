defmodule Menard.IdentityTest do
  # An edit that writes back what is already there must leave the file as it was. Run over every
  # source file in this repo and test/fixtures/weird.ex, that is the check "only the named bytes
  # move" never had: a verb that drops a `rescue`, eats a line, or reshapes a neighbour fails here,
  # however well its output parses. One describe per file, so the files run in parallel.
  use ExUnit.Case, async: true

  alias Menard.{Attr, Block, Clause, Stmt}

  @root Path.expand("../..", __DIR__)
  @kinds [:def, :defp, :defmacro, :defmacrop]

  for path <- Path.wildcard(Path.join(@root, "{lib,test}/**/*.{ex,exs}")) do
    @path path

    describe Path.relative_to(path, @root) do
      test "clause replace with a clause's own body" do
        source = File.read!(@path)

        misses =
          for {mod, node} <- modules(source),
              {kind, meta, [head, [{_do, body} | _]]} <- Clause.module_body(node),
              kind in @kinds and meta[:do] != nil,
              {name, arity, args} = head_of(head),
              out = Clause.replace_body(source, "#{mod}.#{name}/#{arity}", args, slice(source, body)),
              changed?(out, source),
              do: "#{mod}.#{name}/#{arity} `#{args}`"

        assert misses == []
      end

      test "attr set with an attribute's own value" do
        source = File.read!(@path)

        misses =
          for {mod, node} <- modules(source),
              # a name set more than once is refused by `set` — the clause verbs own those
              {name, 1} <- source |> Attr.list(module: mod) |> Enum.frequencies_by(&elem(&1, 0)),
              {:@, _, [{^name, _, [value]}]} <- Clause.module_body(node),
              out = Attr.set(source, name, slice(source, value), module: mod),
              changed?(out, source),
              do: "#{mod} @#{name}"

        assert misses == []
      end

      test "block replace with a block's own body" do
        source = File.read!(@path)

        misses =
          for {mod, _node} <- modules(source),
              {name, label, _line} <- Block.list(source, module: mod),
              body = Block.get(source, name, module: mod, label: label),
              is_binary(body),
              out = Block.replace(source, name, body, module: mod, label: label),
              changed?(out, source),
              do: "#{mod} #{name} #{inspect(label)}"

        assert misses == []
      end

      test "stmt replace with a statement's own text" do
        source = File.read!(@path)

        misses =
          for {mod, node} <- modules(source),
              {kind, _meta, [head | _]} <- Clause.module_body(node),
              kind in @kinds,
              {name, arity, args} = head_of(head),
              na = "#{mod}.#{name}/#{arity}",
              statements = Stmt.list(source, na, args),
              is_list(statements),
              text <- Enum.uniq(statements),
              out = Stmt.replace(source, na, args, text, text),
              changed?(out, source),
              do: "#{na} `#{String.slice(text, 0, 50)}`"

        assert misses == []
      end
    end
  end

  # A refusal is not a miss (an ambiguous head, a name two modules share); a changed file is.
  # Bytes first — formatting both sides is the slow part, and most writes are byte-identical.
  defp changed?(out, source), do: is_binary(out) and out != source and fmt(out) != fmt(source)

  defp fmt(source) do
    source |> Code.format_string!(line_length: 110) |> IO.iodata_to_binary()
  rescue
    _unparseable -> :unparseable
  end

  defp modules(source) do
    {:ok, ast} = Sourceror.parse_string(source)
    Clause.modules(ast)
  end

  # Its own slice, not Menard.Source's: the oracle should not share code with what it checks.
  defp slice(source, node) do
    %{start: [line: a, column: ca], end: [line: b, column: cb]} = Sourceror.get_range(node)
    last_line = source |> String.split("\n") |> Enum.at(b - 1, "")

    # Sourceror's end is off on a line-closing node: past the line after a literal, inside the
    # quotes of an interpolated heredoc
    cb =
      case Regex.run(~r/^\s*"""/, last_line) do
        [closing] -> String.length(closing) + 1
        nil -> min(cb, String.length(last_line) + 1)
      end

    case source |> String.split("\n") |> Enum.slice((a - 1)..(b - 1)) do
      [one] ->
        String.slice(one, ca - 1, cb - ca)

      [first | rest] ->
        {mid, [last]} = Enum.split(rest, -1)
        Enum.join([String.slice(first, (ca - 1)..-1//1) | mid] ++ [String.slice(last, 0, cb - 1)], "\n")
    end
  end

  defp head_of({:when, _, [call, guard]}) do
    {name, arity, args} = head_of(call)
    {name, arity, args <> " when " <> Sourceror.to_string(guard)}
  end

  defp head_of({name, _, args}) when is_list(args),
    do: {name, length(args), Enum.map_join(args, ", ", &Sourceror.to_string/1)}

  defp head_of({name, _, _}), do: {name, 0, ""}
end
