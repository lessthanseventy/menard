defmodule Mix.Tasks.Menard.Outline do
  @shortdoc "Outline a file's modules and defs: mix menard.outline [--json] FILE..."
  @moduledoc """
  `mix menard.outline [--json] lib/a.ex …` — each module with its moduledoc line and line span, then
  its defs (`kind name/arity  L<from>-<to>  — doc`); `--json` prints the reply as the MCP door
  gives it (`file`, `version`, `modules`) for a tool to read.
  """
  use Mix.Task

  alias Menard.Verbs

  import Menard.CLI

  @impl true
  def run(argv) do
    {opts, files} = options(argv, json: :boolean)
    if files == [], do: usage("mix menard.outline [--json] FILE...")

    # every file that parses is outlined; one that does not fails the verb, or a caller going by
    # the exit status took a file it never got for one with nothing in it
    failed =
      Enum.flat_map(files, fn file ->
        case Verbs.Outline.run(%{file: file}) do
          {:ok, reply} -> print(reply, opts[:json] == true)
          {:error, reason} -> [reason]
        end
      end)

    if failed != [], do: Mix.raise(Enum.join(failed, "\n"))
  end

  defp print(reply, true) do
    answer({:ok, reply})
    []
  end

  # the version rides the file line: pass it back with --version on the first edit
  defp print(%{file: file, version: version, modules: modules}, false) do
    Mix.shell().info("#{file}  #{version}")
    Enum.each(modules, &print_module(&1, "  "))
    []
  end

  defp print_module(m, indent) do
    {a, b} = m.lines || {0, 0}
    Mix.shell().info("#{indent}#{m.module}  L#{a}-#{b}#{if m.doc, do: "  — " <> m.doc, else: ""}")

    for d <- m.defs do
      {da, db} = d.lines || {0, 0}

      Mix.shell().info(
        "#{indent}  #{d.kind} #{d.name}/#{d.arity}#{if d.head != "", do: " (#{d.head})"}  L#{da}-#{db}#{if d.doc, do: "  — " <> d.doc, else: ""}"
      )
    end

    Enum.each(m.modules, &print_module(&1, indent <> "  "))
  end
end
