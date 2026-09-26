defmodule Mix.Tasks.Menard.Rename do
  @shortdoc "Rename an identifier AST-aware: mix menard.rename OLD NEW [--atoms] [--comments] FILE..."
  @moduledoc """
  `mix menard.rename old_name new_name [--only functions|variables] [--atoms] [--comments] lib/a.ex lib/b.ex …`

  Every def/defp head, call (local or remote), capture and variable named OLD becomes NEW; strings
  stay. `--only functions` leaves variables alone, `--only variables` leaves functions alone.
  `--atoms` also renames the atom `:old` and the key `old:`; `--comments` the whole-word mentions
  inside `#` comments. The reply lists the files `changed` (each with its version and stages),
  `unchanged`, and `skipped` (not parseable or not written, with why). `--version FILE=SHA` per
  file, from each one's last reply, is checked before any file is written.
  """
  use Mix.Task

  alias Menard.Verbs

  import Menard.CLI

  @flags [atoms: :boolean, comments: :boolean, only: :string, version: :keep, force: :boolean]

  @impl true
  def run(argv) do
    {flags, args, _} = OptionParser.parse(argv, strict: @flags)

    case args do
      [old, new | files] when files != [] ->
        params =
          flags
          |> Keyword.delete(:version)
          |> Map.new()
          |> Map.merge(%{old: old, new: new, files: files, versions: Keyword.get_values(flags, :version)})

        answer(Verbs.Rename.run(params))

      _ ->
        usage("mix menard.rename OLD NEW [--only functions|variables] [--atoms] [--comments] FILE...")
    end
  end
end
