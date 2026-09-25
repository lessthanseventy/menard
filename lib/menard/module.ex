defmodule Menard.Module do
  @moduledoc """
  Whole modules inside a file. `Menard.Clause.insert_at/4` puts a function INTO a module;
  `Menard.Write` replaces a whole file; neither adds a second `defmodule` to a file that already
  has one, the way the MCP tool components live (a dozen modules in `mcp/tools.ex`).
  """

  import Menard.Source, only: [parse: 1]
  alias Menard.Clause

  @doc """
  Add `code` — a complete `defmodule` — to the file. It goes after the LAST module, separated by a
  blank line, which is where a reader of a multi-module file looks for the newest one. Refuses
  anything that is not a module, and refuses a name the file already defines.
  """
  @spec add(String.t(), String.t()) :: String.t() | {:error, String.t()}
  def add(source, code) do
    with {:ok, name} <- module_name(code),
         {:ok, ast} <- parse(source),
         :ok <- absent(ast, name) do
      case names(ast) do
        [] -> {:error, "no module in this file to add one after — use `write` for a new file"}
        _any -> append(source, code)
      end
    end
  end

  @doc "The modules a file defines, in source order."
  @spec list(String.t()) :: [String.t()] | {:error, String.t()}
  def list(source) do
    with {:ok, ast} <- parse(source), do: names(ast)
  end

  @doc """
  The `#` comment block at the top of a module's body — what a test module, say, is about — set,
  replaced, or with `text` nil removed. `above: true` means the one above `defmodule` itself instead.
  `module` is `"Mod.Name"`, or nil in a one-module file.
  """
  @spec comment(String.t(), String.t() | nil, String.t() | nil, keyword()) ::
          String.t() | {:error, String.t()}
  def comment(source, module, text, opts \\ []) do
    with {:ok, ast} <- parse(source),
         {:ok, node} <- Clause.module_scope(ast, module) do
      case {opts[:above], Clause.module_body(node)} do
        # above `defmodule` itself: a license header, why the file exists
        {true, _body} ->
          %{start: [line: line, column: col]} = Sourceror.get_range(node)
          Clause.comment_at(source, line, col - 1, text)

        {_, [first | _]} ->
          %{start: [line: line, column: col]} = Sourceror.get_range(first)
          Clause.comment_at(source, line, col - 1, text)

        {_, []} ->
          {:error, "the module is empty — nothing to put a comment above"}
      end
    end
  end

  @doc """
  Replace the module `name` with `code`, a complete `defmodule` of the same name — one module of a
  file that holds several, where `write` would take them all. Only that module's bytes change; the
  comment above it and its neighbours stay as written.
  """
  @spec replace(String.t(), String.t(), String.t()) :: String.t() | {:error, String.t()}
  def replace(source, name, code) do
    with {:ok, ^name} <- module_name(code),
         {:ok, ast} <- parse(source) do
      case List.keyfind(Clause.modules(ast), name, 0) do
        {^name, node} ->
          range = Menard.Source.range(node, source)

          Sourceror.patch_string(source, [
            %{range: range, change: String.trim(code), preserve_indentation: false}
          ])

        nil ->
          {:error, "no module #{name} in this file — have: #{Enum.join(names(ast), ", ")}"}
      end
    else
      {:ok, other} ->
        {:error, "the code defines #{other}, not #{name}: rename with `rename`, or add it with `module add`"}

      error ->
        error
    end
  end

  defp append(source, code) do
    trimmed = String.trim_trailing(source, "\n")
    trimmed <> "\n\n" <> String.trim(code) <> "\n"
  end

  defp absent(ast, name) do
    if name in names(ast),
      do: {:error, "#{name} is already defined in this file"},
      else: :ok
  end

  defp names(ast) do
    ast
    |> Clause.modules()
    |> Enum.map(&elem(&1, 0))
  end

  defp module_name(code) do
    case Sourceror.parse_string(code) do
      {:ok, {:defmodule, _meta, [{:__aliases__, _alias_meta, parts} | _rest]}} ->
        {:ok, Menard.Source.alias_name(parts)}

      {:ok, _other} ->
        {:error, "add takes a whole `defmodule …`, got: #{String.slice(String.trim(code), 0, 40)}"}

      {:error, reason} ->
        {:error, "not parseable — #{inspect(reason)}"}
    end
  end
end
