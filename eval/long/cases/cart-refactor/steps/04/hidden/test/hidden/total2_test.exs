defmodule Hidden.Total2Test do
  use ExUnit.Case, async: true

  test "total/2 takes the rate" do
    cart = Shop.Cart.new() |> Shop.Cart.add("MUG-1", 2)
    assert Shop.Cart.total(cart, 0.5) == 3600
    assert Shop.Cart.total(cart, 0.0) == 2400
    refute function_exported?(Shop.Cart, :total, 1)
  end
end
