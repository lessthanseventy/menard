defmodule Mix.Tasks.Menard.Hook do
  @shortdoc "The harness's hook payload on stdin, the hook's answer on stdout: mix menard.hook"
  @moduledoc """
  `mix menard.hook < PAYLOAD` — `Menard.Hook` for a harness that can only run a command
  (docs/adapters.md): Claude Code's hook payload as JSON on stdin. What the formatter changed is
  printed as the hook's JSON (`additionalContext`); a file that could not be formatted is named on
  stderr with exit 2, the way a command hook tells the agent.
  """
  use Mix.Task

  alias Menard.Verbs

  import Menard.CLI

  @impl true
  def run([]) do
    case JSON.decode(IO.read(:stdio, :eof)) do
      {:ok, %{} = payload} -> say(Verbs.Hook.run(%{payload: payload}))
      _ -> usage("mix menard.hook < PAYLOAD (the harness's hook payload, a JSON object)")
    end
  end

  def run(_argv), do: usage("mix menard.hook < PAYLOAD (the harness's hook payload, a JSON object)")

  defp say({:ok, %{context: text, event: event}}), do: IO.puts(JSON.encode!(Menard.Hook.context(text, event)))

  defp say({:ok, %{problem: text}}) do
    IO.write(:stderr, text)
    exit({:shutdown, 2})
  end

  defp say({:ok, %{}}), do: :ok
end
