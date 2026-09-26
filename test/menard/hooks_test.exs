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

  test "shell-edits hears a failed command too: PostToolUse does not run when the tool fails" do
    # a shell command that edits a module and then runs a failing test (the usual edit-then-test)
    # fires PostToolUseFailure, not PostToolUse, so a hook on the latter never heard of the edit
    # (found in the eval: arm H's shell hook, 2026-09-25)
    hooks = @root |> Path.join("hooks/hooks.json") |> File.read!() |> JSON.decode!()

    scripts = fn event ->
      for %{"matcher" => "Bash", "hooks" => list} <- hooks["hooks"][event] || [],
          %{"command" => cmd} <- list,
          do: cmd
    end

    assert Enum.any?(scripts.("PostToolUse"), &(&1 =~ "shell-edits.sh"))
    assert Enum.any?(scripts.("PostToolUseFailure"), &(&1 =~ "shell-edits.sh"))
  end
end
