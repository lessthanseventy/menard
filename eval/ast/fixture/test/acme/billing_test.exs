defmodule Acme.BillingTest do
  use ExUnit.Case, async: true

  alias Acme.Billing
  alias Acme.BillingAddress

  test "a charge is pending, in USD" do
    assert %Billing{status: :pending, amount: 500} = Billing.charge("acct", 500)
    assert Billing.currency() == "USD"
  end

  test "a charge of nothing is refused" do
    assert_raise Billing.Error, "amount must be positive", fn -> Billing.charge("acct", 0) end
  end

  test "only a settled charge is refunded" do
    charge = Billing.charge("acct", 500, BillingAddress.new("1 Main St", "Springfield"))
    assert {:error, :not_settled} = Billing.refund(charge)
    assert {:ok, %Billing{status: :refunded}} = charge |> Billing.settle() |> Billing.refund()
  end

  test "an invoice's total" do
    assert Billing.invoice_total([{"a", 100}, {"b", 250}]) == 350
  end
end
