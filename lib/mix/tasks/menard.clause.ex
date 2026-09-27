defmodule Mix.Tasks.Menard.Clause do
  @shortdoc "Edit one clause: mix menard.clause (replace|rewrite|delete|insert-after|insert-before) FILE name/arity HEAD [CODE]"
  @moduledoc """
  `mix menard.clause replace lib/a.ex go/1 ':b' '20'` — swap the clause's body.
  `mix menard.clause delete lib/a.ex go/1 ':a'` — remove the clause (and its glued comment).
  `mix menard.clause insert-after lib/a.ex go/1 ':a' 'def go(:c), do: 3'` — add a clause after it.

  HEAD is the clause's args as written, plus its guard (`'x when is_integer(x)'`); whitespace is
  ignored. CODE may span lines (a block body). Only the clause's bytes change
  (`Menard.Clause`); the file is formatted after. A miss lists the clauses that exist.
  """
  use Mix.Task

  alias Menard.Verbs

  import Menard.CLI

  @flags [nth: :integer, to: :string, as: :string, module: :string, version: :string, force: :boolean]

  @usage "mix menard.clause (replace|rewrite|delete|insert-after|insert-before) FILE name/arity HEAD [CODE] [--nth N]\n" <>
           "       mix menard.clause delete FILE name/arity                (no HEAD: the whole function, every clause)\n" <>
           "       mix menard.clause get FILE name/arity [HEAD]            (the function as written; a HEAD: that clause)\n" <>
           "       mix menard.clause insert-at FILE (Mod.Name|-) [top|bottom] CODE\n" <>
           "       mix menard.clause move FILE name/arity --to DEST [--as Mod.Name]\n" <>
           "       mix menard.clause spec FILE name/arity [SPEC]           (no SPEC deletes it)\n" <>
           "       mix menard.clause visibility FILE name/arity (public|private)"

  @impl true
  def run(argv) do
    {flags, argv} = options(argv, @flags)

    case params(argv) do
      :usage -> usage(@usage)
      params -> answer(Verbs.Clause.run(Map.merge(Map.new(flags), params)))
    end
  end

  defp params([verb | rest]), do: params(verb(verb), rest)
  defp params([]), do: :usage

  defp params("get", [file, na | head]) when length(head) <= 1,
    do: %{verb: "get", file: file, name_arity: na, head: List.first(head)}

  defp params("delete", [file, na]), do: %{verb: "delete", file: file, name_arity: na}
  defp params("move", [file, na]), do: %{verb: "move", file: file, name_arity: na}

  defp params("insert_at", [file, module, code]),
    do: %{verb: "insert_at", file: file, module: module, code: code}

  defp params("insert_at", [file, module, at, code]) when at in ["top", "bottom"],
    do: %{verb: "insert_at", file: file, module: module, at: at, code: code}

  defp params("spec", [file, na | spec]) when length(spec) <= 1,
    do: %{verb: "spec", file: file, name_arity: na, code: List.first(spec)}

  defp params("visibility", [file, na, want]),
    do: %{verb: "visibility", file: file, name_arity: na, visibility: want}

  defp params(verb, [file, na, head, code]) when verb in ~w(replace rewrite insert_after insert_before),
    do: %{verb: verb, file: file, name_arity: na, head: head, code: code}

  defp params("delete", [file, na, head]), do: %{verb: "delete", file: file, name_arity: na, head: head}
  defp params(_verb, _argv), do: :usage
end
