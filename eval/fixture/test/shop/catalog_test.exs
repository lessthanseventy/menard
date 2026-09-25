defmodule Shop.CatalogTest do
  use ExUnit.Case, async: true

  alias Shop.Catalog

  test "finds a product by sku" do
    assert %Shop.Product{name: "Mug"} = Catalog.get_product!("MUG-1")
  end

  test "raises on an unknown sku" do
    assert_raise ArgumentError, fn -> Catalog.get_product!("NOPE") end
  end

  test "price with tax uses the configured rate" do
    assert Catalog.price_with_tax(Catalog.get_product!("MUG-1")) == 1320
  end

  test "stock" do
    refute Catalog.in_stock?(Catalog.get_product!("TEA-2"))
  end
end
