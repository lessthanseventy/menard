defmodule ShopWeb.CoreComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [sigil_H: 2]
  import Phoenix.LiveViewTest
  import ShopWeb.CoreComponents

  alias Shop.Cart
  alias Shop.Catalog

  defp product(sku), do: Catalog.get_product!(sku)
  defp cart(pairs), do: Cart.from_lines(pairs)

  test "price" do
    assert render_component(&price/1, cents: 1320) =~ "$13.20"
  end

  test "product card marks out of stock" do
    html = render_component(&product_card/1, product: Shop.Catalog.get_product!("TEA-2"))
    assert html =~ "Out of stock"
  end

  describe "buttons and notices" do
    test "a button passes its global attributes through" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.button phx-click="clear" disabled>Empty</.button>
        """)

      assert html =~ ~s(type="button")
      assert html =~ ~s(phx-click="clear")
      assert html =~ "disabled"
      assert html =~ "Empty"
    end

    test "an error notice is an alert" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.notice kind={:error}>Something broke</.notice>
        """)

      assert html =~ ~s(role="alert")
      assert html =~ "notice-error"
    end
  end

  describe "prices and stock" do
    test "a sale price strikes the full price" do
      html = render_component(&sale_price/1, product: product("POT-1"))
      assert html =~ "$30.80"
      assert html =~ "<del>"
      assert html =~ "$38.50"
      assert html =~ "-20%"
    end

    test "no sale, just the price" do
      html = render_component(&sale_price/1, product: product("MUG-1"))
      assert html =~ "$13.20"
      refute html =~ "<del>"
    end

    test "stock badges" do
      assert render_component(&stock_badge/1, product: product("TEA-2")) =~ "Out of stock"
      assert render_component(&stock_badge/1, product: product("POT-1")) =~ "Only 2 left"
      assert render_component(&stock_badge/1, product: product("TEA-1")) =~ "In stock"
    end

    test "tier table" do
      html = render_component(&tier_table/1, product: product("MUG-1"))
      assert html =~ "24+"
      assert html =~ "15%"
      assert html =~ "$11.22"
    end
  end

  describe "product lists" do
    test "grid, with an empty state" do
      html = render_component(&product_grid/1, products: [product("MUG-1")])
      assert html =~ ~s(id="product-MUG-1")
      assert render_component(&product_grid/1, products: []) =~ "Nothing matches that search."
    end

    test "table rows" do
      html = render_component(&product_table/1, products: [product("POT-1")])
      assert html =~ ~s(id="row-POT-1")
      assert html =~ "$38.50"
      assert html =~ "Only 2 left"
    end

    test "related products" do
      html = render_component(&related_products/1, product: product("MUG-1"))
      assert html =~ "You may also like"
      assert html =~ "Travel mug"
      assert render_component(&related_products/1, product: product("BOOK-1")) == ""
    end

    test "compare table" do
      html = render_component(&compare_table/1, products: [product("TEA-1"), product("COF-1")])
      assert html =~ "Green tea"
      assert html =~ "$3.08"
    end
  end

  describe "browsing" do
    test "category nav marks the current category" do
      html = render_component(&category_nav/1, current: :drink)
      assert html =~ "Tea &amp; coffee"
      assert html =~ ~r/class="current"[^>]*>\s*Tea &amp; coffee/
    end

    test "search form keeps the query" do
      assert render_component(&search_form/1, query: "oolong") =~ ~s(value="oolong")
    end

    test "sort select marks the current sort" do
      html = render_component(&sort_select/1, current: :name)
      assert html =~ ~r/value="name" selected/
    end
  end

  describe "the cart" do
    test "quantity input stops at the line maximum" do
      refute render_component(&quantity_input/1, sku: "MUG-1", qty: 1) =~ "disabled"
      assert render_component(&quantity_input/1, sku: "MUG-1", qty: 20) =~ "disabled"
    end

    test "a cart line" do
      [line] = Cart.lines(cart([{"MUG-1", 2}]))
      html = render_component(&cart_line/1, line: line)
      assert html =~ ~s(id="line-MUG-1")
      assert html =~ "$26.40"
      assert html =~ "Save for later"
    end

    test "lines, or the empty cart" do
      assert render_component(&cart_lines/1, cart: cart([{"TEA-1", 1}])) =~ "Green tea"
      assert render_component(&cart_lines/1, cart: Cart.new()) =~ "Your cart is empty."
    end

    test "summary shows the discount and shipping" do
      {:ok, c} = Cart.apply_promo(cart([{"MUG-1", 2}]), "WELCOME10")
      html = render_component(&cart_summary/1, cart: c, region: :eu)
      assert html =~ "Subtotal (2 items)"
      assert html =~ "$26.40"
      assert html =~ "$2.64"
      assert html =~ "Shipping, Europe"
      assert html =~ "$39.75"
    end

    test "summary says when shipping is free" do
      assert render_component(&cart_summary/1, cart: cart([{"POT-1", 2}])) =~ "Free"
    end

    test "free shipping bar" do
      html = render_component(&free_shipping_bar/1, cart: cart([{"MUG-1", 1}]))
      assert html =~ "Add $36.80 more for free shipping"
      assert html =~ ~s(value="26")
      assert render_component(&free_shipping_bar/1, cart: cart([{"POT-1", 2}])) =~ "ships free"
    end

    test "promo form, or the applied code" do
      html = render_component(&promo_form/1, cart: cart([{"MUG-1", 1}]), error: "Nope")
      assert html =~ ~s(phx-submit="apply_promo")
      assert html =~ "Nope"

      {:ok, c} = Cart.apply_promo(cart([{"MUG-1", 1}]), "WELCOME10")
      html = render_component(&promo_form/1, cart: c)
      assert html =~ "WELCOME10: -$1.32"
      assert html =~ ~s(phx-click="remove_promo")
    end

    test "region select" do
      html = render_component(&region_select/1, current: :eu)
      assert html =~ "Europe (5-8 working days)"
      assert html =~ ~r/value="eu" selected/
    end

    test "errors" do
      html = render_component(&cart_errors/1, errors: [{:out_of_stock, "TEA-2"}, :empty])
      assert html =~ "Black tea is out of stock"
      assert html =~ "Your cart is empty"
      assert render_component(&cart_errors/1, errors: []) == ""
    end
  end
end
