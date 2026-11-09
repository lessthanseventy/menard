defmodule Acme.SubscriptionsTest do
  use ExUnit.Case, async: true

  alias Acme.Billing

  test "Renewal" do
    assert %Billing{address: %Acme.BillingAddress{city: "Springfield"}} =
             Acme.Subscriptions.Renewal.run("acct", 110)
  end

  test "Pause" do
    assert {:ok, %Billing{status: :refunded}} = Acme.Subscriptions.Pause.run("acct", 111)
  end

  test "Resume" do
    assert {"USD", 224} = Acme.Subscriptions.Resume.run("acct", 112)
  end

  test "Trial" do
    assert %Billing{status: :settled, account: "acct"} = Acme.Subscriptions.Trial.run("acct", 113)
  end

  test "Proration" do
    assert {:error, "amount must be positive"} = Acme.Subscriptions.Proration.run("acct", 0)
  end
end
