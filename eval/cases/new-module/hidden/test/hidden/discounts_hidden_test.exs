defmodule Hidden.DiscountsTest do
  use ExUnit.Case, async: true

  alias Shop.Discounts

  test "codes" do
    assert Discounts.apply_code(1999, "TENOFF") == {:ok, 1799}
    assert Discounts.apply_code(1200, "FIVE") == {:ok, 700}
    assert Discounts.apply_code(300, "FIVE") == {:ok, 0}
    assert Discounts.apply_code(300, "NOPE") == {:error, :unknown_code}
  end
end
