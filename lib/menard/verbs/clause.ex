defmodule Menard.Verbs.Clause do
  @moduledoc "The `clause` verbs (`Menard.Verbs`): `replace`, `rewrite`, `delete`, `insert_after`, `insert_before`, `insert_at`, `move`, `visibility`, `spec`, `get`."

  import Menard.Verbs
  alias Menard.Clause

  @verbs ~w(replace rewrite delete insert_after insert_before insert_at move visibility spec get)

  @spec run(Menard.Verbs.params()) :: Menard.Verbs.result()
  def run(%{verb: "get"} = p) do
    with :ok <- need(p, [:file, :name_arity], "clause get"),
         {:ok, file} <- resolve(p.file, p),
         {:ok, source} <- read(file),
         {:ok, got} <- Clause.get(source, p.name_arity, p[:head], nth(p)) do
      {:ok, Map.merge(got, %{file: file, version: Menard.remember(source)})}
    end
  end

  # Two files change at once, so neither is written until BOTH edits succeed — a move that half
  # lands is worse than one that does not. `version` is the source file's: the one the edit came from.
  # `name_arity` names one function or several (a list, or comma-separated): a split is a call per
  # new module.
  def run(%{verb: "move"} = p) do
    with :ok <- need(p, [:file, :name_arity, :to], "clause move"),
         {:ok, file} <- resolve(p.file, p),
         {:ok, dest} <- resolve(p.to, p),
         :ok <- fresh(file, p),
         names = Menard.Move.names(p.name_arity),
         {:ok, moved} <-
           Menard.Move.run(file, dest, names,
             as: p[:as],
             module: p[:module],
             moduledoc: p[:moduledoc],
             delegate: p[:delegate] == true,
             root: p[:root]
           ) do
      {:ok, Map.put(moved, :did, "move #{Enum.join(names, ", ")} to #{Path.basename(dest)}")}
    end
  end

  # no head: the whole function, every clause. The reply names each call still left, lib and test,
  # so the agent fixes or deletes those on purpose; tests are never deleted for it.
  def run(%{verb: "delete"} = p) when not is_map_key(p, :head) or p.head == nil do
    with :ok <- need(p, [:file, :name_arity], "clause delete"),
         {:ok, file} <- resolve(p.file, p),
         {:ok, source} <- read(file),
         out when is_binary(out) <- Clause.delete_function(source, p.name_arity),
         {:ok, reply} <-
           Menard.write(
             file,
             out,
             [did: "delete #{p.name_arity}, every clause, in #{Path.basename(file)}"] ++ stale(p)
           ) do
      {:ok,
       Map.put(reply, :left, Menard.Find.left(p[:root] || Menard.caller_dir(), file, source, p.name_arity))}
    end
  end

  def run(%{verb: "insert_at"} = p) do
    with :ok <- need(p, [:file, :code], "clause insert_at"),
         {:ok, at} <- at(p[:at]) do
      edit(p, &"insert_at #{p[:module] || "-"}#{if at, do: " #{at}"} in #{&1}", fn source ->
        Clause.insert_at(source, module(p[:module]), at, p.code)
      end)
    end
  end

  def run(%{verb: verb} = p) when verb in @verbs do
    with :ok <- need(p, [:file, :name_arity], "clause #{verb}"),
         {:ok, want} <- visibility(verb, p[:visibility]) do
      # no head is a function's only clause, as `head: ""` is; among several, that is refused with theirs
      head = p[:head] || ""
      did = &"#{verb} #{p.name_arity}#{if head != "", do: " `#{head}`"} in #{&1}"
      edit(p, did, &change(verb, &1, p.name_arity, head, p[:code] || "", want, nth(p)))
    end
  end

  def run(%{verb: verb}),
    do: {:error, "clause has no verb #{inspect(verb)}: one of #{Enum.join(@verbs, ", ")}"}

  def run(_params), do: {:error, "clause needs verb: one of #{Enum.join(@verbs, ", ")}"}

  defp change("replace", source, na, head, code, _want, opts),
    do: Clause.replace_body(source, na, head, code, opts)

  defp change("rewrite", source, na, head, code, _want, opts),
    do: Clause.rewrite(source, na, head, code, opts)

  defp change("delete", source, na, head, _code, _want, opts), do: Clause.delete(source, na, head, opts)

  defp change("insert_after", source, na, head, code, _want, opts),
    do: Clause.insert_after(source, na, head, code, opts)

  defp change("insert_before", source, na, head, code, _want, opts),
    do: Clause.insert_before(source, na, head, code, opts)

  # every clause of the function at once — a half-flipped one does not compile
  defp change("visibility", source, na, _head, _code, want, _opts), do: Clause.visibility(source, na, want)
  # the function's, not a clause's: no head. `code` is the signature, absent deletes it
  defp change("spec", source, na, _head, code, _want, _opts), do: Clause.spec(source, na, blank(code))

  defp blank(""), do: nil
  defp blank(code), do: code

  # the core takes atoms only; the doors' input is strings
  defp at(nil), do: {:ok, nil}
  defp at("top"), do: {:ok, :top}
  defp at("bottom"), do: {:ok, :bottom}
  defp at(other), do: {:error, "at must be top or bottom, got #{other}"}

  defp visibility("visibility", "public"), do: {:ok, :public}
  defp visibility("visibility", "private"), do: {:ok, :private}

  defp visibility("visibility", other),
    do: {:error, "visibility must be public or private, got #{inspect(other)}"}

  defp visibility(_verb, _want), do: {:ok, nil}

  defp fresh(file, %{version: version} = p) when is_binary(version) and version != "" do
    if p[:force] == true, do: :ok, else: Menard.check_versions([{file, version}])
  end

  defp fresh(_file, _params), do: :ok
end
