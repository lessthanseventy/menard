defmodule Shop.OrdersTest do
  use ExUnit.Case, async: true

  alias Shop.Orders

  defp order(attrs) do
    Map.merge(%{id: "o1", status: :paid, lines: [{"MUG-1", 1}], placed_at: ~D[2026-01-10]}, attrs)
  end

  test "transitions" do
    assert {:ok, %{status: :shipped}} = Orders.transition(order(%{}), :shipped)

    assert {:error, {:invalid_transition, :paid, :pending}} =
             Orders.transition(order(%{}), :pending)
  end

  test "revenue skips cancelled orders" do
    orders = [order(%{}), order(%{status: :cancelled})]
    assert Orders.revenue(orders) == 1320
  end

  test "revenue by region" do
    orders = [order(%{region: :eu}), order(%{region: :us}), order(%{})]
    assert Orders.revenue_by_region(orders) == %{eu: 1320, us: 1320, unknown: 1320}
  end
end
