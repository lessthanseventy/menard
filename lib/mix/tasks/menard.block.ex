defmodule Mix.Tasks.Menard.Block do
  @shortdoc "A macro's do-block: mix menard.block get|replace|list FILE NAME [CODE] [--label X]"
  @moduledoc """
  `mix menard.block replace lib/a.ex schema 'field(:x, :string)'` — swap a `schema do … end` body.
  `mix menard.block add test/a_test.exs test 'assert 1 == 1' --label "it works" --in "the leader"`
  `mix menard.block get test/a_test.exs describe --label 'the leader'` · `mix menard.block list FILE`

  A macro call's body is not a clause, so no clause verb reaches one. `--label` is the macro's
  first string argument, which is what makes `describe "…"` and `test "…"` addressable; several
  blocks of one name with no label given is refused, listing them.
  """
  use Mix.Task

  alias Menard.Verbs

  import Menard.CLI

  @flags [
    module: :string,
    label: :string,
    in: :string,
    args: :string,
    tag: :keep,
    version: :string,
    force: :boolean
  ]

  @usage "mix menard.block (get|replace) FILE NAME [CODE] [--label X]\n" <>
           "       mix menard.block add FILE NAME CODE [--label X] [--args CONTEXT] [--in PARENT_LABEL] [--tag T]\n" <>
           "       mix menard.block delete FILE NAME [--label X]\n" <>
           "       mix menard.block relabel FILE NAME OLD_LABEL NEW_LABEL\n" <>
           "       mix menard.block list FILE\n" <>
           "       any of them: --module Mod, when the file holds several modules"

  @impl true
  def run(argv) do
    {flags, argv} = options(argv, @flags)
    # `--tag` repeats: every one is an `@tag` line above the block
    flags = flags |> Keyword.delete(:tag) |> Map.new() |> Map.put(:tag, Keyword.get_values(flags, :tag))

    case params(argv) do
      :usage -> usage(@usage)
      params -> answer(Verbs.Block.run(Map.merge(flags, params)))
    end
  end

  defp params(["get", file, name]), do: %{verb: "get", file: file, name: name}
  defp params(["list", file]), do: %{verb: "list", file: file}
  defp params(["replace", file, name, code]), do: %{verb: "replace", file: file, name: name, code: code}
  defp params(["add", file, name, code]), do: %{verb: "add", file: file, name: name, code: code}
  defp params(["delete", file, name]), do: %{verb: "delete", file: file, name: name}

  defp params(["relabel", file, name, label, new_label]),
    do: %{verb: "relabel", file: file, name: name, label: label, new_label: new_label}

  defp params(_argv), do: :usage
end
