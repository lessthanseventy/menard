defmodule Mix.Tasks.Menard.Map do
  @shortdoc "The project's modules and public functions, one line each: mix menard.map"
  @moduledoc """
  `mix menard.map` — every module under a `lib/` of the project (each app's, in an umbrella or a
  repo of several), one line each: its name, its file, its public functions
  (`Shop.Cart  lib/shop/cart.ex  new/0 add/3 total/1`), a dozen at most. Capped near 12,000 characters, about
  3,000 tokens; what the cap cuts is counted, and `outline` reads any file whole. `--all`: every
  module and function, uncapped.

  A map an agent starts with, in place of the grep and Read that open every eval trace.
  """
  use Mix.Task

  alias Menard.Outline

  @cap 12_000

  @impl true
  def run(argv) do
    root = Menard.caller_dir()
    all = "--all" in argv

    lines =
      root
      |> Path.join("**/lib/**/*.ex")
      |> Path.wildcard()
      |> Enum.reject(&(&1 =~ ~r{/(deps|_build|node_modules)/}))
      |> Enum.sort()
      |> Enum.flat_map(&modules(&1, Path.relative_to(&1, root), all))

    {shown, _} =
      Enum.reduce_while(lines, {[], 0}, fn line, {acc, size} ->
        if not all and size + byte_size(line) > @cap,
          do: {:halt, {acc, size}},
          else: {:cont, {[line | acc], size + byte_size(line) + 1}}
      end)

    Enum.each(Enum.reverse(shown), fn line -> Mix.shell().info(line) end)
    cut = length(lines) - length(shown)
    if cut > 0, do: Mix.shell().info("… #{cut} more modules not shown: `menard outline FILE` reads one whole")
  end

  defp modules(path, rel, all) do
    with {:ok, content} <- File.read(path), {:ok, modules} <- Outline.run(content) do
      flatten(modules, rel, all)
    else
      _ -> []
    end
  end

  defp flatten(modules, rel, all) do
    Enum.flat_map(modules, fn m ->
      public =
        m.defs
        |> Enum.filter(&(&1.kind in [:def, :defmacro, :defdelegate]))
        |> Enum.map(&"#{&1.name}/#{&1.arity}")
        |> Enum.uniq()

      # a module of 150 functions took a third of the map: the first dozen say what it is
      {first, rest} = if all, do: {public, []}, else: Enum.split(public, 12)
      more = if rest == [], do: "", else: " (+#{length(rest)} more)"

      ["#{m.module}  #{rel}  #{Enum.join(first, " ")}#{more}" |> String.trim_trailing()] ++
        flatten(m.modules, rel, all)
    end)
  end
end
