defmodule Menard.ClauseSpecTest do
  # A function's @spec: an attribute that repeats per function, so `attr` refuses it, and the clause
  # verbs carry it without changing it. `clause spec` is the one verb that reaches it.
  use ExUnit.Case, async: true

  alias Menard.Clause

  @src """
  defmodule A do
    @doc "adds"
    @spec add(integer(), integer()) :: integer()
    def add(a, b), do: a + b

    def neg(0), do: 0
    def neg(x), do: -x
  end
  """

  test "replaces the spec, and only its line" do
    out = Clause.spec(@src, "add/2", "add(number(), number()) :: number()")

    assert out == String.replace(@src, "integer()", "number()")
  end

  test "a new spec goes above the function's first clause, below its @doc" do
    out = Clause.spec(@src, "neg/1", "neg(integer()) :: integer()")

    assert out =~ "  @spec neg(integer()) :: integer()\n  def neg(0), do: 0\n  def neg(x)"
  end

  test "the `@spec ` prefix is optional, and no spec removes it" do
    assert Clause.spec(@src, "add/2", "@spec add(number(), number()) :: number()") =~
             "  @spec add(number(), number()) :: number()\n  def add"

    out = Clause.spec(@src, "add/2", nil)
    assert out =~ "  @doc \"adds\"\n  def add(a, b)"
    refute out =~ "@spec"
  end

  test "a function that is not there is named" do
    assert {:error, message} = Clause.spec(@src, "nope/1", "nope(any()) :: any()")
    assert message =~ "nope/1"
  end
end
