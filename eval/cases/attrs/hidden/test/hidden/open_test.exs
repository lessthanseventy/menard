defmodule Hidden.OpenTest do
  use ExUnit.Case, async: true

  test "open?" do
    assert Enum.filter(Shop.Orders.statuses(), &Shop.Orders.open?(%{status: &1})) ==
             [:pending, :paid, :shipped]
  end
end
