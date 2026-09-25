defmodule Hidden.ReceiptTest do
  use ExUnit.Case, async: true

  test "the receipt carries the total and no placeholder" do
    text = Shop.Mailer.receipt("Ada", "o1", 1320)
    assert text =~ "Total: $13.20"
    refute text =~ "{{"
    assert text =~ "Hello Ada,\n\nThank you for your order o1.\n"
  end
end
