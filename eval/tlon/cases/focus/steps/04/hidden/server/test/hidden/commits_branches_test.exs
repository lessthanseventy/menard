defmodule Hidden.CommitsBranchesTest do
  use ExUnit.Case, async: false

  alias Server.Commits

  test "a thread's commits on its work branch count while main is checked out" do
    tmp = Path.join(System.tmp_dir!(), "hidden-commits-#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)

    git = fn args ->
      {_, 0} = System.cmd("git", ["-C", tmp, "-c", "core.hooksPath=/dev/null" | args], stderr_to_stdout: true)
    end

    git.(["init", "-q", "-b", "main"])
    git.(["config", "user.email", "t@t"])
    git.(["config", "user.name", "t"])
    File.write!(Path.join(tmp, "seed"), "seed\n")
    git.(["add", "seed"])
    git.(["commit", "-qm", "seed"])
    git.(["checkout", "-qb", "work/t5"])
    File.write!(Path.join(tmp, "a"), "a\n")
    git.(["add", "a"])
    git.(["commit", "-qm", "coworker change\n\nTlon-Thread: 5"])
    git.(["checkout", "-q", "main"])

    assert {:ok, [%{subject: "coworker change"}]} = Commits.list(tmp, 5)
  end
end
