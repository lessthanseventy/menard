defmodule Shop.CartTest do
  use ExUnit.Case, async: true

  alias Shop.Cart

  test "adds and counts" do
    cart = Cart.new() |> Cart.add("MUG-1") |> Cart.add("MUG-1", 2) |> Cart.add("TEA-1")
    assert Cart.count(cart) == 4
  end

  test "total includes tax" do
    cart = Cart.new() |> Cart.add("MUG-1", 2)
    assert Cart.total(cart) == 2640
  end

  test "shipping is free over the threshold" do
    assert Cart.shipping(Cart.new() |> Cart.add("POT-1", 2)) == 0
    assert Cart.shipping(Cart.new() |> Cart.add("TEA-1")) == 499
  end

  test "formats a line" do
    [line] = Cart.new() |> Cart.add("MUG-1") |> Cart.lines()
    assert Cart.format_line(line) == "1 x Mug: $13.20"
  end
end
