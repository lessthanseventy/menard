defmodule Hidden.WeightTest do
  use ExUnit.Case, async: true

  test "cart weight" do
    cart = Shop.Cart.new() |> Shop.Cart.add("MUG-1", 2) |> Shop.Cart.add("TEA-2")
    assert Shop.Cart.weight(cart) == 700
    assert %Shop.Product{sku: "x", name: "x", price: 1}.weight == 0
  end
end
