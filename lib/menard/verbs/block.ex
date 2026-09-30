defmodule Menard.Verbs.Block do
  @moduledoc "The `block` verbs (`Menard.Verbs`): `get`, `replace`, `add`, `delete`, `relabel`, `list`, `move`."

  import Menard.Verbs
  alias Menard.Block

  @verbs ~w(get replace add delete relabel list move)

  @doc "The noun, as both doors are made from it (`Menard.Verbs.Noun`)."
  @spec noun() :: Menard.Verbs.Noun.t()
  def noun do
    %{
      name: "block",
      doc: """
      The body of a macro's `do` block — `schema do`, `describe "…" do`, `test "…" do`. Not a clause,
      so no clause verb reaches one. `verb` is `get`, `replace` (body := `code`), `list`, or `relabel`
      (`label` becomes `new_label`). `label` is the macro's first string argument, which is what makes
      `describe`/`test` addressable; several blocks of one name with no label is refused, listing them.
      `add` writes a NEW block — at the end of the block named by `in` (a describe, by its label), else
      after the last sibling of that name, else at the end of the module. `move` takes tests and
      describes (`label`: one, or a list) to the test file `to`, created if missing (as the module
      its path names, or `as`), with the private helpers only they call, the attributes and
      alias/import lines they use, their @tag lines; a created file gets the source's `use` and
      `setup`. A helper a staying test calls too is refused: it belongs in test/support.
      """,
      fields: [
        {:version, :string, []},
        {:force, :boolean, []},
        {:verb, :enum,
         [values: ["get", "replace", "add", "delete", "list", "relabel", "move"], required: true]},
        {:file, :string, [required: true]},
        {:name, :string, []},
        {:code, :string, []},
        {:label, {:either, {:string, {:list, :string}}}, []},
        {:new_label, :string, []},
        {:args, :string, []},
        {:in, :string, []},
        {:module, :string, []},
        {:tag, :string, []},
        {:to, :string, []},
        {:as, :string, []}
      ],
      cli: %{
        flags: [tag: {:keep, :tag}],
        shapes: [
          {"get", [:file, :name]},
          {"list", [:file]},
          {"replace", [:file, :name, :code]},
          {"add", [:file, :name, :code]},
          {"delete", [:file, :name]},
          {"relabel", [:file, :name, :label, :new_label]},
          {"move", [:file, {:rest, :label}]}
        ]
      }
    }
  end

  @spec run(Menard.Verbs.params()) :: Menard.Verbs.result()
  def run(%{verb: "list"} = p) do
    with :ok <- need(p, [:file], "block list"),
         {:ok, file} <- resolve(p.file, p),
         {:ok, source} <- read(file),
         found when is_list(found) <- Block.list(source, module: p[:module]) do
      {:ok, %{blocks: Enum.map(found, fn {n, l, line} -> "#{n} #{inspect(l)} (line #{line})" end)}}
    end
  end

  def run(%{verb: "get"} = p) do
    with :ok <- need(p, [:file, :name], "block get"),
         {:ok, file} <- resolve(p.file, p),
         {:ok, source} <- read(file) do
      get(source, p)
    end
  end

  def run(%{verb: "add"} = p) do
    # in a test file, a block added with no name is a test: what an agent leaving `name` out means
    p =
      if p[:name] in [nil, ""] and String.ends_with?(p[:file] || "", "_test.exs"),
        do: Map.put(p, :name, "test"),
        else: p

    with :ok <- need(p, [:file, :name, :code], "block add") do
      edit(p, &"add #{p.name}#{label(p)} in #{&1}", fn source ->
        Block.add(source, p.name, p[:label], p.code,
          in: p[:in],
          module: p[:module],
          args: p[:args],
          tag: p[:tag]
        )
      end)
    end
  end

  def run(%{verb: "relabel"} = p) do
    with :ok <- need(p, [:file, :name, :label, :new_label], "block relabel") do
      edit(p, &"relabel #{p.name}#{label(p)} in #{&1}", fn source ->
        Block.relabel(source, p.name, p.label, p.new_label, module: p[:module])
      end)
    end
  end

  def run(%{verb: "move"} = p) do
    labels = List.wrap(p[:label])

    with :ok <- need(p, [:file, :label, :to], "block move"),
         {:ok, file} <- resolve(p.file, p),
         {:ok, dest} <- resolve(p.to, p),
         {:ok, moved} <- Menard.Move.blocks(file, dest, labels, as: p[:as]) do
      {:ok, Map.put(moved, :did, "move #{Enum.map_join(labels, ", ", &inspect/1)} to #{Path.basename(dest)}")}
    end
  end

  def run(%{verb: verb} = p) when verb in @verbs do
    with :ok <- need(p, [:file, :name], "block #{verb}") do
      edit(p, &"#{verb} #{p.name}#{label(p)} in #{&1}", &change(verb, &1, p))
    end
  end

  def run(%{verb: verb}),
    do: {:error, "block has no verb #{inspect(verb)}: one of #{Enum.join(@verbs, ", ")}"}

  def run(_params), do: {:error, "block needs verb: one of #{Enum.join(@verbs, ", ")}"}

  # no label among several: every one, not a refusal to pick (bench3 new-component.B.haiku)
  defp get(source, p) do
    all = if p[:label], do: [], else: Block.get_all(source, p.name, where(p))

    case all do
      [_, _ | _] -> {:ok, %{blocks: all}}
      _ -> with text when is_binary(text) <- Block.get(source, p.name, where(p)), do: {:ok, %{body: text}}
    end
  end

  defp change("replace", source, p), do: Block.replace(source, p.name, p[:code] || "", where(p))
  defp change("delete", source, p), do: Block.delete(source, p.name, where(p))

  defp where(p), do: [module: p[:module], label: p[:label]]

  # what the reply's `did` names: `replace test "it works"`
  defp label(%{label: label}) when is_binary(label) and label != "", do: " " <> inspect(label)
  defp label(_p), do: ""
end
