defmodule Menard.Test.Identity do
  @moduledoc false
  # The identity oracle: an edit that writes back what is already there must leave the file as it
  # was. Shared by the identity test (this repo, every run) and the hex corpus benchmark (real
  # packages, on demand). It shares no code with what it checks: its own slice, its own heads.

  alias Menard.{Attr, Block, Clause, Stmt}

  @kinds [:def, :defp, :defmacro, :defmacrop]
  @checks [:clause, :attr, :block, :stmt]

  def checks, do: @checks

  @doc """
  Every identity edit of `check` on `source`, as `{label, outcome}`: `:same` (byte for byte),
  `:formatted` (different bytes that format the same), `:changed` (a miss) or `:refused`.
  """
  def run(source, check) do
    edits = edits(source, check)
    for {label, out} <- edits, do: {label, outcome(out, source, formatted(source))}
  end

  @doc "The edits of `check` that changed the file, each with the hunks it changed: what a miss was."
  def changes(source, check) do
    edits = edits(source, check)

    for {label, out} <- edits,
        outcome(out, source, formatted(source)) == :changed,
        do: {label, Menard.Diff.hunks(source, out)}
  end

  defp edits(source, :clause) do
    for {mod, node} <- modules(source),
        {kind, meta, [head, [{_do, body} | _]]} <- Clause.module_body(node),
        kind in @kinds and meta[:do] != nil,
        text = slice(source, body),
        is_binary(text) do
      {name, arity, args} = head_of(head)
      out = Clause.replace_body(source, "#{mod}.#{name}/#{arity}", args, text)
      {"#{mod}.#{name}/#{arity} `#{args}`", out}
    end
  end

  defp edits(source, :attr) do
    for {mod, node} <- modules(source),
        # a module the verbs refuse (defined twice) has nothing to list
        listed = Attr.list(source, module: mod),
        is_list(listed),
        # a name set more than once is refused by `set` — the clause verbs own those
        {name, 1} <- Enum.frequencies_by(listed, &elem(&1, 0)),
        {:@, _, [{^name, _, [value]}]} <- Clause.module_body(node),
        text = slice(source, value),
        is_binary(text) do
      {"#{mod} @#{name}", Attr.set(source, name, text, module: mod)}
    end
  end

  defp edits(source, :block) do
    for {mod, _node} <- modules(source),
        listed = Block.list(source, module: mod),
        is_list(listed),
        {name, label, _line} <- listed,
        body = Block.get(source, name, module: mod, label: label),
        is_binary(body) do
      out = Block.replace(source, name, body, module: mod, label: label)
      {"#{mod} #{name} #{inspect(label)}", out}
    end
  end

  defp edits(source, :stmt) do
    for {mod, node} <- modules(source),
        {kind, _meta, [head | _]} <- Clause.module_body(node),
        kind in @kinds,
        {name, arity, args} = head_of(head),
        na = "#{mod}.#{name}/#{arity}",
        statements = Stmt.list(source, na, args),
        is_list(statements),
        text <- Enum.uniq(statements) do
      {"#{na} `#{String.slice(text, 0, 50)}`", Stmt.replace(source, na, args, text, text)}
    end
  end

  @doc "The edits of `check` that changed the file."
  def misses(source, check), do: for({label, :changed} <- run(source, check), do: label)

  # A refusal is not a miss (an ambiguous head, a name two modules share); a changed file is.
  # Bytes first — formatting both sides is the slow part, and most writes are byte-identical. The
  # source's own format is the same for every edit of it, so it is made once, and only if needed:
  # made per edit, it was most of the hex corpus benchmark's time.
  defp outcome(out, _source, _formatted) when not is_binary(out), do: :refused
  defp outcome(source, source, _formatted), do: :same
  defp outcome(out, _source, formatted), do: if(fmt(out) == formatted.(), do: :formatted, else: :changed)

  defp formatted(source) do
    key = {__MODULE__, :erlang.phash2(source)}

    fn ->
      case Process.get(key) do
        nil -> tap(fmt(source), &Process.put(key, &1))
        cached -> cached
      end
    end
  end

  defp fmt(source) do
    source |> Code.format_string!(line_length: 110) |> IO.iodata_to_binary()
  rescue
    _unparseable -> :unparseable
  end

  defp modules(source) do
    {:ok, ast} = Sourceror.parse_string(source)
    Clause.modules(ast)
  end

  # nil where Sourceror has no range for the node (seen in credo): the oracle cannot say what is
  # there, so it makes no edit, rather than a crash that hides every other edit in the file
  defp slice(source, node) do
    case Sourceror.get_range(node) do
      %{start: start, end: [line: b, column: cb]} ->
        {a, ca} = first_position(node, {start[:line], start[:column]})
        slice(source, a, ca, b, cb)

      nil ->
        nil
    end
  end

  # Sourceror starts `x not in y` at `not` and `__MODULE__.A.f()` after `__MODULE__`; where a node
  # inside says it begins earlier, it does
  defp first_position(node, earliest) do
    node
    |> Macro.prewalker()
    |> Enum.reduce(earliest, fn
      {_, meta, _}, acc when is_list(meta) ->
        here = {meta[:line], meta[:column]}
        if is_integer(elem(here, 0)) and is_integer(elem(here, 1)) and here < acc, do: here, else: acc

      _, acc ->
        acc
    end)
  end

  defp slice(source, a, ca, b, cb) do
    last_line = source |> String.split("\n") |> Enum.at(b - 1, "")

    # Sourceror's end is off on a line-closing node: past the line after a literal, inside the
    # quotes of an interpolated heredoc
    cb =
      case Regex.run(~r/^\s*"""/, last_line) do
        # the closing quotes, or past them when the node goes on: `raise(E, """ … """)` ends after `)`
        [closing] -> cb |> max(String.length(closing) + 1) |> min(String.length(last_line) + 1)
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
