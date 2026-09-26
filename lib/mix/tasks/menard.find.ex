defmodule Mix.Tasks.Menard.Find do
  @shortdoc "Search that knows the code: mix menard.find (calls TARGET|defs NAME[/ARITY]|aliases MOD) [--json] FILE..."
  @moduledoc """
  grep for code (`Menard.Find`): strings and comments never match, and a call is a call.

      mix menard.find calls Server.Channels.general lib/**/*.ex   # remote, alias-aware
      mix menard.find calls general lib/server/channels.ex        # local
      mix menard.find defs general/1 lib/**/*.ex
      mix menard.find aliases Server.Channels lib/**/*.ex

  One line per hit (`file:line:column kind text`), or `--json` for the reply as the MCP door gives
  it (`hits`). Globs are expanded here.
  """
  use Mix.Task

  alias Menard.Verbs

  import Menard.CLI

  @impl true
  def run(argv) do
    {opts, args, _} = OptionParser.parse(argv, strict: [json: :boolean])

    case args do
      [kind, target | files] when files != [] ->
        print(Verbs.Find.run(%{kind: kind, target: target, files: files}), opts[:json] == true)

      _ ->
        usage("mix menard.find (calls TARGET|defs NAME[/ARITY]|aliases MOD) [--json] FILE...")
    end
  end

  defp print(result, true), do: answer(result)
  defp print({:ok, %{hits: hits}}, false), do: Enum.each(hits, &Mix.shell().info(line(&1)))
  defp print({:error, reason}, false), do: Mix.raise(reason)

  # A def's text is its head, which already starts with its kind: `def go(x)`, not `def def go(x)`.
  defp line(%{file: file, line: l, column: c, kind: kind, text: text}) do
    text = if String.starts_with?(text, "#{kind} "), do: text, else: "#{kind} #{text}"
    "#{file}:#{l}:#{c} #{text}"
  end
end
