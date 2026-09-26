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
  test "format-elixir formats a file in a host whose mix.exs does not parse", %{tmp_dir: dir} do
    File.write!(Path.join(dir, "mix.exs"), "defmodule Broken do\n  this does not parse (\n")
    File.write!(Path.join(dir, ".formatter.exs"), "[inputs: [\"*.ex\"]]")
    file = Path.join(dir, "messy.ex")
    File.write!(file, "defmodule M do\n  def   go, do: 1\nend\n")
    input = Path.join(dir, "payload.json")
    File.write!(input, JSON.encode!(%{tool_name: "Write", tool_input: %{file_path: file}}))

    System.cmd("bash", ["-c", "bash #{@root}/hooks/format-elixir.sh < #{input}"],
      env: [{"CLAUDE_PLUGIN_ROOT", @root}],
      stderr_to_stdout: true
    )

    assert File.read!(file) =~ "def go, do: 1"
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

      System.cmd("bash", ["-c", "bash #{@root}/hooks/shell-edits.sh < #{input}"], stderr_to_stdout: true)
    end

    # a command that changes a module
    {_, 0} = hook.("PreToolUse", "sed -i s/A/B/ lib/a.ex")
    Process.sleep(1100)
    File.write!(module, "defmodule B do\nend\n")
    assert {out, 2} = hook.("PostToolUse", "sed -i s/A/B/ lib/a.ex")
    assert out =~ "lib/a.ex"
    assert out =~ "run"

    # one that changes nothing
    {_, 0} = hook.("PreToolUse", "ls")
    assert {_, 0} = hook.("PostToolUse", "ls")

    # menard's own door, and the formatter, rewrite modules by design
    {_, 0} = hook.("PreToolUse", "mix format")
    Process.sleep(1100)
    File.write!(module, "defmodule C do\nend\n")
    assert {_, 0} = hook.("PostToolUse", "mix format")
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
    Process.sleep(1100)

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
    Process.sleep(1100)
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
    File.write!(Path.join(dir, "lib/n.ex"), "defmodule N do\n  def big, do: 999999\nend\n")
    File.write!(Path.join(dir, "menard-touched-s1"), dir <> "\n")

    {out, 0} = stop(%{hook_event_name: "Stop", session_id: "s1"}, dir)
    reply = JSON.decode!(out)
    assert reply["decision"] == "block"
    assert reply["reason"] =~ "lib/n.ex"

    File.write!(Path.join(dir, "lib/n.ex"), "defmodule N do\n  def big, do: 999_999\nend\n")
    assert {"", 0} = stop(%{hook_event_name: "Stop", session_id: "s1"}, dir)
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

  defp stop(payload, dir) do
    input = Path.join(dir, "payload-#{System.unique_integer([:positive])}.json")
    File.write!(input, JSON.encode!(Map.put(payload, :cwd, dir)))

    System.cmd("bash", ["-c", ~s(bash "$0" < "$1"), Path.join(@root, "hooks/stop-gate.sh"), input],
      env: [{"CLAUDE_PLUGIN_ROOT", @root}, {"TMPDIR", dir}]
    )
  end

  defp report(payload, dir) do
    input = Path.join(dir, "payload-#{System.unique_integer([:positive])}.json")
    File.write!(input, JSON.encode!(Map.put(payload, :cwd, dir)))

    # paths as arguments, never inside the -c string: a tmp_dir holds the test's name, quotes and all
    System.cmd("bash", ["-c", ~s(bash "$0" < "$1"), Path.join(@root, "hooks/format-report.sh"), input],
      env: [{"CLAUDE_PLUGIN_ROOT", @root}],
      stderr_to_stdout: true
    )
  end
end
