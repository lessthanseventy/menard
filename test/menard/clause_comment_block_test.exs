defmodule Menard.ClauseCommentBlockTest do
  # The why above a def: prose, not AST, so `comment` is the only verb that reaches it.
  use ExUnit.Case, async: true

  alias Menard.Clause

  @src """
  defmodule Cm do
    # the old why, line one
    # and line two
    @doc "kept"
    @spec go(any()) :: any()
    def go(x), do: x

    def bare(y), do: y
  end
  """

  test "replaces the comment block, leaving the attached @doc/@spec where they are" do
    out = Clause.comment(@src, "go/1", "x", "the new why.\n\nand more.")

    assert out =~ "  # the new why.\n  #\n  # and more.\n  @doc \"kept\""
    refute out =~ "the old why"
    assert out =~ ~s(@spec go\(any\(\)\) :: any\(\))
  end

  test "adds a comment to a clause that had none" do
    out = Clause.comment(@src, "bare/1", "y", "why bare exists.")

    assert out =~ "  # why bare exists.\n  def bare(y), do: y"
    assert out =~ "the old why"
  end

  test "nil deletes the block and nothing else" do
    out = Clause.comment(@src, "go/1", "x", nil)

    refute out =~ "the old why"
    assert out =~ ~s(@doc "kept")
    assert out =~ "def go(x), do: x"
  end

  test "deleting a comment that isn't there is a no-op" do
    assert Clause.comment(@src, "bare/1", "y", nil) == @src
  end

  test "a line already starting with # is not double-prefixed" do
    out = Clause.comment(@src, "bare/1", "y", "# already commented")

    assert out =~ "  # already commented\n"
    refute out =~ "# # already"
  end

  test "an ambiguous head is refused here too" do
    src = "defmodule T do\n  def d(x), do: 1\n\n  def d(x), do: 2\nend\n"

    assert {:error, message} = Clause.comment(src, "d/1", "x", "why")
    assert message =~ "--nth"
  end
end
