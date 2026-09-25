defmodule Menard.BlockRelabelTest do
  # A test's label is a string literal, so `relabel` is the only verb that reaches it.
  use ExUnit.Case, async: true

  alias Menard.Block

  @src """
  defmodule TTest do
    describe "the old describe" do
      test "the old name" do
        assert 1 == 1
      end
    end
  end
  """

  test "a test's label is renamed, body untouched" do
    out = Block.relabel(@src, "test", "the old name", "the new name")

    assert out =~ ~s(test "the new name" do)
    assert out =~ "assert 1 == 1"
    assert out =~ ~s(describe "the old describe")
  end

  test "a describe's label too" do
    out = Block.relabel(@src, "describe", "the old describe", "the new describe")

    assert out =~ ~s(describe "the new describe" do)
    assert out =~ ~s(test "the old name")
  end

  test "a label that isn't there is refused" do
    assert {:error, message} = Block.relabel(@src, "test", "nope", "x")
    assert message =~ "nope"
  end
end
