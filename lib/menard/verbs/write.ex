defmodule Menard.Verbs.Write do
  @moduledoc "The `write` verb (`Menard.Verbs`): a whole file, parse-checked, created or replaced."

  import Menard.Verbs

  @doc "The noun, as both doors are made from it (`Menard.Verbs.Noun`)."
  @spec noun() :: Menard.Verbs.Noun.t()
  def noun do
    %{
      name: "write",
      doc: """
      Write a WHOLE file: `code` becomes the entire content of `file`. The verb for what the clause
      verbs structurally cannot do — a NEW module has no clause to address and no file to patch — and
      for a rewrite so total that patching is the wrong tool (a fixture, a generated table). Elixir
      that does not parse is refused before it reaches disk; the file is then formatted with the
      target project's own formatter.
      """,
      fields: [
        {:version, :string, []},
        {:force, :boolean, []},
        {:file, :string, [required: true]},
        {:code, :string, [required: true]}
      ],
      cli: %{
        stdin: [:code],
        shapes: [
          {nil, [:file, :code]}
        ]
      }
    }
  end

  @spec run(Menard.Verbs.params()) :: Menard.Verbs.result()
  def run(p) do
    with :ok <- need(p, [:file, :code], "write"),
         {:ok, file} <- resolve(p.file, p) do
      did = "write #{Path.basename(file)}"

      if File.exists?(file) and File.read!(file) == String.trim_trailing(p.code, "\n") <> "\n" do
        {:ok, %{did: did, file: file, unchanged: true}}
      else
        File.mkdir_p!(Path.dirname(file))
        Menard.write(file, p.code, [did: did] ++ stale(p))
      end
    end
  end
end
