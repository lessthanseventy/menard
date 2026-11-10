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

  test "a big file changed on every line is one hunk, not a search for what its lines share" do
    # 3000 lines each changed took 15 s an edit, and a verb diffs up to three times
    before = Enum.map_join(1..3000, "\n", &"line #{&1}")
    after_ = Enum.map_join(1..3000, "\n", &"LINE #{&1}")
    {:reductions, start} = Process.info(self(), :reductions)
    assert [%{start: 2, removed: removed, added: added}] = Diff.hunks("top\n" <> before, "top\n" <> after_)
    {:reductions, done} = Process.info(self(), :reductions)

    assert {length(removed), length(added)} == {3000, 3000}
    assert done - start < 400_000
  end
end
