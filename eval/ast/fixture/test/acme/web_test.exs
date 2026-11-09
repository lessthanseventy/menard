defmodule Acme.WebTest do
  use ExUnit.Case, async: true

  alias Acme.Billing

  test "CheckoutController" do
    assert {:ok, %Billing{status: :refunded}} = Acme.Web.CheckoutController.run("acct", 135)
  end

  test "InvoiceController" do
    assert {"USD", 272} = Acme.Web.InvoiceController.run("acct", 136)
  end

  test "PlanController" do
    assert %Billing{status: :settled, account: "acct"} = Acme.Web.PlanController.run("acct", 137)
  end

  test "ApiCharges" do
    assert {:error, "amount must be positive"} = Acme.Web.ApiCharges.run("acct", 0)
  end

  test "PortalSession" do
    assert %{count: 1, total: 139} = Acme.Web.PortalSession.run("acct", 139)
  end
end
