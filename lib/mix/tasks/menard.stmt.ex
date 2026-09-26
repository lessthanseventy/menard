defmodule Mix.Tasks.Menard.Stmt do
  @shortdoc "One statement inside a clause body — insert, replace, delete, list"
  @moduledoc """
  ONE statement inside a clause body, addressed the way a clause is: name the clause
  (`name/arity` + HEAD), then the statement by what is WRITTEN.

      mix menard.stmt insert-after FILE init/1 '_opts' 'Bus.subscribe_habits()' 'Import.run()'
      mix menard.stmt replace FILE init/1 '_opts' '0 -> {:ok, :up}' '0 -> {:ok, :running}'
      mix menard.stmt delete FILE init/1 '_opts' 'legacy_call()'
      mix menard.stmt list FILE init/1 '_opts'

  Reaches a line in a body, a step in a `with`, and a `case` arm alike. A miss lists what is
  there; an ambiguous match is refused with line numbers and `--nth`.
  """
  use Mix.Task

  alias Menard.Verbs

  import Menard.CLI

  @usage "mix menard.stmt (insert-after|insert-before|replace) FILE name/arity HEAD MATCH CODE [--nth N]\n" <>
           "       mix menard.stmt delete FILE name/arity HEAD MATCH [--nth N]\n" <>
           "       mix menard.stmt list FILE name/arity HEAD"

  @impl true
  def run(argv) do
    {flags, argv, _} = OptionParser.parse(argv, strict: [nth: :integer, version: :string, force: :boolean])

    case params(argv) do
      :usage -> usage(@usage)
      params -> answer(Verbs.Stmt.run(Map.merge(Map.new(flags), params)))
    end
  end

  defp params([verb | rest]), do: params(verb(verb), rest)
  defp params([]), do: :usage

  defp params("list", [file, na, head]), do: %{verb: "list", file: file, name_arity: na, head: head}

  defp params("delete", [file, na, head, match]),
    do: %{verb: "delete", file: file, name_arity: na, head: head, match: match}

  defp params(verb, [file, na, head, match, code]) when verb in ~w(insert_after insert_before replace),
    do: %{verb: verb, file: file, name_arity: na, head: head, match: match, code: code}

  defp params(_verb, _argv), do: :usage
end
