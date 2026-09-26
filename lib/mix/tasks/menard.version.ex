defmodule Mix.Tasks.Menard.Version do
  @shortdoc "Which menard, on which Elixir and OTP"
  @moduledoc """
  `mix menard.version` — `menard 0.2.0 on Elixir 1.19.4 / OTP 27`. The first question of any
  install: menard runs on its own pinned toolchain (`.tool-versions`), not the caller's.
  """
  use Mix.Task

  alias Menard.Verbs

  @impl true
  def run(_argv) do
    {:ok, reply} = Verbs.Version.run(%{})
    Mix.shell().info(Verbs.Version.line(reply))
  end
end
