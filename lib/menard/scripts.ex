defmodule Menard.Scripts do
  @moduledoc """
  What a shell command may not do where menard is: run a script in another language (python, perl,
  ruby or node), whatever it is for; or read code a menard verb reads exactly: a function's body by
  `grep "def NAME" -A N` or `sed -n '/def NAME/,/end/p'`, the functions over `sed -n 'N,Mp'` of a
  module, the callers of `Mod.fun` by `grep`, each refused with that call. Any other grep runs.

  It is said twice. Up front, at the start of the session, as what is so here (`upfront/1`): a rule
  the agent meets only in a refusal costs the call that was refused, each time. And in the refusal
  (`refused/3`), which is what holds when the first was not read. There is no setting: a ban that
  was off by default was a ban no session met.
  """

  # where a command starts: the line's, after a separator, inside $( ), after a shell keyword
  @starts ~S"(?:^|[;&|(\n`]|\$\(|\b(?:do|then|else)\s)\s*"
  # a command's first word, after the assignments and the wrappers in front of it
  @wrapped ~S"(?:\w+=\S*\s+)*(?:(?:timeout\s+(?:-\S+\s+)*\S+|nohup|env|nice(?:\s+-n\s*\S+)?|time|command|exec)\s+(?:\w+=\S*\s+)*)*"
  @runs Regex.compile!(@starts <> @wrapped <> ~S"(?:\S*/)?(python3?(?:\.\d+)?|perl|ruby|node)(?=\s|$)")
  @heredoc ~r/<<-?\s*(['"]?)(\w+)\1[^\n]*\n.*?\n\s*\2(?=\n|$)/s

  @doc """
  Why `command` is refused, or nil when it runs. `menard` is this menard's path; `root` is the
  directory the command runs in, where a line range read of a module is looked up.
  """
  @spec refused(String.t(), String.t(), String.t() | nil) :: String.t() | nil
  def refused(command, menard, root \\ nil) do
    case interpreter(command) do
      nil -> read(command, menard, root)
      script -> "#{script} does not run here. " <> instead(menard)
    end
  end

  @doc "What is so in every session, said at its start."
  @spec upfront(String.t()) :: String.t()
  def upfront(menard) do
    "There is no python, perl, ruby or node in this session: a command that runs one is refused. " <>
      instead(menard) <>
      "\nReading a module's code is menard's too: `#{menard} clause get FILE NAME` for one function " <>
      "(`grep \"def NAME\" -A N` and `sed -n` over a module are refused), `#{menard} outline FILE` for " <>
      "every function's lines, `#{menard} find calls Mod.fun DIRS` for who calls it."
  end

  defp instead(menard) do
    """
    Text is replaced, in one file or many, in one call, with menard's edit: every text found exactly \
    once or nothing written, and `--then test` runs the tests after.
      #{menard} edit --then test - <<'EOF'
      lib/a.ex
      <<<<<<< SEARCH
      the text to find
      =======
      the text to put there
      >>>>>>> REPLACE
      lib/b.ex
      <<<<<<< SEARCH
      …
      EOF
    A new file is a block with nothing to find, or a heredoc (`cat > lib/new.ex <<'EOF'`). \
    What is no edit is the shell's: a wait or a loop in the shell itself \
    (`until ! pgrep -f X >/dev/null; do sleep 2; done`), JSON with `jq`; past that, Elixir: \
    `elixir -e '…'`, or `mix run -e '…'` for the project's own code.\
    """
  end

  # the interpreter a command runs, by a word where a command starts: `grep python notes.md` runs none
  @doc "The interpreter `command` runs (python, perl, ruby, node) where a command starts, never in a heredoc, or nil."
  @spec interpreter(String.t()) :: String.t() | nil
  def interpreter(command) do
    case Regex.run(@runs, outside_heredocs(command)) do
      [_, script] -> script
      nil -> nil
    end
  end

  # -- reading code --------------------------------------------------------

  # each command of `command` (split at `&&`, `||`, `;`, `|` and new lines), the first that reads
  # code a verb reads exactly
  defp read(command, menard, root) do
    command
    |> outside_heredocs()
    |> String.split(~r/&&|\|\||[;|\n]/)
    |> Enum.find_value(&read_one(String.trim(&1), menard, root))
  end

  defp read_one(segment, menard, root) do
    case words(segment) do
      ["grep" | args] -> grep(args, menard)
      ["sed", "-n", script, file] -> sed(script, file, menard, root)
      _ -> nil
    end
  end

  defp words(segment) do
    OptionParser.split(segment)
  rescue
    _ -> []
  end

  # flags that take the next word as their value
  @valued ~w(-A -B -C -m -e --after-context --before-context --context --max-count)

  defp grep(args, menard) do
    {flags, [pattern | paths]} = grep_args(args, [], [])
    listing? = Enum.any?(flags, &String.match?(&1, ~r/^-[a-zA-Z]*[clLq]/))
    context? = Enum.any?(flags, &String.match?(&1, ~r/^-[A-Za-z]*[ABC]|^--(after-|before-)?context/))
    paths = if paths == [], do: ["."], else: paths
    {name, call} = {def_name(pattern), call_name(pattern)}

    cond do
      listing? or not code?(paths) ->
        nil

      context? and name != nil ->
        def_read(name, paths, menard)

      call != nil ->
        "`grep` for the callers of #{call}: #{menard} find calls #{call} #{Enum.join(paths, " ")}" <>
          read_why()

      true ->
        nil
    end
  rescue
    MatchError -> nil
  end

  defp grep_args([], flags, rest), do: {flags, Enum.reverse(rest)}

  defp grep_args([flag, value | more], flags, rest) when flag in @valued,
    do: grep_args(more, [flag, value | flags], rest)

  defp grep_args(["-" <> _ = flag | more], flags, rest), do: grep_args(more, [flag | flags], rest)
  defp grep_args([word | more], flags, rest), do: grep_args(more, flags, [word | rest])

  defp def_read(name, [file], menard) when is_binary(file) do
    if elixir?(file),
      do: "a function's body by grep: #{menard} clause get #{file} #{name}" <> read_why(),
      else: nil
  end

  defp def_read(name, paths, menard),
    do:
      "a function's body by grep: #{menard} find defs #{name} #{Enum.join(paths, " ")}, then clause get" <>
        read_why()

  defp sed(script, file, menard, root) do
    cond do
      not (elixir?(file) and code?([file])) ->
        nil

      name = def_name(script) ->
        "a function's body by sed: #{menard} clause get #{file} #{name}" <> read_why()

      match = Regex.run(~r/^(\d+),(\d+)p$/, script) ->
        range(file, match, menard, root)

      true ->
        nil
    end
  end

  # A line range that is one function or one test, from the file's outline: the range meets only it,
  # and it is at least half of the range. One over several, or a page of the file around one, is read
  # as the Read tool reads it, and runs.
  defp range(file, [_, from, to], menard, root) do
    {from, to} = {String.to_integer(from), String.to_integer(to)}

    with root when is_binary(root) <- root,
         {:ok, source} <- File.read(Path.expand(file, root)),
         {:ok, modules} <- Menard.Outline.run(source),
         [{what, call, {a, b}}] <-
           Enum.filter(items(modules, file, menard), fn {_, _, {a, b}} -> a <= to and b >= from end),
         true <- 2 * (min(b, to) - max(a, from) + 1) >= to - from + 1 do
      "lines #{from}-#{to} of #{file} are #{what}: #{call}" <> read_why()
    else
      _ -> nil
    end
  end

  # every function and every test (a describe's own, not the describe), as {what, the call, lines}
  defp items(modules, file, menard) do
    Enum.flat_map(modules, fn m ->
      defs =
        for d <- m.defs,
            d.lines,
            uniq: true,
            do:
              {"#{m.module}.#{d.name}/#{d.arity}", "#{menard} clause get #{file} #{d.name}/#{d.arity}",
               d.lines}

      defs ++ tests(m.tests, file, menard) ++ items(m.modules, file, menard)
    end)
    |> Enum.uniq_by(&elem(&1, 0))
  end

  defp tests(tests, file, menard) do
    Enum.flat_map(tests, fn
      %{kind: :describe, tests: inner} ->
        tests(inner, file, menard)

      %{kind: kind, label: label, lines: lines} when lines != nil ->
        labelled = if label, do: " --label #{inspect(label)}", else: ""

        [
          {"#{kind}#{if label, do: " " <> inspect(label)}", "#{menard} block get #{file} #{kind}#{labelled}",
           lines}
        ]

      _ ->
        []
    end)
  end

  defp read_why,
    do: ". Here grep and sed read text; a function, its callers and the lines of one are read with menard."

  defp def_name(pattern) do
    case Regex.run(~r/defp?(?:\\s[+*]|\s)+([a-z_][A-Za-z0-9_]*[?!]?)/, pattern) do
      [_, name] -> name
      nil -> nil
    end
  end

  # `Shop.Cart.total`, `Cart\.total(`: a remote call, the regex escapes and a paren taken off
  defp call_name(pattern) do
    name = pattern |> String.replace("\\.", ".") |> String.replace(~r/\\?\($/, "")
    if String.match?(name, ~r/^[A-Z]\w*(\.[A-Z]\w*)*\.[a-z_]\w*[?!]?$/), do: name
  end

  defp elixir?(path), do: String.match?(path, ~r/\.(ex|exs|heex)$/)

  # every path a place code lives, or a directory: README.md, mix.exs and config/ are text to grep
  defp code?(paths) do
    Enum.all?(paths, fn path ->
      if path not in [".", "./"] and String.contains?(Path.basename(path), "."),
        do: elixir?(path) and Path.basename(path) != "mix.exs" and not String.starts_with?(path, "config/"),
        else: path in [".", "lib", "test"] or String.starts_with?(path, ["lib/", "test/", "./lib", "./test"])
    end)
  end

  # a heredoc's body is what a command reads, not a command: `cat > notes.md <<EOF … python … EOF`
  defp outside_heredocs(command), do: Regex.replace(@heredoc, command, "")
end
