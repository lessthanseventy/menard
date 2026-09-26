defmodule Menard.DiffTest do
  use ExUnit.Case, async: true

  alias Menard.Diff

  # the shape of what changed: the examples in Menard.Diff.hunks/2's doc
  doctest Menard.Diff

  test "a 2000-line file diffs in far less work than a table of its lines" do
    # the vendored LCS table this replaced took 12s on a 1000-line file; a verb diffs twice. Counted
    # in reductions, not timed: a clock measures the host's load as much as the diff
    before = Enum.map_join(1..2000, "\n", &"line #{&1}")
    after_ = String.replace(before, "line 1000\n", "line 1000!\n")
    {:reductions, start} = Process.info(self(), :reductions)
    hunks = Diff.hunks(before, after_)
    {:reductions, done} = Process.info(self(), :reductions)

    assert hunks == [%{start: 1000, removed: ["line 1000"], added: ["line 1000!"]}]
    # about 7_500 here; a 2000 x 2000 table is 4_000_000 cells before any work in them
    assert done - start < 400_000
  end
end
