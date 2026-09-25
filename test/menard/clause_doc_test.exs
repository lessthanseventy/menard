defmodule Menard.ClauseDocTest do
  # A docstring is a string on an attribute: no other verb reaches it.
  use ExUnit.Case, async: true

  alias Menard.Clause

  @src """
  defmodule D do
    @doc "the old doc"
    def kept(x), do: x

    def bare(y), do: y
  end
  """

  test "set replaces an existing @doc, heredoc-wrapped at the clause's indent" do
    out = Clause.doc(@src, "kept/1", "x", "A new doc.\n\nWith a second paragraph.")

    assert out =~ ~s(  @doc """\n  A new doc.\n\n  With a second paragraph.\n  """\n  def kept)
    refute out =~ "the old doc"
  end

  test "set adds a @doc to a clause that had none, leaving the other alone" do
    out = Clause.doc(@src, "bare/1", "y", "Doc for bare.")

    assert out =~ ~s(  @doc """\n  Doc for bare.\n  """\n  def bare)
    assert out =~ ~s(@doc "the old doc")
  end

  test "nil deletes the @doc and nothing else" do
    out = Clause.doc(@src, "kept/1", "x", nil)

    refute out =~ "the old doc"
    assert out =~ "def kept(x), do: x"
    assert out =~ "def bare(y), do: y"
  end

  test "replaces a HEREDOC @doc without eating the newline after its closing quotes" do
    src = """
    defmodule Hd do
      @doc \"\"\"
      old line one
      old line two
      \"\"\"
      @spec go(any()) :: any()
      def go(x), do: x
    end
    """

    out = Clause.doc(src, "go/1", "x", "new doc.\nsecond line.")

    assert out =~ "  @doc \"\"\"\n  new doc.\n  second line.\n  \"\"\"\n  @spec go"
    refute out =~ "old line one"
    refute out =~ ~s(\"\"\"  @spec)
  end

  test "deletes a HEREDOC @doc whole, leaving the @spec" do
    src = """
    defmodule Hd do
      @doc \"\"\"
      old
      \"\"\"
      @spec go(any()) :: any()
      def go(x), do: x
    end
    """

    out = Clause.doc(src, "go/1", "x", nil)

    refute out =~ "old"
    assert out =~ "  @spec go(any()) :: any()\n  def go(x), do: x"
  end

  test "deleting a @doc that isn't there is a no-op, not an error" do
    assert Clause.doc(@src, "bare/1", "y", nil) == @src
  end
end
