defmodule Mix.Tasks.Menard.Help do
  @shortdoc "What menard's verbs are for, by example: mix menard.help [VERB]"
  @moduledoc """
  `mix menard.help` — every verb in a line, with the call it is most reached for.
  `mix menard.help VERB` — what the verb does, the calls it takes, an example of each kind.

  `menard --help` and `menard VERB --help` are these (`bin/menard`).
  """
  use Mix.Task

  alias Menard.Verbs

  import Menard.CLI

  @impl true
  def run(argv) do
    case Verbs.Help.run(%{verb: List.first(argv)}) do
      {:ok, %{text: text}} -> Mix.shell().info(String.trim_trailing(text))
      {:error, why} -> usage(why)
    end
  end
end
