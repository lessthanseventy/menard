defmodule Menard.Verbs.Stmt do
  @moduledoc "The `stmt` verbs (`Menard.Verbs`): `insert_after`, `insert_before`, `replace`, `delete`, `list`."

  import Menard.Verbs
  alias Menard.Stmt

  @verbs ~w(insert_after insert_before replace delete list)

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
