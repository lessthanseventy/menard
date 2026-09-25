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
    {flags, argv, _} = OptionParser.parse(argv, strict: [version: :string, force: :boolean, above: :boolean])
    stale = Keyword.take(flags, [:version, :force])

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
            case Menard.write(file, out, [did: "module add in #{Path.basename(file)}"] ++ stale) do
              {:ok, reply} -> Mix.shell().info(JSON.encode!(reply))
              {:error, message} -> Mix.raise(message)
            end
        end

      ["comment", file, module | text] when length(text) <= 1 ->
        file = Menard.resolve(file)
        module = if module in ["-", ""], do: nil, else: module

        case Menard.Module.comment(File.read!(file), module, List.first(text), above: flags[:above] == true) do
          {:error, message} ->
            Mix.raise(message)

          out ->
            case Menard.write(file, out, [did: "module comment in #{Path.basename(file)}"] ++ stale) do
              {:ok, reply} -> Mix.shell().info(JSON.encode!(reply))
              {:error, message} -> Mix.raise(message)
            end
        end

      ["replace", file, name, code] ->
        file = Menard.resolve(file)

        case Menard.Module.replace(File.read!(file), name, code) do
          {:error, message} ->
            Mix.raise(message)

          out ->
            case Menard.write(file, out, [did: "module replace #{name} in #{Path.basename(file)}"] ++ stale) do
              {:ok, reply} -> Mix.shell().info(JSON.encode!(reply))
              {:error, message} -> Mix.raise(message)
            end
        end

      _ ->
        Mix.raise(
          "usage: mix menard.module add FILE CODE  (CODE of `-` reads stdin) | list FILE\n" <>
            "       mix menard.module replace FILE Mod.Name CODE          one whole module, of several\n" <>
            "       mix menard.module comment FILE (Mod.Name|-) [TEXT] [--above]   (no TEXT removes it; --above: over defmodule)"
        )
    end
  end
end
