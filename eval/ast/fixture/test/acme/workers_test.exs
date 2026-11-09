defmodule Acme.WorkersTest do
  use ExUnit.Case, async: true

  alias Acme.Billing

  test "NightlySettle" do
    assert %{count: 1, total: 115} = Acme.Workers.NightlySettle.run("acct", 115)
  end

  test "RetryFailed" do
    assert %Acme.Billing{amount: 116, status: :pending} =
             Acme.Workers.RetryFailed.run("acct", 116)
  end

  test "Reconcile" do
    assert %Billing{amount: 117, status: :settled} = Acme.Workers.Reconcile.run("acct", 117)
  end

  test "Dunning" do
    assert %Billing{address: %Acme.BillingAddress{city: "Springfield"}} =
             Acme.Workers.Dunning.run("acct", 118)
  end

  test "Sweep" do
    assert {:ok, %Billing{status: :refunded}} = Acme.Workers.Sweep.run("acct", 119)
  end
end
