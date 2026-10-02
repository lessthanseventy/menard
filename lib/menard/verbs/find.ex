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
        # `verb` as every other noun names it, `kind` as find always has: either, one needed
        {:kind, :enum, [values: ["calls", "defs", "aliases"]]},
        {:verb, :enum, [values: ["calls", "defs", "aliases"]]},
        {:target, :string, [required: true]},
        {:files, {:list, :string}, [required: true]}
      ]
    }
  end

  @spec run(Menard.Verbs.params()) :: Menard.Verbs.result()
  # `verb` for `kind`, as every other noun takes it (Fable's review, 2026-10-01)
  def run(%{verb: verb} = p) when is_binary(verb) and not is_map_key(p, :kind),
    do: p |> Map.delete(:verb) |> Map.put(:kind, verb) |> run()

  def run(p) do
    with :ok <- need(p, [:kind, :target], "find"),
         {:ok, finder} <- finder(p.kind, p.target),
         {:ok, patterns} <- patterns(p),
         {:ok, files} <- Find.files(patterns) do
      # a file without the name in it holds no call or def of it: not parsed (about 10x on a repo);
      # one gone mid-walk is skipped, not raised on
      needle = needle(p.target)

      hits = Enum.flat_map(files, &hits_in(&1, needle, finder))

      {:ok, %{hits: hits} |> with_lsp(p, files) |> with_mentions(p.target, files)}
    end
  end

  # Nothing found, where the name is written: `{"hits":[]}` for a config key (Oban 01) sent the
  # agent back to grep. Its first few lines as text, the name as a word.
  defp with_mentions(%{hits: []} = reply, target, files) do
    word = ~r/(?<![\w?!])#{Regex.escape(needle(target))}(?![\w?!])/

    mentions =
      files
      |> Stream.flat_map(fn file ->
        file
        |> File.read()
        |> case do
          {:ok, text} -> text
          _ -> ""
        end
        |> String.split("\n")
        |> Enum.with_index(1)
        |> Enum.filter(fn {line, _} -> line =~ word end)
        |> Enum.map(fn {line, n} -> "#{file}:#{n}: #{String.trim(line)}" end)
      end)
      |> Enum.take(5)

    if mentions == [], do: reply, else: Map.put(reply, :mentions, mentions)
  end

  defp with_mentions(reply, _target, _files), do: reply

  defp hits_in(file, needle, finder) do
    with {:ok, text} <- File.read(file), true <- String.contains?(text, needle) do
      text |> finder.() |> Enum.map(&Map.put(&1, :file, file))
    else
      _ -> []
    end
  end

  # the name a hit has in it: `Mod.fun/2`'s `fun`, a module's last part
  defp needle(target), do: target |> String.split("/") |> hd() |> String.split(".") |> List.last()

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

  # a call is found by name: `Mod.fun/2`'s arity, the address the other verbs take, refused it
  defp finder("calls", target), do: {:ok, &Find.calls(&1, target |> String.split("/") |> hd())}
  defp finder("defs", target), do: {:ok, &Find.defs(&1, target)}
  defp finder("aliases", target), do: {:ok, &Find.aliases(&1, target)}

  defp finder(kind, _target),
    do: {:error, "find has no kind #{inspect(kind)}: one of #{Enum.join(@kinds, ", ")}"}
end
