defmodule Menard.Verbs.Guard do
  @moduledoc """
  The `guard` verb (`Menard.Verbs`): should a text edit of `file` be refused? The enforcement every
  harness adapter calls from its pre-edit hook (docs/adapters.md). An existing `.ex`/`.exs` holding
  a `defmodule` is edited with menard's verbs, so a text edit of it answers `allowed: false` with
  the `reason` and the verbs to use. Everything else is allowed: other languages, a file that does
  not exist yet (creation), a script with no module, and the bare-data or generated paths menard
  has no verbs for (`config/*.exs`, `.formatter.exs`, `mix.lock`, `deps/`, `_build/`).

  `edit` is the harness's edit as JSON (Claude Code's `tool_input`, or pi's): one that only changes
  text inside a string or sigil (a heredoc, a `~H` template) or a `#` comment, where no verb
  reaches, is allowed. `mcp` names the harness's MCP tools (a prefix) in the refusal instead of CLI
  lines, which a blocked agent would run through its shell.
  """

  import Menard.Verbs

  @exempt ~r{(^|/)(_build|deps)/|(^|/)config/[^/]*\.exs$|(^|/)\.formatter\.exs$|(^|/)mix\.lock$}

  @spec run(Menard.Verbs.params()) :: Menard.Verbs.result()
  def run(p) do
    with :ok <- need(p, [:file], "guard"),
         {:ok, path} <- resolve(p.file, p) do
      if module?(path) and not Regex.match?(@exempt, path) and not prose_only?(path, p[:edit]),
        do: {:ok, %{allowed: false, reason: refusal(path, p[:mcp])}},
        else: {:ok, %{allowed: true}}
    end
  end

  defp module?(path) do
    Path.extname(path) in [".ex", ".exs"] and File.regular?(path) and
      Regex.match?(~r/^\s*defmodule\b/m, File.read!(path))
  end

  defp refusal(path, nil) do
    m = Path.join(File.cwd!(), "bin/menard")

    """
    Blocked: #{path} is an Elixir module.

    A module is edited with menard's verbs — they parse the file, change the tree and parse-check
    what they write — not with text substitution:

      #{m} outline FILE                        what is in the file
      #{m} clause replace|rewrite|delete|insert-after FILE name/arity HEAD [CODE]
      #{m} clause move FILE a/1,b/2,… --to NEW_FILE --delegate    a split: one call per new module
      #{m} stmt insert-after|replace|delete FILE name/arity HEAD MATCH [CODE]
      #{m} attr get|set|delete FILE NAME [VAL]
      #{m} block get|replace|add|delete FILE NAME [CODE]
      #{m} rename OLD NEW [--atoms] [--comments] FILES

    CODE full of quotes: write it to a file and pass --stdin. If this file genuinely is not a module,
    say so and edit it directly; do not reach for another way to write it.
    """
  end

  defp refusal(path, p) do
    """
    Blocked: #{path} is an Elixir module.

    A module is edited with menard's MCP tools — they parse the file, change the tree and parse-check
    what they write — not with text substitution. `file` is relative to the project.

      #{p}outline    {file}                                        what is in the file
      #{p}clause     {verb: replace|rewrite|insert_after|delete, file, name_arity, head, code}
      #{p}clause     {verb: move, file, name_arity: ["a/1", "b/2", …], to, delegate: true}   a split: one call per new module
      #{p}stmt       {verb: replace|insert_after|delete, file, name_arity, head, match, code}
      #{p}attr       {verb: get|set|delete, file, name, value}
      #{p}block      {verb: get|replace|add|delete, file, name: "test", label, code}
      #{p}directive  {verb: add|replace|remove, file, kind: "alias", target}
      #{p}rename     {old, new, files}

    `replace` takes the body, `rewrite` the whole clause; `head` is the clause's current head, as
    `outline` prints it.
    Finish on #{p}run {verb: "check"}: format, warnings-as-errors and the tests in one reply.
    If this file genuinely is not a module, say so and edit it directly; do not reach for sed or
    another way to write it.
    """
  end

  # Text inside a string or sigil (a heredoc, a ~H template) is one node to menard, and a comment is
  # no node at all: no verb reaches either. Such an edit passes: the file it leaves parses to the same
  # tree, strings aside. Code interpolated into a string is still tree, so a change to it is refused.
  defp prose_only?(_path, nil), do: false

  defp prose_only?(path, json) do
    old = File.read!(path)

    with {:ok, input} <- JSON.decode(json),
         {:ok, new} <- applied(old, input),
         {:ok, a} <- Code.string_to_quoted(old, emit_warnings: false),
         {:ok, b} <- Code.string_to_quoted(new, emit_warnings: false) do
      unstrung(a) == unstrung(b)
    else
      _ -> false
    end
  end

  # The file the edit would leave, from Claude Code's Write, MultiEdit or Edit input
  defp applied(_old, %{"content" => content}) when is_binary(content), do: {:ok, content}

  defp applied(old, %{"edits" => edits}) when is_list(edits) do
    Enum.reduce_while(edits, {:ok, old}, fn edit, {:ok, src} ->
      case applied(src, edit) do
        {:ok, next} -> {:cont, {:ok, next}}
        error -> {:halt, error}
      end
    end)
  end

  defp applied(old, %{"old_string" => from, "new_string" => to} = edit) when from != "" do
    case {length(:binary.matches(old, from)), edit["replace_all"]} do
      {0, _} -> :error
      {_, true} -> {:ok, String.replace(old, from, to)}
      {1, _} -> {:ok, String.replace(old, from, to, global: false)}
      _ -> :error
    end
  end

  # pi's edit: `edits: [%{oldText, newText}]`, each matched once
  defp applied(old, %{"oldText" => from, "newText" => to}),
    do: applied(old, %{"old_string" => from, "new_string" => to})

  defp applied(_old, _input), do: :error

  defp unstrung(ast) do
    Macro.prewalk(ast, fn
      string when is_binary(string) -> :string
      {form, meta, args} when is_list(meta) -> {form, [], args}
      other -> other
    end)
  end
end
