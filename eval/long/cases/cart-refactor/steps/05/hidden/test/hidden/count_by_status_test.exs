defmodule Hidden.CountByStatusTest do
  use ExUnit.Case, async: true

  test "counts every status" do
    orders = [%{status: :paid}, %{status: :paid}, %{status: :cancelled}]

    assert Shop.Orders.count_by_status(orders) ==
             %{pending: 0, paid: 2, shipped: 0, delivered: 0, cancelled: 1, refunded: 0}

    assert Shop.Orders.count_by_status([]) |> Map.values() |> Enum.all?(&(&1 == 0))
  end
end
