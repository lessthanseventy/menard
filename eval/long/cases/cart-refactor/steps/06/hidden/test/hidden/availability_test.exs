defmodule Hidden.AvailabilityTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest
  import ShopWeb.CoreComponents

  test "availability" do
    tea = Shop.Catalog.get_product!("TEA-2")
    mug = Shop.Catalog.get_product!("MUG-1")
    assert render_component(&availability/1, product: tea) =~ ~s(<span class="availability out">Sold out</span>)
    assert render_component(&availability/1, product: mug) =~ ~s(<span class="availability">In stock</span>)
    card = render_component(&product_card/1, product: tea)
    assert card =~ "Sold out"
    refute card =~ "Out of stock"
  end
end
