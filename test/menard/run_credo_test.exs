defmodule Menard.RunCredoTest do
  # `run credo`: the project's credo as `failures` in the one shape, and `--changed` keeping only
  # what an edit brought. A host with credo compiled in is a slow fixture, so these test the two
  # parts that hold the logic; `run credo` over menard itself exercises the whole.
  use ExUnit.Case, async: true

  alias Menard.Run

  test "reads credo's JSON report out of whatever mix printed before it" do
    out = """
    Compiling 2 files (.ex)
    {
      "issues": [
        {"category": "readability", "check": "Credo.Check.Readability.ModuleDoc", "filename": "lib/a.ex",
         "line_no": 1, "message": "Modules should have a @moduledoc tag."}
      ]
    }
    """

    assert {:ok,
            [%{kind: "credo", at: "lib/a.ex:1", message: "Modules should have a @moduledoc tag. (ModuleDoc)"}]} =
             Run.credo_issues(out)

    assert Run.credo_issues("** (Mix) The task \"credo\" could not be found") == :error
  end

  test "reads the report however it is laid out, after output that has braces of its own" do
    # keyed on the bytes `{\n  "issues"`, a report written any other way was "credo gave no report"
    out = """
    Compiling 1 file (.ex)
    {:noisy, "a dep printing a term"}
    {"issues": [{"check": "Credo.Check.Design.TagTODO", "filename": "lib/a.ex", "line_no": 3, "message": "Found a TODO tag."}]}
    """

    assert {:ok, [%{at: "lib/a.ex:3", message: "Found a TODO tag. (TagTODO)"}]} = Run.credo_issues(out)
  end

  @tag :tmp_dir
  test "--changed keeps the issues on lines changed since the last commit, all of an untracked file", %{
    tmp_dir: dir
  } do
    git = fn args -> {_, 0} = System.cmd("git", ["-C", dir | args], stderr_to_stdout: true) end
    git.(["init", "-q"])
    File.write!(Path.join(dir, "a.ex"), "one\ntwo\nthree\nfour\n")
    git.(["add", "a.ex"])
    git.(["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "base"])
    File.write!(Path.join(dir, "a.ex"), "one\nTWO\nthree\nfour\nfive\n")
    File.write!(Path.join(dir, "new.ex"), "x\n")

    issues = for at <- ~w(a.ex:1 a.ex:2 a.ex:4 a.ex:5 new.ex:1), do: %{kind: "credo", message: "m", at: at}

    assert Enum.map(Run.only_changed(issues, dir), & &1.at) == ~w(a.ex:2 a.ex:5 new.ex:1)
  end
end
