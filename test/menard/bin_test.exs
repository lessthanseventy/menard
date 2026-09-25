defmodule Menard.BinTest do
  # bin/menard's stdout is the verb's answer and nothing else: tools read it (`attr get` → a value,
  # `run` → one JSON line). Not async: it rebuilds menard's dev build.
  use ExUnit.Case, async: false

  @root Path.expand("../..", __DIR__)

  @tag :tmp_dir
  test "a verb run right after menard's own source changed answers without the compile log", %{tmp_dir: dir} do
    file = Path.join(dir, "a.ex")
    File.write!(file, "defmodule A do\n  @limit 5_000\n\n  def go, do: @limit\nend\n")

    # nothing built: the next verb has to compile menard before it answers. The whole app dir, not
    # just its manifest — stale beams left behind get loaded and then "redefined", 43 warnings.
    File.rm_rf!(Path.join(@root, "_build/dev/lib/menard"))

    {out, 0} =
      System.cmd(Path.join(@root, "bin/menard"), ["attr", "get", file, "limit"], env: [{"MIX_ENV", "dev"}])

    assert out == "5_000\n"
  end
end
