defmodule Menard.Move do
  @moduledoc """
  `Menard.Clause.move/4` on files. Both results are parse-checked before either is written — a
  move that half lands is worse than one that does not. A missing destination is created, named
  after its path the way a generator would (`as:` overrides).
  """

  @doc """
  Move `name_arity` from `file` to `dest` (absolute paths). `module:` picks the destination module
  in a file with several. Returns `{:ok, created}` — the module name when `dest` was created, else nil.
  """
  @spec run(String.t(), String.t(), String.t(), keyword()) :: {:ok, String.t() | nil} | {:error, String.t()}
  def run(file, dest, name_arity, opts \\ []) do
    with {:ok, dest_source, created} <- dest_source(dest, opts[:as]),
         {:ok, out_source, out_dest} <-
           Menard.Clause.move(File.read!(file), dest_source, name_arity, module: opts[:module]),
         {:ok, _} <- Menard.Write.checked(dest, out_dest),
         {:ok, _} <- Menard.Write.checked(file, out_source),
         :ok <- Menard.checked_write(dest, out_dest),
         :ok <- Menard.checked_write(file, out_source) do
      {:ok, created}
    end
  end

  defp dest_source(dest, as) do
    cond do
      File.exists?(dest) ->
        {:ok, File.read!(dest), nil}

      as not in [nil, ""] ->
        {:ok, "defmodule #{as} do\nend\n", as}

      true ->
        case derive_module(dest) do
          {:ok, mod} ->
            {:ok, "defmodule #{mod} do\nend\n", mod}

          :error ->
            {:error, "#{dest} does not exist and is not inside a mix project — name it with --as Mod.Name"}
        end
    end
  end

  # What a generator would have called it: `lib/my_app/foo/bar.ex` is `MyApp.Foo.Bar`, relative to
  # the nearest mix.exs, with `lib/` or `test/` dropped.
  defp derive_module(path) do
    with {:ok, root} <- project_root(Path.dirname(path)) do
      path
      |> Path.relative_to(root)
      |> String.replace(~r{^(lib|test)/}, "")
      |> String.replace(~r{\.exs?$}, "")
      |> Path.split()
      |> Enum.map_join(".", &Macro.camelize/1)
      |> then(&{:ok, &1})
    end
  end

  defp project_root("/"), do: :error
  defp project_root("."), do: :error

  defp project_root(dir) do
    if File.exists?(Path.join(dir, "mix.exs")),
      do: {:ok, dir},
      else: dir |> Path.dirname() |> project_root()
  end
end
