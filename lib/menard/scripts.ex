defmodule Menard.Scripts do
  @moduledoc """
  What a shell command may not do where menard is: run a script in another language (python, perl,
  ruby or node), whatever it is for, or read menard's own reply through a filter. Reads of code
  (grep, sed) run: the rules that refused them toward a verb are in the tag pre-slim-2026-10-01.

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

  @doc """
  Why `command` is refused, or nil when it runs. `menard` is this menard's path; `root` is the
  directory the command runs in, where a program the project tracks is looked up. Reads (grep, sed)
  are not refused: agents read as much Elixir with menard as without it, 0 of 7 line-range
  refusals led to the call they named, and the callers rule misfired on alternations and stdlib
  names (Fable's review, 2026-10-01). The rules are in the tag pre-slim-2026-10-01.
  """
  @spec refused(String.t(), String.t(), String.t() | nil) :: String.t() | nil
  def refused(command, menard, root \\ nil) do
    script = interpreter(command)

    cond do
      filtered?(command) ->
        filtered_why()

      script && not (programs?(command, root) or harmless?(command)) ->
        "#{script} does not run here. " <> instead(menard)

      true ->
        nil
    end
  end

  @doc "What is so in every session, said at its start."
  @spec upfront(String.t()) :: String.t()
  def upfront(menard) do
    "There is no python, perl, ruby or node in this session: a command that runs one is refused. " <>
      instead(menard) <>
      "\nFor a module too big to read whole, when you want them: `#{menard} outline FILE` lists every " <>
      "function and its lines, `#{menard} clause get FILE NAME` reads one, `#{menard} find calls " <>
      "Mod.fun DIRS` says who calls it."
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
    # a quoted string is an argument: a commit message's line that starts `python3 -m …` ran nothing
    case Regex.run(
           @runs,
           command |> outside_heredocs() |> String.replace(~r/'[^']*'|"(?:[^"\\]|\\.)*"/, "''")
         ) do
      [_, script] -> script
      nil -> nil
    end
  end

  # -- reading code --------------------------------------------------------

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

  defp words(segment) do
    OptionParser.split(segment)
  rescue
    _ -> []
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
  # every interpreter it runs asked its version or help: no script (Fable's review, 2026-10-01:
  # `node --version` refused). A module run stays a script: `python3 -m json.tool` is jq's here
  defp harmless?(command) do
    runs =
      for segment <- command |> outside_heredocs() |> commands(),
          [first | args] <- [unwrapped(words(segment))],
          interpreter?(first),
          do: args

    runs != [] and Enum.all?(runs, &(&1 in [["--version"], ["-V"], ["-v"], ["--help"]]))
  end

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
    once or nothing written. `--then compile` checks it builds; `--then test`, on the last edit of a \
    change, runs the tests of what it changed (mid-change, tests red for the change not yet made).
      #{menard} edit --then compile - <<'EOF'
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
