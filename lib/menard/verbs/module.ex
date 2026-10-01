defmodule Menard.Verbs.Module do
  @moduledoc "The `module` verbs (`Menard.Verbs`): `add`, `replace`, `list`, `layout`."

  import Menard.Verbs

  @verbs ~w(add replace list layout)

  @doc "The noun, as both doors are made from it (`Menard.Verbs.Noun`)."
  @spec noun() :: Menard.Verbs.Noun.t()
  def noun do
    %{
      name: "module",
      doc: """
      Whole modules inside a file. `verb` is `add` (a complete `defmodule` appended after the last
      one; a name the file already defines is refused), `replace` (the module named `module` swapped
      for `code`, a complete `defmodule` of that name; its neighbours untouched), `list`, or
      `layout` (every private function above a public one moved below them, and every attribute set
      once below a function moved above them, as a write places a new one: what a project that
      takes up that layout runs once per file). `clause insert_at` puts a
      function INTO a module, and `write` replaces the whole file.
      """,
      fields: [
        {:version, :string, []},
        {:force, :boolean, []},
        {:verb, :enum, [values: @verbs, required: true]},
        {:file, :string, [required: true]},
        {:code, :string, []},
        {:module, :string, []}
      ],
      cli: %{
        stdin: [:code],
        shapes: [
          {"list", [:file]},
          {"layout", [:file]},
          {"add", [:file, :code]},
          {"replace", [:file, :module, :code]}
        ]
      }
    }
  end

  @spec run(Menard.Verbs.params()) :: Menard.Verbs.result()
  def run(%{verb: "list"} = p) do
    with :ok <- need(p, [:file], "module list"),
         {:ok, file} <- resolve(p.file, p),
         {:ok, source} <- read(file),
         names when is_list(names) <- Menard.Module.list(source) do
      {:ok, %{modules: names}}
    end
  end

  def run(%{verb: "add"} = p) do
    with :ok <- need(p, [:file, :code], "module add") do
      edit(p, &"add a module in #{&1}", &Menard.Module.add(&1, p.code))
    end
  end

  def run(%{verb: "replace"} = p) do
    with :ok <- need(p, [:file, :module, :code], "module replace") do
      edit(p, &"replace #{p.module} in #{&1}", &Menard.Module.replace(&1, p.module, p.code))
    end
  end

  # every private function counts as new against an empty file: all of them above a public one move
  def run(%{verb: "layout"} = p) do
    with :ok <- need(p, [:file], "module layout") do
      edit(
        p,
        &"lay out #{&1}: attributes at the top, private functions below the public ones",
        &elem(Menard.Layout.private_last("", &1), 0)
      )
    end
  end

  def run(%{verb: verb}),
    do: {:error, "module has no verb #{inspect(verb)}: one of #{Enum.join(@verbs, ", ")}"}

  def run(_params), do: {:error, "module needs verb: one of #{Enum.join(@verbs, ", ")}"}
end
