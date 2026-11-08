defmodule Menard.BinCopyReadonlyTest do
  # a copy of this checkout (Menard.Test.Checkout) whose _build is read-only: one module per cold
  # compile, so the bin_copy tests run beside each other
  use ExUnit.Case, async: true

  import Menard.Test.Checkout

  @moduletag timeout: 300_000

  @tag :tmp_dir
  test "a read-only _build is said so and the last build runs, not blamed on a half-applied edit", %{
    tmp_dir: dir
  } do
    # ticket #571: in a sandboxed seat menard's _build is not writable; the compile it tried failed
    # on the write and the launcher called that "a compile error in menard ITSELF"
    copy = checkout_copy!(dir)
    bin = Path.join(copy, "bin/menard")
    env = [{"MIX_ENV", "dev"}]
    file = Path.join(dir, "a.ex")
    File.write!(file, "defmodule A do\n  def go, do: 1\nend\n")
    {_, 0} = System.cmd(bin, ["version"], env: env, stderr_to_stdout: true)

    # source newer than the build, so the launcher wants to compile
    File.touch!(Path.join(copy, "lib/menard/source.ex"), System.os_time(:second) + 60)
    build = Path.join(copy, "_build")
    {_, 0} = System.cmd("chmod", ["-R", "a-w", build])
    on_exit(fn -> System.cmd("chmod", ["-R", "u+w", build]) end)

    {out, status} = System.cmd(bin, ["outline", file], env: env, stderr_to_stdout: true)
    assert status == 0
    assert out =~ "go/0"
    assert out =~ "read-only"
    refute out =~ "compile error in menard ITSELF"
  end
end
