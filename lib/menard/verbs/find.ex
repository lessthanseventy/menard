defmodule Menard.Verbs.Find do
  @moduledoc "The `find` verb (`Menard.Verbs`): `kind` (`calls`, `defs`, `aliases`) of `target` in `files` (paths, directories or globs); the reply is `hits`."

  import Menard.Verbs
  alias Menard.Find

  @kinds ~w(calls defs aliases)

  @doc "The noun, as both doors are made from it (`Menard.Verbs.Noun`)."
  @spec noun() :: Menard.Verbs.Noun.t()
  def noun do
    %{
      name: "find",
      doc: """
      grep that knows the code: `kind` is `calls` (target: "fun" or "Mod.fun", alias-aware), `defs`
      (target: "name" or "name/arity") or `aliases` (target: "Mod.Sub"). Strings and comments never
      match. `files` may be globs, under the launch root. `calls` of "Mod.fun" also asks the
      language server: what it finds that the AST cannot (a call through an import, a
      defdelegate, an apply) comes back as `kind: reference`, and `lsp` says what answered.
      """,
      fields: [
        {:kind, :enum, [values: ["calls", "defs", "aliases"], required: true]},
        {:target, :string, [required: true]},
        {:files, {:list, :string}, [required: true]}
      ]
    }
  end

  @spec run(Menard.Verbs.params()) :: Menard.Verbs.result()
  def run(p) do
    with :ok <- need(p, [:kind, :target], "find"),
         {:ok, finder} <- finder(p.kind, p.target),
         {:ok, patterns} <- patterns(p),
         {:ok, files} <- Find.files(patterns) do
      hits =
        Enum.flat_map(files, fn file ->
          file |> File.read!() |> finder.() |> Enum.map(&Map.put(&1, :file, file))
        end)

      {:ok, with_lsp(%{hits: hits}, p, files)}
    end
  end

  # `calls` of `Mod.fun` also asks the language server, which sees the calls the AST cannot: one
  # through an `import`, a `defdelegate`, a `use`, an `apply`. What only it found is a `reference`,
  # not a `call`. `lsp` says what answered: the server's name, or why the hits are the AST's alone.
  defp with_lsp(reply, %{kind: "calls", target: target} = p, files) do
    case String.split(target, ".") do
      [_fun] ->
        reply

      parts ->
        project = Path.expand(p[:root] || Menard.caller_dir())
        {mod, fun} = {parts |> Enum.drop(-1) |> Enum.join("."), List.last(parts)}

        case references(project, mod, fun) do
          {:ok, locations} ->
            %{reply | hits: reply.hits ++ only_lsp(locations, reply.hits, files)}
            |> Map.put(:lsp, Menard.Lsp.server())

          :warming ->
            # read as "retry": explore-callers asked the same find twice in a row, and got this twice
            Map.put(
              reply,
              :lsp,
              "these are the AST's hits, every direct and aliased call; #{Menard.Lsp.server()} is still " <>
                "indexing (about a minute from the session's start), so a call through an import, a " <>
                "defdelegate or an apply is not among them. The same find asked again now answers the same"
            )

          :off ->
            Map.put(
              reply,
              :lsp,
              "no language server here (only the MCP server keeps one): these hits are the AST's alone"
            )
        end
    end
  end

  defp with_lsp(reply, _p, _files), do: reply

  # every clause of the function, asked where it is defined in the project's lib/
  defp references(project, mod, fun) do
    sites =
      for file <- Path.wildcard(Path.join(project, "lib/**/*.ex")),
          source = File.read!(file),
          String.contains?(source, fun),
          {line, column} <- Menard.Find.def_sites(source, mod, fun),
          do: {file, line, column}

    Enum.reduce_while(sites, {:ok, []}, fn {file, line, column}, {:ok, acc} ->
      case Menard.Lsp.references(project, file, line, column, 5_000) do
        {:ok, found} -> {:cont, {:ok, acc ++ found}}
        other -> {:halt, other}
      end
    end)
  end

  # in the files asked about, on a line the AST has no hit on; a `@spec` names the function without
  # referring to it, and a server that counts one says nothing about who calls it
  defp only_lsp(locations, hits, files) do
    seen = MapSet.new(hits, &{&1.file, &1.line})
    asked = MapSet.new(files)

    for %{file: file, line: line, column: column} <- Enum.uniq(locations),
        file in asked,
        not MapSet.member?(seen, {file, line}),
        text = file |> File.read!() |> String.split("\n") |> Enum.at(line - 1) |> String.trim(),
        not String.starts_with?(text, "@spec "),
        do: %{file: file, line: line, column: column, kind: :reference, text: text}
  end

  defp patterns(%{files: [_ | _] = files} = p), do: resolve_all(files, p)
  defp patterns(_p), do: {:error, "find needs files"}

  defp finder("calls", target), do: {:ok, &Find.calls(&1, target)}
  defp finder("defs", target), do: {:ok, &Find.defs(&1, target)}
  defp finder("aliases", target), do: {:ok, &Find.aliases(&1, target)}

  defp finder(kind, _target),
    do: {:error, "find has no kind #{inspect(kind)}: one of #{Enum.join(@kinds, ", ")}"}
end
