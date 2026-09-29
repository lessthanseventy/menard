defmodule Menard.Write do
  @moduledoc """
  The parse check every write goes through (`Menard.write/3`): bytes that do not parse as Elixir
  are refused before they reach disk, instead of at the next compile.
  """

  @doc """
  `code` as the content of `path` would be written: `{:ok, content}` with exactly one trailing
  newline, or `{:error, message}` when a `.ex`/`.exs` does not parse. Only those are parsed —
  menard writes Elixir, but a fixture next to it may be anything, and refusing a `.json` because
  it is not Elixir would be nonsense.
  """
  @spec checked(String.t(), String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def checked(path, code) do
    content = if String.ends_with?(code, "\n"), do: code, else: code <> "\n"

    if Path.extname(path) in [".ex", ".exs"] do
      case Code.string_to_quoted(content, emit_warnings: false) do
        {:ok, _ast} ->
          {:ok, content}

        {:error, {meta, {prefix, suffix}, token}} ->
          {:error, "not parseable at line #{line(meta)}: #{prefix}#{token}#{suffix}"}

        {:error, {meta, message, token}} ->
          {:error, "not parseable at line #{line(meta)}: #{message}#{token}"}

        {:error, reason} ->
          {:error, "not parseable — #{inspect(reason)}"}
      end
    else
      {:ok, content}
    end
  end

  @doc """
  `:ok`, or why `code` is not written over `original`: it would put a function between the
  clauses of another, where they were together. That parses, the compiler warns that the clauses
  are not grouped, and a build with warnings as errors fails: written by `edit` twice in an hour
  by the one who wrote it, a helper under the clause that calls it and above the function's next.
  Clauses that were apart already are no part of this write, and are not held against it.
  """
  @spec together(String.t(), String.t(), String.t()) :: :ok | {:error, String.t()}
  def together(path, original, code) do
    if Path.extname(path) in [".ex", ".exs"], do: newly_apart(apart(original), apart(code)), else: :ok
  end

  defp newly_apart(was, now) do
    was = for {module, function, _between, _line} <- was, do: {module, function}

    case Enum.reject(now, fn {module, function, _, _} -> {module, function} in was end) do
      [] ->
        :ok

      [{_module, {name, arity}, {other, other_arity}, line} | _] ->
        {:error,
         "it would put #{other}/#{other_arity} between the clauses of #{name}/#{arity} (the next is at " <>
           "line #{line}): a function's clauses stay together, or the compiler warns and a build " <>
           "with warnings as errors fails. Put #{other}/#{other_arity} after the last clause of #{name}/#{arity}"}
    end
  end

  # each function with a clause that comes after another function's: the module, the function, the
  # one between, and the line of the clause that is apart
  defp apart(code) do
    case Menard.Source.parse(code) do
      {:ok, ast} -> Enum.flat_map(Menard.Tree.modules(ast), fn {name, node} -> apart(name, node) end)
      _ -> []
    end
  end

  defp apart(module, node) do
    node
    |> Menard.Tree.definitions()
    |> Enum.flat_map(fn {_kind, _meta, [head | _]} = definition ->
      case Menard.Tree.name_arity(head) do
        {name, arity} when is_atom(name) -> [{{name, arity}, Menard.Tree.start_line(definition)}]
        _unquoted -> []
      end
    end)
    |> Enum.reduce({[], nil, MapSet.new()}, fn {key, line}, {found, last, seen} ->
      found = if key != last and key in seen, do: [{module, key, last, line} | found], else: found
      {found, key, MapSet.put(seen, key)}
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp line(meta) when is_list(meta), do: Keyword.get(meta, :line, "?")
  defp line(_meta), do: "?"
end
