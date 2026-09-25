defmodule Shop.MoneyTest do
  use ExUnit.Case, async: true
  doctest Shop.Money

  alias Shop.Money

  test "pads the cents" do
    assert Money.format(1205) == "$12.05"
  end

  test "negative amounts" do
    assert Money.format(-50) == "-$0.50"
  end
end
