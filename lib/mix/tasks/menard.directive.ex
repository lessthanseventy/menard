defmodule Mix.Tasks.Menard.Directive do
  @shortdoc "alias/import/require/use, placed where they belong: mix menard.directive add|remove|list FILE ..."
  @moduledoc """
  `mix menard.directive add lib/a.ex alias Console.Picker` — add it in sorted position.
  `mix menard.directive add lib/a.ex import Console.Panel 'only: [pad: 3]'` — with its options.
  `mix menard.directive remove lib/a.ex alias Console.Picker` — take it out.
  `mix menard.directive list lib/a.ex` — what the module already pulls in.

  The placement is the point: Elixir's conventional order is `use`, `import`, `alias`, `require`,
  each alphabetised, and a formatter plugin that sorts them will move a directive dropped at a
  guessed line. `--module Mod.Name` names which module in a file that has several.
  """
  use Mix.Task

  alias Menard.Verbs

  import Menard.CLI

  @usage "mix menard.directive add FILE (alias|import|require|use|doctest) MOD [OPTS] [--module Mod]\n" <>
           "       mix menard.directive replace FILE (alias|import|require|use|doctest) MOD [OPTS] [--module Mod]\n" <>
           "       mix menard.directive remove FILE (alias|import|require|use|doctest) MOD [--module Mod]\n" <>
           "       mix menard.directive list FILE [--module Mod]"

  @impl true
  def run(argv) do
    {flags, argv} = options(argv, module: :string, version: :string, force: :boolean)

    case params(argv) do
      :usage -> usage(@usage)
      params -> answer(Verbs.Directive.run(Map.merge(Map.new(flags), params)))
    end
  end

  defp params(["list", file]), do: %{verb: "list", file: file}
  defp params(["remove", file, kind, target]), do: %{verb: "remove", file: file, kind: kind, target: target}

  defp params([verb, file, kind, target | rest]) when verb in ["add", "replace"] and length(rest) <= 1,
    do: %{verb: verb, file: file, kind: kind, target: target, args: List.first(rest)}

  defp params(_argv), do: :usage
end
