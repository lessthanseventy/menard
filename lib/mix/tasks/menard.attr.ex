defmodule Mix.Tasks.Menard.Attr do
  @shortdoc "Module attributes: mix menard.attr get|set|delete|list FILE [NAME] [VALUE]"
  @moduledoc """
  `mix menard.attr get lib/a.ex hints` — the value as written.
  `mix menard.attr set lib/a.ex hints '[{"a", "b"}]'` — replace it, or add it above the first def.
  `mix menard.attr delete lib/a.ex hints` · `mix menard.attr list lib/a.ex`

  The tables a module keeps at the top, which every clause verb walks past because an attribute is
  not a clause. A name several attributes share (`@doc`, `@impl`, `@spec` repeat per clause) is
  refused with their lines — those belong to the clause verbs. `--module Mod.Name` picks one of
  several modules in a file.
  """
  use Mix.Task

  alias Menard.Verbs

  import Menard.CLI

  @impl true
  def run(argv) do
    {flags, argv, _} = OptionParser.parse(argv, strict: [module: :string, version: :string, force: :boolean])

    case params(argv) do
      :usage -> usage("mix menard.attr (get|set|delete) FILE NAME [VALUE] | list FILE [--module Mod]")
      params -> answer(Verbs.Attr.run(Map.merge(Map.new(flags), params)))
    end
  end

  defp params(["get", file, name]), do: %{verb: "get", file: file, name: name}
  defp params(["list", file]), do: %{verb: "list", file: file}
  defp params(["set", file, name, value]), do: %{verb: "set", file: file, name: name, value: value}
  defp params(["delete", file, name]), do: %{verb: "delete", file: file, name: name}
  defp params(_argv), do: :usage
end
