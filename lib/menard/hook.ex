defmodule Menard.Hook do
  @moduledoc """
  What menard does when the harness says a tool ran: every Elixir file an edit or a shell command
  wrote is formatted with its own project's formatter, plugins included, and what the formatter
  changed goes back to the agent, so its next edit is written against the file as it is (`999999`
  became `999_999` under an agent in the eval, and its next Edit missed). A file that does not
  parse is named, with the compiler's why. Credo, where the project lints with it, on the lines
  changed.

  `run/2` takes the harness's hook payload (Claude Code's, string keys) and answers `:quiet`,
  `{:context, text}` (for the agent, beside the tool's result), `{:problem, text}` (a file that
  could not be formatted), `{:deny, text}` (a command this session does not run,
  `Menard.Scripts`) or `{:rewrite, input}` (the tool's input, as it is to run: `Menard.Piped`).
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

  # Edits one after another, a model call each: desk3's sonnet made 83 of them in a session and
  # called `edit` in none, its description loaded or not. Said at the third of a run, when it is
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
    tool(hook)
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

  @doc "A call's input as it is to run in place of what was given, as the harness reads it."
  @spec rewrite(map()) :: map()
  def rewrite(input) do
    %{
      hookSpecificOutput: %{
        hookEventName: "PreToolUse",
        permissionDecision: "allow",
        updatedInput: input
      }
    }
  end

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
      run: opts[:run] || (&Menard.Run.result/3),
      compile: Keyword.get(opts, :compile, System.get_env("MENARD_HOOK_COMPILE") not in [nil, ""])
    }
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
    end

    :quiet
  end

  # A shell command: a mark before it, and after it every Elixir file newer than the mark. One mark
  # per call: per session, a second call in flight moved the first one's mark past the files it had
  # written, and they went unformatted.
  # what is so in this session, said before its first call (`Menard.Scripts`); a resumed session has
  # it from its start (49 of 57 fires were resumes), a compacted one may have lost it
  defp tool(%{event: "SessionStart", source: "resume"}), do: :quiet

  defp tool(%{event: "SessionStart"} = hook) do
    # compacted, what was read is out of the context: a Read of it is no reread
    if hook.source == "compact",
      do: Enum.each(Path.wildcard(Path.join(hook.state, "menard-read-*-#{hook.session}")), &File.rm/1)

    sweep(hook.state)

    {:context, Scripts.upfront(menard()) <> "\n\n" <> Piped.upfront(menard())}
  end

  # A module read whole again unchanged (desk5: tickets.ex six times, 11 rereads in a session): answered
  # that nothing changed since the read. Changed, a part of one, a file that is not Elixir: read.
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
    case Scripts.delegated(hook.input["prompt"] || "", menard()) do
      nil -> :quiet
      why -> {:deny, why}
    end
  end

  defp tool(%{tool: "Bash", event: "PreToolUse"} = hook) do
    command = hook.input["command"] || ""

    case Scripts.refused(command, menard(), hook.root) do
      nil -> hook |> marked() |> piped(hook)
      why -> {:deny, why}
    end
  end

  defp tool(%{tool: "Bash"} = hook) do
    mark = mark(hook)

    if File.exists?(mark) do
      files = newer(hook.root, mark)
      File.rm(mark)
      files |> not_ignored(hook.root) |> written(hook, &not_held/2)
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

  # a test run and its pipe, run through `menard run` in their place: the call goes on, as that
  defp piped(:quiet, hook) do
    case Piped.rewritten(hook.input["command"] || "", menard()) do
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
      note(answer, run_note())
    else
      answer
    end
  end

  defp in_a_run(answer, _hook), do: answer

  defp run_note do
    """
    That is #{@run} Edits in a row, a call each. menard's `edit` makes several replacements in one \\
    call, in one file or many, all written or none, and `--then test` runs the tests of what it changed after:
      #{menard()} edit --then test - <<'EOF'
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

    answer(
      Enum.flat_map(reports, & &1.problems),
      Enum.flat_map(reports, & &1.changes),
      Enum.flat_map(reports, & &1.notes)
    )
  end

  defp menard, do: Menard.bin()

  # What a week-old session left: its marks and reads, and a project's run logs (/tmp held 7,022
  # menard files and 378 log directories, and nothing swept them; Fable's review, 2026-10-01)
  defp sweep(state) do
    week_ago = System.os_time(:second) - 7 * 24 * 3600
    old? = fn path -> match?({:ok, %{mtime: m}} when m < week_ago, File.stat(path, time: :posix)) end

    for file <- Path.wildcard(Path.join(state, "menard-*")),
        File.regular?(file),
        old?.(file),
        do: File.rm(file)

    for logs <- Path.wildcard(Path.join([System.tmp_dir!(), "menard-run", "*"])),
        File.dir?(logs),
        Enum.all?([logs | Path.wildcard(Path.join(logs, "*"))], old?),
        do: File.rm_rf(logs)
  end

  # Unchanged since it was read: what was read is what it holds (worked 5 of 5). Changed, it is read:
  # answered with the diff, 3 of 6 were read at once anyway (`cat`), the diff, the file and a turn all
  # paid (Fable's review, 2026-10-01)
  defp reread(hook, file, seen, now) do
    rel = Path.relative_to(file, hook.root)

    if seen == now,
      do:
        {:deny,
         "This is the Read's answer, not an error: #{rel} is unchanged since you read it, so what you " <>
           "read is what it holds, and a Read again answers the same. One function of it: " <>
           "#{menard()} clause get #{rel} NAME; every function's lines: #{menard()} outline #{rel}."},
      else: :quiet
  end

  defp whole?(input), do: input["offset"] == nil and input["limit"] == nil
  # a Read's file: the hook's own elixir?/1 takes a project's relative path
  defp elixir_file?(file), do: is_binary(file) and Path.extname(file) in [".ex", ".exs", ".heex"]
  defp read_path(hook, file), do: session_file(hook, "read-" <> Base.encode16(:crypto.hash(:md5, file)))

  # What the agent wrote, and what the formatter did after it (the write's report told it), it knows:
  # a module's read snapshot follows its own writes, and a read again is no news (desk7: its own edit
  # of router.ex came back as what had changed)
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
    %{problems: problems, changes: changes, notes: credo(hook, dir, rels) ++ compiler(hook, dir, files)}
  end

  # credo on what this session changed in the files, when the project lints with it: found at write
  # time it is one edit; found in CI it is a round trip. Its default level; --strict is the project's.
  defp credo(_hook, _dir, []), do: []

  defp credo(hook, dir, rels) do
    # as strict as the project's gate: at credo's default a strict-only check (AliasUsage) passed
    # every write, and failed the gate
    strict = if Menard.Run.credo_strict?(dir), do: ["--strict"], else: []

    with true <- Menard.Run.credo?(dir),
         [_ | _] = found <- hook.run.(dir, "credo", ["--changed" | rels] ++ strict)[:failures] do
      ["credo, on lines you changed:\n" <> Enum.map_join(found, "\n", &"  #{&1[:at]} #{&1.message}")]
    else
      _ -> []
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

  # The Elixir files under `dir` newer than the mark, builds, deps and git's own files skipped.
  # `find`, for its clock: a stat here is whole seconds, and a command writes within its mark's own.
  defp newer(dir, mark) do
    prune = @prune |> Enum.flat_map(&["-o", "-name", &1]) |> tl()
    names = ["(", "-name", "*.ex", "-o", "-name", "*.exs", ")"]
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
  # purpose, and each was named as a file the agent wrote and could not format
  defp not_ignored([], _root), do: []

  defp not_ignored(files, root) do
    # -z: without it git prints a path with a non-ASCII byte quoted and escaped, which matches nothing
    case git(root, ["check-ignore", "-z", "--stdin"], Enum.join(files, <<0>>)) do
      {out, status} when status in [0, 1] -> files -- String.split(out, <<0>>, trim: true)
      _no_repo -> files
    end
  end

  # What git wrote (a checkout, a reset, a new worktree, a popped stash) is content its repo already
  # holds: no one's edit, and none to format. Read off the command, `cd D && git …` was taken for an
  # edit of every file git checked out, and `git … && sed …` hid the sed's. An edit makes new
  # content; one staged in the same command is left as it was staged.
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
