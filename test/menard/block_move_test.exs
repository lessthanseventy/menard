defmodule Menard.BlockMoveTest do
  # `block move`: tests out of one test module into another, what `clause move` is for functions.
  # Splitting hooks_test.exs took a Python script: nothing moved a test.
  use ExUnit.Case, async: true

  alias Menard.Test.Host

  @src """
  defmodule Shop.CartTest do
    use ExUnit.Case, async: true

    alias Shop.Cart

    @price 3

    setup do
      {:ok, cart: []}
    end

    test "stays", %{cart: cart} do
      assert shared(cart) == []
    end

    # a comment that explains the test
    @tag :tmp_dir
    test "goes", %{cart: cart} do
      assert Cart.total(only_here(cart)) == @price
    end

    describe "group" do
      test "inner" do
        assert shared(1)
      end
    end

    defp only_here(x), do: x
    defp shared(x), do: x
  end
  """

  defp project(dir) do
    Host.mix_project(dir, :shop)
    File.mkdir_p!(Path.join(dir, "test/shop"))
    file = Path.join(dir, "test/shop/cart_test.exs")
    File.write!(file, @src)
    file
  end

  @tag :tmp_dir
  test "a test moves to a new file with its tags, comment, helper, attribute, alias and setup", %{
    tmp_dir: dir
  } do
    file = project(dir)
    dest = Path.join(dir, "test/shop/cart_total_test.exs")

    assert {:ok, reply} = Menard.Move.blocks(file, dest, ["goes"])
    assert reply.moved == [~s(test "goes")]
    assert reply.carried == ["only_here/1"]
    assert reply.created == "Shop.CartTotalTest"

    moved = File.read!(dest)
    assert moved =~ "defmodule Shop.CartTotalTest do\n  use ExUnit.Case, async: true\n"
    assert moved =~ "alias Shop.Cart"
    assert moved =~ "@price 3"
    assert moved =~ "setup do\n    {:ok, cart: []}\n  end"
    assert moved =~ "  # a comment that explains the test\n  @tag :tmp_dir\n  test \"goes\""
    assert moved =~ "defp only_here(x), do: x"
    refute moved =~ "shared"

    left = File.read!(file)
    refute left =~ "goes"
    refute left =~ "only_here"
    refute left =~ "@tag :tmp_dir"
    # nothing left reads them: an unused alias or attribute warns, and the build fails
    refute left =~ "@price"
    refute left =~ "alias Shop.Cart"
    assert left =~ "setup do"
    assert left =~ ~s(test "stays")
  end

  @tag :tmp_dir
  test "a helper a staying test calls too is refused, naming it, and nothing is written", %{tmp_dir: dir} do
    file = project(dir)
    dest = Path.join(dir, "test/shop/other_test.exs")

    assert {:error, why} = Menard.Move.blocks(file, dest, ["group"])
    assert why =~ "shared/1"
    assert why =~ "test/support"
    assert File.read!(file) == @src
    refute File.exists?(dest)
  end

  @tag :tmp_dir
  test "a describe moves into an existing test module, after its last test", %{tmp_dir: dir} do
    file = project(dir)
    dest = Path.join(dir, "test/shop/other_test.exs")

    File.write!(dest, """
    defmodule Shop.OtherTest do
      use ExUnit.Case

      test "there" do
        assert true
      end
    end
    """)

    File.write!(file, String.replace(@src, "assert shared(1)", "assert 1"))
    assert {:ok, reply} = Menard.Move.blocks(file, dest, ["group"])
    assert reply.created == nil

    assert File.read!(dest) =~
             ~s(test "there" do\n    assert true\n  end\n\n  describe "group" do\n    test "inner" do)

    refute File.read!(file) =~ "group"
  end

  @tag :tmp_dir
  test "a label that is no test of the module is refused with the ones there are", %{tmp_dir: dir} do
    file = project(dir)
    assert {:error, why} = Menard.Move.blocks(file, Path.join(dir, "test/x_test.exs"), ["nope"])
    assert why =~ ~s(no test or describe "nope")
    assert why =~ ~s("stays")
  end
end
