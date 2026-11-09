defmodule Acme.Reports.BillingTest do
  use ExUnit.Case, async: true

  alias Acme.BillingAddress
  alias Acme.Reports.Billing
  alias Acme.Reports.Dashboard

  test "the summary counts and sums" do
    charges = [Acme.Billing.charge("a", 100), Acme.Billing.charge("b", 250)]
    assert %{count: 2, total: 350} = Billing.summary(charges)
    assert Dashboard.headline(charges) == "Billing report: 2 charges, 350 cents"
  end

  test "the dashboard names the first address" do
    charges = [Acme.Billing.charge("a", 100, BillingAddress.new("9 Oak", "Capital City"))]
    assert Dashboard.first_address(charges) == "9 Oak, Capital City"
  end

  test "shipping labels" do
    assert Acme.Shipping.Freight.label("4 Pine") == "4 Pine, Shelbyville"
  end
end
