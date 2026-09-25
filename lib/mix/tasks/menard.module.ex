defmodule Mix.Tasks.Menard.Module do
  @shortdoc "Whole modules in a file: mix menard.module add|list FILE [CODE]"
  @moduledoc """
  `mix menard.module add lib/tools.ex 'defmodule A.B do\\n  def go, do: 1\\nend'` — add a module to a
  file that already has one (`-` for CODE reads stdin). `mix menard.module list FILE`.

  `clause insert-at` puts a function INTO a module and `write` replaces a whole file; neither adds
  a second `defmodule` to a file that already has one — the shape the MCP tool components use.
  """
  use Mix.Task

  @impl true
  def run(argv) do
    case argv do
      ["list", file] ->
        case Menard.Module.list(File.read!(Menard.resolve(file))) do
          {:error, message} -> Mix.raise(message)
          names -> Mix.shell().info(Enum.join(names, "\n"))
        end

      ["add", file, code] ->
        file = Menard.resolve(file)
        code = if code == "-", do: IO.read(:stdio, :eof), else: code

        case Menard.Module.add(File.read!(file), to_string(code)) do
          {:error, message} ->
            Mix.raise(message)

          out ->
            case Menard.checked_write(file, out) do
              :ok -> :ok
              {:error, message} -> Mix.raise(message)
            end
        end

        Mix.shell().info("menard.module: #{file} written")

      ["comment", file, module | text] when length(text) <= 1 ->
        file = Menard.resolve(file)
        module = if module in ["-", ""], do: nil, else: module

        case Menard.Module.comment(File.read!(file), module, List.first(text)) do
          {:error, message} ->
            Mix.raise(message)

          out ->
            case Menard.checked_write(file, out) do
              :ok -> Mix.shell().info("menard.module: #{file} written")
              {:error, message} -> Mix.raise(message)
            end
        end

      ["replace", file, name, code] ->
        file = Menard.resolve(file)

        case Menard.Module.replace(File.read!(file), name, code) do
          {:error, message} ->
            Mix.raise(message)

          out ->
            case Menard.checked_write(file, out) do
              :ok -> Mix.shell().info("menard.module: #{file} written")
              {:error, message} -> Mix.raise(message)
            end
        end

      _ ->
        Mix.raise(
          "usage: mix menard.module add FILE CODE  (CODE of `-` reads stdin) | list FILE\n" <>
            "       mix menard.module replace FILE Mod.Name CODE          one whole module, of several\n" <>
            "       mix menard.module comment FILE (Mod.Name|-) [TEXT]   (no TEXT removes it)"
        )
    end
  end
end
