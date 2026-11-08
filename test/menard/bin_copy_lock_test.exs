defmodule Menard.BinCopyLockTest do
  # a copy of this checkout (Menard.Test.Checkout) built from a mix.lock behind its deps: one
  # module per cold compile, so the bin_copy tests run beside each other
  use ExUnit.Case, async: true

  import Menard.Test.Checkout

  @moduletag timeout: 300_000

  @root Path.expand("../..", __DIR__)

  @tag :tmp_dir
  test "a checkout whose mix.lock gained a dep since its first run fetches it, and says nothing", %{
    tmp_dir: dir
  } do
    # Found 2026-09-26: a worktree first run at an older commit, then moved to one whose mix.lock
    # has more deps. deps/ is untracked, so it kept the old ones, and the first-run check (one dep's
    # directory) passed: the compile died on "dependency not available". The same after any pull that
    # adds a dep. Here: a copy of this checkout, its deps and dev build, with one dep taken away.
    copy = checkout_copy!(dir)
    File.rm_rf!(Path.join(copy, "deps/jason"))
    # fetched for a mix.lock that had no jason yet
    lock = File.read!(Path.join(@root, "mix.lock"))
    old = lock |> String.split("\n") |> Enum.reject(&(&1 =~ ~s("jason":))) |> Enum.join("\n")
    File.write!(Path.join(copy, "deps/.menard-mix-lock"), old)

    # stdout the answer, stderr nothing: fetching and building itself is menard's business
    assert {"menard " <> _, 0} =
             System.cmd(Path.join(copy, "bin/menard"), ["version"],
               env: [{"MIX_ENV", "dev"}],
               stderr_to_stdout: true
             )

    assert File.dir?(Path.join(copy, "deps/jason"))
  end
end
