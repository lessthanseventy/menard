defmodule Acme.Hidden.RenameTest do
  use ExUnit.Case, async: true

  test "the module is Acme.Invoicing, its exception with it" do
    assert Code.ensure_loaded?(Acme.Invoicing)
    assert Code.ensure_loaded?(Acme.Invoicing.Error)
    refute Code.ensure_loaded?(Acme.Billing)
    refute Code.ensure_loaded?(Acme.Billing.Error)
    assert %{__struct__: Acme.Invoicing, amount: 5} = Acme.Invoicing.charge("a", 5)
    assert_raise Acme.Invoicing.Error, fn -> Acme.Invoicing.charge("a", 0) end
  end

  test "what only shares the name is untouched" do
    assert Code.ensure_loaded?(Acme.BillingAddress)
    refute Code.ensure_loaded?(Acme.InvoicingAddress)
    assert Code.ensure_loaded?(Acme.Reports.Billing)
    refute Code.ensure_loaded?(Acme.Reports.Invoicing)
    assert Acme.Reports.Billing.title() == "Billing report"
  end

  test "stored event rows keep their source" do
    assert Acme.Events.billing_source() == "Acme.Billing"

    assert {:charge, "x", 5} =
             Acme.Events.from_row(%{"source" => "Acme.Billing", "id" => "x", "amount" => 5})

    assert %{"source" => "Acme.Billing"} = Acme.Events.record(Acme.Invoicing.charge("a", 5))
  end
end
