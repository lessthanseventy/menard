defmodule Mix.Tasks.Menard.Guard do
  @shortdoc "Should a text edit of FILE be refused? Exit 2 with the reason for an Elixir module, 0 otherwise"
  @moduledoc """
  `mix menard.guard FILE` — the enforcement every harness adapter calls from its pre-edit hook
  (docs/adapters.md). An existing `.ex`/`.exs` holding a `defmodule` is edited with menard's verbs,
  so a text edit of it exits 2 with the reason and the verbs to use on stderr. Everything else exits
  0: other languages, a file that does not exist yet (creation), a script with no module, and the
  bare-data or generated paths menard has no verbs for (`config/*.exs`, `.formatter.exs`,
  `mix.lock`, `deps/`, `_build/`).
  """
  use Mix.Task

  @exempt ~r{(^|/)(_build|deps)/|(^|/)config/[^/]*\.exs$|(^|/)\.formatter\.exs$|(^|/)mix\.lock$}

  # `--mcp PREFIX`: the harness has menard as MCP tools named PREFIX<noun>, so the refusal names those,
  # not CLI lines a blocked agent would then run through its shell. `--edit JSON`: the harness's edit
  # (Claude Code's tool_input), so an edit that only changes text inside strings can pass.
  @impl true
  def run(argv) do
    case OptionParser.parse(argv, strict: [mcp: :string, edit: :string]) do
      {opts, [file], []} -> check(file, opts[:mcp], opts[:edit])
      _ -> Mix.raise("usage: mix menard.guard FILE [--mcp TOOL_PREFIX] [--edit TOOL_INPUT_JSON]")
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
      #{p}stmt       {verb: replace|insert_after|delete, file, name_arity, head, match, code}
      #{p}attr       {verb: get|set|delete, file, name, value}
      #{p}block      {verb: get|replace|add|delete, file, name: "test", label, code}
      #{p}directive  {verb: add|replace|remove, file, kind: "alias", target}
      #{p}rename     {old, new, files}

    `replace` takes the body, `rewrite` the whole clause; `head` is the clause's current head, as
    `outline` prints it.
    Not loaded yet: ToolSearch "select:#{p}outline,#{p}clause,#{p}stmt".
    Finish on #{p}run {verb: "check"}: format, warnings-as-errors and the tests in one reply.
    If this file genuinely is not a module, say so and edit it directly; do not reach for sed or
    another way to write it.
    """
  end

  defp check(file, prefix, edit) do
    path = Menard.resolve(file)

    if module?(path) and not Regex.match?(@exempt, path) and not strings_only?(path, edit) do
      IO.puts(:stderr, refusal(path, prefix))
      exit({:shutdown, 2})
    end
  end

  # Text inside a string or sigil (a heredoc, a ~H template) is one node to menard, so no verb reaches
  # into it. Such an edit passes: the file it leaves parses to the same tree, strings aside, with the
  # same comments. Code interpolated into a string is still tree, so a change to it is refused.
  defp strings_only?(_path, nil), do: false

  defp strings_only?(path, json) do
    old = File.read!(path)

    with {:ok, input} <- JSON.decode(json),
         {:ok, new} <- applied(old, input),
         {:ok, a, a_comments} <- Code.string_to_quoted_with_comments(old),
         {:ok, b, b_comments} <- Code.string_to_quoted_with_comments(new) do
      unstrung(a) == unstrung(b) and Enum.map(a_comments, & &1.text) == Enum.map(b_comments, & &1.text)
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

  defp applied(_old, _input), do: :error

  defp unstrung(ast) do
    Macro.prewalk(ast, fn
      string when is_binary(string) -> :string
      {form, meta, args} when is_list(meta) -> {form, [], args}
      other -> other
    end)
  end
end
