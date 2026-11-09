defmodule Acme.NotificationsTest do
  use ExUnit.Case, async: true

  alias Acme.Billing

  test "Receipt" do
    assert {"USD", 240} = Acme.Notifications.Receipt.run("acct", 120)
  end

  test "Reminder" do
    assert %Billing{status: :settled, account: "acct"} =
             Acme.Notifications.Reminder.run("acct", 121)
  end

  test "Overdue" do
    assert {:error, "amount must be positive"} = Acme.Notifications.Overdue.run("acct", 0)
  end

  test "Digest" do
    assert %{count: 1, total: 123} = Acme.Notifications.Digest.run("acct", 123)
  end

  test "Webhook" do
    assert %Acme.Billing{amount: 124, status: :pending} =
             Acme.Notifications.Webhook.run("acct", 124)
  end
end
