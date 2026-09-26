defmodule Menard.Verbs.Rename do
  @moduledoc """
  The `rename` verb (`Menard.Verbs`): `old` to `new` in `files` (paths or globs). The reply is
  `did`, `changed` (each file's write reply: its version and stages), `unchanged` (the files the
  name was not in) and `skipped` (not parseable or not written, with why). `versions` is
  `FILE=SHA` per file, from each one's last reply, all checked before any file is written: a rename
  refused halfway leaves the name changed in some files and not the others.
  """

  import Menard.Verbs

  @spec run(Menard.Verbs.params()) :: Menard.Verbs.result()
  def run(p) do
    with :ok <- need(p, [:old, :new], "rename"),
         {:ok, files} <- files(p),
         {:ok, only} <- only(p[:only]),
         :ok <- versions(p) do
      opts = [atoms: p[:atoms] == true, comments: p[:comments] == true, docs: p[:docs] != false, only: only]
      results = Enum.map(files, &{&1, rename(&1, p.old, p.new, opts)})

      {:ok,
       %{
         did:
           "rename #{p.old} → #{p.new} in #{Enum.count(results, &match?({_, {:changed, _}}, &1))} of #{length(files)} file(s)",
         changed: for({_file, {:changed, reply}} <- results, do: reply),
         unchanged: for({file, :unchanged} <- results, do: file),
         skipped: for({file, {:skipped, why}} <- results, do: %{file: file, why: why})
       }}
    end
  end

  defp files(%{files: [_ | _] = files} = p), do: resolve_all(files, p)
  defp files(_p), do: {:error, "rename needs files"}

  defp only(nil), do: {:ok, nil}
  defp only("functions"), do: {:ok, :functions}
  defp only("variables"), do: {:ok, :variables}
  defp only(other), do: {:error, "only takes functions or variables, got #{other}"}

  defp versions(%{force: true}), do: :ok

  defp versions(p) do
    pairs =
      Enum.reduce_while(p[:versions] || [], {:ok, []}, fn spec, {:ok, acc} ->
        with [file, version] <- String.split(spec, "=", parts: 2),
             {:ok, abs} <- resolve(file, p) do
          {:cont, {:ok, [{abs, version} | acc]}}
        else
          {:error, _} = refused -> {:halt, refused}
          _ -> {:halt, {:error, "versions are FILE=SHA, got #{spec}"}}
        end
      end)

    with {:ok, pairs} <- pairs, do: Menard.check_versions(Enum.reverse(pairs))
  end

  # a file it could not parse or write is neither: "unchanged" told the agent the old name was
  # not in a file it never looked into
  defp rename(file, old, new, opts) do
    with {:ok, source} <- read(file),
         out when is_binary(out) <- Menard.Rename.run(source, old, new, opts) do
      if out == source, do: :unchanged, else: written(file, out, old, new)
    else
      {:error, why} -> {:skipped, why}
    end
  end

  defp written(file, out, old, new) do
    case Menard.write(file, out, did: "rename #{old} → #{new} in #{Path.basename(file)}") do
      {:ok, reply} -> {:changed, reply}
      {:error, why} -> {:skipped, why}
    end
  end
end
