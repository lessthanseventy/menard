defmodule Menard.RunCommittedTest do
  # `run … --committed`: the last commit, in a worktree menard keeps, so a run does not read a
  # working tree that is being edited under it.
  use ExUnit.Case, async: true

  alias Menard.Run.Committed
  alias Menard.Verbs.Run

  @moduletag :tmp_dir

  defp git(dir, args) do
    env = [{"GIT_CONFIG_GLOBAL", "/dev/null"}, {"GIT_CONFIG_SYSTEM", "/dev/null"}]
    who = ["-c", "user.name=t", "-c", "user.email=t@t", "-c", "commit.gpgsign=false"]
    {out, 0} = System.cmd("git", ["-C", dir | who ++ args], stderr_to_stdout: true, env: env)
    out
  end

  defp repo(dir) do
    root = Path.join(dir, "shop")
    File.mkdir_p!(Path.join(root, "lib"))
    File.mkdir_p!(Path.join(root, "deps/dep"))
    File.write!(Path.join(root, ".gitignore"), "/deps/\n/_build/\n")
    File.write!(Path.join(root, "lib/a.ex"), "one\n")
    git(root, ["init", "-q"])
    git(root, ["add", "."])
    git(root, ["commit", "-qm", "one"])
    root
  end

  test "the worktree holds the last commit, not the edit under way, and follows the next commit", %{
    tmp_dir: dir
  } do
    root = repo(dir)
    kept = Path.join(dir, "kept")
    File.write!(Path.join(root, "lib/a.ex"), "edited\n")

    assert {:ok, %{dir: at, sha: sha, uncommitted: 1}} = Committed.at_head(root, kept)
    assert String.starts_with?(at, kept)
    assert sha == root |> git(["rev-parse", "--short", "HEAD"]) |> String.trim()
    assert File.read!(Path.join(at, "lib/a.ex")) == "one\n"
    # the project's dependencies, fetched once, are the worktree's too
    assert File.dir?(Path.join(at, "deps/dep"))

    # what a run left behind in it does not outlive the run
    File.write!(Path.join(at, "lib/a.ex"), "formatted by a check\n")
    git(root, ["commit", "-qam", "two"])

    assert {:ok, %{dir: ^at, sha: next, uncommitted: 0}} = Committed.at_head(root, kept)
    assert next != sha
    assert File.read!(Path.join(at, "lib/a.ex")) == "edited\n"
  end

  test "a project below its repository's root is run at its own path in the worktree", %{tmp_dir: dir} do
    root = repo(dir)

    assert {:ok, %{dir: at}} = Committed.at_head(Path.join(root, "lib"), Path.join(dir, "kept"))
    assert Path.basename(at) == "lib"
    assert File.read!(Path.join(at, "a.ex")) == "one\n"
  end

  test "a verb that writes the working tree, or reads its changes, is not run on a commit", %{tmp_dir: dir} do
    for verb <- ~w(format credo) do
      assert {:error, why} = Run.run(%{verb: verb, dir: dir, committed: true})
      assert why =~ "--committed is for check, test and compile"
    end
  end

  test "outside git there is no commit to run", %{tmp_dir: dir} do
    # the test's own directory is inside menard's repository
    bare = Path.join(System.tmp_dir!(), "menard-test-committed-#{System.pid()}")
    File.mkdir_p!(bare)
    on_exit(fn -> File.rm_rf!(bare) end)

    assert {:error, "--committed runs the last commit" <> _} = Committed.at_head(bare, Path.join(dir, "kept"))
  end
end
