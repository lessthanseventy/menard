defmodule Menard.Hook do
  @moduledoc """
  What menard does when the harness says a tool ran: every Elixir file an edit or a shell command
  wrote is formatted with its own project's formatter, plugins included, and what the formatter
  changed goes back to the agent, so its next edit is written against the file as it is (`999999`
  becomes `999_999`, and the next Edit would miss). A file that does not
  parse is named, with the compiler's why. Credo, where the project lints with it, on the lines
  changed.

  `run/2` takes the harness's hook payload (Claude Code's, string keys) and answers `:quiet`,
  `{:context, text}` (for the agent, beside the tool's result), `{:problem, text}` (a file that
  could not be formatted), `{:deny, text}` (a command this session does not run,
  `Menard.Scripts`) or `{:rewrite, input}` (the tool's input, as it is to run: `Menard.Piped`),
  `{:rewrite, input, note}` with what the agent is told of it (`Menard.Scripts.unfiltered/1`).
  Both doors call it: the MCP tool `hook`, which a `mcp_tool` hook reaches
  in the server already running, and `menard hook`, for a harness that can only run a command.

  The session's state is files under the temp directory (`state_dir:` overrides it): what was read
  (`menard-read-*-SESSION`), and one `menard-format-SESSION-CALL` mark per shell command in flight.
  """

  alias Menard.Piped
  alias Menard.Scripts

  @prune ~w(_build deps .git node_modules)
  @diff_lines 40
  @moved "Edit against these lines as they are now, not as you last read them."

  @type answer ::
          :quiet
          | {:context, String.t()}
          | {:problem, String.t()}
          | {:deny, String.t()}
          | {:rewrite, map()}
          | {:rewrite, map(), String.t()}

  # Edits one after another, a model call each, with `edit` called in none. Said at the third of a
  # run, when it is
  # what the agent is doing, and once a session: a note at the start of a session, on what it
  # might do, cost its tokens in every round that tried one and changed nothing.
  @run 3

  @doc """
  The hook for `payload`. `run:` is the run verb it formats and lints with (`Menard.Run.result/3`),
  `compile:` adds the compiler's warnings on the files written (else `MENARD_HOOK_COMPILE`).
  """
  @spec run(map(), keyword()) :: answer()
  def run(payload, opts \\ []) do
    hook = Map.merge(call(payload), settings(opts))
    hook |> tool() |> with_pending(hook)
  end

  @doc "What goes back to the agent beside the tool's result, as the harness reads it from a hook."
  @spec context(String.t(), String.t() | nil) :: map()
  def context(text, event),
    do: %{hookSpecificOutput: %{hookEventName: event || "PostToolUse", additionalContext: text}}

  @doc "A call refused before it runs, as the harness reads it from a PreToolUse hook."
  @spec denial(String.t()) :: map()
  def denial(text) do
    %{
      hookSpecificOutput: %{
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: text
      }
    }
  end

  @doc """
  A call's input as it is to run in place of what was given, as the harness reads it; `note`, what
  the agent is told of it (Claude Code 2.1.293 shows a PreToolUse's `additionalContext` beside it).
  With no decision the harness holds the rewritten command to the user's permission rules.
  """
  @spec rewrite(map(), String.t() | nil) :: map()
  def rewrite(input, note \\ nil) do
    output = %{hookEventName: "PreToolUse", updatedInput: input}

    # "allow" passes the whole command with no prompt, whatever the user's rules say of it: given
    # only to menard's own run standing where the test run stood. Anything more (the commands
    # before it, a filter dropped from another verb) goes by the user's rules, as rewritten.
    output =
      if input["command"] =~ ~r{\A\S*menard run (test|check|credo)[\w\s./:=,@+-]*\z},
        do: Map.put(output, :permissionDecision, "allow"),
        else: output

    %{hookSpecificOutput: if(note, do: Map.put(output, :additionalContext, note), else: output)}
  end

  @doc """
  The directory session `session` stood in at its last call of a menard tool, as that call's
  PreToolUse said, or nil: none yet, or one gone since. The MCP server is started in the
  session's first directory and hears nothing of a `cd` after; this is how it follows the shell.
  """
  @spec session_dir(String.t(), String.t()) :: String.t() | nil
  def session_dir(session, state \\ System.tmp_dir!()) do
    case File.read(cwd_path(state, safe(session))) do
      {:ok, dir} -> if File.dir?(dir), do: dir
      {:error, _} -> nil
    end
  end

  defp cwd_path(state, session), do: Path.join(state, "menard-cwd-#{session}")

  # what the harness said of the call
  defp call(payload) do
    %{
      event: payload["hook_event_name"] || "",
      # a session's start: startup, resume, clear or compact
      source: payload["source"],
      tool: payload["tool_name"] || "",
      input: payload["tool_input"] || %{},
      response: payload["tool_response"] || %{},
      root: nonempty(payload["cwd"]) || System.get_env("CLAUDE_PROJECT_DIR") || File.cwd!(),
      session: safe(payload["session_id"] || "none"),
      call: safe(payload["tool_use_id"] || "none")
    }
  end

  defp settings(opts) do
    %{
      state: opts[:state_dir] || System.tmp_dir!(),
      env_file: Keyword.get(opts, :env_file, System.get_env("CLAUDE_ENV_FILE")),
      run: opts[:run] || (&Menard.Run.result/3),
      # under the hooks server, whose process outlives the call: credo off the call's path
      async: opts[:async] == true,
      compile: Keyword.get(opts, :compile, System.get_env("MENARD_HOOK_COMPILE") not in [nil, ""])
    }
  end

  defp tool(%{tool: "mcp__" <> _ = tool, event: "PreToolUse"} = hook) do
    if tool =~ "menard__", do: File.write!(cwd_path(hook.state, hook.session), hook.root)
    :quiet
  end

  # A write through menard's own tools: menard wrote and formatted the file itself, so there is
  # nothing to format; what it wrote is known, as a Read's is. Reads write nothing.
  defp tool(%{tool: "mcp__" <> _ = tool} = hook) do
    noun = tool |> String.split("__") |> List.last()

    if tool =~ "menard__" and noun not in ~w(outline find run hook) and
         hook.input["verb"] not in ~w(get list refs) do
      files = [hook.input["file"], hook.input["to"] | List.wrap(hook.input["files"])]
      edits = for %{"file" => file} <- List.wrap(hook.input["edits"]), do: file
      known(hook, files ++ edits)
      if hook.input["then"] in [nil, ""], do: linted(hook, files ++ edits), else: :quiet
    else
      :quiet
    end
  end

  # A shell command: a mark before it, and after it every Elixir file newer than the mark. One mark
  # per call: per session, a second call in flight moved the first one's mark past the files it had
  # written, and they went unformatted.
  # what is so in this session, said before its first call (`Menard.Scripts`); a resumed session has
  # it from its start, a compacted one may have lost it
  # its marks gone with its end (see SessionEnd), a resumed session is still one told at its start
  defp tool(%{event: "SessionStart", source: "resume"} = hook) do
    File.write!(told_path(hook), "")
    on_path(hook)
    :quiet
  end

  # A session's marks go with it. The sweep is for a session that never ended
  defp tool(%{event: "SessionEnd"} = hook) do
    Enum.each(Path.wildcard(Path.join(hook.state, "menard-*#{hook.session}*")), &File.rm/1)
    :quiet
  end

  defp tool(%{event: "SessionStart"} = hook) do
    # compacted, what was read is out of the context: a Read of it is no reread
    if hook.source == "compact",
      do: Enum.each(Path.wildcard(Path.join(hook.state, "menard-read-*-#{hook.session}")), &File.rm/1)

    sweep(hook.state)
    File.write!(told_path(hook), "")
    on_path(hook)

    {:context, upfront(hook)}
  end

  # A module read whole again unchanged: answered that nothing changed since the read. Changed, a
  # part of one, a file that is not Elixir: read.
  defp tool(%{tool: "Read", event: "PreToolUse"} = hook) do
    file = hook.input["file_path"]

    with true <- whole?(hook.input) and elixir_file?(file),
         {:ok, seen} <- File.read(read_path(hook, file)),
         {:ok, now} <- File.read(file) do
      reread(hook, file, seen, now)
    else
      _ -> :quiet
    end
  end

  defp tool(%{tool: "Read"} = hook) do
    file = hook.input["file_path"]

    if whole?(hook.input) and elixir_file?(file) do
      with {:ok, text} <- File.read(file), do: File.write!(read_path(hook, file), text)
    end

    :quiet
  end

  defp tool(%{tool: tool, event: "PreToolUse"} = hook) when tool in ["Agent", "Task"] do
    case Scripts.delegated(hook.input["prompt"] || "", menard(hook)) do
      nil -> :quiet
      why -> {:deny, told(hook, why)}
    end
  end

  defp tool(%{tool: "Bash", event: "PreToolUse"} = hook) do
    command = hook.input["command"] || ""
    bare = Scripts.unfiltered(command)

    case Scripts.refused(bare || command, menard(hook), hook.root) do
      nil when is_binary(bare) ->
        marked(hook)
        {:rewrite, Map.put(hook.input, "command", bare), Scripts.unfiltered_note(command, bare)}

      nil ->
        hook |> marked() |> piped(hook)

      why ->
        {:deny, told(hook, why)}
    end
  end

  defp tool(%{tool: "Bash"} = hook) do
    mark = mark(hook)

    if File.exists?(mark) do
      files = newer(hook.root, mark)
      File.rm(mark)
      files |> not_ignored(hook.root) |> not_menards(hook) |> written(hook, &not_held/2)
    else
      :quiet
    end
  end

  defp tool(hook) do
    file = hook.response["filePath"] || hook.input["file_path"]
    answer = written(List.wrap(file), hook, fn files, _dir -> files end)
    known(hook, List.wrap(file))
    in_a_run(answer, hook)
  end

  # menard formatted what it wrote, so credo is all that is left to say of it
  defp linted(hook, files) do
    paths = for file <- files, is_binary(file), do: Path.expand(file, hook.root)

    notes =
      for {dir, written} <- by_project(paths),
          note <- lint(hook, dir, Enum.map(written, &Path.relative_to(&1, dir))),
          do: note

    if notes == [], do: :quiet, else: {:context, Enum.join(notes, "\n") <> "\n"}
  end

  # a command that is menard's own write: its reply said what it found on these files, and the same
  # lint a second time, beside it, says nothing. With a `--then`, its reply has the compiler's and
  # credo's word on its Elixir too.
  defp not_menards(files, hook) do
    command = hook.input["command"] || ""

    cond do
      command =~ ~r/(^|[\s\/;&|])menard\s+\w+\s[^\n]*--then\s/ ->
        Enum.reject(files, &(Menard.Lang.known?(&1) or elixir?(&1)))

      command =~ ~r/\A\s*(\S*\/)?menard\s/ ->
        Enum.reject(files, &Menard.Lang.known?/1)

      true ->
        files
    end
  end

  # menard's bin/ on the session's PATH, through the env file the harness gives a SessionStart hook:
  # named by its absolute path, the agent types that path on every call. Put there, every text names
  # it `menard`
  defp on_path(hook) do
    with env when is_binary(env) <- hook.env_file,
         :ok <- File.write(env, ~s(export PATH="#{Path.dirname(Menard.bin())}:$PATH"\n), [:append]) do
      File.write!(path_mark(hook), "")
    end
  end

  defp path_mark(hook), do: Path.join(hook.state, "menard-path-#{hook.session}")
  # A session's first refusal carries what is so in it. A session that started before the plugin
  # was enabled under it never heard the start-of-session text, and a resumed one is taken to have
  # it from its start
  defp told(hook, why) do
    path = told_path(hook)

    if File.exists?(path) do
      why
    else
      File.write!(path, "")
      why <> "\n\nWhat is so in this session, said once: " <> upfront(hook)
    end
  end

  defp told_path(hook), do: Path.join(hook.state, "menard-told-#{hook.session}")

  defp upfront(hook), do: Scripts.upfront(menard(hook)) <> "\n\n" <> Piped.upfront(menard(hook))
  # a test run and its pipe, run through `menard run` in their place: the call goes on, as that
  defp piped(:quiet, hook) do
    case Piped.rewritten(hook.input["command"] || "", menard(hook)) do
      command when is_binary(command) -> {:rewrite, Map.put(hook.input, "command", command)}
      nil -> :quiet
    end
  end

  defp marked(hook) do
    # written, not touched: File.touch! sets whole seconds, which dates the mark before files written
    # earlier in its own second, and they read as the command's
    File.write!(mark(hook), "")
    # a command between two Edits: they are no run of Edits
    File.rm(session_file(hook, "edits"))
    :quiet
  end

  defp in_a_run(answer, %{tool: tool} = hook) when tool in ["Edit", "MultiEdit"] do
    count = session_file(hook, "edits")
    noted = session_file(hook, "batched")
    File.write!(count, ".", [:append])

    if File.stat!(count).size == @run and not File.exists?(noted) do
      File.write!(noted, "")
      note(answer, run_note(hook))
    else
      answer
    end
  end

  defp in_a_run(answer, _hook), do: answer

  defp run_note(hook) do
    """
    That is #{@run} Edits in a row, a call each. menard's `edit` makes several replacements in one \\
    call, in one file or many, all written or none, and `--then test` runs the tests of what it changed after:
      #{menard(hook)} edit --then test - <<'EOF'
      lib/a.ex
      <<<<<<< SEARCH
      the text to find
      =======
      the text to put there
      >>>>>>> REPLACE
      lib/b.ex
      <<<<<<< SEARCH
      …
      EOF\\
    """
  end

  defp written(files, hook, keep) do
    reports =
      for {dir, files} <- by_project(files),
          files = files |> keep.(dir) |> in_inputs(dir),
          files != [],
          do: report(hook, dir, files)

    reports =
      reports ++
        for file <-
              files
              |> Enum.filter(&(is_binary(&1) and File.regular?(&1) and Menard.Lang.known?(&1)))
              |> then(&if(&1 == [], do: [], else: keep.(&1, hook.root))),
            do: lang_report(hook, file)

    answer(
      Enum.flat_map(reports, & &1.problems),
      Enum.flat_map(reports, & &1.changes),
      Enum.flat_map(reports, & &1.notes)
    )
  end

  # by its path, or `menard` where this session's PATH has it (`on_path/1`)
  defp menard(hook), do: if(File.exists?(path_mark(hook)), do: "menard", else: Menard.bin())

  # What a week-old session left: its marks and reads, and a project's run logs. Once a day: each
  # start stat'ed every run log there was, thousands, through the VM's one file server
  defp sweep(state) do
    swept = Path.join(state, "menard-swept")
    day_ago = System.os_time(:second) - 24 * 3600

    unless match?({:ok, %{mtime: m}} when m > day_ago, File.stat(swept, time: :posix)) do
      File.write!(swept, "")
      sweep_week_old(state)
    end
  end

  defp sweep_week_old(state) do
    week_ago = System.os_time(:second) - 7 * 24 * 3600
    old? = fn path -> match?({:ok, %{mtime: m}} when m < week_ago, File.stat(path, time: :posix)) end

    for file <- Path.wildcard(Path.join(state, "menard-*")),
        File.regular?(file),
        old?.(file),
        do: File.rm(file)

    for logs <- Path.wildcard(Path.join(Menard.log_dir(), "*")),
        File.dir?(logs),
        Enum.all?([logs | Path.wildcard(Path.join(logs, "*"))], old?),
        do: File.rm_rf(logs)
  end

  # Unchanged since it was read: what was read is what it holds. Changed, it is read: answered with
  # the diff, the agent often reads it at once anyway (`cat`), and the diff, the file and a turn are
  # all paid
  defp reread(hook, file, seen, now) do
    rel = Path.relative_to(file, hook.root)

    if seen == now,
      do:
        {:deny,
         told(
           hook,
           "This is the Read's answer, not an error: #{rel} is unchanged since you read it, so what you " <>
             "read is what it holds, and a Read again answers the same. One function of it: " <>
             "#{menard(hook)} clause get #{rel} NAME; every function's lines: #{menard(hook)} outline #{rel}."
         )},
      else: :quiet
  end

  defp whole?(input), do: input["offset"] == nil and input["limit"] == nil
  # a Read's file: the hook's own elixir?/1 takes a project's relative path
  defp elixir_file?(file), do: is_binary(file) and Path.extname(file) in [".ex", ".exs", ".heex"]
  defp read_path(hook, file), do: session_file(hook, "read-" <> Base.encode16(:crypto.hash(:md5, file)))

  # What the agent wrote, and what the formatter did after it (the write's report told it), it knows:
  # a module's read snapshot follows its own writes, and a read again is no news
  defp known(hook, files) do
    for file <- files, is_binary(file), path = Path.expand(file, hook.root), elixir_file?(path) do
      with {:ok, text} <- File.read(path), do: File.write!(read_path(hook, path), text)
    end
  end

  defp note(:quiet, note), do: {:context, note <> "\n"}
  defp note({kind, text}, note), do: {kind, text <> note <> "\n"}

  # a problem carries what was reformatted in the same call with it, or the next Edit on those files
  # is written against a stale read
  defp answer([], [], []), do: :quiet
  defp answer([], changes, notes), do: {:context, text(changes ++ notes, changes)}
  defp answer(problems, changes, notes), do: {:problem, text(problems ++ changes ++ notes, changes)}

  defp text(parts, changes) do
    body = Enum.map_join(parts, &(&1 <> "\n"))
    if changes == [], do: body, else: body <> @moved
  end

  defp report(hook, dir, files) do
    before = Map.new(files, &{&1, File.read!(&1)})
    reply = hook.run.(dir, "format", files)
    failed = Map.new(reply[:failures] || [], &{&1.at, &1.message})
    rel = &Path.relative_to(&1, dir)

    problems = for f <- files, why = failed[rel.(f)], do: "#{rel.(f)} was written but #{why}"
    formatted = Enum.reject(files, &failed[rel.(&1)])

    changes =
      for f <- formatted,
          diff = diff(before[f], File.read!(f)),
          diff != "",
          do: "#{rel.(f)} was reformatted:\n#{diff}"

    rels = Enum.map(formatted, rel)
    %{problems: problems, changes: changes, notes: lint(hook, dir, rels) ++ compiler(hook, dir, files)}
  end

  # what a write tool wrote in a language `Menard.Lang` has a row for: the write is done, so a file
  # that does not parse is named, not refused
  defp lang_report(hook, file) do
    code = File.read!(file)
    rel = Path.relative_to(file, hook.root)

    case Menard.Lang.parse(file, code) do
      {:error, why} ->
        %{problems: ["#{rel} was written but #{why}"], changes: [], notes: []}

      :ok ->
        formatted = Menard.Lang.format(file, code)
        if formatted != code, do: File.write!(file, formatted)
        changes = if formatted != code, do: ["#{rel} was reformatted:\n#{diff(code, formatted)}"], else: []
        %{problems: [], changes: changes, notes: lang_lint(file, hook.root) ++ lang_missing(hook, file)}
    end
  end

  defp lang_lint(file, root) do
    case Menard.Lang.lint(file) do
      [] ->
        []

      found ->
        lines = Enum.map_join(found, "\n", &"  #{Path.relative_to(&1.at, root)} #{&1.kind}: #{&1.message}")
        ["lint, on lines you changed:\n#{lines}"]
    end
  end

  # a tool not installed is skipped, and a clean run would read as a clean file: said once a session
  defp lang_missing(hook, file) do
    new =
      for tool <- Menard.Lang.missing(file),
          mark = session_file(hook, "lang-missing-#{tool}"),
          not File.exists?(mark) do
        File.write!(mark, "")
        tool
      end

    if new == [], do: [], else: ["not installed, so skipped on this write: #{Enum.join(new, ", ")}"]
  end

  # credo off the call's path: 2 s of CPU and up to 10 s of wall under load, paid at every write.
  # Under the hooks server its notes come with the session's next
  # PostToolUse answer (`with_pending/2`); at the CLI door, where no process outlives the call, now
  defp lint(%{async: true} = hook, dir, rels) do
    Task.start(fn ->
      case credo(hook, dir, rels) do
        [] -> :ok
        notes -> File.write!(pending_path(hook), Enum.join(notes, "\n"))
      end
    end)

    []
  end

  defp lint(hook, dir, rels), do: credo(hook, dir, rels)

  defp pending_path(hook), do: Path.join(hook.state, "menard-pending-#{hook.session}-#{hook.call}")

  # what an earlier call's lint found, with this answer (this call's own waits for the next)
  defp with_pending(answer, %{event: "PostToolUse"} = hook) do
    files =
      hook.state
      |> Path.join("menard-pending-#{hook.session}-*")
      |> Path.wildcard()
      |> Enum.reject(&String.ends_with?(&1, "-#{hook.call}"))

    notes = Enum.map(files, &File.read!/1)
    Enum.each(files, &File.rm/1)

    case {notes, answer} do
      {[], _} -> answer
      {_, :quiet} -> {:context, Enum.join(notes, "\n")}
      {_, {kind, text}} -> {kind, Enum.join(notes, "\n") <> "\n" <> text}
    end
  end

  defp with_pending(answer, _hook), do: answer

  # credo on what this session changed in the files, when the project lints with it: found at write
  # time it is one edit; found in CI it is a round trip. Its default level; --strict is the project's.
  defp credo(_hook, _dir, []), do: []

  defp credo(hook, dir, rels) do
    case Menard.Run.credo_changed(dir, rels, hook.run) do
      [] -> []
      found -> ["credo, on lines you changed:\n" <> Enum.map_join(found, "\n", &"  #{&1[:at]} #{&1.message}")]
    end
  end

  # The compile arm: the compiler's warnings in the files this call wrote. 42 red gates in the
  # operator's sessions were warnings-as-errors, found only when the gate ran; an incremental
  # compile is under a second.
  defp compiler(%{compile: false}, _dir, _files), do: []

  defp compiler(hook, dir, files) do
    mine = MapSet.new(files, &Path.relative_to(&1, dir))

    found =
      for %{kind: kind, at: at, message: message} <- hook.run.(dir, "compile", [])[:failures] || [],
          kind in ["warning", "error"],
          is_binary(at),
          at |> String.split(":") |> hd() |> then(&(&1 in mine)),
          do: "  #{at} #{message |> String.split("\n") |> hd()}"

    if found == [], do: [], else: ["the compiler, on files you changed:\n" <> Enum.join(found, "\n")]
  end

  defp diff(before, now) do
    lines =
      Enum.flat_map(Menard.Diff.hunks(before, now), fn %{start: start, removed: removed, added: added} ->
        ["@@ line #{start} @@"] ++ Enum.map(removed, &("-" <> &1)) ++ Enum.map(added, &("+" <> &1))
      end)

    case Enum.split(lines, @diff_lines) do
      {lines, []} -> Enum.join(lines, "\n")
      {lines, more} -> Enum.join(lines, "\n") <> "\n… #{length(more)} more lines of the diff"
    end
  end

  defp mark(hook), do: session_file(hook, "format") <> "-" <> hook.call
  defp session_file(hook, name), do: Path.join(hook.state, "menard-#{name}-#{hook.session}")
  defp safe(id), do: String.replace(id, ~r/[^A-Za-z0-9_-]/, "")
  defp nonempty(text), do: if(text not in [nil, ""], do: text)

  # The Elixir files under `dir` newer than the mark, and those of the languages `Menard.Lang` has a
  # row for by name (a script with no extension is no `find` away), builds, deps and git's own skipped.
  # `find`, for its clock: a stat here is whole seconds, and a command writes within its mark's own.
  defp newer(dir, mark) do
    prune = @prune |> Enum.flat_map(&["-o", "-name", &1]) |> tl()
    # and a file with no extension: a script that is a row's by its shebang (Menard.Lang)
    names = ["(", "-name", "*.ex", "-o", "-name", "*.exs", "-o", "!", "-name", "*.*"]
    names = names ++ Enum.flat_map(Menard.Lang.extensions(), &["-o", "-name", "*" <> &1]) ++ [")"]
    args = [dir, "("] ++ prune ++ [")", "-prune", "-o", "-type", "f"] ++ names ++ ["-newer", mark, "-print0"]

    case System.cmd("find", args, stderr_to_stdout: false) do
      {out, _status} -> out |> String.split(<<0>>, trim: true) |> Enum.sort()
    end
  end

  # what the project's own `mix format` takes: a file its .formatter.exs inputs leave out (another
  # project's code kept as a fixture, under eval/) is not the project's to format. No .formatter.exs
  # to go by: all of them
  defp in_inputs(files, dir) do
    if File.regular?(Path.join(dir, ".formatter.exs")) do
      inputs = MapSet.new(Menard.Run.formatter_inputs(dir), &Path.expand/1)
      Enum.filter(files, &MapSet.member?(inputs, Path.expand(&1)))
    else
      files
    end
  end

  defp elixir?(name), do: Path.extname(name) in [".ex", ".exs"]

  # each project's files, the project the nearest mix.exs above the file as the OS follows it
  defp by_project(files) do
    files
    |> Enum.filter(&(is_binary(&1) and elixir?(&1) and File.regular?(&1)))
    |> Enum.map(&{project(real(&1)), &1})
    |> Enum.reject(fn {dir, _file} -> is_nil(dir) end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  defp real(file) do
    case :file.read_link_all(file) do
      {:ok, target} -> real(Path.expand(to_string(target), Path.dirname(file)))
      {:error, _} -> file
    end
  end

  defp project(file), do: file |> Path.dirname() |> up()
  defp up("/"), do: nil
  defp up(dir), do: if(File.regular?(Path.join(dir, "mix.exs")), do: dir, else: up(Path.dirname(dir)))

  # what git ignores is no one's edit: menard's own test run writes fixtures under tmp/, broken on
  # purpose, and each was named as a file the agent wrote and could not format. Asked of each file's
  # own project, not the session's cwd: a suite run from another directory writes into its own repo
  defp not_ignored(files, root) do
    ignored =
      files
      |> Enum.group_by(&(project(&1) || Path.dirname(&1)))
      |> Enum.flat_map(fn {dir, group} -> ignored_in(dir, group, Path.expand(root)) end)
      |> MapSet.new()

    Enum.reject(files, &MapSet.member?(ignored, &1))
  end

  # its own repo's ignores, and those of every repo around it up to the session's directory: a
  # test's fixture is a repo of its own, under a tmp/ that only the repo around it ignores
  defp ignored_in(dir, files, root) do
    # -z: without it git prints a path with a non-ASCII byte quoted and escaped, which matches nothing
    with {out, status} when status in [0, 1] <-
           git(dir, ["check-ignore", "-z", "--stdin"], Enum.join(files, <<0>>)),
         {top, 0} <- git(dir, ["rev-parse", "--show-toplevel"], "") do
      ignored = String.split(out, <<0>>, trim: true)
      parent = top |> String.trim_trailing("\n") |> Path.dirname()
      ignored ++ ignored_around(parent, files -- ignored, root)
    else
      _no_repo -> []
    end
  end

  defp ignored_around(_parent, [], _root), do: []

  defp ignored_around(parent, files, root) do
    if parent == root or String.starts_with?(parent, root <> "/"),
      do: ignored_in(parent, files, root),
      else: []
  end

  # What git wrote (a checkout, a reset, a new worktree, a popped stash) is content its repo already
  # holds: no one's edit, and none to format. Read off the command, `cd D && git …` is not an
  # edit of every file git checked out, and `git … && sed …` does not hide the sed's. An edit makes
  # new content; one staged in the same command is left as it was staged.
  defp not_held(files, dir) do
    with {hashes, 0} <- git(dir, ["hash-object", "--stdin-paths"], Enum.join(files, "\n")),
         {held, 0} <- git(dir, ["cat-file", "--batch-check"], hashes),
         held = String.split(held, "\n", trim: true),
         true <- length(held) == length(files) do
      for {file, line} <- Enum.zip(files, held), String.ends_with?(line, " missing"), do: file
    else
      # nothing to go by (no repo): format them all
      _ -> files
    end
  end

  # git with `input` on its stdin, which System.cmd cannot give: through a file and sh's redirect
  defp git(dir, args, input) do
    path = Path.join(System.tmp_dir!(), "menard-hook-#{System.pid()}-#{System.unique_integer([:positive])}")
    File.write!(path, input)
    # sh, not bash: no "${@:3}"
    script = ~s(dir=$1; input=$2; shift 2; exec git -C "$dir" "$@" <"$input")

    try do
      System.cmd("sh", ["-c", script, "sh", dir, path | args])
    after
      File.rm(path)
    end
  end
end
