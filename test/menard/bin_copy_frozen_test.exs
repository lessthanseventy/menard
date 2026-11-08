defmodule Menard.BinCopyFrozenTest do
  # a copy of this checkout (Menard.Test.Checkout) whose compile of menard itself fails: one module
  # per cold compile, so the bin_copy tests run beside each other
  use ExUnit.Case, async: true

  import Menard.Test.Checkout

  @moduletag timeout: 300_000

  @tag :tmp_dir
  test "--frozen still runs the last good build after a verb without it failed to compile menard", %{
    tmp_dir: dir
  } do
    # Found 2026-09-26: one verb run without --frozen mid-edit (menard not compiling) failed its
    # compile, and the compiler had already removed the beams of the modules it was recompiling;
    # every --frozen verb after it died on "module Menard.Source is not available".
    copy = checkout_copy!(dir)
    bin = Path.join(copy, "bin/menard")
    env = [{"MIX_ENV", "dev"}]
    file = Path.join(dir, "a.ex")
    File.write!(file, "defmodule A do\n  def go, do: 1\nend\n")
    {_, 0} = System.cmd(bin, ["version"], env: env, stderr_to_stdout: true)

    # a half-applied edit: a clause calling a helper the next call adds
    source = Path.join(copy, "lib/menard/source.ex")

    File.write!(
      source,
      String.replace(
        File.read!(source),
        "defmodule Menard.Source do\n",
        "defmodule Menard.Source do\n  def half, do: not_there_yet()\n",
        global: false
      )
    )

    assert {_, 1} = System.cmd(bin, ["outline", file], env: env, stderr_to_stdout: true)

    assert {out, 0} = System.cmd(bin, ["--frozen", "outline", file], env: env, stderr_to_stdout: true)
    assert out =~ "go/0"
  end

  @tag :tmp_dir
  test "--frozen still runs the last good build after a `run compile` of menard itself failed", %{
    tmp_dir: dir
  } do
    # 2026-10-20: `--frozen edit --then compile` on an edit that broke lib/mix/tasks/menard.edit.ex
    # compiled through the verb, not through this file's own build step, so nothing put the beams
    # back; the next `--frozen edit` said the task menard.edit could not be found
    copy = checkout_copy!(dir)
    bin = Path.join(copy, "bin/menard")
    env = [{"MIX_ENV", "dev"}]
    file = Path.join(dir, "a.ex")
    File.write!(file, "defmodule A do\n  def go, do: 1\nend\n")
    {_, 0} = System.cmd(bin, ["version"], env: env, stderr_to_stdout: true)

    source = Path.join(copy, "lib/menard/source.ex")

    File.write!(
      source,
      String.replace(
        File.read!(source),
        "defmodule Menard.Source do\n",
        "defmodule Menard.Source do\n  def half, do: not_there_yet()\n",
        global: false
      )
    )

    assert {out, 1} =
             System.cmd(bin, ["--frozen", "run", "compile", "--in", copy], env: env, stderr_to_stdout: true)

    assert out =~ "not_there_yet"

    assert {out, 0} = System.cmd(bin, ["--frozen", "outline", file], env: env, stderr_to_stdout: true)
    assert out =~ "go/0"
  end
end
