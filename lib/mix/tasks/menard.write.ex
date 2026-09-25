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

  @impl true
  def run(argv) do
    case argv do
      [file, "-"] ->
        # an empty stdin is a pipe that lost its input, not a request to empty the file
        case IO.read(:stdio, :eof) do
          text when is_binary(text) and text != "" -> write(file, text)
          _empty -> Mix.raise("menard.write: stdin was empty — nothing written to #{file}")
        end

      [file, code] ->
        write(file, code)

      _ ->
        Mix.raise("usage: mix menard.write FILE CODE   (CODE of `-` reads stdin)")
    end
  end

  defp write(file, code) do
    file = Menard.resolve(file)

    case Menard.Write.run(file, code) do
      {:error, message} ->
        Mix.raise(message)

      {:ok, :unchanged} ->
        Mix.shell().info("menard.write: #{file} unchanged")

      {:ok, what} ->
        Menard.format(file)
        Mix.shell().info("menard.write: #{file} #{what}")
    end
  end
end
