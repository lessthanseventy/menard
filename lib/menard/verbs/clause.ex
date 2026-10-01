defmodule Menard.Verbs.Clause do
  @moduledoc "The `clause` verbs (`Menard.Verbs`): `replace`, `rewrite`, `delete`, `insert_after`, `insert_before`, `insert_at`, `move`, `visibility`, `spec`, `get`."

  import Menard.Verbs
  alias Menard.Clause

  @verbs ~w(replace rewrite delete insert_after insert_before insert_at move split visibility spec get)

  @doc "The noun, as both doors are made from it (`Menard.Verbs.Noun`)."
  @spec noun() :: Menard.Verbs.Noun.t()
  def noun do
    %{
      name: "clause",
      doc: """
      Edit ONE function or clause. Address it by `name_arity` ("go/1"; "Mod.go/1" where several
      modules define it) and `head`: the clause's CURRENT head as `outline` prints it (args as written;
      guard and parens optional), "" or none for a function's only clause. What it becomes goes in
      `code`. A miss lists the heads that exist; two clauses that share a head are told apart by `nth`.
      An ExUnit `test` is a macro, not a clause: `block` reaches it.

      `verb`:
      - `replace`: the clause's body := `code`.
      - `rewrite`: the WHOLE clause, head included, for changed args or a guard: from `total(cart)` to
        `total(cart, rate)` is `name_arity: "total/1"`, `head: "cart"`.
      - `insert_after`, `insert_before`: `code` is a new clause beside this one. `insert_at`: a new
        function with no sibling, into `module`; a `defp` lands with the private functions, a `def`
        with the public ones, unless `at` says.
      - `get`, `delete`: with no `head`, the whole function, every clause, its `@doc` and `@spec` too;
        `delete` answers `left`, each call still to fix.
      - `visibility`: every clause public or private at once.
      - `spec`: `code` is the `@spec` signature; none deletes it.
      - `move`: functions to the file `to`, several at once (`name_arity` a list, or "a/1,b/2"). What
        they need comes along: private helpers, attributes, alias/import/require lines. `delegate: true`
        leaves a `defdelegate` for each public one, so callers keep working. A missing file is created
        (`as` names its module, `moduledoc` its doc). The reply says what moved, what came along and
        what is left to fix.
      - `split`: a module into several in ONE call. `plan` is a list, one `{to, functions, as?,
        moduledoc?}` per new module; all of it is written or none. Each is a `move`, and leaves
        delegates unless `delegate: false`.
      """,
      fields: [
        {:version, :string, []},
        {:force, :boolean, []},
        {:verb, :enum,
         [
           values: [
             "replace",
             "rewrite",
             "delete",
             "insert_after",
             "insert_before",
             "insert_at",
             "move",
             "split",
             "visibility",
             "spec",
             "get"
           ],
           required: true
         ]},
        {:file, :string, [required: true]},
        {:name_arity, {:either, {:string, {:list, :string}}}, []},
        {:head, :string, []},
        {:code, :string, []},
        {:module, :string, []},
        {:at, :enum, [values: ["top", "bottom"]]},
        {:visibility, :enum, [values: ["public", "private"]]},
        {:nth, :integer, []},
        {:to, :string, []},
        {:as, :string, []},
        {:moduledoc, :string, []},
        {:delegate, :boolean, []},
        {:plan,
         {:list,
          %{
            to: {:required, :string},
            functions: {:required, {:list, :string}},
            as: :string,
            moduledoc: :string
          }}, []}
      ],
      cli: %{
        shapes: [
          {"get", [:file, :name_arity, {:optional, :head}]},
          {"delete", [:file, :name_arity, {:optional, :head}]},
          {"replace", [:file, :name_arity, :head, :code]},
          {"rewrite", [:file, :name_arity, :head, :code]},
          {"insert_after", [:file, :name_arity, :head, :code]},
          {"insert_before", [:file, :name_arity, :head, :code]},
          {"insert_at", [:file, :module, :code]},
          {"insert_at", [:file, :module, :at, :code]},
          {"move", [:file, :name_arity]},
          {"split", [:file, {:rest, :plan}]},
          {"spec", [:file, :name_arity, {:optional, :code}]},
          {"visibility", [:file, :name_arity, :visibility]}
        ]
      }
    }
  end

  @spec run(Menard.Verbs.params()) :: Menard.Verbs.result()
  # a name with no arity, as an agent first writes it (desk7: `clause get … layouts.ex app`, refused
  # "expected name/arity"): the one function of that name in the file; of several, their arities
  def run(%{name_arity: na, file: file} = p)
      when is_binary(na) and is_binary(file) and not is_map_key(p, :arity_given) do
    with {:ok, p} <- arity(p), do: run(Map.put(p, :arity_given, true))
  end

  def run(%{verb: "get"} = p) do
    with :ok <- need(p, [:file, :name_arity], "clause get"),
         {:ok, file} <- resolve(p.file, p),
         {:ok, source} <- read(file),
         {:ok, got} <- got(source, p) do
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

  # The whole plan or none of it (`Menard.Split`). An entry is the MCP door's object, or the CLI's
  # `DEST=a/1,b/2`.
  def run(%{verb: "split"} = p) do
    with :ok <- need(p, [:file, :plan], "clause split"),
         {:ok, file} <- resolve(p.file, p),
         {:ok, plan} <- plan(p.plan, p),
         :ok <- fresh(file, p) do
      Menard.Split.run(file, plan, delegate: p[:delegate] != false, root: p[:root])
    end
  end

  # no head: the whole function, every clause. The reply names each call still left, lib and test,
  # so the agent fixes or deletes those on purpose; tests are never deleted for it.
  # Several at once: `name_arity` a list or `a/1,b/2`, all deleted or none, and `left` the calls to
  # any of them that are still in the file after it, or anywhere else.
  def run(%{verb: "delete"} = p) when not is_map_key(p, :head) or p.head == nil do
    with :ok <- need(p, [:file, :name_arity], "clause delete"),
         names = Menard.Move.names(p.name_arity),
         {:ok, file} <- resolve(p.file, p),
         {:ok, source} <- read(file),
         out when is_binary(out) <- delete_all(source, names),
         {:ok, reply} <-
           Menard.write(
             file,
             out,
             [did: "delete #{Enum.join(names, ", ")}, every clause, in #{Path.basename(file)}"] ++ stale(p)
           ) do
      root = p[:root] || Menard.caller_dir()
      left = names |> Enum.flat_map(&Menard.Find.left(root, file, source, &1)) |> Enum.uniq()
      {:ok, Map.put(reply, :left, left)}
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

  defp plan(entries, p) do
    Enum.reduce_while(List.wrap(entries), {:ok, []}, fn entry, {:ok, plan} ->
      with {:ok, %{to: to} = entry} <- entry(entry),
           {:ok, dest} <- resolve(to, p) do
        {:cont, {:ok, plan ++ [%{entry | to: dest}]}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  # the CLI's entry with an `as` or a `moduledoc` is the MCP door's object, as JSON
  defp entry("{" <> _ = json) do
    case JSON.decode(json) do
      {:ok, %{} = entry} -> entry(entry)
      _ -> {:error, "a plan entry in braces is a JSON object, got #{inspect(json)}"}
    end
  end

  defp entry(text) when is_binary(text) do
    # at the last `=`: a path may hold one, the names after it do not
    case Regex.run(~r/^(.+)=([^=]+)$/, text) do
      [_, to, names] -> {:ok, %{to: to, functions: names}}
      _ -> {:error, "a plan entry is DEST=a/1,b/2, got #{inspect(text)}"}
    end
  end

  defp entry(%{} = entry) do
    entry = Map.new(entry, fn {key, value} -> {to_string(key), value} end)

    case entry do
      %{"to" => to, "functions" => names} when is_binary(to) and names not in [nil, [], ""] ->
        {:ok, %{to: to, functions: names, as: entry["as"], moduledoc: entry["moduledoc"]}}

      _ ->
        {:error, "a plan entry needs `to` (the new module's file) and `functions`, got #{inspect(entry)}"}
    end
  end

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

  defp delete_all(source, names) do
    Enum.reduce_while(names, source, fn name, acc ->
      case Clause.delete_function(acc, name) do
        out when is_binary(out) -> {:cont, out}
        error -> {:halt, error}
      end
    end)
  end

  defp arity(%{name_arity: na} = p) do
    with false <- String.contains?(na, ["/", ","]),
         {:ok, file} <- resolve(p.file, p),
         {:ok, source} <- File.read(file),
         {:ok, modules} <- Menard.Outline.run(source) do
      name = na |> String.split(".") |> List.last()
      arities = for m <- all_modules(modules), d <- m.defs, to_string(d.name) == name, uniq: true, do: d.arity

      case arities do
        [one] -> {:ok, %{p | name_arity: "#{na}/#{one}"}}
        [] -> {:ok, p}
        # a read reads them all, as the grep it stands in for did; a write is told to name one
        many when p.verb == "get" -> {:ok, %{p | name_arity: Enum.map_join(many, ",", &"#{na}/#{&1}")}}
        many -> {:error, "#{na} has #{Enum.map_join(many, ", ", &"#{name}/#{&1}")} here: name one"}
      end
    else
      _ -> {:ok, p}
    end
  end

  defp all_modules(modules), do: Enum.flat_map(modules, &[&1 | all_modules(&1.modules)])

  defp got_one(source, na, {:ok, acc}) do
    case Clause.get(source, na, nil, []) do
      {:ok, got} -> {:cont, {:ok, %{functions: acc.functions ++ [Map.put(got, :name_arity, na)]}}}
      error -> {:halt, error}
    end
  end

  # one function, or each of several arities (`go/1,go/2`, a bare name's)
  defp got(source, p) do
    case String.split(p.name_arity, ",") do
      [_one] ->
        Clause.get(source, p.name_arity, p[:head], nth(p))

      names ->
        Enum.reduce_while(names, {:ok, %{functions: []}}, &got_one(source, &1, &2))
    end
  end
end
