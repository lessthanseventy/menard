defmodule Menard.FormatTest do
  # format/1 shells out, so it must be BOUNDED: an unbounded wait hangs the caller, and over stdio
  # that is an MCP tool that never answers.
  use ExUnit.Case, async: true

  test "returns within its own timeout rather than blocking forever" do
    # a REAL directory with no mix project: mix fails fast instead of the spawn erroring on cd
    file = Path.join(System.tmp_dir!(), "menard_format_probe.ex")
    File.write!(file, "defmodule P do\nend\n")
    on_exit(fn -> File.rm_rf!(file) end)

    {micros, result} = :timer.tc(fn -> Menard.format(file) end)

    assert result == :ok or match?({:error, _}, result)
    assert micros < 60_000_000, "format/1 must be bounded"
  end
end
