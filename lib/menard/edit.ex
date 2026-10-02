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

  @def_kinds Menard.Tree.def_kinds()

  @type edit :: %{
          required(:file) => String.t(),
          required(:old) => String.t(),
          required(:new) => String.t(),
          optional(:all) => boolean()
        }

  # A marker inside a block's text is a block written wrong far more often than it is the text: a
  # second `=======` was taken for a line of the replacement, and written into the file.
  @marks ["<<<<<<< SEARCH", "=======", ">>>>>>> REPLACE"]

  @doc """
  Make `edits` (absolute paths), in order. `{:ok, reply}`: `changed`, each file's path and version,
  and the stages after the patch that changed anything (the formatter's, the plugins'), in the
  order the files were first named, and `replacements`.
  An `old` of `""` makes a file that is not there, of `new`. `root:` is what a refusal names its
  file under.
  """
  @spec run([edit()], keyword()) :: {:ok, map()} | {:error, String.t()}
  def run(edits, opts \\ [])
  def run([], _opts), do: {:error, "edit needs edits: a list of {file, old, new}"}

  def run(edits, opts) do
    files = edits |> Enum.map(& &1.file) |> Enum.uniq()
    before = Map.new(files, &{&1, File.read(&1)})

    with {:ok, contents, notes} <- replaced(edits, before),
         :ok <- parsed(files, contents, before),
         {:ok, changed} <- written(files, contents, before) do
      root = opts[:root] || File.cwd!()

      # each note under its key: `moved` (a function put after its clauses), `indented` (text found deeper)
      notes =
        notes
        |> Enum.group_by(fn {_file, {key, _}} -> key end, fn {file, {_, what}} ->
          "#{Path.relative_to(file, root)}: #{what}"
        end)
        # once a file: `indented` was said per replacement, 42 copies in 29 replies
        |> Map.new(fn {key, notes} -> {key, Enum.uniq(notes)} end)

      {:ok, Map.merge(%{changed: changed, replacements: length(edits)}, notes)}
    else
      # a file as the caller named it: under `root:`, where there is one
      {:error, {file, why}} ->
        {:error, "#{Path.relative_to(file, opts[:root] || File.cwd!())}: #{why}\nnothing was written"}
    end
  end

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
  def blocks(text), do: text |> String.split("\n") |> Enum.flat_map(&markers/1) |> blocks([])

  defp blocks([], edits), do: {:ok, Enum.reverse(edits)}
  defp blocks(["" | lines], edits), do: blocks(lines, edits)

  defp blocks([file, "<<<<<<< SEARCH" | lines], edits) do
    with {:ok, old, lines} <- upto(lines, "=======", file),
         {:ok, new, lines} <- replacement(lines, file) do
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

  # A replacement ends at `>>>>>>> REPLACE`, or at a second `=======` with the next block or the end
  # right after it: written so as often, and the batch was sent again for it (Fable's review,
  # 2026-10-01). A `=======` with more text before a REPLACE is a block written wrong, refused.
  defp replacement(lines, file) do
    {text, rest} = Enum.split_while(lines, &(&1 not in [">>>>>>> REPLACE", "======="]))

    case {rest, Enum.drop_while(Enum.drop(rest, 1), &(&1 == ""))} do
      {["=======" | _], []} -> unmarked(text, [], file)
      {["=======" | _], [_file, "<<<<<<< SEARCH" | _] = next} -> unmarked(text, next, file)
      _ -> upto(lines, ">>>>>>> REPLACE", file)
    end
  end

  # `=======>>>>>>> REPLACE` on one line, as it is often written: the two markers
  defp markers(line),
    do: if(line =~ ~r/^=======\s*>>>>>>> REPLACE$/, do: ["=======", ">>>>>>> REPLACE"], else: [line])

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

  defp replaced(edits, before) do
    Enum.reduce_while(edits, {:ok, before, []}, fn edit, {:ok, contents, moved} ->
      case replace(contents[edit.file], edit) do
        {:ok, text} ->
          {:cont, {:ok, Map.put(contents, edit.file, {:ok, text}), moved}}

        {:ok, text, what} ->
          {:cont, {:ok, Map.put(contents, edit.file, {:ok, text}), moved ++ notes(edit.file, what)}}

        {:error, why} ->
          {:halt, {:error, refusal(edit.file, why)}}
      end
    end)
  end

  # a replacement's notes, one or several (found deeper, and a function moved there)
  defp notes(file, what), do: for(note <- List.wrap(what), do: {file, note})

  defp replace({:error, :enoent}, %{old: "", new: new}), do: {:ok, new}
  defp replace({:error, :enoent}, _edit), do: {:error, "the file is not there (an empty `old` makes it)"}
  defp replace({:error, reason}, _edit), do: {:error, "cannot be read: #{:file.format_error(reason)}"}

  defp replace({:ok, _text}, %{old: ""}),
    do: {:error, "the file exists, and an empty `old` is no place in it: name the text to replace"}

  defp replace({:ok, _text}, %{old: same, new: same}) when same != "",
    do: {:error, "the text and what replaces it are the same: nothing to change (a block left as it was?)"}

  defp replace({:ok, text}, %{old: old, new: new} = edit) do
    case {:binary.matches(text, old), edit[:all] == true} do
      {[], _all} -> deeper(text, edit) || {:error, missed(text, old)}
      {[{at, length}], _all} -> placed(text, edit, at + length)
      {_several, true} -> {:ok, String.replace(text, old, new)}
      {several, false} -> {:error, several(text, old, several)}
    end
  end

  # New functions written under a clause (whole defs ending `new`), where the function has more
  # clauses below: there they would split it, which parses and does not build. They have one place
  # to go, after its last clause, and go there; the rest of `new` stays where `old` was, and the
  # reply says so. A clause of that function among them is refused as before: moved, it would
  # reorder the function's matches.
  defp placed(text, %{old: old, new: new} = edit, anchor_end) do
    plain = String.replace(text, old, new)
    start = anchor_end - byte_size(old)

    with {head, added} <- trailing_defs(new),
         {:error, _} <- Menard.Write.together(edit.file, text, plain),
         kept =
           binary_part(text, 0, start) <> head <> binary_part(text, anchor_end, byte_size(text) - anchor_end),
         {:ok, at, {name, arity}} <- after_run(kept, start + byte_size(head), String.ends_with?(head, "\n")),
         false <- "#{name}/#{arity}" in String.split(defined(added), ", "),
         moved = binary_part(kept, 0, at) <> added <> binary_part(kept, at, byte_size(kept) - at),
         :ok <- Menard.Write.together(edit.file, text, moved) do
      {:ok, moved,
       {:moved, "#{defined(added)} after the last clause of #{name}/#{arity}, not between its clauses"}}
    else
      _ -> {:ok, plain}
    end
  end

  # `new` as the text that takes `old`'s place and the whole functions written after it: the longest
  # tail, from a line's start, that is defs alone, and what is before it (never empty)
  defp trailing_defs(new) do
    starts = for {at, 1} <- :binary.matches(new, "\n"), at + 1 < byte_size(new), do: at + 1

    Enum.find_value(starts, fn at ->
      tail = binary_part(new, at, byte_size(new) - at)
      if defs?(tail), do: {binary_part(new, 0, at), tail}
    end)
  end

  defp defs?(code) do
    forms =
      case Menard.Source.parse(code) do
        {:ok, {:__block__, _, forms}} -> forms
        {:ok, form} -> [form]
        _ -> []
      end

    Enum.any?(forms, &match?({kind, _, _} when kind in @def_kinds, &1)) and
      Enum.all?(forms, &match?({kind, _, _} when kind in [:@ | @def_kinds], &1))
  end

  # Where the added text goes when the anchor ends inside a function's run of clauses: after the
  # run's last line, at the same line boundary the anchor ended on (the start of the next line when
  # it took its newline, else that line's end), so the blank lines come out as they were written.
  defp after_run(text, anchor_end, took_newline?) do
    line =
      text |> binary_part(0, anchor_end - if(took_newline?, do: 1, else: 0)) |> String.split("\n") |> length()

    with {:ok, ast} <- Menard.Source.parse(text),
         clauses = for({_name, node} <- Menard.Tree.modules(ast), clauses <- [runs(node)], do: clauses),
         {key, last} <- Enum.find_value(clauses, &enclosing(&1, line)) do
      starts = [0 | for({at, 1} <- :binary.matches(text, "\n"), do: at + 1)]
      at = if took_newline?, do: Enum.at(starts, last), else: Enum.at(starts, last) - 1
      {:ok, at, key}
    end
  end

  # each module's definitions as runs of one function's consecutive clauses: {key, first, last}
  defp runs(module) do
    module
    |> Menard.Tree.definitions()
    |> Enum.flat_map(fn {_kind, _meta, [head | _]} = d ->
      case {Menard.Tree.name_arity(head), Menard.Tree.line_span(d)} do
        {{name, arity}, {first, last}} when is_atom(name) -> [{{name, arity}, first, last}]
        _ -> []
      end
    end)
    |> Enum.chunk_by(&elem(&1, 0))
    |> Enum.map(fn [{key, first, _} | _] = run -> {key, first, run |> List.last() |> elem(2)} end)
  end

  # the run the anchor ends inside of, short of its last clause: {key, its last line}
  defp enclosing(runs, line) do
    Enum.find_value(runs, fn {key, first, last} ->
      if line >= first and line < last, do: {key, last}
    end)
  end

  defp defined(added) do
    names =
      case Menard.Source.parse(added) do
        {:ok, {:__block__, _, forms}} -> forms
        {:ok, form} -> [form]
        _ -> []
      end
      |> Enum.flat_map(fn
        {kind, _, [head | _]} when kind in @def_kinds ->
          case Menard.Tree.name_arity(head) do
            {name, arity} when is_atom(name) -> ["#{name}/#{arity}"]
            _ -> []
          end

        _ ->
          []
      end)
      |> Enum.uniq()

    if names == [], do: "the added text", else: Enum.join(names, ", ")
  end

  # A miss answers with what IS there, so the next try needs no read: how many of `old`'s lines the
  # file has as written, and its own lines from where they part (most often the formatter wrapped
  # what the agent last wrote). Echoing `old` whole told the agent only its own text.
  defp missed(text, old) do
    olds = String.split(old, "\n")

    found =
      Enum.find(
        (length(olds) - 1)..1//-1,
        &(:binary.match(text, Enum.join(Enum.take(olds, &1), "\n")) != :nomatch)
      )

    if found do
      {at, _} = :binary.match(text, Enum.join(Enum.take(olds, found), "\n"))
      from = String.to_integer(line(text, at)) + found
      there = text |> String.split("\n") |> Enum.slice(from - 1, length(olds) - found + 3) |> Enum.join("\n")

      "this text is not there: the first #{found} lines are there, at line #{line(text, at)}; from line #{from} the file reads:\n#{there}"
    else
      "this text is not there, not even its first line: #{hd(olds)}" <> nearest(text, hd(olds), length(olds))
    end
  end

  # the line that starts most like `first` (trimmed; 6 characters in common at least), and the lines
  # after it: the formatter wrapped a head, and the next try needs no read
  defp nearest(text, first, n) do
    want = String.trim(first)
    lines = String.split(text, "\n")
    common = &:binary.longest_common_prefix([String.trim(&1), want])
    {line, at} = lines |> Enum.with_index(1) |> Enum.max_by(fn {line, _} -> common.(line) end)

    if common.(line) >= 6,
      do: "\nnearest, at line #{at}:\n" <> Enum.join(Enum.slice(lines, at - 1, n + 3), "\n"),
      else: ""
  end

  # each place it is, with the lines around it: what to add to tell them apart. Said back, the text
  # told its writer nothing it had not sent (Fable's review)
  defp several(text, _old, found) do
    all = String.split(text, "\n")

    places =
      Enum.map_join(found, "\n", fn {at, _length} ->
        n = String.to_integer(line(text, at))
        "line #{n}:\n" <> Enum.map_join(Enum.slice(all, max(n - 2, 0), 3), "\n", &("  " <> &1))
      end)

    lines = Enum.map_join(found, ", ", fn {at, _length} -> line(text, at) end)

    "this text is there #{length(found)} times (lines #{lines}): give more of what is around it, or " <>
      "`all: true` for every one:\n#{places}"
  end

  # `old` as clause get and block get give code, at column 0, where the file has it deeper: found once
  # at one depth, whole lines from a line's start, it is replaced there and `new` written at that depth
  defp deeper(text, %{old: old, new: new} = edit) do
    found =
      for n <- 1..16,
          at = :binary.matches("\n" <> text, "\n" <> indented(old, n)),
          at != [],
          do: {n, length(at)}

    case found do
      # the edit at that depth, as if given there: a function added under a clause still goes after
      # the run (`placed`)
      [{n, 1}] ->
        indented = {:indented, "found #{n} spaces deeper than given, and written there"}

        case replace({:ok, text}, %{edit | old: indented(old, n), new: indented(new, n)}) do
          {:ok, out} -> {:ok, out, indented}
          {:ok, out, what} -> {:ok, out, [what, indented]}
          error -> error
        end

      _ ->
        nil
    end
  end

  defp indented(code, n) do
    pad = String.duplicate(" ", n)
    code |> String.split("\n") |> Enum.map_join("\n", &if(&1 == "", do: "", else: pad <> &1))
  end

  defp line(text, at), do: text |> binary_part(0, at) |> String.split("\n") |> length() |> to_string()

  defp parsed(files, contents, before) do
    Enum.find_value(files, :ok, fn file ->
      {:ok, text} = contents[file]
      checked(file, text, before[file])
    end)
  end

  # nil when the file may be written as `text`, the refusal when not
  defp checked(file, text, was) do
    original = with {:ok, original} <- was, do: original
    original = if is_binary(original), do: original, else: ""

    with {:ok, content} <- Menard.Write.checked(file, text),
         :ok <- Menard.Write.together(file, original, content) do
      nil
    else
      {:error, "not parseable" <> _ = why} -> {:error, refusal(file, "with these edits it is #{why}")}
      {:error, why} -> {:error, refusal(file, why)}
    end
  end

  defp written(files, contents, before) do
    Enum.reduce_while(files, {:ok, []}, fn file, {:ok, done} ->
      File.mkdir_p!(Path.dirname(file))
      {:ok, text} = contents[file]

      case Menard.write(file, text, did: "edit #{Path.basename(file)}") do
        {:ok, reply} ->
          {:cont, {:ok, done ++ [lean(reply)]}}

        {:error, why} ->
          restore(Enum.map(done, & &1.file) ++ [file], before)
          {:halt, {:error, refusal(file, why)}}
      end
    end)
  end

  # The patch is what the caller wrote, to the letter: said back, a reply was the call over again.
  # What is news is what came after it, the formatter's changes and the plugins', and only where
  # there were any.
  defp lean(reply) do
    after_it = for %{stage: stage, hunks: [_ | _]} = s <- reply.stages, stage != :patch, do: s

    reply
    |> Map.take([:file, :version, :unformatted, :moved])
    |> Map.merge(if(after_it == [], do: %{}, else: %{stages: after_it}))
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
end
