defmodule Menard.ModTest do
  # The plugin's hooks module (hooks/register.tsx): the rows a folded run of menard calls is drawn
  # as. Its tests are Claude Code's to run (`claude plugin test`), which takes every *.test.ts
  # under the folder it is given: the pi extension's and each test's scratch copy of this checkout
  # among them. So they run on a copy of the plugin's own two folders.
  use ExUnit.Case, async: true

  alias Menard.Verbs.Help

  @root Path.expand("../..", __DIR__)
  @moduletag :tmp_dir

  if System.find_executable("claude") == nil, do: @moduletag(skip: "no claude on the PATH")

  test "the hooks module's tests pass, and the plugin validates with it", %{tmp_dir: dir} do
    for part <- ~w(.claude-plugin/plugin.json hooks) do
      File.mkdir_p!(Path.dirname(Path.join(dir, part)))
      File.cp_r!(Path.join(@root, part), Path.join(dir, part))
    end

    assert {out, 0} = System.cmd("claude", ["plugin", "test", dir], stderr_to_stdout: true)
    assert out =~ " 0 fail"
    assert {out, 0} = System.cmd("claude", ["plugin", "validate", dir], stderr_to_stdout: true)
    assert out =~ "./register.tsx hooks: ui.render{component=ToolUse}"
  end

  test "the module knows a shell call by menard's verbs, every one the help names" do
    said = File.read!(Path.join(@root, "hooks/said.ts"))
    assert said =~ "export const VERBS = '#{Enum.join(Help.verbs(), " ")}'"
  end
end
