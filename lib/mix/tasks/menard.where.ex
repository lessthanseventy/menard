defmodule Mix.Tasks.Menard.Where do
  @shortdoc "Name the function each FILE:LINE sits in: mix menard.where FILE:LINE..."
  @moduledoc """
  `mix menard.where lib/a.ex:42 lib/b.ex:7 …` — for each, the module and function whose lines hold
  it (`lib/a.ex:42  Shop.Cart.total/1`), or the module alone for a line outside every def. The MCP
  door's `outline {verb: "where", at: [...]}`.

  What grep cannot say: every eval trace began with a grep, then a Read of each hit's file to see
  which function it sat in. The format hook adds this to a grep over Elixir files.
  """
  use Mix.Task

  alias Menard.Verbs

  import Menard.CLI

  @impl true
  def run(argv) do
    if argv == [], do: usage("mix menard.where FILE:LINE...")
    {:ok, %{at: found}} = Verbs.Outline.run(%{verb: "where", at: argv})

    Enum.each(found, fn %{file: file, line: line, in: name} ->
      Mix.shell().info("#{file}:#{line}  #{name}")
    end)
  end
end
