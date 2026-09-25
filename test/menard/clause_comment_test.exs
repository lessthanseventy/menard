defmodule Menard.ClauseCommentTest do
  # A clause and the comment glued above it are one unit to a reader, so `rewrite` takes both.
  use ExUnit.Case, async: true

  alias Menard.Clause

  @src """
  defmodule C do
    # the old why
    def go(x), do: x
  end
  """

  test "rewrite accepts a leading comment and carries it in" do
    out = Clause.rewrite(@src, "go/1", "x", "# the new why\ndef go(x), do: x * 2")

    assert out =~ "# the new why"
    assert out =~ "def go(x), do: x * 2"
    refute out =~ "the old why"
  end

  test "a bare expression is still refused — the check reads past the comment" do
    assert {:error, message} = Clause.rewrite(@src, "go/1", "x", "# just a comment\n:not_a_clause")
    assert message =~ "needs a whole clause"
  end

  test "a comment between the attributes and the def is the one replaced, in place" do
    # written between `@doc false` and the def, the old comment was missed: the new one went above
    # the @doc and the old stayed, two comments for one clause
    src = """
    defmodule A do
      @doc false
      # old why
      def go, do: 1
    end
    """

    out = Clause.comment(src, "go/0", "", "new why")
    assert out == String.replace(src, "old why", "new why")
    assert Clause.comment(src, "go/0", "", nil) == "defmodule A do\n  @doc false\n  def go, do: 1\nend\n"
  end
end
