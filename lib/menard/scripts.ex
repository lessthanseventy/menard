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

  @wrappers ~w(nohup env exec time command)

  # flags that take the next word as their value
  @valued ~w(-A -B -C -m -e --after-context --before-context --context --max-count)

  @doc """
  Why `command` is refused, or nil when it runs. `menard` is this menard's path; `root` is the
  directory the command runs in, where a line range read of a module is looked up.
  """
  @spec refused(String.t(), String.t(), String.t() | nil) :: String.t() | nil
  def refused(command, menard, root \\ nil) do
    script = interpreter(command)

    cond do
      filtered?(command) -> filtered_why()
      script && not programs?(command, root) -> "#{script} does not run here. " <> instead(menard)
      true -> read(command, menard, root)
    end
  end

  @doc """
  `command` with each read a verb reads exactly swapped for that verb's call, to run in its place:
  refused, nothing in the command ran, and all of it was sent again. nil where nothing in it is
  such a read, or one has no single call in its place (`find defs …, then clause get`), or is not
  once in the command; and for an interpreter or a filtered reply, which are refusals still.
  """
  @spec in_place(String.t(), String.t(), String.t() | nil) :: String.t() | nil
  def in_place(command, menard, root \\ nil) do
    reads =
      for segment <- command |> outside_heredocs() |> commands() |> Enum.map(&String.trim/1),
          why = read_one(segment, menard, root),
          do: {segment, call(why, menard)}

    cond do
      interpreter(command) || filtered?(command) || reads == [] ->
        nil

      Enum.any?(reads, fn {segment, call} -> call == nil or length(String.split(command, segment)) != 2 end) ->
        nil

      true ->
        Enum.reduce(reads, command, fn {segment, call}, acc -> String.replace(acc, segment, call) end)
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

  @doc """
  Why a subagent is not sent, or nil: one sent to find the calls of a function (desk5: an Explore
  agent, 1,404 characters of prompt, for what `find calls` answers in one call). A prompt that asks
  for the references, usages or callers of a `Mod.fun`, and is no bigger job than that.
  """
  @spec delegated(String.t(), String.t()) :: String.t() | nil
  def delegated(prompt, menard) when byte_size(prompt) < 2_000 do
    asks? =
      String.match?(prompt, ~r/\b(references?|usages?|uses of|callers?|call sites?|calls? (to|it|of))\b/i)

    target =
      ~r/\b((?:[A-Z]\w*\.)+[a-z_]\w*[?!]?)/
      |> Regex.scan(prompt, capture: :all_but_first)
      |> List.flatten()
      |> Enum.max_by(&String.length/1, fn -> nil end)

    if asks? and target do
      "a subagent to find the calls of #{target}: #{menard} find calls #{target} lib test answers it in one " <>
        "call (the `find` tool, kind calls): every call site, by the AST, strings, comments and names that " <>
        "only share its word left out."
    end
  end

  def delegated(_prompt, _menard), do: nil

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
    |> commands()
    |> Enum.find_value(&read_one(String.trim(&1), menard, root))
  end

  # the commands of a command line, split at `&&`, `||`, `;`, `|` and new lines outside quotes: a
  # path in quotes may hold a `;`
  defp commands(line), do: commands(line, "", nil, [])

  defp commands("", cur, _quote, acc), do: Enum.reverse([cur | acc])

  defp commands(<<q, rest::binary>>, cur, nil, acc) when q in [?', ?"],
    do: commands(rest, cur <> <<q>>, q, acc)

  defp commands(<<q, rest::binary>>, cur, q, acc), do: commands(rest, cur <> <<q>>, nil, acc)

  defp commands(<<c::utf8, rest::binary>>, cur, q, acc) when q != nil,
    do: commands(rest, cur <> <<c::utf8>>, q, acc)

  defp commands(<<op::binary-size(2), rest::binary>>, cur, nil, acc) when op in ["&&", "||"],
    do: commands(rest, "", nil, [cur | acc])

  defp commands(<<c, rest::binary>>, cur, nil, acc) when c in [?;, ?|, ?\n],
    do: commands(rest, "", nil, [cur | acc])

  defp commands(<<c::utf8, rest::binary>>, cur, nil, acc), do: commands(rest, cur <> <<c::utf8>>, nil, acc)
  # a byte that is no UTF-8: kept as it is, not a crash of the hook that reads the command
  defp commands(<<c, rest::binary>>, cur, q, acc), do: commands(rest, cur <> <<c>>, q, acc)

  defp read_one(segment, menard, root) do
    case words(segment) do
      ["grep" | args] -> grep(args, menard, root)
      ["sed", "-n", script, file] -> sed(script, file, menard, root)
      _ -> nil
    end
  end

  defp words(segment) do
    OptionParser.split(segment)
  rescue
    _ -> []
  end

  defp grep(args, menard, root) do
    {flags, [pattern | paths]} = grep_args(args, [], [])
    paths = if paths == [], do: ["."], else: paths
    has = fn letters -> Enum.any?(flags, &String.match?(&1, ~r/^-[a-zA-Z]*[#{letters}]/)) end

    # who calls a function is find's however the grep lists or counts it; else a list of files reads
    # no code, nor does a count of text (a count of a file's shape is its outline's); outside lib/ and
    # test/ is text
    cond do
      not code?(paths) -> nil
      call_name(pattern) != nil -> callers(pattern, paths, menard)
      has.("lLq") -> nil
      has.("c") and not structure?(pattern) -> nil
      true -> grep_read(pattern, paths, Enum.any?(flags, &context?/1) && asked(flags), menard, root)
    end
  rescue
    MatchError -> nil
  end

  defp context?(flag), do: String.match?(flag, ~r/^-[A-Za-z]*[ABC]|^--(after-|before-)?context/)

  # what the grep reads, first that holds: a file's structure (outline), with context a function's
  # body (clause get) or one test (block get), else a remote call's callers (find calls)
  defp grep_read(pattern, paths, asked, menard, root) do
    structure_read(pattern, paths, menard) || (asked && context_read(pattern, paths, asked, menard, root)) ||
      callers(pattern, paths, menard)
  end

  # the lines a grep with context reads at its match (`-A 5`: 6), weighed against what a verb would
  # answer in its place; a count not given is any
  defp asked(flags) do
    counts =
      for [_, flag, n] <-
            Regex.scan(~r/(?:^|\s)(-[ABC]|--(?:after-|before-)?context)[=\s]?(\d+)/, Enum.join(flags, " ")),
          do: if(flag in ["-C", "--context"], do: 2, else: 1) * String.to_integer(n)

    if counts == [], do: :any, else: 1 + Enum.sum(counts)
  end

  # a verb's answer of `size` lines in place of a read of `asked`: not much more than was asked
  defp fits?(_size, :any), do: true
  defp fits?(size, asked), do: size <= max(2 * asked, asked + 10)

  defp structure_read(pattern, [file], menard) when is_binary(file) do
    if elixir?(file) and structure?(pattern),
      do:
        "a listing of #{file}'s structure by grep: #{menard} outline #{file}, every module, function " <>
          "and test with its lines" <> read_why()
  end

  defp structure_read(_pattern, _paths, _menard), do: nil

  # with context: a function's body, or one test's
  defp context_read(pattern, paths, asked, menard, root) do
    case def_name(pattern) do
      nil -> test_read(pattern, paths, asked, menard, root)
      name -> def_read(name, paths, asked, menard, root)
    end
  end

  defp callers(pattern, paths, menard) do
    if call = call_name(pattern),
      do:
        "`grep` for the callers of #{call}: #{menard} find calls #{call} #{Enum.join(paths, " ")}" <>
          read_why()
  end

  # a pattern that is only keywords of the file's shape: `test "`, `describe "`, `def `, `defmodule`,
  # a component's `attr` and `slot`, one or several (`def \|attr`, `(def|attr|slot)`)
  defp structure?(pattern) do
    pattern
    |> String.replace(["\\|", "\\(", "\\)"], fn
      "\\|" -> "|"
      _ -> ""
    end)
    |> String.replace(["\\", "^", "(", ")"], "")
    |> String.split("|")
    |> Enum.all?(
      &String.match?(String.trim(&1), ~r/^(test|describe|setup|defmodule|defp?|defmacrop?|attr|slot)\s*"?$/)
    )
  end

  # One test of a test file read by (part of) its label: the pattern is in that test's label and no
  # other's. One over several, `test "` say, is a listing, and runs.
  defp test_read(pattern, [file], asked, menard, root) when is_binary(root) do
    with true <- elixir?(file),
         {:ok, source} <- File.read(Path.expand(file, root)),
         {:ok, modules} <- Menard.Outline.run(source),
         literal = String.replace(pattern, "\\", ""),
         [{what, call, {a, b}}] <-
           for(
             {what, "" <> call, _} = item <- items(modules, file, menard) ++ describes(modules, file, menard),
             String.contains?(call, " block get "),
             String.contains?(what, literal),
             do: item
           ),
         true <- fits?(b - a + 1, asked) do
      "#{what} read by grep: #{call}" <> read_why()
    else
      _ -> nil
    end
  end

  defp test_read(_pattern, _paths, _asked, _menard, _root), do: nil

  # each describe, for a read of one by its label; not among `items/3`, where a range in one of its
  # tests would meet it as well and read as two
  defp describes(modules, file, menard) do
    for m <- modules, %{kind: :describe, label: label, lines: lines} <- m.tests, label do
      {"describe #{inspect(label)}", "#{menard} block get #{file} describe --label #{inspect(label)}", lines}
    end ++ Enum.flat_map(modules, &describes(&1.modules, file, menard))
  end

  defp grep_args([], flags, rest), do: {flags, Enum.reverse(rest)}

  defp grep_args([flag, value | more], flags, rest) when flag in @valued,
    do: grep_args(more, [flag, value | flags], rest)

  defp grep_args(["-" <> _ = flag | more], flags, rest), do: grep_args(more, [flag | flags], rest)
  defp grep_args([word | more], flags, rest), do: grep_args(more, flags, [word | rest])

  # only toward a function the file has: `grep "defp auto_approve"` over a struct field was sent to a
  # clause get that answered nothing (Symphony 08)
  defp def_read(name, [file], asked, menard, root) when is_binary(file) do
    if elixir?(file) and fits_def?(file, name, asked, root),
      do: "a function's body by grep: #{menard} clause get #{file} #{name}" <> read_why(),
      else: nil
  end

  defp def_read(name, paths, _asked, menard, _root),
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
         true <- 2 * (min(b, to) - max(a, from) + 1) >= to - from + 1,
         true <- fits?(b - a + 1, to - from + 1),
         # the lines past it hold module code its verb does not give (Oban 03: lines 1-20 of a test
         # file, its `use` and aliases with the first test): read as asked
         false <- module_code?(source, Enum.to_list(from..(a - 1)//1) ++ Enum.to_list((b + 1)..to//1)) do
      "lines #{from}-#{to} of #{file} are #{what}: #{call}" <> read_why()
    else
      _ -> nil
    end
  end

  # a function the file has, no longer than a read of `asked` lines would take in; nil root: no file
  # to look in, and the refusal stands as it was
  defp fits_def?(_file, _name, _asked, nil), do: true

  defp fits_def?(file, name, asked, root) do
    with {:ok, source} <- File.read(Path.expand(file, root)),
         {:ok, modules} <- Menard.Outline.run(source),
         [_ | _] = lines <- for(d <- all_defs(modules), to_string(d.name) == name, d.lines, do: d.lines) do
      {first, _} = Enum.min(lines)
      {_, last} = Enum.max_by(lines, &elem(&1, 1))
      fits?(last - first + 1, asked)
    else
      [] -> false
      _ -> true
    end
  end

  defp all_defs(modules), do: Enum.flat_map(modules, &(&1.defs ++ all_defs(&1.modules)))

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

  defp module_code?(source, lines) do
    all = String.split(source, "\n")
    Enum.any?(lines, &(Enum.at(all, &1 - 1, "") =~ ~r/^\s*(defmodule|use|alias|import|require|@moduledoc)\b/))
  end

  # the call a read's refusal names, from menard's path to the sentence after it; none where it is
  # two (`find defs …, then clause get`)
  defp call(why, menard) do
    case Regex.run(~r/#{Regex.escape(menard)} [^\n]*?(?=\. Here grep|\z)/, why) do
      [call] -> if String.contains?(call, ", then"), do: nil, else: call
      nil -> nil
    end
  end

  defp read_why,
    do: ". Here grep and sed read text; a function, its callers and the lines of one are read with menard."

  defp def_name(pattern) do
    case Regex.run(~r/defp?(?:\\s[+*]|\s)+([a-z_][A-Za-z0-9_]*[?!]?)/, pattern) do
      [_, name] -> name
      nil -> nil
    end
  end

  # a remote call, where an alternative of the pattern starts with one: `Shop.Cart.total`, `Cart\.total(`,
  # `Tickets\.transition\([a-z_]+, :[a-z]+\)`, `Tickets\.transition\|def transition`
  defp call_name(pattern) do
    pattern
    |> String.replace("\\|", "|")
    |> String.split("|")
    |> Enum.find_value(fn alternative ->
      alternative =
        alternative
        |> String.replace(["\\.", "\\("], fn
          "\\." -> "."
          _ -> "("
        end)
        |> String.trim_leading("^")

      case Regex.run(~r/^([A-Z]\w*(?:\.[A-Z]\w*)*\.[a-z_]\w*[?!]?)(?:\(|$)/, alternative) do
        [_, name] -> name
        nil -> nil
      end
    end)
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

  # menard's reply through a filter. The reply is the answer, whole; a filter drops what its writer
  # did not think to ask for (an edit's `stages`, the formatter's changes to it), and a rule that
  # said "read it whole" was broken by the agent that wrote it, ten times in a session.
  defp filtered?(command) do
    # a heredoc's body goes, the rest of its opening line stays: `menard edit - <<'EOF' | jq`
    line =
      ~r/<<-?\s*(['"]?)(\w+)\1([^\n]*)\n.*?\n\s*\2(?=\n|$)/s
      |> Regex.replace(command, "\\3")
      |> String.replace("2>&1", "")
      # a quoted string is an argument, not a command: `mix run -e '… "bin/menard x | head" …'`
      |> String.replace(~r/'[^']*'|"(?:[^"\\]|\\.)*"/, "''")

    # menard where a command starts (after a separator, or a loop's `do`, `then`, `xargs`), its
    # reply piped into a filter or thrown away
    Regex.match?(
      ~r/(?:^|[;&|(]\s*|\b(?:do|then|else)\s+|\bxargs(?:\s+-\S+)*\s+)(?:\S*\/)?menard\s[^|;&\n>]*(?:\|\s*(?:jq|head|tail|cut|grep|sed|awk)\b|>\s*\/dev\/null)/m,
      line
    )
  end

  defp filtered_why,
    do:
      "menard's reply is read whole, not through a filter: what a filter drops is what you did not " <>
        "think to ask for (an edit's `stages`, a failure past the first). Run it bare. A reply too " <>
        "big or too noisy to read whole is menard's to fix, not to cut."

  # Every interpreter the command runs runs a program git tracks in the project (eval/run.py): that
  # is the project's own tool, not a script. Inline code (-c, -e, -m, a heredoc on stdin) and a file
  # git does not track (one the agent just wrote) are scripts. `cd DIR &&` before one is followed.
  defp programs?(_command, nil), do: false

  defp programs?(command, root) do
    runs =
      command
      |> outside_heredocs()
      |> commands()
      |> Enum.map_reduce(root, fn segment, base ->
        case unwrapped(words(segment)) do
          ["cd", dir | _] -> {nil, Path.expand(dir, base)}
          [first | args] = words -> {if(interpreter?(first), do: {base, args}), base} |> then(&(words && &1))
          [] -> {nil, base}
        end
      end)
      |> elem(0)
      |> Enum.reject(&is_nil/1)

    runs != [] and Enum.all?(runs, fn {base, args} -> tracked?(program(args), base) end)
  end

  defp unwrapped([word | rest]) do
    cond do
      String.match?(word, ~r/^\w+=/) or word in @wrappers ->
        unwrapped(rest)

      word == "timeout" ->
        rest |> Enum.drop_while(&String.starts_with?(&1, "-")) |> Enum.drop(1) |> unwrapped()

      true ->
        [word | rest]
    end
  end

  defp unwrapped([]), do: []

  defp interpreter?(word), do: String.match?(Path.basename(word), ~r/^(python3?(\.\d+)?|perl|ruby|node)$/)

  # the file it runs, or nil for code given inline
  defp program(args) do
    case Enum.drop_while(args, &(String.starts_with?(&1, "-") and &1 not in ~w(- -c -e -m))) do
      [file | _] when file not in ~w(- -c -e -m) -> file
      _ -> nil
    end
  end

  defp tracked?(nil, _base), do: false

  defp tracked?(file, base) do
    File.regular?(Path.expand(file, base)) and
      match?(
        {_, 0},
        System.cmd("git", ["-C", base, "ls-files", "--error-unmatch", "--", file], stderr_to_stdout: true)
      )
  end

  defp instead(menard) do
    """
    Text is replaced, in one file or many, in one call, with menard's edit: every text found exactly \
    once or nothing written, and `--then test` runs the tests of what it changed after.
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
end
