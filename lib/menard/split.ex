defmodule Menard.Split do
  @moduledoc """
  `clause split`: a module into several, the whole plan in one call. Each entry of the plan is a
  `Menard.Move` (the functions for one new module, with what they need carried along), made in the
  order given, so a helper two entries share stays in the source, made public, and both call it
  there.

  All of it lands or none of it: an entry that is refused puts every file back as it was and takes
  away the ones the split created, and the refusal names the entry. A split that half lands is
  worse than one that does not.
  """

  alias Menard.Move

  @type entry :: %{
          required(:to) => String.t(),
          required(:functions) => [String.t()],
          optional(:as) => String.t() | nil,
          optional(:moduledoc) => String.t() | nil
        }

  @doc """
  Split `file` by `plan`: each entry's `functions` (`"name/arity"`) to the file `to` (absolute),
  `as` naming a module it creates and `moduledoc` its `@moduledoc`. `delegate:` (true unless told)
  leaves a `defdelegate` for each public function moved, so the source keeps its API; `root:` is
  where the calls left behind are looked for, without it.

  Returns `{:ok, reply}`: `modules`, each entry's `to`, `version` and what `Menard.Move` said of
  it (`created`, `moved`, `carried`, `published`, `unresolved`, `left`, `unformatted`, …), and the source's
  `file` and `version`. No stages: what moved is what was there, and the new files are it.
  """
  @spec run(String.t(), [entry()], keyword()) :: {:ok, map()} | {:error, String.t()}
  def run(file, plan, opts \\ []) do
    plan = Enum.map(plan, &Map.update!(&1, :functions, fn names -> Move.names(names) end))

    with :ok <- once(plan) do
      before = Map.new([file | Enum.map(plan, & &1.to)], &{&1, File.read(&1)})
      done(moves(file, plan, opts), file, plan, before)
    end
  end

  defp done({:ok, modules}, file, plan, _before) do
    {:ok,
     %{
       did: did(file, plan),
       file: file,
       version: List.last(modules).from,
       modules: Enum.map(modules, &Map.delete(&1, :from))
     }}
  end

  defp done({:error, entry, reason}, _file, _plan, before) do
    restore(before)
    {:error, "#{Path.basename(entry.to)}: #{reason}. The split stopped there, and nothing was written"}
  end

  defp did(file, plan),
    do: "split #{Path.basename(file)} into #{Enum.map_join(plan, ", ", &Path.basename(&1.to))}"

  defp once([]), do: {:error, "split needs a plan: the functions for each new module"}

  defp once(plan) do
    twice = plan |> Enum.flat_map(& &1.functions) |> Enum.frequencies() |> Enum.filter(&(elem(&1, 1) > 1))

    case twice do
      [] -> :ok
      _ -> {:error, "the plan sends #{Enum.map_join(twice, ", ", &elem(&1, 0))} to more than one module"}
    end
  end

  defp moves(file, plan, opts) do
    delegate = Keyword.get(opts, :delegate, true)

    Enum.reduce_while(plan, {:ok, []}, fn entry, {:ok, done} ->
      move = [as: entry[:as], moduledoc: entry[:moduledoc], delegate: delegate, root: opts[:root]]

      case Move.run(file, entry.to, entry.functions, move) do
        {:ok, moved} -> {:cont, {:ok, done ++ [lean(moved)]}}
        {:error, reason} -> {:halt, {:error, entry, reason}}
      end
    end)
  end

  # each file's reply is its path and version: the stages of a move are the functions themselves
  defp lean(%{to: to, from: from} = moved) do
    moved
    |> Map.drop([:to, :from])
    |> Map.reject(fn {_key, value} -> value in [nil, []] end)
    |> Map.merge(%{to: to.file, version: to.version, moved: moved.moved, from: from.version})
    |> unformatted(to[:unformatted] || from[:unformatted])
  end

  # written but not formatted is an answer the agent has to see, here as in every write
  defp unformatted(module, nil), do: module
  defp unformatted(module, reason), do: Map.put(module, :unformatted, reason)

  defp restore(before) do
    for {file, was} <- before do
      case was do
        {:ok, content} -> File.write!(file, content)
        {:error, _} -> File.rm(file)
      end
    end
  end
end
