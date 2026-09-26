defmodule Menard.HooksTest do
  use ExUnit.Case, async: true

  @root Path.expand("../..", __DIR__)
  # a stub menard's red reply (stub_menard/3)
  @red ~s(echo '{"ok":false,"failures":[{"kind":"test","at":"t.exs:1","message":"red"}]}')

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

  # Installed as a plugin, menard is reachable through CLAUDE_PLUGIN_ROOT, not a repo layout or PATH.
  test "prefer-menard-run fires for a bare mix test when menard is only reachable as the plugin" do
    path =
      "PATH"
      |> System.get_env()
      |> String.split(":")
      |> Enum.reject(&File.exists?(Path.join(&1, "menard")))
      |> Enum.join(":")

    payload = JSON.encode!(%{tool_name: "Bash", tool_input: %{command: "mix test"}})
    tmp = Path.join(System.tmp_dir!(), "menard-hooks-#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    input = Path.join(tmp, "payload.json")
    File.write!(input, payload)

    {_out, status} =
      System.cmd("bash", ["-c", "bash #{@root}/hooks/prefer-menard-run.sh < #{input}"],
        env: [{"PATH", path}, {"CLAUDE_PLUGIN_ROOT", @root}, {"CLAUDE_PROJECT_DIR", tmp}],
        stderr_to_stdout: true
      )

    assert status == 2
  end

  @tag :tmp_dir
  test "menard-only blocks an Edit on a module through the guard verb, and passes the rest", %{tmp_dir: dir} do
    module = Path.join(dir, "a.ex")
    File.write!(module, "defmodule A do\nend\n")
    notes = Path.join(dir, "notes.md")
    File.write!(notes, "hi\n")

    run = fn file ->
      input = Path.join(dir, "payload.json")
      File.write!(input, JSON.encode!(%{tool_name: "Edit", tool_input: %{file_path: file}}))

      System.cmd("bash", ["-c", "bash #{@root}/hooks/menard-only.sh < #{input}"],
        env: [{"CLAUDE_PLUGIN_ROOT", @root}],
        stderr_to_stdout: true
      )
    end

    assert {out, 2} = run.(module)
    # the plugin's MCP tools by name: CLI lines sent blocked agents to Bash
    assert out =~ "mcp__plugin_menard_menard__clause"
    assert {_, 0} = run.(notes)
  end

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

    scripts = fn event ->
      for %{"matcher" => "Bash", "hooks" => list} <- hooks["hooks"][event] || [],
          %{"command" => cmd} <- list,
          do: cmd
    end

    for event <- ["PreToolUse", "PostToolUse", "PostToolUseFailure"],
        do:
          assert(
            Enum.any?(scripts.(event), &(&1 =~ "format-report.sh")),
            "#{event} on Bash runs no format-report"
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
  test "stop-gate refuses the stop while a project the session wrote into is red, and says why", %{
    tmp_dir: dir
  } do
    # agents told CI runs precommit ran it in 0 of 6 sessions (focus1): the gate runs at the stop
    host(dir)
    File.mkdir_p!(Path.join(dir, "test"))
    File.write!(Path.join(dir, "test/test_helper.exs"), "ExUnit.start()\n")
    File.write!(Path.join(dir, "lib/n.ex"), "defmodule N do\n  def f(x) do\n    y = 1\n    x\n  end\nend\n")
    File.write!(Path.join(dir, "menard-touched-s1"), dir <> "\n")

    {out, 0} = stop(%{hook_event_name: "Stop", session_id: "s1"}, dir)
    reply = JSON.decode!(out)
    assert reply["decision"] == "block"
    assert reply["reason"] =~ "lib/n.ex"

    File.write!(Path.join(dir, "lib/n.ex"), "defmodule N do\n  def f(x), do: x\nend\n")
    assert {"", 0} = stop(%{hook_event_name: "Stop", session_id: "s1"}, dir)
  end

  @tag :tmp_dir
  test "stop-gate runs the tests the change made stale, not the suite", %{tmp_dir: dir} do
    host(dir)
    File.mkdir_p!(Path.join(dir, "test"))
    File.write!(Path.join(dir, "test/test_helper.exs"), "ExUnit.start()\n")
    File.write!(Path.join(dir, "lib/n.ex"), "defmodule N do\n  def f, do: 1\nend\n")
    File.write!(Path.join(dir, "lib/o.ex"), "defmodule O do\n  def g, do: 1\nend\n")

    File.write!(
      Path.join(dir, "test/n_test.exs"),
      "defmodule NTest do\n  use ExUnit.Case\n  test \"f\", do: assert(N.f() == 1)\nend\n"
    )

    # red by a file no module depends on, so no change makes it stale: a suite run would refuse the stop
    File.write!(
      Path.join(dir, "test/o_test.exs"),
      "defmodule OTest do\n  use ExUnit.Case\n  test \"g\", do: refute(File.exists?(\"red\"))\nend\n"
    )

    # mix tells stale by mtime, to the second: sources older than the build, the build older than
    # the edit, with no wait for the clock
    now = System.os_time(:second)

    backdate = fn glob, t ->
      for f <- Path.wildcard(Path.join(dir, glob), match_dot: true), do: File.touch!(f, t)
    end

    backdate.("**", now - 20)

    # green once: mix records what is fresh only after a green `--stale` run
    {_, 0} = System.cmd("mix", ["test", "--stale"], cd: dir, stderr_to_stdout: true)
    backdate.("_build/**", now - 10)
    File.write!(Path.join(dir, "red"), "")

    File.write!(Path.join(dir, "lib/n.ex"), "defmodule N do\n  def f, do: 2\nend\n")
    File.write!(Path.join(dir, "menard-touched-s3"), dir <> "\n")
    {out, 0} = stop(%{hook_event_name: "Stop", session_id: "s3"}, dir)
    reason = JSON.decode!(out)["reason"]
    assert reason =~ "test/n_test.exs"
    refute reason =~ "test/o_test.exs"
  end

  @tag :tmp_dir
  test "stop-gate passes a stop with nothing written since it was last green", %{tmp_dir: dir} do
    host(dir)
    File.write!(Path.join(dir, "lib/n.ex"), "defmodule N do\n  def f(x), do: x\nend\n")
    File.write!(Path.join(dir, "menard-touched-s4"), dir <> "\n")
    assert {"", 0} = stop(%{hook_event_name: "Stop", session_id: "s4"}, dir)

    # red now, but not by a write this session made since: the gate already passed it
    File.write!(Path.join(dir, "lib/n.ex"), "defmodule N do\n  def f(x) do\n    y = 1\n    x\n  end\nend\n")
    assert {"", 0} = stop(%{hook_event_name: "Stop", session_id: "s4"}, dir)

    File.write!(Path.join(dir, "menard-touched-s4"), dir <> "\n" <> dir <> "\n")
    {out, 0} = stop(%{hook_event_name: "Stop", session_id: "s4"}, dir)
    assert JSON.decode!(out)["decision"] == "block"
  end

  @tag :tmp_dir
  test "commit-gate refuses a git commit while a project the session wrote into fails its whole gate", %{
    tmp_dir: dir
  } do
    host(dir)
    File.mkdir_p!(Path.join(dir, "test"))
    File.write!(Path.join(dir, "test/test_helper.exs"), "ExUnit.start()\n")
    File.write!(Path.join(dir, "lib/n.ex"), "defmodule N do\n  def f, do: 1\nend\n")

    File.write!(
      Path.join(dir, "test/o_test.exs"),
      "defmodule OTest do\n  use ExUnit.Case\n  test \"g\", do: assert(N.f() == 2)\nend\n"
    )

    File.write!(Path.join(dir, "menard-touched-c1"), dir <> "\n")

    commit = %{hook_event_name: "PreToolUse", tool_name: "Bash", session_id: "c1"}
    {out, 0} = commit_gate(put_in(commit[:tool_input], %{command: "git add -A && git commit -qm wip"}), dir)
    denied = JSON.decode!(out)["hookSpecificOutput"]
    assert denied["permissionDecision"] == "deny"
    assert denied["permissionDecisionReason"] =~ "test/o_test.exs"

    assert {"", 0} = commit_gate(put_in(commit[:tool_input], %{command: "git log --grep=commit"}), dir)

    assert {"", 0} =
             commit_gate(
               Map.merge(commit, %{session_id: "c2", tool_input: %{command: "git commit -m x"}}),
               dir
             )

    File.write!(
      Path.join(dir, "test/o_test.exs"),
      "defmodule OTest do\n  use ExUnit.Case\n  test \"g\", do: assert(N.f() == 1)\nend\n"
    )

    assert {"", 0} = commit_gate(put_in(commit[:tool_input], %{command: "git commit -m x"}), dir)
  end

  @tag :tmp_dir
  test "commit-gate knows a git commit behind git's global options, a shell keyword or a wrapper", %{
    tmp_dir: dir
  } do
    host(dir)
    File.mkdir_p!(Path.join(dir, "my dir"))
    File.write!(Path.join(dir, "menard-touched-c4"), dir <> "\n")
    red = stub_menard(dir, "red", @red)
    gate = fn cmd -> commit_gate(%{session_id: "c4", tool_input: %{command: cmd}}, dir, red) end

    for cmd <- [
          ~s(git -C "my dir" commit -m x),
          "git --no-pager commit -m x",
          "git --git-dir=.git commit -m x",
          "git -c user.name=x commit -m x",
          "if true; then git commit -m x; fi",
          "env A=1 git commit -m x",
          "time git commit -m x",
          ~s(bash -c "git commit -m x"),
          "/usr/bin/git commit -m x"
        ] do
      {out, 0} = gate.(cmd)
      assert out =~ ~s("deny"), "not gated: #{cmd}"
    end

    for cmd <- ["git log --grep=commit", "git commit-tree HEAD^{tree}", "legit commit"],
        do: assert({"", 0} = gate.(cmd))
  end

  @tag :tmp_dir
  test "commit-gate gates the projects of the repo the commit lands in, not every one written into", %{
    tmp_dir: dir
  } do
    [one, two] = for name <- ["one", "two"], do: Path.join(dir, name)
    host(one)
    host(two)
    File.write!(Path.join(dir, "menard-touched-c5"), one <> "\n")
    red = stub_menard(dir, "red", @red)

    gate = fn cwd, cmd ->
      commit_gate(%{session_id: "c5", cwd: cwd, tool_input: %{command: cmd}}, dir, red)
    end

    assert {"", 0} = gate.(two, "git commit -m x")
    assert {"", 0} = gate.(dir, "git -C two commit -m x")
    assert {out, 0} = gate.(one, "git commit -m x")
    assert out =~ ~s("deny")
    assert {out, 0} = gate.(two, "git -C ../one commit -m x")
    assert out =~ ~s("deny")
  end

  @tag :tmp_dir
  test "the gates read ok from menard's reply, not from a stderr line that says it", %{tmp_dir: dir} do
    host(dir)
    File.write!(Path.join(dir, "menard-touched-g1"), dir <> "\n")
    liar = stub_menard(dir, "liar", @red <> ~s(\necho 'building: {"ok":true}' >&2))
    refused = stub_menard(dir, "refused", "echo 'menard: no such verb' >&2\nexit 1")

    {out, 0} = stop(%{hook_event_name: "Stop", session_id: "g1"}, dir, liar)
    assert JSON.decode!(out)["reason"] =~ "t.exs:1 red"

    commit = %{session_id: "g1", tool_input: %{command: "git commit -m x"}}
    {out, 0} = commit_gate(commit, dir, liar)
    assert JSON.decode!(out)["hookSpecificOutput"]["permissionDecisionReason"] =~ "t.exs:1 red"

    # no reply at all: menard's own error is the reason
    {out, 0} = commit_gate(commit, dir, refused)
    assert JSON.decode!(out)["hookSpecificOutput"]["permissionDecisionReason"] =~ "menard: no such verb"
  end

  @tag :tmp_dir
  test "the gates block, and say so, when menard does not answer by their deadline", %{tmp_dir: dir} do
    # a hook the harness kills fails open, and its mix test outlives it: the gates keep their own
    # deadline under `timeout`, whose 124 this stub answers with
    host(dir)
    File.write!(Path.join(dir, "menard-touched-g2"), dir <> "\n")
    slow = stub_menard(dir, "slow", "exit 124")

    {out, 0} = stop(%{hook_event_name: "Stop", session_id: "g2"}, dir, slow)
    assert JSON.decode!(out)["reason"] =~ "no answer within 280s"

    {out, 0} = commit_gate(%{session_id: "g2", tool_input: %{command: "git commit -m x"}}, dir, slow)
    assert JSON.decode!(out)["hookSpecificOutput"]["permissionDecisionReason"] =~ "no answer within 280s"
  end

  @tag :tmp_dir
  test "stop-gate lets a session end that wrote nothing, or was refused three times", %{tmp_dir: dir} do
    assert {"", 0} = stop(%{hook_event_name: "Stop", session_id: "none-written"}, dir)

    host(dir)
    File.write!(Path.join(dir, "lib/n.ex"), "defmodule N do\n  def big, do: 999999\nend\n")
    File.write!(Path.join(dir, "menard-touched-s2"), dir <> "\n")
    File.write!(Path.join(dir, "menard-stop-blocks-s2"), "3")
    assert {"", 0} = stop(%{hook_event_name: "Stop", session_id: "s2"}, dir)
  end

  @tag :tmp_dir
  test "stop-gate clears its refusals on green, and gates again after it let a saturated stop through", %{
    tmp_dir: dir
  } do
    # three early refusals switched the gate off for the rest of a multi-step session (the all arm)
    red = stub_menard(dir, "red", @red)
    green = stub_menard(dir, "green", ~s(echo '{"ok":true}'))
    touched = Path.join(dir, "menard-touched-s5")
    blocks = Path.join(dir, "menard-stop-blocks-s5")

    File.write!(touched, dir <> "\n")
    File.write!(blocks, "2")
    assert {"", 0} = stop(%{hook_event_name: "Stop", session_id: "s5"}, dir, green)
    refute File.exists?(blocks)

    File.write!(touched, dir <> "\n" <> dir <> "\n")
    File.write!(blocks, "3")
    assert {"", 0} = stop(%{hook_event_name: "Stop", session_id: "s5"}, dir, red)
    {out, 0} = stop(%{hook_event_name: "Stop", session_id: "s5"}, dir, red)
    assert JSON.decode!(out)["decision"] == "block"
  end

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
  test "big-read answers a whole read of a big Elixir file with its outline, once", %{tmp_dir: dir} do
    file = Path.join(dir, "big.ex")
    defs = Enum.map_join(1..300, "\n", &"  def f#{&1}(x) do\n    x\n  end\n")
    File.write!(file, "defmodule Big do\n" <> defs <> "end\n")
    run = fn input -> bigread(Map.merge(%{session_id: "b1", tool_input: %{file_path: file}}, input), dir) end

    reason = JSON.decode!(run.(%{}))["hookSpecificOutput"]["permissionDecisionReason"]
    assert reason =~ "def f150/1"
    assert reason =~ "offset and limit"
    # the second whole read, and any read by range, go through
    assert run.(%{}) == ""
    assert bigread(%{session_id: "b2", tool_input: %{file_path: file, offset: 10}}, dir) == ""
  end

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
  test "commit-gate does not run the gate again over the very files a green run check passed", %{tmp_dir: dir} do
    # focus3: the agent ran the gate, green, and committed; the hook ran the whole gate again
    host(dir)
    # the hook's own files (its TMPDIR is this dir here) are no part of the project
    File.write!(Path.join(dir, ".gitignore"), "/_build/\n/menard-*\n/payload-*\n")
    File.mkdir_p!(Path.join(dir, "test"))
    File.write!(Path.join(dir, "test/test_helper.exs"), "ExUnit.start()\n")
    File.write!(Path.join(dir, "lib/n.ex"), "defmodule N do\n  def f, do: 1\nend\n")
    File.write!(Path.join(dir, "menard-touched-c3"), dir <> "\n")
    assert %{ok: true} = Menard.Run.result(dir, "check", [])

    commit = %{
      hook_event_name: "PreToolUse",
      tool_name: "Bash",
      session_id: "c3",
      tool_input: %{command: "git commit -m x"}
    }

    gate_runs = fn -> Path.wildcard(Path.join(dir, "menard-run/**/*.log")) end

    assert {"", 0} = commit_gate(commit, dir)
    assert gate_runs.() == []
    assert gate_err(dir) == "commit gate: skipped, files already green\n"

    File.write!(Path.join(dir, "lib/n.ex"), "defmodule N do\n  def f, do: 2\nend\n")
    assert {"", 0} = commit_gate(commit, dir)
    assert gate_runs.() != []
  end

  @tag :tmp_dir
  test "the gates leave one stderr line on every outcome, with timings, and nothing for the model", %{
    tmp_dir: dir
  } do
    # a green gate was indistinguishable from one that never ran in the trace
    host(dir)
    green = stub_menard(dir, "green", ~s(echo '{"ok":true}'))
    red = stub_menard(dir, "red", @red)
    stop = fn root -> stop(%{hook_event_name: "Stop", session_id: "g3"}, dir, root) end

    assert {"", 0} = stop.(green)
    assert gate_err(dir) == "stop gate: nothing written this session\n"

    File.write!(Path.join(dir, "menard-touched-g3"), dir <> "\n")
    assert {"", 0} = stop.(green)

    assert gate_err(dir) =~
             ~r/\Astop gate: green in \d+s \(compile \d+s, credo --changed \d+s, test --stale \d+s\)\n\z/

    assert {"", 0} = stop.(green)
    assert gate_err(dir) == "stop gate: nothing new since green\n"

    File.write!(Path.join(dir, "menard-touched-g3"), dir <> "\n" <> dir <> "\n")
    {out, 0} = stop.(red)
    assert JSON.decode!(out)["decision"] == "block"
    assert gate_err(dir) =~ ~r/\Astop gate: red in \d+s \(compile \d+s\), refusal 1 of 3\n\z/

    File.write!(Path.join(dir, "menard-stop-blocks-g3"), "3")
    assert {"", 0} = stop.(red)
    assert gate_err(dir) == "stop gate: let through after 3 refusals\n"

    commit = fn cmd, session ->
      commit_gate(%{session_id: session, tool_input: %{command: cmd}}, dir, green)
    end

    assert {"", 0} = commit.("git commit -m x", "g3")
    assert gate_err(dir) =~ ~r/\Acommit gate: green in \d+s\n\z/
    assert {"", 0} = commit.("git commit -m x", "none")
    assert gate_err(dir) == "commit gate: nothing written this session\n"
    # not a commit: no gate, no line
    assert {"", 0} = commit.("git status", "g3")
    assert gate_err(dir) == ""
  end

  defp bigread(payload, dir) do
    input = Path.join(dir, "payload-#{System.unique_integer([:positive])}.json")
    File.write!(input, JSON.encode!(payload))

    {out, 0} =
      System.cmd("bash", ["-c", ~s(bash "$0" < "$1"), Path.join(@root, "hooks/big-read.sh"), input],
        env: [{"CLAUDE_PLUGIN_ROOT", @root}, {"TMPDIR", dir}]
      )

    out
  end

  # A plugin root whose menard answers what the test says: the gates' own logic, without a real suite
  defp stub_menard(dir, name, body) do
    bin = Path.join([dir, name, "bin/menard"])
    File.mkdir_p!(Path.dirname(bin))
    File.write!(bin, "#!/usr/bin/env bash\n" <> body <> "\n")
    File.chmod!(bin, 0o755)
    Path.join(dir, name)
  end

  # a gate's stdout and exit status, as the harness reads them; its stderr, which the harness keeps
  # in the trace and does not give the model, is in gate_err/1
  defp stop(payload, dir, root \\ @root) do
    input = Path.join(dir, "payload-#{System.unique_integer([:positive])}.json")
    File.write!(input, JSON.encode!(Map.put(payload, :cwd, dir)))

    System.cmd(
      "bash",
      ["-c", ~s(bash "$0" < "$1" 2>"$2"), Path.join(@root, "hooks/stop-gate.sh"), input, gate_err_file(dir)],
      env: [{"CLAUDE_PLUGIN_ROOT", root}, {"TMPDIR", dir}]
    )
  end

  defp commit_gate(payload, dir, root \\ @root) do
    input = Path.join(dir, "payload-#{System.unique_integer([:positive])}.json")
    File.write!(input, JSON.encode!(Map.put_new(payload, :cwd, dir)))

    System.cmd(
      "bash",
      [
        "-c",
        ~s(bash "$0" < "$1" 2>"$2"),
        Path.join(@root, "hooks/commit-gate.sh"),
        input,
        gate_err_file(dir)
      ],
      env: [{"CLAUDE_PLUGIN_ROOT", root}, {"TMPDIR", dir}]
    )
  end

  defp gate_err_file(dir), do: Path.join(dir, "menard-gate.err")
  defp gate_err(dir), do: File.read!(gate_err_file(dir))

  defp report(payload, dir) do
    input = Path.join(dir, "payload-#{System.unique_integer([:positive])}.json")
    File.write!(input, JSON.encode!(Map.put(payload, :cwd, dir)))

    # paths as arguments, never inside the -c string: a tmp_dir holds the test's name, quotes and all
    System.cmd("bash", ["-c", ~s(bash "$0" < "$1"), Path.join(@root, "hooks/format-report.sh"), input],
      env: [{"CLAUDE_PLUGIN_ROOT", @root}, {"TMPDIR", dir}],
      stderr_to_stdout: true
    )
  end

  # the mark a shell command's PreToolUse left, dated back: what the command writes is newer without
  # waiting out find's second
  defp backdate_format_mark(%{session_id: session}, dir),
    do: File.touch!(Path.join(dir, "menard-format-#{session}"), System.os_time(:second) - 10)
end
