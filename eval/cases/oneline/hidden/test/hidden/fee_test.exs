defmodule Hidden.FeeTest do
  use ExUnit.Case, async: true

  test "fee" do
    assert Shop.Cart.shipping(Shop.Cart.new() |> Shop.Cart.add("TEA-1")) == 599
  end
end
