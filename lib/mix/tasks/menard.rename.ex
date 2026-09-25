defmodule Mix.Tasks.Menard.Rename do
  @shortdoc "Rename an identifier AST-aware: mix menard.rename OLD NEW [--atoms] [--comments] FILE..."
  @moduledoc """
  `mix menard.rename old_name new_name [--only functions|variables] [--atoms] [--comments] lib/a.ex lib/b.ex …`

  Every def/defp head, call (local or remote), capture and variable named OLD becomes NEW; strings
  stay. `--only functions` leaves variables alone, `--only variables` leaves functions alone.
  `--atoms` also renames the atom `:old` and the key `old:`; `--comments` the whole-word mentions
  inside `#` comments. Files that don't change are not rewritten; an unparseable file is reported and
  skipped. Runs `mix format` on what it wrote.
  """
  use Mix.Task

  alias Menard.Rename

  @impl true
  def run(argv) do
    {opts, args, _} = OptionParser.parse(argv, strict: [atoms: :boolean, comments: :boolean, only: :string])

    case args do
      [old, new | files] when files != [] ->
        replies =
          files
          |> Enum.map(&Menard.resolve/1)
          |> Enum.map(&rewrite(&1, old, new, opts))
          |> Enum.reject(&is_nil/1)

        Mix.shell().info(
          JSON.encode!(%{
            did: "rename #{old} → #{new} in #{length(replies)} of #{length(files)} file(s)",
            files: replies
          })
        )

      _ ->
        Mix.raise(
          "usage: mix menard.rename OLD NEW [--only functions|variables] [--atoms] [--comments] FILE..."
        )
    end
  end

  defp rewrite(file, old, new, opts) do
    source = File.read!(file)

    case Rename.run(source, old, new,
           atoms: opts[:atoms] == true,
           comments: opts[:comments] == true,
           only: only(opts[:only])
         ) do
      {:error, reason} ->
        Mix.shell().error("#{file}: not parseable, skipped — #{inspect(reason)}")
        nil

      ^source ->
        nil

      out ->
        case Menard.write(file, out, did: "rename #{old} → #{new} in #{Path.basename(file)}") do
          {:ok, reply} ->
            reply

          {:error, message} ->
            Mix.shell().error(message)
            nil
        end
    end
  end

  defp only(nil), do: nil
  defp only("functions"), do: :functions
  defp only("variables"), do: :variables
  defp only(other), do: Mix.raise("--only takes functions or variables, got #{other}")
end
