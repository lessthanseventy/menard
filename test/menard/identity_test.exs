defmodule Menard.IdentityTest do
  # An edit that writes back what is already there must leave the file as it was. Run over every
  # source file in this repo, that is the check "only the named bytes move" never had: a verb that
  # drops a `rescue`, eats a line, or reshapes a neighbour fails here, however well its output parses.
  use ExUnit.Case, async: true

  alias Menard.{Attr, Block, Clause}

  @root Path.expand("../..", __DIR__)
  @files Path.wildcard(Path.join(@root, "{lib,test}/**/*.{ex,exs}"))
  @kinds [:def, :defp, :defmacro, :defmacrop]

  defp fmt(source) do
    source |> Code.format_string!(line_length: 110) |> IO.iodata_to_binary()
  rescue
    _unparseable -> :unparseable
  end

  defp slice(source, %{start: [line: a, column: ca], end: [line: b, column: cb]}) do
    lines = source |> String.split("\n") |> Enum.slice((a - 1)..(b - 1))

    case lines do
      [one] ->
        String.slice(one, ca - 1, cb - ca)

      [first | rest] ->
        {mid, [last]} = Enum.split(rest, -1)
        Enum.join([String.slice(first, (ca - 1)..-1//1) | mid] ++ [String.slice(last, 0, cb - 1)], "\n")
    end
  end

  defp modules(source) do
    {:ok, ast} = Sourceror.parse_string(source)
    Clause.modules(ast)
  end

  defp misses(check) do
    for file <- @files,
        source = File.read!(file),
        miss <- check.(source),
        do: "#{Path.relative_to(file, @root)}: #{miss}"
  end

  test "clause replace with a clause's own body changes nothing" do
    misses =
      misses(fn source ->
        for {mod, node} <- modules(source),
            {kind, meta, [head, [{_do, body} | _]]} <- Clause.module_body(node),
            kind in @kinds and meta[:do] != nil,
            {name, arity, args} = head_of(head),
            out =
              Clause.replace_body(
                source,
                "#{mod}.#{name}/#{arity}",
                args,
                slice(source, Sourceror.get_range(body))
              ),
            is_binary(out) and fmt(out) != fmt(source),
            do: "#{mod}.#{name}/#{arity} `#{args}`"
      end)

    assert misses == []
  end

  test "attr set with an attribute's own value changes nothing" do
    misses =
      misses(fn source ->
        for {mod, node} <- modules(source),
            {name, _line} <- Attr.list(source, module: mod),
            {:@, _, [{^name, _, [value]}]} <- Clause.module_body(node),
            out = Attr.set(source, name, slice(source, Sourceror.get_range(value)), module: mod),
            is_binary(out) and fmt(out) != fmt(source),
            do: "#{mod} @#{name}"
      end)

    assert misses == []
  end

  test "block replace with a block's own body changes nothing" do
    misses =
      misses(fn source ->
        for {mod, _node} <- modules(source),
            {name, label, _line} <- Block.list(source, module: mod),
            body = Block.get(source, name, module: mod, label: label),
            is_binary(body),
            out = Block.replace(source, name, body, module: mod, label: label),
            is_binary(out) and fmt(out) != fmt(source),
            do: "#{mod} #{name} #{inspect(label)}"
      end)

    assert misses == []
  end

  defp head_of({:when, _, [call, guard]}) do
    {name, arity, args} = head_of(call)
    {name, arity, args <> " when " <> Sourceror.to_string(guard)}
  end

  defp head_of({name, _, args}) when is_list(args),
    do: {name, length(args), Enum.map_join(args, ", ", &Sourceror.to_string/1)}

  defp head_of({name, _, _}), do: {name, 0, ""}
end
