defmodule Shop.MailerTest do
  use ExUnit.Case, async: true

  alias Shop.Mailer

  test "greets by name" do
    assert Mailer.receipt("Ada", "o1", 1320) =~ "Hello Ada,"
  end

  test "subject quotes the order id" do
    assert Mailer.subject("o1") == ~s(Your order "o1")
  end
end
