defmodule Menard.LangMissingTest do
  # A tool not installed is skipped, and a skip that says nothing reads as a clean file. Not async:
  # no tool on PATH is the whole of the test, and PATH is the VM's.
  use ExUnit.Case, async: false

  @moduletag :tmp_dir

  setup %{tmp_dir: dir} do
    path = System.get_env("PATH")
    System.put_env("PATH", Path.join(dir, "empty"))
    on_exit(fn -> System.put_env("PATH", path) end)
    :ok
  end

  defp written(file, dir, call) do
    payload = %{
      "hook_event_name" => "PostToolUse",
      "tool_name" => "Edit",
      "session_id" => "s1",
      "tool_use_id" => call,
      "cwd" => dir,
      "tool_input" => %{"file_path" => file},
      "tool_response" => %{"filePath" => file}
    }

    Menard.Hook.run(payload, state_dir: dir)
  end

  test "each tool is named", %{tmp_dir: dir} do
    assert Menard.Lang.missing(Path.join(dir, "a.lua"), "x = 1\n") == ~w(luac stylua)
    assert Menard.Lang.missing(Path.join(dir, "a.json"), "{}") == []
  end

  test "a verb's reply says so", %{tmp_dir: dir} do
    File.write!(Path.join(dir, "a.lua"), "x = 1\n")

    assert {:ok, %{changed: [%{skipped: ~w(luac stylua)}]}} =
             Menard.Verbs.call(Menard.Verbs.Edit, %{
               root: dir,
               edits: [%{file: "a.lua", old: "x = 1", new: "x = 2"}]
             })
  end

  test "the hook says so, once a session", %{tmp_dir: dir} do
    file = Path.join(dir, "a.lua")
    File.write!(file, "x = 1\n")

    assert {:context, text} = written(file, dir, "c1")
    assert text =~ "not installed, so skipped on this write: luac, stylua"
    assert written(file, dir, "c2") == :quiet
  end
end
