# The mix task of every noun that declares its `cli` (`Menard.Verbs.Noun`): `mix menard.attr`,
# `menard.clause`, …, each the noun's shapes read by `Menard.CLI.run/2`. The nouns whose CLI prints
# lines for a reader (`outline`, `find`), or hands its arguments on to mix (`run`), keep a task file
# of their own beside this one.
for verbs <- Menard.Verbs.Noun.modules(), noun = Menard.Verbs.Noun.of(verbs), is_map_key(noun, :cli) do
  defmodule Module.concat(Mix.Tasks.Menard, Macro.camelize(noun.name)) do
    @shortdoc noun.doc |> String.split(~r/(?<=[.:])\s/, parts: 2) |> hd() |> String.replace("\n", " ")
    @moduledoc "    " <> Menard.Verbs.Noun.usage(noun) <> "\n\n" <> noun.doc
    use Mix.Task

    @verbs verbs

    @impl true
    def run(argv), do: Menard.CLI.run(@verbs, argv)
  end
end
