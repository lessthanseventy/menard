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

  @impl true
  def run([file]), do: check(file, nil)
  # `--mcp PREFIX`: the harness has menard as MCP tools named PREFIX<noun>, so the refusal names those,
  # not CLI lines a blocked agent would then run through its shell
  def run([file, "--mcp", prefix]), do: check(file, prefix)

  def run(_argv), do: Mix.raise("usage: mix menard.guard FILE [--mcp TOOL_PREFIX]")

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

    `replace` takes the body, `rewrite` the whole clause, `head` is the clause's arguments as written.
    Not loaded yet: ToolSearch "select:#{p}outline,#{p}clause,#{p}stmt".
    If this file genuinely is not a module, say so and edit it directly; do not reach for sed or
    another way to write it.
    """
  end

  defp check(file, prefix) do
    path = Menard.resolve(file)

    if module?(path) and not Regex.match?(@exempt, path) do
      IO.puts(:stderr, refusal(path, prefix))
      exit({:shutdown, 2})
    end
  end
end
