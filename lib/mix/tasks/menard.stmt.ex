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

  alias Menard.Stmt

  @impl true
  def run(argv) do
    {flags, argv, _} = OptionParser.parse(argv, strict: [nth: :integer, version: :string, force: :boolean])

    did = did(argv)

    case normalize(argv) do
      ["insert_after", file, na, head, match, code] ->
        write(file, did, flags, &Stmt.insert_after(&1, na, head, match, code, flags))

      ["insert_before", file, na, head, match, code] ->
        write(file, did, flags, &Stmt.insert_before(&1, na, head, match, code, flags))

      ["replace", file, na, head, match, code] ->
        write(file, did, flags, &Stmt.replace(&1, na, head, match, code, flags))

      ["delete", file, na, head, match] ->
        write(file, did, flags, &Stmt.delete(&1, na, head, match, flags))

      ["comment", file, na, head, match, text] ->
        write(file, did, flags, &Stmt.comment(&1, na, head, match, text, flags))

      ["comment", file, na, head, match] ->
        write(file, did, flags, &Stmt.comment(&1, na, head, match, nil, flags))

      ["list", file, na, head] ->
        case Stmt.list(File.read!(Menard.resolve(file)), na, head, flags) do
          {:error, message} -> Mix.raise(message)
          statements -> Mix.shell().info(Enum.map_join(statements, "\n", &"- #{&1}"))
        end

      _ ->
        Mix.raise(
          "usage: mix menard.stmt (insert-after|insert-before|replace) FILE name/arity HEAD MATCH CODE [--nth N]\n" <>
            "       mix menard.stmt delete FILE name/arity HEAD MATCH [--nth N]\n" <>
            "       mix menard.stmt comment FILE name/arity HEAD MATCH [TEXT]   (no TEXT removes it)\n" <>
            "       mix menard.stmt list FILE name/arity HEAD"
        )
    end
  end

  defp normalize([verb | rest]) when is_binary(verb), do: [String.replace(verb, "-", "_") | rest]
  defp normalize(argv), do: argv

  defp write(file, did, flags, edit) do
    file = Menard.resolve(file)

    case edit.(File.read!(file)) do
      {:error, message} ->
        Mix.raise(message)

      out ->
        case Menard.write(
               file,
               out,
               [did: "#{did} in #{Path.basename(file)}"] ++ Keyword.take(flags, [:version, :force])
             ) do
          {:ok, reply} -> Mix.shell().info(JSON.encode!(reply))
          {:error, message} -> Mix.raise(message)
        end
    end
  end

  # what the reply's `did` names: `replace `x = 1` in go/1`
  defp did([verb, _file, na, _head, match | _]), do: "#{verb} `#{match}` in #{na}"
  defp did(_), do: nil
end
