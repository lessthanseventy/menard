defmodule Menard.Verbs.Stmt do
  @moduledoc "The `stmt` verbs (`Menard.Verbs`): `insert_after`, `insert_before`, `replace`, `delete`, `list`."

  import Menard.Verbs
  alias Menard.Stmt

  @verbs ~w(insert_after insert_before replace delete list)

  @doc "The noun, as both doors are made from it (`Menard.Verbs.Noun`)."
  @spec noun() :: Menard.Verbs.Noun.t()
  def noun do
    %{
      name: "stmt",
      doc: """
      ONE statement inside a clause body — a line in a `do` block, a step in a `with`, a `case` arm.
      Name the clause (`name_arity` + `head`), then the statement by what is WRITTEN (`match`),
      whitespace-insensitive. `verb` is `insert_after`, `insert_before`, `replace`, `delete` or
      `list`; `code` is the new statement.

      A miss lists the statements that are there. An ambiguous match is refused with line numbers
      rather than guessed at; `nth` says which one.
      """,
      fields: [
        {:version, :string, []},
        {:force, :boolean, []},
        {:verb, :enum,
         [values: ["insert_after", "insert_before", "replace", "delete", "list"], required: true]},
        {:file, :string, [required: true]},
        {:name_arity, :string, [required: true]},
        {:head, :string, [required: true]},
        {:match, :string, []},
        {:code, :string, []},
        {:nth, :integer, []}
      ],
      cli: %{
        shapes: [
          {"list", [:file, :name_arity, :head]},
          {"delete", [:file, :name_arity, :head, :match]},
          {"insert_after", [:file, :name_arity, :head, :match, :code]},
          {"insert_before", [:file, :name_arity, :head, :match, :code]},
          {"replace", [:file, :name_arity, :head, :match, :code]}
        ]
      }
    }
  end

  @spec run(Menard.Verbs.params()) :: Menard.Verbs.result()
  def run(%{verb: "list"} = p) do
    with :ok <- need(p, [:file, :name_arity], "stmt list"),
         {:ok, file} <- resolve(p.file, p),
         {:ok, source} <- read(file),
         statements when is_list(statements) <- Stmt.list(source, p.name_arity, p[:head] || "", nth(p)) do
      {:ok, %{statements: statements, file: file}}
    end
  end

  def run(%{verb: verb} = p) when verb in @verbs do
    with :ok <- need(p, [:file, :name_arity, :match], "stmt #{verb}") do
      head = p[:head] || ""
      code = p[:code] || ""

      edit(p, &"#{verb} `#{p.match}` in #{p.name_arity} of #{&1}", fn source ->
        change(verb, source, p.name_arity, head, p.match, code, nth(p))
      end)
    end
  end

  def run(%{verb: verb}), do: {:error, "stmt has no verb #{inspect(verb)}: one of #{Enum.join(@verbs, ", ")}"}
  def run(_params), do: {:error, "stmt needs verb: one of #{Enum.join(@verbs, ", ")}"}

  defp change("insert_after", source, na, head, match, code, opts),
    do: Stmt.insert_after(source, na, head, match, code, opts)

  defp change("insert_before", source, na, head, match, code, opts),
    do: Stmt.insert_before(source, na, head, match, code, opts)

  defp change("replace", source, na, head, match, code, opts),
    do: Stmt.replace(source, na, head, match, code, opts)

  defp change("delete", source, na, head, match, _code, opts), do: Stmt.delete(source, na, head, match, opts)
end
