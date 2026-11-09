defmodule Acme.PayoutsTest do
  use ExUnit.Case, async: true

  alias Acme.Billing

  test "Transfer" do
    assert %Billing{amount: 125, status: :settled} = Acme.Payouts.Transfer.run("acct", 125)
  end

  test "Schedule" do
    assert %Billing{address: %Acme.BillingAddress{city: "Springfield"}} =
             Acme.Payouts.Schedule.run("acct", 126)
  end

  test "Hold" do
    assert {:ok, %Billing{status: :refunded}} = Acme.Payouts.Hold.run("acct", 127)
  end

  test "Release" do
    assert {"USD", 256} = Acme.Payouts.Release.run("acct", 128)
  end

  test "Ledger" do
    assert %Billing{status: :settled, account: "acct"} = Acme.Payouts.Ledger.run("acct", 129)
  end
end
