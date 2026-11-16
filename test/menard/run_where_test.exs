defmodule Menard.RunWhereTest do
  use ExUnit.Case, async: true

  alias Menard.Test.Host
  alias Menard.Verbs.Run

  @moduletag :tmp_dir

  defp repo(dir) do
    root = Path.join(dir, "shop")
    demo = Path.join(root, "demo")
    File.mkdir_p!(Path.join(demo, ".mise/tasks"))
    Host.mix_project(root, :where_shop)
    task = Path.join(demo, ".mise/tasks/check")
    File.write!(task, "#!/bin/sh\ntrue\n")
    File.chmod!(task, 0o755)
    {_, 0} = System.cmd("git", ["-C", root, "init", "-q"])
    {root, demo}
  end

  test "a run says which directory of its repository it ran in", %{tmp_dir: dir} do
    {root, _demo} = repo(dir)

    assert {:ok, %{ok: true, dir: "."} = r} = Run.run(%{verb: "compile", dir: root})
    refute Map.has_key?(r, :outer)
  end

  test "a project nested in a repository whose root is a mix project says so", %{tmp_dir: dir} do
    {_root, demo} = repo(dir)

    assert {:ok, %{ok: true, dir: "demo", outer: "."}} = Run.run(%{verb: "check", dir: demo})
  end

  test "outside git, the directory is said whole" do
    bare = Path.join(System.tmp_dir!(), "menard-where-#{System.pid()}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(bare)
    on_exit(fn -> File.rm_rf!(bare) end)
    Host.mix_project(bare, :where_bare)

    assert {:ok, %{ok: true, dir: ^bare}} = Run.run(%{verb: "compile", dir: bare})
  end
end
