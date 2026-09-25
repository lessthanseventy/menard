defmodule Menard.AmbiguityTest do
  # Two clauses can share a head — an insert beside a twin is the usual way — and acting on "the
  # first" silently is how a delete eats the clause a verb has just written.
  use ExUnit.Case, async: true

  alias Menard.Clause

  @src """
  defmodule Dup do
    def pick(x), do: {:first, x}

    def other(y), do: y

    def pick(x), do: {:second, x}
  end
  """

  test "a head two clauses share is refused, and the message says where they are" do
    assert {:error, message} = Clause.delete(@src, "pick/1", "x")
    assert message =~ "2 clauses of pick/1 share the head"
    assert message =~ "line 2"
    assert message =~ "line 6"
    assert message =~ "--nth 1..2"
  end

  test "--nth picks the one meant, counting in source order" do
    out = Clause.rewrite(@src, "pick/1", "x", "def pick(x), do: {:SECOND, x}", nth: 2)

    assert out =~ "{:first, x}"
    assert out =~ "{:SECOND, x}"
    refute out =~ "{:second, x}"
  end

  test "--nth past the end says so rather than picking the last" do
    assert {:error, message} = Clause.delete(@src, "pick/1", "x", nth: 3)
    assert message =~ "past the 2 clauses"
  end

  test "an unambiguous head still needs no --nth" do
    assert Clause.delete(@src, "other/1", "y") =~ "def pick"
  end
end
