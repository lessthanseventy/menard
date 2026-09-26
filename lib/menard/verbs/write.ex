defmodule Menard.Verbs.Write do
  @moduledoc "The `write` verb (`Menard.Verbs`): a whole file, parse-checked, created or replaced."

  import Menard.Verbs

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
