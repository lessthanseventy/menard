defmodule Hidden.AvailabilityTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest
  import ShopWeb.CoreComponents

  # the HEEx formatter lays a span out over lines: what it says, not its whitespace
  defp squash(html),
    do:
      String.replace(html, ~r/\s+/, " ") |> String.replace("> ", ">") |> String.replace(" <", "<")

  test "availability" do
    tea = Shop.Catalog.get_product!("TEA-2")
    mug = Shop.Catalog.get_product!("MUG-1")

    assert squash(render_component(&availability/1, product: tea)) =~
             ~s(<span class="availability out">Sold out</span>)

    assert squash(render_component(&availability/1, product: mug)) =~
             ~s(<span class="availability">In stock</span>)

    card = render_component(&product_card/1, product: tea)
    assert card =~ "Sold out"
    refute card =~ "Out of stock"
  end
end
