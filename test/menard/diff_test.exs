defmodule Menard.DiffTest do
  use ExUnit.Case, async: true

  alias Menard.Diff

  # the shape of what changed: the examples in Menard.Diff.hunks/2's doc
  doctest Menard.Diff

  test "a 2000-line file diffs in well under a second" do
    # the vendored LCS table this replaced took 12s on a 1000-line file; a verb diffs twice
    before = Enum.map_join(1..2000, "\n", &"line #{&1}")
    after_ = String.replace(before, "line 1000\n", "line 1000!\n")
    {us, hunks} = :timer.tc(fn -> Diff.hunks(before, after_) end)

    assert hunks == [%{start: 1000, removed: ["line 1000"], added: ["line 1000!"]}]
    assert us < 1_000_000
  end
end
