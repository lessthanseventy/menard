defmodule Hidden.BadgeTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest
  import ShopWeb.CoreComponents

  test "badge" do
    assert render_component(&stock_badge/1, product: Shop.Catalog.get_product!("TEA-2")) =~
             "Sold out"

    assert render_component(&stock_badge/1, product: Shop.Catalog.get_product!("MUG-1")) =~
             "In stock"

    card = render_component(&product_card/1, product: Shop.Catalog.get_product!("TEA-2"))
    assert card =~ "Sold out"
    refute card =~ "Out of stock"
  end
end
