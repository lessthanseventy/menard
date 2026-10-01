defmodule Menard.Verbs.Edit do
  @moduledoc """
  The `edit` verb (`Menard.Verbs`): `edits`, each `{file, old, new, all?}`, made in one call by
  `Menard.Edit`, all written or none; `then` runs a `run` verb after (`test`, `check`, `compile`)
  and puts its answer in the reply's `run`.
  """

  import Menard.Verbs

  alias Menard.Verbs.Run

  @then ~w(test check compile)

  @doc "The noun, as both doors are made from it (`Menard.Verbs.Noun`)."
  @spec noun() :: Menard.Verbs.Noun.t()
  def noun do
    %{
      name: "edit",
      doc: """
      Replace text, several times and in several files, in ONE call: what you would write a
      script for (`s.replace(old, new)`, file after file). `edits` is a list of `{file, old,
      new}`: `old` is text found exactly once in the file, as the edits before it in the list
      left it; `all: true` takes every occurrence; an empty `old` makes a new file of `new`. A text
      that is not there, or is there twice, refuses the whole call and says which: nothing is
      written unless all of it is. Elixir is parse-checked, and every file formatted with its
      project's formatter: the reply says what the formatter changed, and nothing of what you
      wrote. `then` runs `test`, `check` or `compile` after, its answer in `run`.
      """,
      deadline: 600_000,
      fields: [
        {:edits,
         {:list,
          %{
            file: {:required, :string},
            old: {:required, :string},
            new: {:required, :string},
            all: :boolean
          }}, [required: true]},
        {:then, :enum, [values: @then]}
      ]
    }
  end

  @spec run(Menard.Verbs.params()) :: Menard.Verbs.result()
  def run(%{then: then}) when then not in [nil | @then],
    do: {:error, "edit has no then #{inspect(then)}: one of #{Enum.join(@then, ", ")}"}

  def run(p) do
    with :ok <- need(p, [:edits], "edit"),
         {:ok, edits} <- edits(p.edits, p),
         {:ok, reply} <- Menard.Edit.run(edits, root: p[:root] || Menard.caller_dir()) do
      files = Enum.map_join(reply.changed, ", ", &Path.basename(&1.file))
      did = "edit #{files}: #{reply.replacements} replacement#{if reply.replacements != 1, do: "s"}"
      {:ok, reply |> Map.put(:did, did) |> then_run(p)}
    end
  end

  defp then_run(reply, %{then: verb} = p) when is_binary(verb) do
    args = if verb == "test", do: tests_of(reply.changed, p[:root] || Menard.caller_dir()), else: []
    {:ok, run} = Run.run(Map.merge(Map.take(p, [:root, :timeout]), %{verb: verb, args: args}))
    %{reply | did: reply.did <> ", then run #{verb}"} |> Map.put(:run, run)
  end

  defp then_run(reply, _params), do: reply

  # a run while working, not the gate: an edited test file, and the test file of an edited lib file
  # (lib/a/b.ex, test/a/b_test.exs); none of those, the tests stale since the last run
  defp tests_of(changed, root) do
    tests =
      for %{file: file} <- changed,
          test = test_of(Path.relative_to(file, root)),
          test && File.regular?(Path.join(root, test)),
          uniq: true,
          do: test

    if tests == [], do: ["--stale"], else: tests
  end

  defp test_of("test/" <> _ = rel), do: if(String.ends_with?(rel, "_test.exs"), do: rel)
  defp test_of("lib/" <> rest), do: "test/" <> Path.rootname(rest) <> "_test.exs"
  defp test_of(_rel), do: nil

  defp edits(edits, p) do
    Enum.reduce_while(List.wrap(edits), {:ok, []}, fn edit, {:ok, done} ->
      with {:ok, %{file: file} = edit} <- one(edit),
           {:ok, path} <- resolve(file, p) do
        {:cont, {:ok, done ++ [%{edit | file: path}]}}
      else
        {:error, why} -> {:halt, {:error, why}}
      end
    end)
  end

  defp one(%{} = edit) do
    edit = Map.new(edit, fn {key, value} -> {to_string(key), value} end)

    case edit do
      %{"file" => file, "old" => old, "new" => new}
      when is_binary(file) and is_binary(old) and is_binary(new) ->
        {:ok, %{file: file, old: old, new: new, all: edit["all"] == true}}

      _ ->
        {:error, "an edit is {file, old, new}, each a string, got #{inspect(edit)}"}
    end
  end

  defp one(other), do: {:error, "an edit is {file, old, new}, got #{inspect(other)}"}
end
