defmodule Menard.DiffTest do
  use ExUnit.Case, async: true

  alias Menard.Diff

  describe "hunks/2 — the shape of what changed" do
    test "identical strings → no hunks" do
      assert Diff.hunks("a\nb\nc", "a\nb\nc") == []
    end

    test "a single line changed" do
      assert Diff.hunks("a\nb\nc\nd\ne", "a\nB\nc\nd\ne") ==
               [%{start: 2, removed: ["b"], added: ["B"]}]
    end

    test "a line inserted at the end" do
      assert Diff.hunks("a\nb\nc", "a\nb\nc\nd") ==
               [%{start: 4, removed: [], added: ["d"]}]
    end

    test "a line inserted at the start" do
      assert Diff.hunks("b\nc", "a\nb\nc") ==
               [%{start: 1, removed: [], added: ["a"]}]
    end

    test "a line deleted" do
      assert Diff.hunks("a\nb\nc\nd", "a\nc\nd") ==
               [%{start: 2, removed: ["b"], added: []}]
    end

    test "two changes in different parts of the file" do
      assert Diff.hunks("a\nb\nc\nd\ne\nf\ng\nh", "a\nB\nc\nd\ne\nf\nG\nh") ==
               [
                 %{start: 2, removed: ["b"], added: ["B"]},
                 %{start: 7, removed: ["g"], added: ["G"]}
               ]
    end

    test "a whole block replaced with no common lines is a delete then an insert" do
      before = "def go do\n  :a\n  :b\nend"
      after_ = "def go do\n  :c\n  :d\n  :e\nend"

      assert Diff.hunks(before, after_) ==
               [
                 %{start: 2, removed: ["  :a", "  :b"], added: []},
                 %{start: 4, removed: [], added: ["  :c", "  :d", "  :e"]}
               ]
    end

    test "an empty before (a new file) is one insert hunk" do
      assert Diff.hunks("", "a\nb\nc") ==
               [%{start: 1, removed: [], added: ["a", "b", "c"]}]
    end

    test "start is the 1-based line in the BEFORE file where the change begins" do
      # delete the first line: the change is at line 1 of the original
      assert Diff.hunks("x\ny\nz", "y\nz") ==
               [%{start: 1, removed: ["x"], added: []}]
    end

    test "a trailing newline added shows as an inserted empty line" do
      assert Diff.hunks("a\nb", "a\nb\n") ==
               [%{start: 3, removed: [], added: [""]}]
    end
  end
end
