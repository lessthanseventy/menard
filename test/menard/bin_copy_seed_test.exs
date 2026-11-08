defmodule Menard.BinCopySeedTest do
  # a fresh install beside a built sibling version, the plugin cache's layout (Menard.Test.Checkout):
  # one module per cold compile, so the bin_copy tests run beside each other
  use ExUnit.Case, async: true

  import Menard.Test.Checkout

  @moduletag timeout: 300_000

  @tag :tmp_dir
  test "a fresh install starts from the newest sibling version's deps and build", %{tmp_dir: dir} do
    # 0.8.7's first session: its first boot compiled deps and menard from nothing, 40 s, past the
    # harness's 30 s to connect a server, with 0.8.6 built in the directory beside it
    built = checkout_copy!(dir)
    File.write!(Path.join(built, "deps/.seeded-from-sibling"), "")
    fresh = tracked_copy!(dir, "next")
    refute File.exists?(Path.join(fresh, "deps"))

    assert {"menard " <> _, 0} =
             System.cmd(Path.join(fresh, "bin/menard"), ["version"],
               env: [{"MIX_ENV", "dev"}],
               stderr_to_stdout: true
             )

    assert File.exists?(Path.join(fresh, "deps/.seeded-from-sibling"))
    assert File.dir?(Path.join(fresh, "_build/dev/lib/sourceror/ebin"))
    assert File.dir?(Path.join(fresh, "_build/dev/lib/menard/ebin"))
  end
end
