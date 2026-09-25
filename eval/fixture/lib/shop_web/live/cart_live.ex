defmodule ShopWeb.CartLive do
  @moduledoc "The cart page."
  use Phoenix.LiveView

  import ShopWeb.CoreComponents

  alias Shop.Cart
  alias Shop.Catalog

  def mount(_params, _session, socket) do
    {:ok, assign(socket, cart: Cart.new(), products: Catalog.list_products())}
  end

  def handle_event("add", %{"sku" => sku}, socket) do
    {:noreply, update(socket, :cart, &Cart.add(&1, sku))}
  end

  def handle_event("remove", %{"sku" => sku}, socket) do
    {:noreply, update(socket, :cart, &Cart.remove(&1, sku))}
  end

  def render(assigns) do
    ~H"""
    <section id="catalog">
      <.product_card :for={product <- @products} product={product} />
    </section>
    <section id="cart">
      <p :for={line <- Cart.lines(@cart)}>{Cart.format_line(line)}</p>
      <p class="total">Total: <.price cents={Cart.total(@cart)} /></p>
      <p :if={
        Catalog.price_with_tax(%Shop.Product{sku: "", name: "", price: Cart.shipping(@cart)}) > 0
      }>
        Shipping: <.price cents={Cart.shipping(@cart)} />
      </p>
    </section>
    """
  end
end
