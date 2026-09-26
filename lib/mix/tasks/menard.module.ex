defmodule Mix.Tasks.Menard.Module do
  @shortdoc "Whole modules in a file: mix menard.module add|replace|list FILE [CODE]"
  @moduledoc """
  `mix menard.module add lib/tools.ex 'defmodule A.B do\\n  def go, do: 1\\nend'` — add a module to a
  file that already has one (`-` for CODE reads stdin). `mix menard.module list FILE`.

  `clause insert-at` puts a function INTO a module and `write` replaces a whole file; neither adds
  a second `defmodule` to a file that already has one — the shape the MCP tool components use.
  """
  use Mix.Task

  alias Menard.Verbs

  import Menard.CLI

  @usage "mix menard.module add FILE CODE  (CODE of `-` reads stdin) | list FILE\n" <>
           "       mix menard.module replace FILE Mod.Name CODE          one whole module, of several"

  @impl true
  def run(argv) do
    {flags, argv, _} = OptionParser.parse(argv, strict: [version: :string, force: :boolean])

    case params(argv) do
      :usage -> usage(@usage)
      params -> answer(Verbs.Module.run(Map.merge(Map.new(flags), params)))
    end
  end

  defp params(["list", file]), do: %{verb: "list", file: file}
  defp params(["add", file, code]), do: %{verb: "add", file: file, code: stdin(code, "menard.module")}
  defp params(["replace", file, name, code]), do: %{verb: "replace", file: file, module: name, code: code}
  defp params(_argv), do: :usage
end
