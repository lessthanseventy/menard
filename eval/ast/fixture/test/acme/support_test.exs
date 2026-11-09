defmodule Acme.SupportTest do
  use ExUnit.Case, async: true

  alias Acme.Billing

  test "RefundDesk" do
    assert {:error, "amount must be positive"} = Acme.Support.RefundDesk.run("acct", 0)
  end

  test "Dispute" do
    assert %{count: 1, total: 131} = Acme.Support.Dispute.run("acct", 131)
  end

  test "Goodwill" do
    assert %Acme.Billing{amount: 132, status: :pending} = Acme.Support.Goodwill.run("acct", 132)
  end

  test "Escalation" do
    assert %Billing{amount: 133, status: :settled} = Acme.Support.Escalation.run("acct", 133)
  end

  test "Credit" do
    assert %Billing{address: %Acme.BillingAddress{city: "Springfield"}} =
             Acme.Support.Credit.run("acct", 134)
  end
end
