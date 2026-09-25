defmodule ShopWeb.CoreComponents do
  @moduledoc "Small function components shared by the shop's pages."
  use Phoenix.Component

  alias Shop.Catalog
  alias Shop.Money

  attr :cents, :integer, required: true
  attr :class, :string, default: nil

  def price(assigns) do
    ~H"""
    <span class={["price", @class]}>{Money.format(@cents)}</span>
    """
  end

  attr :product, Shop.Product, required: true

  def product_card(assigns) do
    ~H"""
    <div class="product" id={"product-#{@product.sku}"}>
      <h3>{@product.name}</h3>
      <.price cents={Catalog.price_with_tax(@product)} />
      <p :if={!Catalog.in_stock?(@product)} class="out">Out of stock</p>
    </div>
    """
  end
end
