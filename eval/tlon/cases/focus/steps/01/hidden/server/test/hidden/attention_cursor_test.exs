defmodule Hidden.AttentionCursorTest do
  use ExUnit.Case, async: true

  alias Server.Attention

  @claude File.read!("test/fixtures/panes/claude_permission_prompt.txt")

  test "a Claude Code dialog is waiting wherever its highlight sits" do
    moved =
      @claude |> String.replace("❯ 1. Yes", "  1. Yes") |> String.replace("  2. Yes, and", "❯ 2. Yes, and")

    assert moved != @claude

    assert %{harness: "claude", summary: "Do you want to proceed?", options: options} =
             Attention.detect(moved)

    assert Enum.map(options, & &1.key) == ~w(1 2 3)
  end
end
