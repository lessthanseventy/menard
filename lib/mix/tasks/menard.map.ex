defmodule Mix.Tasks.Menard.Map do
  @shortdoc "The project's modules and public functions, one line each: mix menard.map"
  @moduledoc """
  `mix menard.map` — every module under a `lib/` of the project (each app's, in an umbrella or a
  repo of several), one line each: its name, its file, its public functions
  (`Shop.Cart  lib/shop/cart.ex  new/0 add/3 total/1`), a dozen at most. Capped near 12,000 characters, about
  3,000 tokens; what the cap cuts is counted, and `outline` reads any file whole. `--all`: every
  module and function, uncapped. The MCP door's `outline {verb: "map"}`.

  A map an agent starts with, in place of the grep and Read that open every eval trace.
  """
  use Mix.Task

  alias Menard.Verbs

  @impl true
  def run(argv) do
    {:ok, %{modules: modules, cut: cut}} = Verbs.Outline.run(%{verb: "map", all: "--all" in argv})
    Enum.each(modules, &Mix.shell().info(Verbs.Outline.line(&1)))
    if cut > 0, do: Mix.shell().info("… #{cut} more modules not shown: `menard outline FILE` reads one whole")
  end
end
