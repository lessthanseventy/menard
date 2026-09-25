defmodule Hidden.GoneTest do
  use ExUnit.Case, async: true

  test "a sku gone from the catalog is skipped" do
    cart = Shop.Cart.new() |> Shop.Cart.add("GONE-1") |> Shop.Cart.add("MUG-1")
    assert [{%Shop.Product{sku: "MUG-1"}, 1, 1320}] = Shop.Cart.lines(cart)
    assert Shop.Cart.total(cart) == 1320
  end
end
