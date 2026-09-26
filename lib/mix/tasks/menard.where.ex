defmodule Mix.Tasks.Menard.Where do
  @shortdoc "Name the function each FILE:LINE sits in: mix menard.where FILE:LINE..."
  @moduledoc """
  `mix menard.where lib/a.ex:42 lib/b.ex:7 …` — for each, the module and function whose lines hold
  it (`lib/a.ex:42  Shop.Cart.total/1`), or the module alone for a line outside every def.

  What grep cannot say: every eval trace began with a grep, then a Read of each hit's file to see
  which function it sat in. The format hook adds this to a grep over Elixir files.
  """
  use Mix.Task

  alias Menard.Outline

  @impl true
  def run(argv) do
    if argv == [], do: Mix.raise("usage: mix menard.where FILE:LINE...")

    argv
    |> Enum.flat_map(&parse/1)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.each(fn {file, lines} ->
      with {:ok, content} <- File.read(Menard.resolve(file)),
           {:ok, modules} <- Outline.run(content) do
        for line <- lines, name = at(modules, line), do: Mix.shell().info("#{file}:#{line}  #{name}")
      end
    end)
  end

  defp parse(arg) do
    case Regex.run(~r/\A(.+\.exs?):(\d+)/, arg) do
      [_, file, line] -> [{file, String.to_integer(line)}]
      nil -> []
    end
  end

  # the innermost module holding the line, then its def: a nested module's defs are its own
  defp at(modules, line) do
    Enum.find_value(modules, fn m ->
      {a, b} = m.lines || {0, 0}

      if line in a..b//1 do
        at(m.modules, line) ||
          case Enum.find(m.defs, &(line in elem(&1.lines || {0, 0}, 0)..elem(&1.lines || {0, 0}, 1)//1)) do
            nil -> m.module
            d -> "#{m.module}.#{d.name}/#{d.arity}"
          end
      end
    end)
  end
end
