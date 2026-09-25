defmodule ShopWeb.CartLive do
  @moduledoc """
  The cart page: the catalog to browse on the left, the cart on the right.

  The product list is worked out again from `:query`, `:category` and `:sort` whenever one of
  them changes; the cart's figures are worked out from `:cart` and `:region` at render.
  """
  use Phoenix.LiveView

  import ShopWeb.CoreComponents

  alias Shop.Cart
  alias Shop.Catalog
  alias Shop.Money

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(cart: Cart.new(), products: Catalog.list_products())
     |> assign(query: "", category: nil, sort: :price_asc, region: :domestic)
     |> assign(promo_error: nil, errors: [], notice: nil, selected: nil, saved: [])
     |> refresh_products()}
  end

  def handle_event("add", %{"sku" => sku}, socket) do
    {:noreply, update(socket, :cart, &Cart.add(&1, sku))}
  end

  def handle_event("remove", %{"sku" => sku}, socket) do
    {:noreply, update(socket, :cart, &Cart.remove(&1, sku))}
  end

  # -- quantities ---------------------------------------------------------------------------------

  def handle_event("inc", %{"sku" => sku}, socket) do
    if Cart.quantity(socket.assigns.cart, sku) >= Cart.max_line_qty() do
      {:noreply, assign(socket, :notice, "At most #{Cart.max_line_qty()} of one product")}
    else
      {:noreply, update(socket, :cart, &Cart.increment(&1, sku))}
    end
  end

  def handle_event("dec", %{"sku" => sku}, socket) do
    {:noreply, update(socket, :cart, &Cart.decrement(&1, sku))}
  end

  def handle_event("set_qty", %{"sku" => sku, "qty" => qty}, socket) do
    max = Cart.max_line_qty()

    case Integer.parse(qty) do
      {qty, ""} when qty >= 0 and qty <= max ->
        {:noreply, update(socket, :cart, &Cart.set_quantity(&1, sku, qty))}

      _ ->
        {:noreply, assign(socket, :notice, "Enter a quantity from 0 to #{max}")}
    end
  end

  def handle_event("clear", _params, socket) do
    {:noreply, assign(socket, cart: Cart.new(), errors: [], promo_error: nil, notice: nil)}
  end

  # -- promotions ---------------------------------------------------------------------------------

  def handle_event("apply_promo", %{"code" => code}, socket) do
    case Cart.apply_promo(socket.assigns.cart, code) do
      {:ok, cart} ->
        {:noreply, assign(socket, cart: cart, promo_error: nil)}

      {:error, :unknown_promo} ->
        {:noreply, assign(socket, :promo_error, "That code is not valid")}

      {:error, {:minimum_not_met, short_by}} ->
        message = "Add #{Money.format(short_by)} more to use that code"
        {:noreply, assign(socket, :promo_error, message)}
    end
  end

  def handle_event("remove_promo", _params, socket) do
    {:noreply, update(socket, :cart, &Cart.remove_promo/1)}
  end

  # -- browsing -----------------------------------------------------------------------------------

  def handle_event("search", %{"query" => query}, socket) do
    {:noreply, socket |> assign(:query, query) |> refresh_products()}
  end

  def handle_event("filter_category", %{"category" => value}, socket) do
    case Catalog.parse_category(value) do
      {:ok, category} -> {:noreply, socket |> assign(:category, category) |> refresh_products()}
      {:error, :unknown_category} -> {:noreply, socket}
    end
  end

  def handle_event("sort", %{"sort" => value}, socket) do
    case Catalog.parse_sort(value) do
      {:ok, sort} -> {:noreply, socket |> assign(:sort, sort) |> refresh_products()}
      {:error, :unknown_sort} -> {:noreply, socket}
    end
  end

  # -- checkout -----------------------------------------------------------------------------------

  def handle_event("set_region", %{"region" => value}, socket) do
    case Cart.parse_region(value) do
      {:ok, region} -> {:noreply, assign(socket, :region, region)}
      {:error, :unknown_region} -> {:noreply, socket}
    end
  end

  def handle_event("prune", _params, socket) do
    cart = Cart.prune(socket.assigns.cart)
    {:noreply, assign(socket, cart: cart, errors: validation_errors(cart))}
  end

  def handle_event("checkout", _params, socket) do
    %{cart: cart, region: region} = socket.assigns

    case Cart.validate(cart) do
      :ok ->
        notice = "Order placed: #{Money.format(Cart.grand_total(cart, region))}"
        {:noreply, assign(socket, cart: Cart.new(), errors: [], notice: notice)}

      {:error, errors} ->
        {:noreply, assign(socket, errors: errors, notice: nil)}
    end
  end

  # -- product detail -----------------------------------------------------------------------------

  def handle_event("show", %{"sku" => sku}, socket) do
    case Catalog.fetch_product(sku) do
      {:ok, product} -> {:noreply, assign(socket, :selected, product)}
      {:error, :not_found} -> {:noreply, socket}
    end
  end

  def handle_event("close", _params, socket) do
    {:noreply, assign(socket, :selected, nil)}
  end

  # -- saved for later ----------------------------------------------------------------------------

  def handle_event("save_for_later", %{"sku" => sku}, socket) do
    case Cart.quantity(socket.assigns.cart, sku) do
      0 ->
        {:noreply, socket}

      qty ->
        {:noreply,
         socket
         |> update(:cart, &Cart.remove(&1, sku))
         |> update(:saved, &(List.keydelete(&1, sku, 0) ++ [{sku, qty}]))}
    end
  end

  def handle_event("move_to_cart", %{"sku" => sku}, socket) do
    case List.keyfind(socket.assigns.saved, sku, 0) do
      nil ->
        {:noreply, socket}

      {^sku, qty} ->
        {:noreply,
         socket
         |> update(:cart, &Cart.add(&1, sku, qty))
         |> update(:saved, &List.keydelete(&1, sku, 0))}
    end
  end

  @doc """
  Reads the browsing state from the URL, so a filtered list can be linked to:
  `?q=tea&category=drink&sort=price_desc`. Anything it cannot parse is ignored.
  """
  def handle_params(params, _uri, socket) do
    socket =
      socket
      |> assign(:query, Map.get(params, "q", ""))
      |> assign_parsed(:category, Catalog.parse_category(Map.get(params, "category", "")))
      |> assign_parsed(:sort, Catalog.parse_sort(Map.get(params, "sort", "price_asc")))

    {:noreply, refresh_products(socket)}
  end

  defp assign_parsed(socket, key, {:ok, value}), do: assign(socket, key, value)
  defp assign_parsed(socket, _key, {:error, _reason}), do: socket

  @doc """
  Stock moves while the page is open: the warehouse broadcasts `{:stock_changed, sku}`, and the
  page re-checks the cart so the customer hears about it before paying.
  """
  def handle_info({:stock_changed, _sku}, socket) do
    {:noreply,
     socket
     |> assign(:errors, validation_errors(socket.assigns.cart))
     |> refresh_products()}
  end

  defp validation_errors(cart) do
    case Cart.validate(cart) do
      :ok -> []
      {:error, errors} -> errors
    end
  end

  @doc false
  def visible_products(%{query: query, category: category, sort: sort}) do
    searching? = String.trim(query) != ""
    products = if searching?, do: Catalog.search(query), else: Catalog.list_products()
    products = if category, do: Catalog.in_categories(products, [category]), else: products

    # A search keeps its best-match order; browsing uses the chosen sort.
    if searching?, do: products, else: Catalog.sort(products, sort)
  end

  defp refresh_products(socket) do
    assign(socket, :products, visible_products(socket.assigns))
  end

  def render(assigns) do
    ~H"""
    <aside :if={@selected} id="detail">
      <h2>{@selected.name}</h2>
      <.sale_price product={@selected} />
      <.stock_badge product={@selected} />
      <p :if={Catalog.sale_label(@selected)} class="sale-label">{Catalog.sale_label(@selected)}</p>
      <.tier_table product={@selected} />
      <.related_products product={@selected} />
      <.button phx-click="add" phx-value-sku={@selected.sku} disabled={!Catalog.in_stock?(@selected)}>
        Add to cart
      </.button>
      <.button phx-click="close" class="link">Close</.button>
    </aside>
    <header id="toolbar">
      <.search_form query={@query} />
      <.category_nav current={@category} />
      <.sort_select current={@sort} />
    </header>
    <.notice :if={@notice} id="notice">{@notice}</.notice>
    <section id="catalog">
      <.product_card :for={product <- @products} product={product} />
      <.empty_state :if={@products == []} id="catalog-empty">
        Nothing matches "{@query}".
        <:action>
          <.button phx-click="search" phx-value-query="">Show everything</.button>
        </:action>
      </.empty_state>
    </section>
    <section id="cart">
      <p :for={line <- Cart.lines(@cart)}>{Cart.format_line(line)}</p>
      <p class="total">Total: <.price cents={Cart.total(@cart)} /></p>
      <p :if={
        Catalog.price_with_tax(%Shop.Product{sku: "", name: "", price: Cart.shipping(@cart)}) > 0
      }>
        Shipping: <.price cents={Cart.shipping(@cart)} />
      </p>
      <.cart_lines cart={@cart} />
      <.cart_errors errors={@errors} />
      <div :if={!Cart.empty?(@cart)} id="checkout">
        <.free_shipping_bar cart={@cart} />
        <.promo_form cart={@cart} error={@promo_error} />
        <.region_select current={@region} />
        <.cart_summary cart={@cart} region={@region} />
        <p class="weight">Parcel weight: {format_weight(Cart.weight(@cart))}</p>
        <.button :if={@errors != []} phx-click="prune">Fix my cart</.button>
        <.button phx-click="checkout" class="primary">
          Pay {Money.format(Cart.grand_total(@cart, @region))}
        </.button>
        <.button phx-click="clear" class="link">Empty cart</.button>
      </div>
      <section :if={@saved != []} id="saved">
        <h3>Saved for later</h3>
        <p :for={{sku, qty} <- @saved}>
          {qty} x {Catalog.get_product!(sku).name}
          <.button phx-click="move_to_cart" phx-value-sku={sku} class="link">Move to cart</.button>
        </p>
      </section>
    </section>
    """
  end

  defp format_weight(grams) when grams < 1_000, do: "#{grams} g"

  defp format_weight(grams) do
    kg = div(grams, 1_000)
    tenths = div(rem(grams, 1_000), 100)
    "#{kg}.#{tenths} kg"
  end
end
