defmodule Hidden.WindowNameTest do
  use ExUnit.Case, async: true

  test "Server.WindowName names windows as Server.LeafWindow did, and the old name is gone" do
    mod = Server.WindowName
    assert mod.name(:reviewer, "let's review this PR") == "reviewer-let-s-review-this-pr"
    assert mod.name(:planner, "???") == "planner"
    assert mod.name(:reviewer, "review", ["reviewer-review", "reviewer-review-2"]) == "reviewer-review-3"
    refute Code.ensure_loaded?(Server.LeafWindow)
  end
end
