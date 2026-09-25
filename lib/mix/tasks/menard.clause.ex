defmodule Mix.Tasks.Menard.Clause do
  @shortdoc "Edit one clause: mix menard.clause (replace|delete|insert-after|insert-before) FILE name/arity HEAD [CODE]"
  @moduledoc """
  `mix menard.clause replace lib/a.ex go/1 ':b' '20'` — swap the clause's body.
  `mix menard.clause delete lib/a.ex go/1 ':a'` — remove the clause (and its glued comment).
  `mix menard.clause insert-after lib/a.ex go/1 ':a' 'def go(:c), do: 3'` — add a clause after it.

  HEAD is the clause's args as written, plus its guard (`'x when is_integer(x)'`); whitespace is
  ignored. CODE may span lines (a block body). Only the clause's bytes change
  (`Menard.Clause`); the file is formatted after. A miss lists the clauses that exist.
  """
  use Mix.Task

  alias Menard.Clause

  @impl true
  def run(argv) do
    {flags, argv, _} =
      OptionParser.parse(argv,
        strict: [nth: :integer, to: :string, as: :string, module: :string, version: :string, force: :boolean]
      )

    case normalize(argv) do
      ["replace", file, na, head, code] ->
        write(
          file,
          &Clause.replace_body(&1, na, head, code, nth: flags[:nth]),
          "replace #{na} in #{Path.basename(file)}",
          flags
        )

      ["rewrite", file, na, head, code] ->
        write(
          file,
          &Clause.rewrite(&1, na, head, code, nth: flags[:nth]),
          "rewrite #{na} in #{Path.basename(file)}",
          flags
        )

      ["delete", file, na, head] ->
        write(
          file,
          &Clause.delete(&1, na, head, nth: flags[:nth]),
          "delete #{na} in #{Path.basename(file)}",
          flags
        )

      ["insert_after", file, na, head, code] ->
        write(
          file,
          &Clause.insert_after(&1, na, head, code, nth: flags[:nth]),
          "insert-after #{na} in #{Path.basename(file)}",
          flags
        )

      ["insert_before", file, na, head, code] ->
        write(
          file,
          &Clause.insert_before(&1, na, head, code, nth: flags[:nth]),
          "insert-before #{na} in #{Path.basename(file)}",
          flags
        )

      ["insert_at", file, module, code] ->
        write(
          file,
          &Clause.insert_at(&1, module(module), nil, code),
          "insert-at #{module || "-"} in #{Path.basename(file)}",
          flags
        )

      ["insert_at", file, module, where, code] when where in ["top", "bottom"] ->
        write(
          file,
          &Clause.insert_at(&1, module(module), where, code),
          "insert-at #{module || "-"} #{where} in #{Path.basename(file)}",
          flags
        )

      ["move", file, na] ->
        move(file, flags[:to], na, flags)

      ["comment", file, na, head, text] ->
        write(
          file,
          &Clause.comment(&1, na, head, text, nth: flags[:nth]),
          "comment #{na} in #{Path.basename(file)}",
          flags
        )

      ["comment", file, na, head] ->
        write(
          file,
          &Clause.comment(&1, na, head, nil, nth: flags[:nth]),
          "comment #{na} in #{Path.basename(file)}",
          flags
        )

      ["doc", file, na, head, text] ->
        write(
          file,
          &Clause.doc(&1, na, head, text, nth: flags[:nth]),
          "doc #{na} in #{Path.basename(file)}",
          flags
        )

      ["doc", file, na, head] ->
        write(
          file,
          &Clause.doc(&1, na, head, nil, nth: flags[:nth]),
          "doc #{na} in #{Path.basename(file)}",
          flags
        )

      ["spec", file, na | spec] when length(spec) <= 1 ->
        write(
          file,
          &Clause.spec(&1, na, List.first(spec)),
          "spec #{na} in #{Path.basename(file)}",
          flags
        )

      ["visibility", file, na, want] ->
        write(
          file,
          &Clause.visibility(&1, na, visibility(want)),
          "visibility #{na} #{want} in #{Path.basename(file)}",
          flags
        )

      _ ->
        Mix.raise(
          "usage: mix menard.clause (replace|rewrite|delete|insert-after|insert-before) FILE name/arity HEAD [CODE] [--nth N]\n" <>
            "       mix menard.clause insert-at FILE (Mod.Name|-) [top|bottom] CODE\n" <>
            "       mix menard.clause move FILE name/arity --to DEST [--as Mod.Name]\n" <>
            "       mix menard.clause doc FILE name/arity HEAD [TEXT]       (no TEXT deletes it)\n" <>
            "       mix menard.clause comment FILE name/arity HEAD [TEXT]   (no TEXT deletes it)\n" <>
            "       mix menard.clause spec FILE name/arity [SPEC]           (no SPEC deletes it)\n" <>
            "       mix menard.clause visibility FILE name/arity (public|private)"
        )
    end
  end

  # Two files change at once, so neither is written until BOTH edits succeed — a move that half
  # lands is worse than one that does not.
  defp move(file, dest, na, flags) do
    file = Menard.resolve(file)
    dest = Menard.resolve(dest)

    # `--version` is the source file's: the one the agent's edit came from
    if flags[:version] && !flags[:force] do
      with {:error, message} <- Menard.check_versions([{file, flags[:version]}]), do: Mix.raise(message)
    end

    case Menard.Move.run(file, dest, na, as: flags[:as], module: flags[:module]) do
      {:ok, created} ->
        if created, do: Mix.shell().info("menard.clause: created #{dest} as defmodule #{created}")
        Mix.shell().info("menard.clause: #{na} moved to #{dest}")

      {:error, message} ->
        Mix.raise(message)
    end
  end

  # The two doors spelled these differently — the CLI with dashes, the MCP with underscores — so a
  # verb learned at one door failed at the other. Both spellings work everywhere now.
  defp normalize([verb | rest]) when is_binary(verb), do: [String.replace(verb, "-", "_") | rest]
  defp normalize(argv), do: argv

  # `-` (or an empty string) means "the file's one module" — there is nothing to name.
  defp module(m) when m in ["-", ""], do: nil
  defp module(m), do: m

  defp visibility("public"), do: :public
  defp visibility("private"), do: :private
  defp visibility(other), do: Mix.raise("visibility must be public or private, got #{other}")

  defp write(file, edit, did, flags) do
    file = Menard.resolve(file)

    case edit.(File.read!(file)) do
      {:error, message} ->
        Mix.raise(message)

      out ->
        case Menard.write(file, out, [did: did] ++ Keyword.take(flags, [:version, :force])) do
          {:ok, reply} -> Mix.shell().info(JSON.encode!(reply))
          {:error, message} -> Mix.raise(message)
        end
    end
  end
end
