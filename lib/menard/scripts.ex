defmodule Menard.Scripts do
  @moduledoc """
  Scripts in another language, and whether a session may run them: `MENARD_SCRIPTS`, set where the
  plugin's MCP server gets its environment (`.claude-plugin/plugin.json`).

  - `off` (the default): any command runs. A script that edited a module is told of `edit` after
    the fact (`Menard.Hook`), and that is all.
  - `narrow`: a script that names an Elixir file is refused: python, perl, ruby or node with a
    `.ex`, `.exs` or `.heex` path in its text, and `sed -i` on one. Scripts for anything else run.
  - `full`: a command that runs python, perl, ruby or node is refused, whatever it is for.

  Either ban is said twice. Up front, at the start of the session, as what is so here (`upfront/1`):
  a rule the agent meets only in a refusal costs the call that was refused, each time. And in the
  refusal (`refused/2`), which is what holds when the first was not read.

  What a command will write cannot be known from its text, so `narrow` goes by what the text
  names: a script that reads a module and writes a report is refused with the ones that edit it.
  """

  @elixir ~r/[\w.\/~*-]+\.(?:exs?|heex)\b/

  # where a command starts: the line's, after a separator, inside $( ), after a shell keyword
  @starts ~S"(?:^|[;&|(\n`]|\$\(|\b(?:do|then|else)\s)\s*"
  # a command's first word, after the assignments and the wrappers in front of it
  @wrapped ~S"(?:\w+=\S*\s+)*(?:(?:timeout\s+(?:-\S+\s+)*\S+|nohup|env|nice(?:\s+-n\s*\S+)?|time|command|exec)\s+(?:\w+=\S*\s+)*)*"
  @runs Regex.compile!(@starts <> @wrapped <> ~S"(?:\S*/)?(python3?(?:\.\d+)?|perl|ruby|node)(?=\s|$)")
  @sed Regex.compile!(@starts <> @wrapped <> ~S"(?:\S*/)?sed\s+(?:-\S+\s+)*(?:-\w*i|--in-place)")
  @heredoc ~r/<<-?\s*(['"]?)(\w+)\1[^\n]*\n.*?\n\s*\2(?=\n|$)/s

  @type mode :: :off | :narrow | :full

  @doc "The ban this session is under."
  @spec mode() :: mode()
  def mode do
    case System.get_env("MENARD_SCRIPTS") do
      "narrow" -> :narrow
      "full" -> :full
      _ -> :off
    end
  end

  @doc "Why `command` is refused under `mode`, or nil when it runs. `menard` is this menard's path."
  @spec refused(String.t(), mode(), String.t()) :: String.t() | nil
  def refused(_command, :off, _menard), do: nil

  def refused(command, :full, menard) do
    case interpreter(command) do
      nil -> nil
      script -> "#{script} does not run here. " <> instead(:full, menard)
    end
  end

  def refused(command, :narrow, menard) do
    script = interpreter(command) || if(Regex.match?(@sed, outside_heredocs(command)), do: "sed -i")

    case script && Regex.run(@elixir, command) do
      [file] -> "#{script} does not edit Elixir here (#{file}). " <> instead(:narrow, menard)
      _ -> nil
    end
  end

  @doc "What is so in this session, said at its start: nil where nothing is refused."
  @spec upfront(mode(), String.t()) :: String.t() | nil
  def upfront(:off, _menard), do: nil

  def upfront(:full, menard) do
    "There is no python, perl, ruby or node in this session: a command that runs one is refused. " <>
      instead(:full, menard)
  end

  def upfront(:narrow, menard) do
    "In this session no script edits an Elixir file (.ex, .exs, .heex): python, perl, ruby, node and " <>
      "`sed -i` on one are refused. Scripts for anything else run. " <> instead(:narrow, menard)
  end

  defp instead(mode, menard) do
    """
    Text is replaced, in one file or many, in one call, with menard's edit: every text found exactly \
    once or nothing written, and `--then test` runs the tests after.
      #{menard} edit --then test - <<'EOF'
      lib/a.ex
      <<<<<<< SEARCH
      the text to find
      =======
      the text to put there
      >>>>>>> REPLACE
      lib/b.ex
      <<<<<<< SEARCH
      …
      EOF
    A new file is a block with nothing to find, or a heredoc (`cat > lib/new.ex <<'EOF'`). \
    #{other(mode, menard)}\
    """
  end

  defp other(:full, _menard),
    do: "Any other script is Elixir: `elixir -e '…'`, or `mix run -e '…'` for the project's own code."

  defp other(:narrow, menard),
    do: "A name changed everywhere it is used is `#{menard} rename OLD NEW FILES…`."

  # the interpreter a command runs, by a word where a command starts: `grep python notes.md` runs none
  @doc "The interpreter `command` runs (python, perl, ruby, node) where a command starts, never in a heredoc, or nil."
  @spec interpreter(String.t()) :: String.t() | nil
  def interpreter(command) do
    case Regex.run(@runs, outside_heredocs(command)) do
      [_, script] -> script
      nil -> nil
    end
  end

  # a heredoc's body is what a command reads, not a command: `cat > notes.md <<EOF … python … EOF`
  defp outside_heredocs(command), do: Regex.replace(@heredoc, command, "")
end
