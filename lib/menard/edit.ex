defmodule Menard.Edit do
  @moduledoc """
  `edit`: replacements of text, several in a file and in several files, in one call: what an agent
  otherwise writes a script for (`s = s.replace(old, new)`, file after file). Each `old` is found
  exactly once in its file as the edits before it left it, or the call is refused and says which
  text, in which file, was not there or was there more than once: a script's `replace` that finds
  nothing says nothing, and the edit is believed made.

  All of it is written or none of it. Every file's new content is made first and the Elixir among
  it parse-checked; then each is written through `Menard.write/3`, formatted by its project's
  formatter, and a write that fails puts back the ones before it.
  """

  @type edit :: %{
          required(:file) => String.t(),
          required(:old) => String.t(),
          required(:new) => String.t(),
          optional(:all) => boolean()
        }

  @doc """
  Make `edits` (absolute paths), in order. `{:ok, reply}`: `changed`, each file's `Menard.write/3`
  reply (its version and stages), in the order the files were first named, and `replacements`.
  An `old` of `""` makes a file that is not there, of `new`. `root:` is what a refusal names its
  file under.
  """
  @spec run([edit()], keyword()) :: {:ok, map()} | {:error, String.t()}
  def run(edits, opts \\ [])
  def run([], _opts), do: {:error, "edit needs edits: a list of {file, old, new}"}

  def run(edits, opts) do
    files = edits |> Enum.map(& &1.file) |> Enum.uniq()
    before = Map.new(files, &{&1, File.read(&1)})

    with {:ok, contents} <- replaced(edits, before),
         :ok <- parsed(files, contents),
         {:ok, changed} <- written(files, contents, before) do
      {:ok, %{changed: changed, replacements: length(edits)}}
    else
      # a file as the caller named it: under `root:`, where there is one
      {:error, {file, why}} ->
        {:error, "#{Path.relative_to(file, opts[:root] || File.cwd!())}: #{why}\nnothing was written"}
    end
  end

  defp replaced(edits, before) do
    Enum.reduce_while(edits, {:ok, before}, fn edit, {:ok, contents} ->
      case replace(contents[edit.file], edit) do
        {:ok, text} -> {:cont, {:ok, Map.put(contents, edit.file, {:ok, text})}}
        {:error, why} -> {:halt, {:error, refusal(edit.file, why)}}
      end
    end)
  end

  defp replace({:error, :enoent}, %{old: "", new: new}), do: {:ok, new}
  defp replace({:error, :enoent}, _edit), do: {:error, "the file is not there (an empty `old` makes it)"}
  defp replace({:error, reason}, _edit), do: {:error, "cannot be read: #{:file.format_error(reason)}"}

  defp replace({:ok, _text}, %{old: ""}),
    do: {:error, "the file exists, and an empty `old` is no place in it: name the text to replace"}

  defp replace({:ok, text}, %{old: old, new: new} = edit) do
    case {:binary.matches(text, old), edit[:all] == true} do
      {[], _all} -> {:error, "this text is not there:\n#{old}"}
      {[_one], _all} -> {:ok, String.replace(text, old, new)}
      {_several, true} -> {:ok, String.replace(text, old, new)}
      {several, false} -> {:error, several(text, old, several)}
    end
  end

  defp several(text, old, found) do
    lines = Enum.map_join(found, ", ", fn {at, _length} -> line(text, at) end)

    "this text is there #{length(found)} times (lines #{lines}): give more of what is around it, " <>
      "or `all: true` for every one:\n#{old}"
  end

  defp line(text, at), do: text |> binary_part(0, at) |> String.split("\n") |> length() |> to_string()

  defp parsed(files, contents) do
    Enum.find_value(files, :ok, fn file ->
      {:ok, text} = contents[file]

      case Menard.Write.checked(file, text) do
        {:ok, _content} -> nil
        {:error, why} -> {:error, refusal(file, "with these edits it is #{why}")}
      end
    end)
  end

  defp written(files, contents, before) do
    Enum.reduce_while(files, {:ok, []}, fn file, {:ok, done} ->
      File.mkdir_p!(Path.dirname(file))
      {:ok, text} = contents[file]

      case Menard.write(file, text, did: "edit #{Path.basename(file)}") do
        {:ok, reply} ->
          {:cont, {:ok, done ++ [reply]}}

        {:error, why} ->
          restore(Enum.map(done, & &1.file) ++ [file], before)
          {:halt, {:error, refusal(file, why)}}
      end
    end)
  end

  defp restore(files, before) do
    for file <- files do
      case before[file] do
        {:ok, text} -> File.write!(file, text)
        {:error, _} -> File.rm(file)
      end
    end
  end

  defp refusal(file, why), do: {file, why}

  @doc """
  The edits written as search/replace blocks, the CLI's form, where JSON would have every line
  break and quote of the code escaped:

      lib/a.ex
      <<<<<<< SEARCH
      the text to find
      =======
      the text to put there
      >>>>>>> REPLACE
  """
  @spec blocks(String.t()) :: {:ok, [edit()]} | {:error, String.t()}
  def blocks(text), do: text |> String.split("\n") |> blocks([])

  defp blocks([], edits), do: {:ok, Enum.reverse(edits)}
  defp blocks(["" | lines], edits), do: blocks(lines, edits)

  defp blocks([file, "<<<<<<< SEARCH" | lines], edits) do
    with {:ok, old, lines} <- upto(lines, "=======", file),
         {:ok, new, lines} <- upto(lines, ">>>>>>> REPLACE", file) do
      blocks(lines, [%{file: String.trim(file), old: old, new: new} | edits])
    end
  end

  defp blocks([line | _lines], _edits),
    do: {:error, "expected a file's path and then `<<<<<<< SEARCH`, got: #{line}"}

  defp upto(lines, mark, file) do
    case Enum.split_while(lines, &(&1 != mark)) do
      {_text, []} -> {:error, "#{file}: a block has no `#{mark}` line"}
      {text, [^mark | rest]} -> unmarked(text, rest, file)
    end
  end

  # A marker inside a block's text is a block written wrong far more often than it is the text: a
  # second `=======` was taken for a line of the replacement, and written into the file.
  @marks ["<<<<<<< SEARCH", "=======", ">>>>>>> REPLACE"]

  defp unmarked(text, rest, file) do
    case Enum.find(text, &(&1 in @marks)) do
      nil ->
        {:ok, Enum.join(text, "\n"), rest}

      mark ->
        {:error,
         "#{file}: a block holds a second `#{mark}` line. If the text itself has that line, " <>
           "make this edit through the MCP tool, whose edits are fields"}
    end
  end
end
