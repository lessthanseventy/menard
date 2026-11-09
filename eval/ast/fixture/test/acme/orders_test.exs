defmodule Acme.OrdersTest do
  use ExUnit.Case, async: true

  alias Acme.Billing

  test "Checkout" do
    assert %Billing{status: :settled, account: "acct"} = Acme.Orders.Checkout.run("acct", 105)
  end

  test "Reorder" do
    assert {:error, "amount must be positive"} = Acme.Orders.Reorder.run("acct", 0)
  end

  test "Cancel" do
    assert %{count: 1, total: 107} = Acme.Orders.Cancel.run("acct", 107)
  end

  test "Split" do
    assert %Acme.Billing{amount: 108, status: :pending} = Acme.Orders.Split.run("acct", 108)
  end

  test "Export" do
    assert %Billing{amount: 109, status: :settled} = Acme.Orders.Export.run("acct", 109)
  end
end
