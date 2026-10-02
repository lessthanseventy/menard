defmodule Menard.HooksTest do
  use ExUnit.Case, async: true

  @root Path.expand("../..", __DIR__)

  # `sh` is dash on Debian/Ubuntu, and a bash script parsed by dash dies with exit 2 — which a
  # PreToolUse hook reads as "block", so every Edit/Write on every file was refused there.
  test "every hook command runs its script with the interpreter its shebang names" do
    hooks = @root |> Path.join("hooks/hooks.json") |> File.read!() |> JSON.decode!()

    for {_event, groups} <- hooks["hooks"], %{"hooks" => list} <- groups, %{"command" => cmd} <- list do
      [interpreter | _] = String.split(cmd, " ")

      script =
        cmd
        |> String.replace("${CLAUDE_PLUGIN_ROOT}", @root)
        |> then(&Regex.run(~r/"([^"]+)"/, &1))
        |> List.last()

      wants = script |> File.read!() |> String.split("\n") |> hd() |> String.split(~r{[ /]}) |> List.last()

      assert interpreter == wants, "#{cmd} runs under #{interpreter}, script wants #{wants}"
    end
  end

  @tag :tmp_dir

  @tag :tmp_dir
  test "shell-edits names a module a Bash command changed, and stays quiet otherwise", %{tmp_dir: dir} do
    module = Path.join(dir, "lib/a.ex")
    File.mkdir_p!(Path.dirname(module))
    File.write!(module, "defmodule A do\nend\n")
    session = "s#{System.unique_integer([:positive])}"

    hook = fn event, cmd ->
      input = Path.join(dir, "payload.json")

      File.write!(
        input,
        JSON.encode!(%{
          hook_event_name: event,
          session_id: session,
          cwd: dir,
          tool_name: "Bash",
          tool_input: %{command: cmd}
        })
      )

      System.cmd("bash", ["-c", "bash #{@root}/hooks/shell-edits.sh < #{input}"],
        env: [{"TMPDIR", dir}],
        stderr_to_stdout: true
      )
    end

    # the hook's mark, dated back: a write after it is newer without waiting out find's second
    backdate_mark = fn ->
      File.touch!(Path.join(dir, "menard-shell-edits-#{session}"), System.os_time(:second) - 10)
    end

    # a command that changes a module
    {_, 0} = hook.("PreToolUse", "sed -i s/A/B/ lib/a.ex")
    backdate_mark.()
    File.write!(module, "defmodule B do\nend\n")
    assert {out, 2} = hook.("PostToolUse", "sed -i s/A/B/ lib/a.ex")
    assert out =~ "lib/a.ex"
    assert out =~ "run"

    # one that changes nothing
    {_, 0} = hook.("PreToolUse", "ls")
    assert {_, 0} = hook.("PostToolUse", "ls")

    # menard's own door, and the formatter, rewrite modules by design
    {_, 0} = hook.("PreToolUse", "mix format")
    backdate_mark.()
    File.write!(module, "defmodule C do\nend\n")
    assert {_, 0} = hook.("PostToolUse", "mix format")

    # a path with a space in it is one path
    spaced = Path.join(dir, "lib/my dir/d.ex")
    File.mkdir_p!(Path.dirname(spaced))
    {_, 0} = hook.("PreToolUse", "sed -i s/D/E/ 'lib/my dir/d.ex'")
    backdate_mark.()
    File.write!(spaced, "defmodule E do\nend\n")
    assert {out, 2} = hook.("PostToolUse", "sed -i s/D/E/ 'lib/my dir/d.ex'")
    assert out =~ "lib/my dir/d.ex"
  end

  @tag :tmp_dir
  test "read-hint points a whole-file Read of a big module at outline, and passes the rest", %{tmp_dir: dir} do
    big = Path.join(dir, "big.ex")
    File.write!(big, "defmodule Big do\n" <> String.duplicate("  def f, do: 1\n", 400) <> "end\n")
    small = Path.join(dir, "small.ex")
    File.write!(small, "defmodule Small do\nend\n")

    read = fn input ->
      path = Path.join(dir, "payload.json")
      File.write!(path, JSON.encode!(%{hook_event_name: "PostToolUse", tool_name: "Read", tool_input: input}))
      System.cmd("bash", ["-c", "bash #{@root}/hooks/read-hint.sh < #{path}"], stderr_to_stdout: true)
    end

    assert {out, 2} = read.(%{file_path: big})
    assert out =~ "outline"
    assert {_, 0} = read.(%{file_path: big, offset: 10, limit: 40})
    assert {_, 0} = read.(%{file_path: small})
  end

  test "the format hook hears a failed shell command too: PostToolUse does not run when the tool fails" do
    # a shell command that edits a module and then runs a failing test (the usual edit-then-test)
    # fires PostToolUseFailure, not PostToolUse, so a hook on the latter never heard of the edit
    # (found in the eval: arm H's shell hook, 2026-09-25)
    hooks = @root |> Path.join("hooks/hooks.json") |> File.read!() |> JSON.decode!()

    # a matcher is a set of tools, `Bash|Agent|Task`
    scripts = fn event, on ->
      for %{"matcher" => matcher, "hooks" => list} <- hooks["hooks"][event] || [],
          on in String.split(matcher, "|"),
          %{"type" => "mcp_tool", "tool" => tool} <- list,
          do: tool
    end

    # a subagent sent to search is asked about before it starts (Scripts.delegated/2)
    assert "hook" in scripts.("PreToolUse", "Agent")

    for event <- ["PreToolUse", "PostToolUse", "PostToolUseFailure"],
        do:
          assert(
            "hook" in scripts.(event, "Bash"),
            "#{event} on Bash does not call the hook tool"
          )
  end

  @tag :tmp_dir
  test "format-report formats what an Edit wrote and tells the agent what the formatter changed", %{
    tmp_dir: dir
  } do
    # the eval: `999999` became `999_999` under an agent, and its next Edit, written against its
    # own read, missed
    host(dir)
    file = Path.join(dir, "lib/n.ex")
    File.write!(file, "defmodule N do\n  def big, do: 999999\nend\n")

    {out, 0} =
      report(%{hook_event_name: "PostToolUse", tool_name: "Edit", tool_input: %{file_path: file}}, dir)

    assert File.read!(file) =~ "999_999"
    context = JSON.decode!(out)["hookSpecificOutput"]["additionalContext"]
    assert context =~ "-  def big, do: 999999"
    assert context =~ "+  def big, do: 999_999"
  end

  @tag :tmp_dir
  test "format-report's diff keeps a line that starts with --, and says when it is cut short", %{tmp_dir: dir} do
    host(dir)
    file = Path.join(dir, "lib/n.ex")
    edit = %{hook_event_name: "PostToolUse", tool_name: "Edit", tool_input: %{file_path: file}}

    # a removed `-- [1]` reads `--- [1]` in the diff, which the header filter took for a header
    File.write!(file, "defmodule N do\n  def f(x) do\n    x\n-- [1]\n  end\nend\n")
    {out, 0} = report(edit, dir)
    assert JSON.decode!(out)["hookSpecificOutput"]["additionalContext"] =~ "--- [1]\n"

    defs = Enum.map_join(1..30, "\n", &"  def f#{&1}, do: 999999")
    File.write!(file, "defmodule N do\n#{defs}\nend\n")
    {out, 0} = report(edit, dir)
    context = JSON.decode!(out)["hookSpecificOutput"]["additionalContext"]
    assert context =~ "def f1, do: 999_999"
    assert context =~ ~r/… \d+ more lines of the diff/
  end

  @tag :tmp_dir
  test "format-report keeps what it reformatted when another file in the call does not parse", %{tmp_dir: dir} do
    # the refusal carried only the broken file, and the next Edit on the other was written against a
    # stale read
    host(dir)

    bash = %{
      tool_name: "Bash",
      session_id: "t#{System.unique_integer([:positive])}",
      tool_input: %{command: "sed"}
    }

    {_, 0} = report(Map.put(bash, :hook_event_name, "PreToolUse"), dir)
    backdate_format_mark(bash, dir)
    File.write!(Path.join(dir, "lib/bad.ex"), "defmodule Bad do\n  def f(x, do: x\nend\n")
    File.write!(Path.join(dir, "lib/ok.ex"), "defmodule Ok do\n  def big, do: 999999\nend\n")

    {out, 2} = report(Map.put(bash, :hook_event_name, "PostToolUse"), dir)
    assert out =~ "lib/bad.ex was written but"
    assert out =~ "+  def big, do: 999_999"
  end

  @tag :tmp_dir
  test "format-report names a file that does not parse, with the compiler's why", %{tmp_dir: dir} do
    host(dir)
    file = Path.join(dir, "lib/bad.ex")
    File.write!(file, "defmodule Bad do\n  def f(x, do: x\nend\n")

    {out, 2} =
      report(%{hook_event_name: "PostToolUse", tool_name: "Write", tool_input: %{file_path: file}}, dir)

    assert out =~ "lib/bad.ex was written but"
    assert out =~ "unclosed delimiter"
  end

  @tag :tmp_dir
  test "format-report formats every file a shell command changed, a failed command too", %{tmp_dir: dir} do
    # PostToolUse does not run when the tool fails, so the hook sits on PostToolUseFailure too; and
    # mix inside the file loop read its stdin, which was the rest of the list: one of six formatted
    host(dir)

    bash = %{
      tool_name: "Bash",
      session_id: "t#{System.unique_integer([:positive])}",
      tool_input: %{command: "sed"}
    }

    {_, 0} = report(Map.put(bash, :hook_event_name, "PreToolUse"), dir)
    backdate_format_mark(bash, dir)

    files = for n <- 1..3, do: Path.join(dir, "lib/m#{n}.ex")

    for {f, n} <- Enum.with_index(files, 1),
        do: File.write!(f, "defmodule M#{n} do\n  def   f(x), do: x\nend\n")

    {_, 0} = report(Map.put(bash, :hook_event_name, "PostToolUseFailure"), dir)
    for f <- files, do: assert(File.read!(f) =~ "  def f(x), do: x\n")
  end

  @tag :tmp_dir
  test "format-report keeps each shell command's own mark: a second call in flight does not move it", %{
    tmp_dir: dir
  } do
    host(dir)
    session = "t#{System.unique_integer([:positive])}"

    call = fn id ->
      %{tool_name: "Bash", session_id: session, tool_use_id: id, tool_input: %{command: "sed"}}
    end

    {_, 0} = report(Map.put(call.("a"), :hook_event_name, "PreToolUse"), dir)
    backdate_format_mark(call.("a"), dir)
    file = Path.join(dir, "lib/m.ex")
    File.write!(file, "defmodule M do\n  def   f(x), do: x\nend\n")
    File.touch!(file, System.os_time(:second) - 5)
    # call b starts after a wrote the file, before a ends
    {_, 0} = report(Map.put(call.("b"), :hook_event_name, "PreToolUse"), dir)

    {_, 0} = report(Map.put(call.("a"), :hook_event_name, "PostToolUse"), dir)
    assert File.read!(file) =~ "  def f(x), do: x\n"
  end

  @tag :tmp_dir
  test "format-report starts menard once per project for a shell command's files", %{
    tmp_dir: dir
  } do
    # one start per file (format 0.46s, credo 1.2s): a checkout of 100 files took ~170s, past the
    # hook's 60s, and the agent heard nothing
    host(dir)

    counting = counting()

    bash = fn cmd ->
      %{tool_name: "Bash", session_id: "t#{System.unique_integer([:positive])}", tool_input: %{command: cmd}}
    end

    call = bash.("sed")
    {_, 0} = report(Map.put(call, :hook_event_name, "PreToolUse"), dir, counting)
    backdate_format_mark(call, dir)
    files = for n <- 1..3, do: Path.join(dir, "lib/m#{n}.ex")

    for {f, n} <- Enum.with_index(files, 1),
        do: File.write!(f, "defmodule M#{n} do\n  def   f(x), do: x\nend\n")

    {out, 0} = report(Map.put(call, :hook_event_name, "PostToolUse"), dir, counting)
    for f <- files, do: assert(File.read!(f) =~ "  def f(x), do: x\n")
    assert out =~ "lib/m3.ex was reformatted"
    # the files the command wrote (the host's own mix.exs among them), in one call
    assert_received {:ran, "format", [_, _, _ | _]}
    refute_received {:ran, "format", _}
  end

  @tag :tmp_dir
  test "format-report leaves what git wrote alone, behind a cd or a -C: a worktree, a stash, a checkout",
       %{tmp_dir: dir} do
    # `cd DIR && git worktree add …` got past a check for a command that starts with git, and every
    # file git checked out was formatted: ~45 "Unknown dependency :phoenix" in a fixture with no deps
    host(dir)

    git = fn args ->
      {_, 0} = System.cmd("git", ["-C", dir, "-c", "user.name=t", "-c", "user.email=t@t" | args])
    end

    file = Path.join(dir, "lib/m.ex")
    unformatted = "defmodule M do\n  def   f(x), do: x\nend\n"
    File.write!(file, unformatted)
    git.(["add", "-A"])
    git.(["commit", "-qm", "m"])

    counting = counting()

    shell = fn cmd ->
      call = %{
        tool_name: "Bash",
        session_id: "t#{System.unique_integer([:positive])}",
        tool_input: %{command: cmd}
      }

      {_, 0} = report(Map.put(call, :hook_event_name, "PreToolUse"), dir, counting)
      backdate_format_mark(call, dir)
      {_, 0} = System.cmd("bash", ["-c", cmd], stderr_to_stdout: true)
      report(Map.put(call, :hook_event_name, "PostToolUse"), dir, counting)
    end

    assert {"", 0} = shell.("cd #{dir} && git worktree add -q #{dir}/wt")
    assert File.read!(Path.join(dir, "wt/lib/m.ex")) == unformatted

    File.write!(file, "defmodule M do\n  def   g(x), do: x\nend\n")
    git.(["stash", "-q"])
    assert {"", 0} = shell.("cd #{dir} && git stash pop -q")
    assert File.read!(file) =~ "def   g(x)"

    assert {"", 0} = shell.("git -C #{dir} checkout -q -- lib")
    assert File.read!(file) == unformatted
    refute_received {:ran, _, _}
  end

  @tag :tmp_dir
  test "format-report formats an edit a shell command made after a git command", %{tmp_dir: dir} do
    # the git in front made the whole command no one's edit, the sed after it included
    host(dir)
    file = Path.join(dir, "lib/m.ex")
    File.write!(file, "defmodule M do\n  def   f(x), do: x\nend\n")
    {_, 0} = System.cmd("git", ["-C", dir, "add", "-A"])

    cmd = "git -C #{dir} checkout -q -b x && sed -i 's/f(x)/g(x)/' #{file}"

    call = %{
      tool_name: "Bash",
      session_id: "t#{System.unique_integer([:positive])}",
      tool_input: %{command: cmd}
    }

    {_, 0} = report(Map.put(call, :hook_event_name, "PreToolUse"), dir)
    backdate_format_mark(call, dir)
    {_, 0} = System.cmd("bash", ["-c", cmd], stderr_to_stdout: true)
    {out, 0} = report(Map.put(call, :hook_event_name, "PostToolUse"), dir)
    assert out =~ "lib/m.ex was reformatted"
    assert File.read!(file) =~ "  def g(x), do: x\n"
  end

  @tag :tmp_dir
  test "format-report runs credo once over the files a call formatted, in a project that lints", %{
    tmp_dir: dir
  } do
    host(dir)
    File.write!(Path.join(dir, "mix.lock"), ~s(%{"credo": {:hex, :credo, "1.7.0"}}\n))

    test = self()

    linting = fn _dir, verb, args ->
      send(test, {:ran, verb, args})

      case verb do
        "format" -> %{ok: true, failures: [], changed: []}
        "credo" -> %{ok: false, failures: [%{kind: "credo", at: "lib/m2.ex:1", message: "a nit"}]}
      end
    end

    call = %{
      tool_name: "Bash",
      session_id: "t#{System.unique_integer([:positive])}",
      tool_input: %{command: "sed"}
    }

    {_, 0} = report(Map.put(call, :hook_event_name, "PreToolUse"), dir, linting)
    backdate_format_mark(call, dir)
    for n <- 1..2, do: File.write!(Path.join(dir, "lib/m#{n}.ex"), "defmodule M#{n} do\nend\n")

    {out, 0} = report(Map.put(call, :hook_event_name, "PostToolUse"), dir, linting)
    assert JSON.decode!(out)["hookSpecificOutput"]["additionalContext"] =~ "  lib/m2.ex:1 a nit"

    assert_received {:ran, "credo", ["--changed", "lib/m1.ex", "lib/m2.ex" | _] = args}
    refute "--strict" in args
    refute_received {:ran, "credo", _}

    # a project that gates with `credo --strict` is linted so at the write too: a check only strict
    # runs (AliasUsage) passed every edit, and failed the gate
    File.write!(
      Path.join(dir, "mix.exs"),
      File.read!(Path.join(dir, "mix.exs")) <> "# precommit: credo --strict\n"
    )

    call = %{call | session_id: "t#{System.unique_integer([:positive])}"}
    {_, 0} = report(Map.put(call, :hook_event_name, "PreToolUse"), dir, linting)
    backdate_format_mark(call, dir)
    File.write!(Path.join(dir, "lib/m3.ex"), "defmodule M3 do\nend\n")
    {_, 0} = report(Map.put(call, :hook_event_name, "PostToolUse"), dir, linting)
    assert_received {:ran, "credo", ["--changed" | _] = args}
    assert "--strict" in args
  end

  @tag :tmp_dir
  test "format-report leaves what git ignores alone: a test run's fixtures are no agent's edit", %{
    tmp_dir: dir
  } do
    # menard's own `run check` wrote broken-on-purpose fixtures under tmp/, and the hook named every
    # one as a file the agent had written and could not format
    host(dir)
    File.write!(Path.join(dir, ".gitignore"), "/tmp/\n")
    # a name git would print quoted and escaped, as menard's own test dirs are (`skipped silently — the`)
    File.mkdir_p!(Path.join(dir, "tmp/a — b"))

    bash = %{
      tool_name: "Bash",
      session_id: "t#{System.unique_integer([:positive])}",
      tool_input: %{command: "mix test"}
    }

    {_, 0} = report(Map.put(bash, :hook_event_name, "PreToolUse"), dir)
    backdate_format_mark(bash, dir)
    File.write!(Path.join(dir, "tmp/a — b/bad.ex"), "defmodule Bad do\n  def f(x, do: x\nend\n")
    File.write!(Path.join(dir, "lib/ok.ex"), "defmodule Ok do\n  def   f(x), do: x\nend\n")

    {out, 0} = report(Map.put(bash, :hook_event_name, "PostToolUse"), dir)
    refute out =~ "bad.ex"
    assert File.read!(Path.join(dir, "lib/ok.ex")) =~ "  def f(x), do: x\n"
  end

  @tag :tmp_dir

  @tag :tmp_dir

  @tag :tmp_dir

  @tag :tmp_dir

  @tag :tmp_dir

  @tag :tmp_dir

  @tag :tmp_dir

  @tag :tmp_dir

  @tag :tmp_dir

  @tag :tmp_dir

  @tag :tmp_dir
  test "format-report with MENARD_HOOK_COMPILE names a compiler warning in the file written", %{tmp_dir: tmp} do
    # a project path with a regex's characters in it: `[x]` matched no path, and every warning dropped
    dir = Path.join(tmp, "p[x]")
    host(dir)
    file = Path.join(dir, "lib/w.ex")
    File.write!(file, "defmodule W do\n  def f(x) do\n    y = 1\n    x\n  end\nend\n")

    input = Path.join(dir, "payload.json")

    File.write!(
      input,
      JSON.encode!(%{
        hook_event_name: "PostToolUse",
        tool_name: "Write",
        cwd: dir,
        tool_input: %{file_path: file}
      })
    )

    {out, 0} =
      System.cmd("bash", ["-c", ~s(bash "$0" < "$1"), Path.join(@root, "hooks/format-report.sh"), input],
        env: [{"CLAUDE_PLUGIN_ROOT", @root}, {"MENARD_HOOK_COMPILE", "1"}]
      )

    assert JSON.decode!(out)["hookSpecificOutput"]["additionalContext"] =~
             ~s(lib/w.ex:3 variable "y" is unused)
  end

  @tag :tmp_dir

  # A host menard can format: a mix.exs and a formatter, nothing fetched
  defp host(dir) do
    File.mkdir_p!(Path.join(dir, "lib"))
    # its own repo: the tmp_dir sits under menard's tmp/, which git ignores
    {_, 0} = System.cmd("git", ["init", "-q", dir])

    File.write!(
      Path.join(dir, "mix.exs"),
      "defmodule Host.MixProject do\n  use Mix.Project\n  def project, do: [app: :host, version: \"0.1.0\"]\nend\n"
    )

    File.write!(Path.join(dir, ".formatter.exs"), "[inputs: [\"lib/**/*.ex\"]]")
  end

  @tag :tmp_dir

  @tag :tmp_dir

  @tag :tmp_dir
  test "format-report leaves a file a merge stopped on alone: git wrote its conflict markers", %{tmp_dir: dir} do
    # a merge (or a stash pop) that stops on a conflict stores the file, markers and all, as a blob
    # before writing it (git 2.55, checked): content the repo holds, so it is not formatted and named
    # back as not parsing. This holds that, against a rule keyed on the index or HEAD instead.
    host(dir)

    git = fn args ->
      System.cmd("git", ["-C", dir, "-c", "user.name=t", "-c", "user.email=t@t" | args],
        stderr_to_stdout: true
      )
    end

    file = Path.join(dir, "lib/m.ex")
    File.write!(file, "defmodule M do\n  def f(x), do: x\nend\n")
    {_, 0} = git.(["add", "-A"])
    {_, 0} = git.(["commit", "-qm", "m"])
    {_, 0} = git.(["checkout", "-qb", "other"])
    File.write!(file, "defmodule M do\n  def f(x), do: x + 1\nend\n")
    {_, 0} = git.(["commit", "-qam", "other"])
    {_, 0} = git.(["checkout", "-q", "-"])
    File.write!(file, "defmodule M do\n  def f(x), do: x + 2\nend\n")
    {_, 0} = git.(["commit", "-qam", "mine"])

    counting = counting()

    cmd = "cd #{dir} && git -c user.name=t -c user.email=t@t merge -q other"

    call = %{
      tool_name: "Bash",
      session_id: "t#{System.unique_integer([:positive])}",
      tool_input: %{command: cmd}
    }

    {_, 0} = report(Map.put(call, :hook_event_name, "PreToolUse"), dir, counting)
    backdate_format_mark(call, dir)
    {_, 1} = System.cmd("bash", ["-c", cmd], stderr_to_stdout: true)

    assert {"", 0} = report(Map.put(call, :hook_event_name, "PostToolUse"), dir, counting)
    assert File.read!(file) =~ "<<<<<<<"
    refute_received {:ran, _, _}
  end

  @tag :tmp_dir

  @tag :tmp_dir

  @tag @tag :tmp_dir
  test "format-report formats what a shell command wrote within the second of its mark", %{tmp_dir: dir} do
    # a stat's time is whole seconds: newer-than-the-mark missed every file a quick command wrote
    host(dir)

    bash = %{
      tool_name: "Bash",
      session_id: "t#{System.unique_integer([:positive])}",
      tool_input: %{command: "printf"}
    }

    {_, 0} = report(Map.put(bash, :hook_event_name, "PreToolUse"), dir, counting())
    file = Path.join(dir, "lib/m.ex")
    File.write!(file, "defmodule M do\n  def   f(x), do: x\nend\n")
    {out, 0} = report(Map.put(bash, :hook_event_name, "PostToolUse"), dir, counting())
    assert out =~ "lib/m.ex was reformatted"
    assert File.read!(file) =~ "  def f(x), do: x\n"
  end

  @tag :tmp_dir
  test "format-report leaves a file the project's formatter inputs do not take as it was written", %{
    tmp_dir: dir
  } do
    # 2026-09-30: another project's tests, written under eval/ as fixtures, came out in menard's style;
    # the project's own `mix format` never takes them
    host(dir)

    bash = %{
      tool_name: "Bash",
      session_id: "t#{System.unique_integer([:positive])}",
      tool_input: %{command: "printf"}
    }

    {_, 0} = report(Map.put(bash, :hook_event_name, "PreToolUse"), dir, counting())
    taken = Path.join(dir, "lib/m.ex")
    File.write!(taken, "defmodule M do\n  def   f(x), do: x\nend\n")
    fixture = Path.join(dir, "eval/hidden/test/a_test.exs")
    File.mkdir_p!(Path.dirname(fixture))
    File.write!(fixture, "defmodule ATest do\n  def   f(x), do: x\nend\n")
    {out, 0} = report(Map.put(bash, :hook_event_name, "PostToolUse"), dir, counting())
    assert out =~ "lib/m.ex was reformatted"
    refute out =~ "a_test.exs"
    assert File.read!(fixture) == "defmodule ATest do\n  def   f(x), do: x\nend\n"
  end

  @tag @tag :tmp_dir

  @tag @tag :tmp_dir
  test "the third Edit of a run is told of edit, once a session; a command between two Edits ends the run", %{
    tmp_dir: dir
  } do
    # desk3: sonnet made 83 Edits in a session, a model call each, and called edit in none
    host(dir)
    file = Path.join(dir, "lib/m.ex")
    File.write!(file, "defmodule M do\n  def f(x), do: x\nend\n")
    session = "t#{System.unique_integer([:positive])}"

    edit = fn tool ->
      call = %{
        hook_event_name: "PostToolUse",
        tool_name: tool,
        session_id: session,
        tool_input: %{file_path: file}
      }

      report(Map.put(call, :tool_use_id, "c#{System.unique_integer([:positive])}"), dir, counting())
    end

    bash = fn ->
      call = %{
        hook_event_name: "PreToolUse",
        tool_name: "Bash",
        session_id: session,
        tool_input: %{command: "ls"}
      }

      {"", 0} = report(Map.put(call, :tool_use_id, "c#{System.unique_integer([:positive])}"), dir, counting())
    end

    # two Edits, a command, two Edits: no run of three
    assert {"", 0} = edit.("Edit")
    assert {"", 0} = edit.("Edit")
    bash.()
    assert {"", 0} = edit.("Edit")
    # a Write is a new file's content, not a replacement: it neither counts nor ends the run
    assert {"", 0} = edit.("Write")
    assert {"", 0} = edit.("Edit")

    {out, 0} = edit.("Edit")
    context = JSON.decode!(out)["hookSpecificOutput"]["additionalContext"]
    assert context =~ "3 Edits in a row"
    assert context =~ "#{@root}/bin/menard edit --then test - <<'EOF'"

    # once: the fourth, and the next run of three, say nothing
    for _ <- 1..5, do: assert({"", 0} = edit.("Edit"))
    # no file of a call's writes is left behind
    assert Path.wildcard(Path.join(dir, "menard-written-*")) == []
  end

  @tag @tag :tmp_dir
  test "every session is told at its start what is refused, and a script is refused before it runs", %{
    tmp_dir: dir
  } do
    host(dir)
    python = "python3 - <<'E'\nopen('lib/m.ex','w').write('x')\nE"

    call = fn event, tool, command ->
      %{
        hook_event_name: event,
        tool_name: tool,
        session_id: "s1",
        tool_use_id: "c1",
        tool_input: %{command: command}
      }
    end

    script = fn name, payload ->
      input = Path.join(dir, "payload-#{System.unique_integer([:positive])}.json")
      File.write!(input, JSON.encode!(Map.put(payload, :cwd, dir)))

      System.cmd("bash", ["-c", ~s(bash "$0" < "$1"), Path.join(@root, "hooks/#{name}"), input],
        env: [{"CLAUDE_PLUGIN_ROOT", @root}, {"TMPDIR", dir}],
        stderr_to_stdout: true
      )
    end

    # there is no setting: a ban that was off by default was one no session met
    {out, 0} = script.("session-start.sh", call.("SessionStart", nil, nil))
    start = JSON.decode!(out)["hookSpecificOutput"]
    assert start["hookEventName"] == "SessionStart"
    assert start["additionalContext"] =~ "There is no python"
    assert start["additionalContext"] =~ "#{@root}/bin/menard edit --then compile"
    assert start["additionalContext"] =~ "#{@root}/bin/menard clause get FILE NAME"

    for command <- [python, "python3 -c 'print(1)'"] do
      {out, 0} = script.("format-report.sh", call.("PreToolUse", "Bash", command))
      refusal = JSON.decode!(out)["hookSpecificOutput"]
      assert refusal["permissionDecision"] == "deny"
      assert refusal["permissionDecisionReason"] =~ "python3 does not run here"
      # a command refused is no command in flight: it left no mark to find files by
      refute File.exists?(Path.join(dir, "menard-format-s1-c1"))
    end
  end

  @tag :tmp_dir
  test "a subagent sent to find a function's calls is refused before it starts, with the find that answers it",
       %{tmp_dir: dir} do
    payload = fn prompt ->
      %{
        "hook_event_name" => "PreToolUse",
        "tool_name" => "Agent",
        "session_id" => "a1",
        "tool_use_id" => "t1",
        "cwd" => dir,
        "tool_input" => %{"subagent_type" => "Explore", "prompt" => prompt}
      }
    end

    search = "Find every reference to Desk.Tickets.transition/2 in lib/ and test/, as file:line."
    assert {:deny, why} = Menard.Hook.run(payload.(search), state_dir: dir)
    assert why =~ "find calls Desk.Tickets.transition lib test"

    assert Menard.Hook.run(payload.("Summarize what this project does"), state_dir: dir) == :quiet
  end

  @tag :tmp_dir
  test "a module read again is answered with what changed since the last read, not read whole", %{
    tmp_dir: dir
  } do
    # desk5's with session read lib/desk/tickets.ex whole six times, 11 rereads in all: each time the
    # file it had, and the few lines that had changed
    file = Path.join(dir, "lib/a.ex")
    File.mkdir_p!(Path.dirname(file))
    lines = for n <- 1..20, do: "  def f#{n}, do: #{n}\n"
    File.write!(file, "defmodule A do\n" <> Enum.join(lines) <> "end\n")

    read = fn event, input ->
      Menard.Hook.run(
        %{
          "hook_event_name" => event,
          "tool_name" => "Read",
          "session_id" => "r1",
          "tool_use_id" => "t#{System.unique_integer([:positive])}",
          "cwd" => dir,
          "tool_input" => Map.merge(%{"file_path" => file}, input)
        },
        state_dir: dir
      )
    end

    # the first read is read
    assert read.("PreToolUse", %{}) == :quiet
    read.("PostToolUse", %{})

    # again, unchanged: nothing to read
    assert {:deny, why} = read.("PreToolUse", %{})
    assert why =~ "lib/a.ex is unchanged since you read it"

    # desk7: shown as a "hook error", the answer was taken for a failure and the Read asked again
    assert why =~ "This is the Read's answer, not an error"

    # changed: read, and what it holds then is what was read (answered with a diff, it was read at
    # once anyway half the time)
    File.write!(file, String.replace(File.read!(file), "def f3, do: 3", "def f3, do: :three"))
    assert read.("PreToolUse", %{}) == :quiet
    read.("PostToolUse", %{})
    assert {:deny, why} = read.("PreToolUse", %{})
    assert why =~ "unchanged since you read it"

    # a part of it is read, as asked
    assert read.("PreToolUse", %{"offset" => 5, "limit" => 3}) == :quiet

    # rewritten past half its lines, the file itself is shorter to read than its diff
    File.write!(file, "defmodule A do\n  def g, do: 1\nend\n")
    assert read.("PreToolUse", %{}) == :quiet

    # not Elixir: read
    other = Path.join(dir, "notes.md")
    File.write!(other, "x\n")
    input = %{"file_path" => other}
    read.("PostToolUse", input)
    assert read.("PreToolUse", input) == :quiet
  end

  @tag :tmp_dir
  test "a module the agent wrote since its read is no news to it: a read again answers unchanged", %{
    tmp_dir: dir
  } do
    # desk7: router.ex, read then edited by the agent, was read again and answered with its own edit as
    # what had changed; what it wrote, and what the formatter did after (reported to it), it knows
    file = Path.join(dir, "lib/r.ex")
    File.mkdir_p!(Path.dirname(file))
    File.write!(file, "defmodule R do\n  def a, do: 1\nend\n")

    hook = fn event, tool, input ->
      Menard.Hook.run(
        %{
          "hook_event_name" => event,
          "tool_name" => tool,
          "session_id" => "k1",
          "tool_use_id" => "t#{System.unique_integer([:positive])}",
          "cwd" => dir,
          "tool_input" => input,
          "tool_response" => %{}
        },
        state_dir: dir,
        run: fn _dir, _verb, _args -> %{ok: true, failures: [], changed: []} end
      )
    end

    hook.("PostToolUse", "Read", %{"file_path" => file})

    # its own Edit
    File.write!(file, "defmodule R do\n  def a, do: 2\nend\n")
    hook.("PostToolUse", "Edit", %{"file_path" => file})
    assert {:deny, why} = hook.("PreToolUse", "Read", %{"file_path" => file})
    assert why =~ "unchanged since you read it"

    # menard's edit, over MCP
    File.write!(file, "defmodule R do\n  def a, do: 3\nend\n")

    hook.("PostToolUse", "mcp__plugin_menard_menard__edit", %{
      "edits" => [%{"file" => "lib/r.ex", "old" => "2", "new" => "3"}]
    })

    assert {:deny, why} = hook.("PreToolUse", "Read", %{"file_path" => file})
    assert why =~ "unchanged since you read it"
  end

  @tag :tmp_dir

  @tag :tmp_dir
  test "the old command-hook wiring run under Claude Code says once to restart it", %{tmp_dir: dir} do
    # 2026-09-30: a session started 09-26 ran the 09-26 wiring for days, with no MCP tools and no Read
    # hook, and nothing said so. Today's wiring calls the MCP server: this script run under Claude Code
    # (CLAUDE_PLUGIN_ROOT) is the old one, and says once to restart
    root = Path.expand(".")

    hook = fn session ->
      payload =
        JSON.encode!(%{
          hook_event_name: "PostToolUse",
          tool_name: "Bash",
          session_id: session,
          cwd: dir,
          tool_input: %{command: "ls"}
        })

      {out, 0} =
        System.cmd("sh", ["-c", ~s(printf '%s' "$P" | bash hooks/format-report.sh)],
          env: [{"P", payload}, {"CLAUDE_PLUGIN_ROOT", root}, {"TMPDIR", dir}],
          cd: root
        )

      out
    end

    session = "stale#{System.unique_integer([:positive])}"
    assert hook.(session) =~ "restart Claude Code"
    refute hook.(session) =~ "restart Claude Code"
  end

  @tag :tmp_dir
  test "the session's start says what is so once, not again on a resume", %{tmp_dir: dir} do
    # Fable 2026-10-01: said again on every resume (49 of 57 fires), and its example's `--then test`
    # was taken on 28 of 37 edits, the suite red mid-change. Reads are no longer refused, and the
    # verbs are there when wanted, not the required path
    start = fn source ->
      Menard.Hook.run(
        %{"hook_event_name" => "SessionStart", "source" => source, "session_id" => "s", "cwd" => dir},
        state_dir: dir
      )
    end

    assert {:context, text} = start.("startup")
    assert text =~ "--then compile"
    refute text =~ "are refused"
    assert {:context, _} = start.("compact")
    assert start.("resume") == :quiet
  end

  @tag :tmp_dir
  test "after a compaction a file read before is read again", %{tmp_dir: dir} do
    # compacted, what was read is out of the context: a Read of it is no reread
    file = Path.join(dir, "lib/c.ex")
    File.mkdir_p!(Path.dirname(file))
    File.write!(file, "defmodule C do\nend\n")

    read = fn event ->
      Menard.Hook.run(
        %{
          "hook_event_name" => event,
          "tool_name" => "Read",
          "session_id" => "c1",
          "cwd" => dir,
          "tool_use_id" => "t#{System.unique_integer([:positive])}",
          "tool_input" => %{"file_path" => file}
        },
        state_dir: dir
      )
    end

    read.("PostToolUse")
    assert {:deny, _} = read.("PreToolUse")

    Menard.Hook.run(
      %{"hook_event_name" => "SessionStart", "source" => "compact", "session_id" => "c1", "cwd" => dir},
      state_dir: dir
    )

    assert read.("PreToolUse") == :quiet
  end

  @tag :tmp_dir
  test "a session's start sweeps menard's files a week old", %{tmp_dir: dir} do
    # Fable 2026-10-01: 7,022 menard-* files in /tmp, 5,054 of them per-session marks, and 378 run-log
    # directories, and nothing swept them. A session's start sweeps what is a week old
    old = System.os_time(:second) - 8 * 24 * 3600
    mark = Path.join(dir, "menard-touched-oldsession")
    recent = Path.join(dir, "menard-touched-thissession")
    File.write!(mark, "")
    File.write!(recent, "")
    File.touch!(mark, old)

    name = "sweep-test-#{System.pid()}-#{System.unique_integer([:positive])}"
    logs = Path.join([System.tmp_dir!(), "menard-run", name <> "-#{System.pid()}"])

    File.mkdir_p!(logs)
    File.write!(Path.join(logs, "x.log"), "")
    File.touch!(Path.join(logs, "x.log"), old)
    File.touch!(logs, old)

    Menard.Hook.run(
      %{"hook_event_name" => "SessionStart", "source" => "startup", "session_id" => "s", "cwd" => dir},
      state_dir: dir
    )

    refute File.exists?(mark)
    assert File.exists?(recent)
    refute File.exists?(logs)
  end

  # the real run verbs, each call sent to the test as `{:ran, verb, args}`
  defp counting do
    test = self()

    fn dir, verb, args ->
      send(test, {:ran, verb, args})
      Menard.Run.result(dir, verb, args)
    end
  end

  defp report(payload, dir, root \\ @root)

  # With a run function in place of a plugin root, the hook runs here, in this process, and answers
  # as its script would: what it formats and lints with is the test's to count or to stub.
  defp report(payload, dir, run) when is_function(run) do
    payload = payload |> Map.put(:cwd, dir) |> JSON.encode!() |> JSON.decode!()

    case Menard.Hook.run(payload, state_dir: dir, run: run) do
      :quiet -> {"", 0}
      {:context, text} -> {JSON.encode!(Menard.Hook.context(text, payload["hook_event_name"])), 0}
      {:problem, text} -> {text, 2}
    end
  end

  defp report(payload, dir, root) do
    input = Path.join(dir, "payload-#{System.unique_integer([:positive])}.json")
    File.write!(input, JSON.encode!(Map.put(payload, :cwd, dir)))

    # paths as arguments, never inside the -c string: a tmp_dir holds the test's name, quotes and all
    System.cmd("bash", ["-c", ~s(bash "$0" < "$1"), Path.join(@root, "hooks/format-report.sh"), input],
      env: [{"CLAUDE_PLUGIN_ROOT", root}, {"TMPDIR", dir}],
      stderr_to_stdout: true
    )
  end

  # the mark a shell command's PreToolUse left, dated back: what the command writes is newer without
  # waiting out find's second
  defp backdate_format_mark(%{session_id: session} = call, dir) do
    mark = "menard-format-#{session}-#{Map.get(call, :tool_use_id, "none")}"
    File.touch!(Path.join(dir, mark), System.os_time(:second) - 10)
  end
end
