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

  defp line(meta) when is_list(meta), do: Keyword.get(meta, :line, "?")
  defp line(_meta), do: "?"
end
