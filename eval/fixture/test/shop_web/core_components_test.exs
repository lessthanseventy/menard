defmodule ShopWeb.CoreComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest
  import ShopWeb.CoreComponents

  test "price" do
    assert render_component(&price/1, cents: 1320) =~ "$13.20"
  end

  test "product card marks out of stock" do
    html = render_component(&product_card/1, product: Shop.Catalog.get_product!("TEA-2"))
    assert html =~ "Out of stock"
  end
end
