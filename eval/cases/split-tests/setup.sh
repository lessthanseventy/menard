# A test file grown past one subject: the case moves two of its describes out.
cat > test/shop/checkout_test.exs <<'EOF'
defmodule Shop.CheckoutTest do
  use ExUnit.Case, async: true

  alias Shop.Cart
  alias Shop.Money
  alias Shop.Orders

  @mug "MUG-1"

  setup do
    {:ok, cart: Cart.new()}
  end

  test "an empty cart counts nothing", %{cart: cart} do
    assert Cart.count(cart) == 0
  end

  describe "totals" do
    test "a total includes tax", %{cart: cart} do
      assert cart |> Cart.add(@mug, 2) |> Cart.total() == 2640
    end

    test "shipping is free over the threshold", %{cart: cart} do
      assert Cart.shipping(Cart.add(cart, "POT-1", 2)) == 0
    end

    test "an order totals its lines" do
      assert Orders.total(order_with([{@mug, 2}])) == 2640
    end
  end

  describe "formatting" do
    test "a line reads quantity, name and amount", %{cart: cart} do
      [line] = cart |> mug_cart() |> Cart.lines()
      assert Cart.format_line(line) == "1 x Mug: $13.20"
    end

    test "cents read as dollars" do
      assert Money.format(1320) == "$13.20"
    end
  end

  test "removing a product leaves the rest", %{cart: cart} do
    cart = cart |> mug_cart() |> Cart.add("TEA-1") |> Cart.remove(@mug)
    assert Cart.count(cart) == 1
  end

  defp order_with(lines), do: %{id: 1, status: :pending, lines: lines, placed_at: ~D[2026-01-01]}
  defp mug_cart(cart), do: Cart.add(cart, @mug)
end
EOF
