defmodule Acme.AccountsTest do
  use ExUnit.Case, async: true

  alias Acme.Billing

  test "Signup" do
    assert %Acme.Billing{amount: 100, status: :pending} = Acme.Accounts.Signup.run("acct", 100)
  end

  test "Upgrade" do
    assert %Billing{amount: 101, status: :settled} = Acme.Accounts.Upgrade.run("acct", 101)
  end

  test "Closure" do
    assert %Billing{address: %Acme.BillingAddress{city: "Springfield"}} =
             Acme.Accounts.Closure.run("acct", 102)
  end

  test "Merge" do
    assert {:ok, %Billing{status: :refunded}} = Acme.Accounts.Merge.run("acct", 103)
  end

  test "Audit" do
    assert {"USD", 208} = Acme.Accounts.Audit.run("acct", 104)
  end
end
