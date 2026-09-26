defmodule Menard.OnPathTest do
  # `menard` on PATH is scripts/menard-on-path: inside a menard checkout it runs that checkout's
  # bin/menard (a worktree's own code), anywhere else the checkout it was installed from.
  use ExUnit.Case, async: true

  @shim Path.expand("../../scripts/menard-on-path", __DIR__)

  defp git_init!(dir), do: {_, 0} = System.cmd("git", ["init", "-q", dir])

  @tag :tmp_dir
  test "inside another menard checkout, that checkout's bin/menard answers", %{tmp_dir: dir} do
    git_init!(dir)
    File.mkdir_p!(Path.join(dir, "lib/mix/tasks"))
    File.write!(Path.join(dir, "lib/mix/tasks/menard.run.ex"), "")
    bin = Path.join(dir, "bin/menard")
    File.mkdir_p!(Path.dirname(bin))
    File.write!(bin, "#!/bin/sh\necho \"this checkout: $*\"\n")
    File.chmod!(bin, 0o755)
    File.mkdir_p!(Path.join(dir, "lib/sub"))

    assert {"this checkout: version\n", 0} = System.cmd(@shim, ["version"], cd: Path.join(dir, "lib/sub"))
  end

  @tag :tmp_dir
  test "outside any menard checkout, the installed checkout answers", %{tmp_dir: dir} do
    git_init!(dir)
    {theirs, 0} = System.cmd(Path.expand("../../bin/menard", __DIR__), ["version"], cd: dir)

    assert {^theirs, 0} = System.cmd(@shim, ["version"], cd: dir)
  end
end
