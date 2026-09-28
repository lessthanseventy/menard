defmodule Menard.Verbs.Directive do
  @moduledoc "The `directive` verbs (`Menard.Verbs`): `add`, `replace`, `remove`, `list`."

  import Menard.Verbs
  alias Menard.Directive

  @verbs ~w(add replace remove list)
  @kinds ~w(alias import require use doctest)

  @doc "The noun, as both doors are made from it (`Menard.Verbs.Noun`)."
  @spec noun() :: Menard.Verbs.Noun.t()
  def noun do
    %{
      name: "directive",
      doc: """
      `alias` / `import` / `require` / `use`, placed where they belong. `verb` is `add` (in sorted
      position inside its own block, opening the block in Elixir's conventional order — use, import,
      alias, require — when there isn't one), `replace` (new `args` for one that is there, in
      place, in one step), `remove`, or `list` (what the module already pulls in).
      `kind` is which directive; `target` the module; `args` the rest as written ("only: [pad: 3]",
      "as: Thing"). Adding one that is already there is a no-op, never a duplicate line. `module` names
      which module in a file that has several.
      """,
      fields: [
        {:version, :string, []},
        {:force, :boolean, []},
        {:verb, :enum, [values: ["add", "replace", "remove", "list"], required: true]},
        {:file, :string, [required: true]},
        {:kind, :enum, [values: ["alias", "import", "require", "use", "doctest"]]},
        {:target, :string, []},
        {:args, :string, []},
        {:module, :string, []}
      ],
      cli: %{
        shapes: [
          {"list", [:file]},
          {"remove", [:file, :kind, :target]},
          {"add", [:file, :kind, :target, {:optional, :args}]},
          {"replace", [:file, :kind, :target, {:optional, :args}]}
        ]
      }
    }
  end

  @spec run(Menard.Verbs.params()) :: Menard.Verbs.result()
  def run(%{verb: "list"} = p) do
    with :ok <- need(p, [:file], "directive list"),
         {:ok, file} <- resolve(p.file, p),
         {:ok, source} <- read(file),
         found when is_list(found) <- Directive.list(source, module: p[:module]) do
      {:ok, %{directives: Enum.map(found, fn {kind, target} -> "#{kind} #{target}" end)}}
    end
  end

  def run(%{verb: verb} = p) when verb in @verbs do
    with :ok <- need(p, [:file, :kind, :target], "directive #{verb}"),
         {:ok, kind} <- kind(p.kind) do
      edit(p, &"#{verb} #{kind} #{p.target} in #{&1}", &change(verb, &1, kind, p))
    end
  end

  def run(%{verb: verb}),
    do: {:error, "directive has no verb #{inspect(verb)}: one of #{Enum.join(@verbs, ", ")}"}

  def run(_params), do: {:error, "directive needs verb: one of #{Enum.join(@verbs, ", ")}"}

  defp change("add", source, kind, p),
    do: Directive.add(source, kind, p.target, module: p[:module], args: p[:args])

  defp change("replace", source, kind, p),
    do: Directive.replace(source, kind, p.target, module: p[:module], args: p[:args])

  defp change("remove", source, kind, p), do: Directive.remove(source, kind, p.target, module: p[:module])

  # the core takes the kind as an atom; the doors' input is a string, checked here, never to_atom'd
  defp kind(kind) when kind in @kinds, do: {:ok, String.to_existing_atom(kind)}
  defp kind(kind), do: {:error, "unknown directive #{inspect(kind)} — one of #{Enum.join(@kinds, ", ")}"}
end
