defmodule Hidden.CheapestTest do
  use ExUnit.Case, async: true

  test "cheapest in stock" do
    assert %Shop.Product{sku: "TEA-1"} = Shop.Catalog.cheapest_in_stock(:drink)
    assert %Shop.Product{sku: "MUG-1"} = Shop.Catalog.cheapest_in_stock(:kitchen)
    assert Shop.Catalog.cheapest_in_stock(:garden) == nil
  end
end
