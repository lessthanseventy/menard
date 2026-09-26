defmodule Mix.Tasks.Menard.Write do
  @shortdoc "Write a whole file, parse-checked: mix menard.write FILE CODE (or - to read stdin)"
  @moduledoc """
  `mix menard.write lib/a.ex 'defmodule A do\\n  def go, do: 1\\nend'` — create or replace a file.
  `mix menard.write lib/a.ex -` — read the content from stdin (the door for a long module).

  The verb for what the clause verbs structurally cannot do: a NEW module has no clause to address
  and no file to patch. Elixir content that does not parse is refused before it reaches disk;
  the file is then formatted with the target project's own formatter (`Menard.format/1`).
  """
  use Mix.Task

  alias Menard.Verbs

  import Menard.CLI

  @impl true
  def run(argv) do
    {flags, argv, _} = OptionParser.parse(argv, strict: [version: :string, force: :boolean])

    case argv do
      [file, code] ->
        answer(Verbs.Write.run(Map.merge(Map.new(flags), %{file: file, code: stdin(code, "menard.write")})))

      _ ->
        usage("mix menard.write FILE CODE   (CODE of `-` reads stdin)")
    end
  end
end
