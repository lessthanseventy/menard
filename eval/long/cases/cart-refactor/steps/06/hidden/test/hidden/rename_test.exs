defmodule Hidden.RenameTest do
  use ExUnit.Case, async: true

  test "gross_price/1 and /2" do
    mug = Shop.Catalog.get_product!("MUG-1")
    assert Shop.Catalog.gross_price(mug) == 1320
    assert Shop.Catalog.gross_price(mug, 0.5) == 1800
    refute function_exported?(Shop.Catalog, :price_with_tax, 1)
  end
end
