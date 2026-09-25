defmodule Hidden.MovedTest do
  use ExUnit.Case, async: true

  test "format_line lives in Money" do
    [line] = Shop.Cart.new() |> Shop.Cart.add("MUG-1") |> Shop.Cart.lines()
    assert Shop.Money.format_line(line) == "1 x Mug: $13.20"
    refute function_exported?(Shop.Cart, :format_line, 1)
  end
end
