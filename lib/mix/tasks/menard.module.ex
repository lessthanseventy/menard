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
    verb(argv, flags)
  end

  defp verb(["list", file], _flags) do
    case Menard.Module.list(File.read!(Menard.resolve(file))) do
      {:error, message} -> Mix.raise(message)
      names -> Mix.shell().info(Enum.join(names, "\n"))
    end
  end

  defp verb(["add", file, code], flags) do
    file = Menard.resolve(file)
    code = if code == "-", do: IO.read(:stdio, :eof), else: code

    write(
      file,
      Menard.Module.add(File.read!(file), to_string(code)),
      "module add in #{Path.basename(file)}",
      flags
    )
  end

  defp verb(["comment", file, module | text], flags) when length(text) <= 1 do
    file = Menard.resolve(file)
    module = if module in ["-", ""], do: nil, else: module
    out = Menard.Module.comment(File.read!(file), module, List.first(text), above: flags[:above] == true)
    write(file, out, "module comment in #{Path.basename(file)}", flags)
  end

  defp verb(["replace", file, name, code], flags) do
    file = Menard.resolve(file)
    out = Menard.Module.replace(File.read!(file), name, code)
    write(file, out, "module replace #{name} in #{Path.basename(file)}", flags)
  end

  defp verb(_argv, _flags) do
    Mix.raise(
      "usage: mix menard.module add FILE CODE  (CODE of `-` reads stdin) | list FILE\n" <>
        "       mix menard.module replace FILE Mod.Name CODE          one whole module, of several\n" <>
        "       mix menard.module comment FILE (Mod.Name|-) [TEXT] [--above]   (no TEXT removes it; --above: over defmodule)"
    )
  end

  defp write(_file, {:error, message}, _did, _flags), do: Mix.raise(message)

  defp write(file, out, did, flags) do
    case Menard.write(file, out, [did: did] ++ Keyword.take(flags, [:version, :force])) do
      {:ok, reply} -> Mix.shell().info(JSON.encode!(reply))
      {:error, message} -> Mix.raise(message)
    end
  end
end
