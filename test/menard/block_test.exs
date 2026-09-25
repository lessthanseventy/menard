defmodule Menard.BlockTest do
  # A macro's do-block: schema do, describe "…" do, test "…" do.
  use ExUnit.Case, async: true

  alias Menard.Block

  @src """
  defmodule A do
    schema do
      field(:x, :string)
      field(:y, :integer)
    end

    describe "one" do
      test "a" do
        assert 1 == 1
      end
    end

    describe "two" do
      test "b" do
        assert 2 == 2
      end
    end
  end
  """

  test "replace swaps a block's body, keeping the header line and the end" do
    out = Block.replace(@src, "schema", "field(:only, :string)")

    assert out =~ "schema do\n    field(:only, :string)\n  end"
    refute out =~ "field(:y, :integer)"
    assert out =~ ~s(describe "one" do)
  end

  test "get reads a block's body as written" do
    assert Block.get(@src, "schema") =~ "field(:x, :string)"
  end

  test "a label addresses one of several blocks sharing a name" do
    out = Block.replace(@src, "describe", "test \"c\" do\n  assert 3 == 3\nend", label: "two")

    assert out =~ ~s(describe "two" do\n    test "c" do)
    assert out =~ ~s(test "a" do)
  end

  test "several blocks of one name with no label is refused, listing them" do
    assert {:error, message} = Block.replace(@src, "describe", "x")
    assert message =~ "2 `describe` blocks"
    assert message =~ ~s("one")
    assert message =~ ~s("two")
  end

  test "a block that isn't there is an error, not a silent no-op" do
    assert {:error, message} = Block.get(@src, "nope")
    assert message =~ "no `nope do` block"
  end

  test "list finds nested blocks too — a test lives inside a describe" do
    found = Block.list(@src)

    assert {:schema, nil, _line} = Enum.find(found, &(elem(&1, 0) == :schema))
    assert Enum.any?(found, &match?({:test, "a", _}, &1))
  end

  test "def and defmodule are not blocks — they have their own verbs" do
    names = @src |> Block.list() |> Enum.map(&elem(&1, 0))
    refute :defmodule in names
    refute :def in names
  end

  test "add writes a new block after the last sibling of its name" do
    out = Block.add(@src, "describe", "three", "test \"c\" do\n  assert 3 == 3\nend")

    assert out =~ ~s(describe "three" do)
    assert out =~ ~s(describe "two" do)
    # the new one lands AFTER the last sibling, not before the first
    assert String.slice(out, 0, :binary.match(out, "describe \"three\"") |> elem(0)) =~ "describe \"two\""
  end

  test "add --in appends inside the named parent block" do
    out = Block.add(@src, "test", "c", "assert 3 == 3", in: "two")

    # inside the named describe, at its end — where a new test goes
    assert out =~ ~s(test "b" do\n      assert 2 == 2\n    end\n\n    test "c" do)
    # and not inside the other one
    refute out =~ ~s(test "a" do\n      assert 1 == 1\n    end\n\n    test "c")
  end

  test "a label-less macro (setup do) is added without one" do
    out = Block.add(@src, "setup", nil, ":ok")

    assert out =~ "setup do\n    :ok\n  end"
  end

  test "an --in parent that isn't there is refused, not guessed at" do
    assert {:error, message} = Block.add(@src, "test", "x", "assert true", in: "nope")
    assert message =~ "no block or module"
  end

  test "replace on a do: block keeps the call line" do
    src = """
    defmodule ATest do
      use ExUnit.Case
      test "one", do: assert(1 == 1)
    end
    """

    assert Block.replace(src, "test", "assert 2 == 2", label: "one") =~ ~s(test "one", do: assert 2 == 2)

    assert Block.replace(src, "test", "x = 2\nassert x == 2", label: "one") == """
           defmodule ATest do
             use ExUnit.Case
             test "one" do
               x = 2
               assert x == 2
             end
           end
           """
  end

  test "replace of a body that ends in a heredoc keeps the end" do
    src = """
    defmodule ATest do
      use ExUnit.Case

      test "t" do
        assert x() == \"\"\"
        a
        \"\"\"
      end
    end
    """

    assert Block.replace(src, "test", "assert true", label: "t") =~ "test \"t\" do\n    assert true\n  end\n"
  end

  test "get returns the body alone, dedented — for do: and do…end alike" do
    src = """
    defmodule ATest do
      use ExUnit.Case
      test "one", do: assert(1 == 1)

      test "two" do
        x = 2
        assert x == 2
      end
    end
    """

    assert Block.get(src, "test", label: "one") == "assert(1 == 1)"
    assert Block.get(src, "test", label: "two") == "x = 2\nassert x == 2"
  end

  test "control flow inside a function is not a block — that is stmt's" do
    src = """
    defmodule A do
      schema "t" do
        field :a
      end

      def go(x) do
        if x do
          :y
        end
      end
    end
    """

    assert Block.list(src) == [{:schema, "t", 2}]
  end

  test "delete removes one block, its glued comment, and the blank line it leaves" do
    src = """
    defmodule ATest do
      use ExUnit.Case

      # about one
      test "one" do
        assert 1
      end

      test "two" do
        assert 2
      end
    end
    """

    assert Block.delete(src, "test", label: "one") == """
           defmodule ATest do
             use ExUnit.Case

             test "two" do
               assert 2
             end
           end
           """

    assert {:error, _} = Block.delete(src, "test", label: "nope")
  end

  test "add writes a test that takes the context" do
    src = """
    defmodule ATest do
      use ExUnit.Case

      test "one" do
        assert 1
      end
    end
    """

    out = Block.add(src, "test", "with ctx", "assert ws", args: "%{workspace: ws}")
    assert out =~ ~s(test "with ctx", %{workspace: ws} do\n    assert ws\n  end)
  end

  test "replace refuses a whole block given as the body" do
    # a whole `test "…" do … end` given as the body nested a test inside the test, and it parsed
    code = "describe \"two\" do\n  test \"c\" do\n    assert 3 == 3\n  end\nend"
    assert {:error, message} = Block.replace(@src, "describe", code, label: "two")
    assert message =~ "BODY"
  end

  test "replace with a body that repeats its leading comment writes it once" do
    # a new body that opens with the comment the old one opened with: once, not twice
    src = """
    defmodule A do
      describe "one" do
        # the setup these share
        test "a" do
          assert 1 == 1
        end
      end
    end
    """

    body = "# the setup these share\ntest \"b\" do\n  assert 2 == 2\nend"
    once = Block.replace(src, "describe", body, label: "one")
    assert length(String.split(once, "# the setup these share")) == 2

    # a duplicate already there is cleared by the next replace, and a body with no comment keeps it
    doubled = String.replace(src, "    # the setup", "    # the setup these share\n    # the setup")

    assert length(
             String.split(Block.replace(doubled, "describe", body, label: "one"), "# the setup these share")
           ) == 2

    assert Block.replace(src, "describe", "test \"c\", do: :ok", label: "one") =~ "# the setup these share"
  end
end
