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
end
