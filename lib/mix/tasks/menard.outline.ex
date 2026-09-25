defmodule Mix.Tasks.Menard.Outline do
  @shortdoc "Outline a file's modules and defs: mix menard.outline [--json] FILE..."
  @moduledoc """
  `mix menard.outline [--json] lib/a.ex …` — each module with its moduledoc line and line span, then
  its defs (`kind name/arity  L<from>-<to>  — doc`); `--json` prints the data instead
  (`Menard.Outline.run/1`'s shape) for a tool to read.
  """
  use Mix.Task

  alias Menard.Outline

  @impl true
  def run(argv) do
    {opts, files, _} = OptionParser.parse(argv, strict: [json: :boolean])
    if files == [], do: Mix.raise("usage: mix menard.outline [--json] FILE...")

    for file <- Enum.map(files, &Menard.resolve/1) do
      content = File.read!(file)

      case Outline.run(content) do
        {:ok, modules} -> print(file, Menard.remember(content), modules, opts[:json] == true)
        {:error, reason} -> Mix.shell().error("#{file}: not parseable — #{inspect(reason)}")
      end
    end
  end

  defp print(file, version, modules, true),
    do: Mix.shell().info(JSON.encode!(Menard.jsonable(%{file: file, version: version, modules: modules})))

  # the version rides the file line: pass it back with --version on the first edit
  defp print(file, version, modules, false) do
    Mix.shell().info("#{file}  #{version}")
    Enum.each(modules, &print_module(&1, "  "))
  end

  defp print_module(m, indent) do
    {a, b} = m.lines || {0, 0}
    Mix.shell().info("#{indent}#{m.module}  L#{a}-#{b}#{if m.doc, do: "  — " <> m.doc, else: ""}")

    for d <- m.defs do
      {da, db} = d.lines || {0, 0}

      Mix.shell().info(
        "#{indent}  #{d.kind} #{d.name}/#{d.arity}  L#{da}-#{db}#{if d.doc, do: "  — " <> d.doc, else: ""}"
      )
    end

    Enum.each(m.modules, &print_module(&1, indent <> "  "))
  end
end
