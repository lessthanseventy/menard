defmodule Hidden.AvailabilityTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest
  import ShopWeb.CoreComponents

  # What the span says and which classes it has: not its whitespace, or the order or spacing of its
  # class list, which the HEEx formatter and a class list each shape their own way
  defp span(html) do
    [_, classes, text] = Regex.run(~r/<span class="([^"]*)">\s*(.*?)\s*<\/span>/s, html)
    {classes |> String.split() |> Enum.sort(), text}
  end

  test "availability" do
    tea = Shop.Catalog.get_product!("TEA-2")
    mug = Shop.Catalog.get_product!("MUG-1")

    assert span(render_component(&availability/1, product: tea)) ==
             {["availability", "out"], "Sold out"}

    assert span(render_component(&availability/1, product: mug)) == {["availability"], "In stock"}
    card = render_component(&product_card/1, product: tea)
    assert card =~ "Sold out"
    refute card =~ "Out of stock"
  end
end
