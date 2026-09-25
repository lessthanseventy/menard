defmodule ShopWeb.CoreComponents do
  @moduledoc """
  Function components shared by the shop's pages: prices, product cards and tables, and the
  pieces of the cart page.

  Components that send events name them in `phx-click` or `phx-submit`; the page that renders
  them handles the event. `ShopWeb.CartLive` handles all of them.
  """
  use Phoenix.Component

  alias Shop.Cart
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

  # -- buttons and notices ------------------------------------------------------------------------

  attr :type, :string, default: "button"
  attr :class, :string, default: nil
  attr :rest, :global, include: ~w(disabled form name value)
  slot :inner_block, required: true

  def button(assigns) do
    ~H"""
    <button type={@type} class={["button", @class]} {@rest}>
      {render_slot(@inner_block)}
    </button>
    """
  end

  attr :kind, :atom, values: [:info, :error], default: :info
  attr :id, :string, default: nil
  slot :inner_block, required: true

  def notice(assigns) do
    ~H"""
    <p id={@id} class={["notice", "notice-#{@kind}"]} role={if @kind == :error, do: "alert"}>
      {render_slot(@inner_block)}
    </p>
    """
  end

  attr :id, :string, required: true
  slot :inner_block, required: true
  slot :action

  def empty_state(assigns) do
    ~H"""
    <div id={@id} class="empty">
      <p>{render_slot(@inner_block)}</p>
      <div :for={action <- @action} class="empty-action">{render_slot(action)}</div>
    </div>
    """
  end

  # -- prices and stock ---------------------------------------------------------------------------

  attr :product, Shop.Product, required: true

  @doc "The price with tax, or the sale price with the full price struck through."
  def sale_price(assigns) do
    ~H"""
    <span :if={Catalog.on_sale?(@product)} class="sale">
      <.price cents={Catalog.sale_price(@product)} class="now" />
      <del><.price cents={Catalog.price_with_tax(@product)} class="was" /></del>
      <span class="badge">-{Catalog.sale_percent(@product)}%</span>
    </span>
    <.price :if={!Catalog.on_sale?(@product)} cents={Catalog.price_with_tax(@product)} />
    """
  end

  attr :product, Shop.Product, required: true

  @doc "In stock, only a few left, or out of stock."
  def stock_badge(assigns) do
    ~H"""
    <span :if={@product.stock == 0} class="stock out">Out of stock</span>
    <span :if={@product.stock in 1..3} class="stock low">Only {@product.stock} left</span>
    <span :if={@product.stock > 3} class="stock">In stock</span>
    """
  end

  attr :product, Shop.Product, required: true

  @doc "The quantity discounts for one product, with the unit price at each tier."
  def tier_table(assigns) do
    ~H"""
    <table class="tiers" id={"tiers-#{@product.sku}"}>
      <thead>
        <tr>
          <th>Quantity</th>
          <th>Discount</th>
          <th>Each</th>
        </tr>
      </thead>
      <tbody>
        <tr :for={tier <- Catalog.tier_table(@product)}>
          <td>{tier.min_qty}+</td>
          <td>{if tier.percent_off == 0, do: "-", else: "#{tier.percent_off}%"}</td>
          <td><.price cents={tier.unit_price} /></td>
        </tr>
      </tbody>
    </table>
    """
  end

  # -- product lists ------------------------------------------------------------------------------

  attr :products, :list, required: true
  attr :id, :string, default: "products"

  def product_grid(assigns) do
    ~H"""
    <section id={@id} class="grid">
      <.product_card :for={product <- @products} product={product} />
      <.empty_state :if={@products == []} id={"#{@id}-empty"}>
        Nothing matches that search.
      </.empty_state>
    </section>
    """
  end

  attr :products, :list, required: true

  @doc "The back office's product table: sku, name, price with tax and stock."
  def product_table(assigns) do
    ~H"""
    <table class="products">
      <thead>
        <tr>
          <th>SKU</th>
          <th>Name</th>
          <th>Price</th>
          <th>Stock</th>
        </tr>
      </thead>
      <tbody>
        <.product_row :for={product <- @products} product={product} />
      </tbody>
    </table>
    """
  end

  attr :product, Shop.Product, required: true

  def product_row(assigns) do
    ~H"""
    <tr id={"row-#{@product.sku}"}>
      <td>{@product.sku}</td>
      <td>{@product.name}</td>
      <td><.price cents={Catalog.price_with_tax(@product)} /></td>
      <td><.stock_badge product={@product} /></td>
    </tr>
    """
  end

  attr :product, Shop.Product, required: true

  @doc "The \"you may also like\" row under a product."
  def related_products(assigns) do
    ~H"""
    <aside :if={Catalog.related(@product) != []} class="related">
      <h4>You may also like</h4>
      <.product_card :for={other <- Catalog.related(@product)} product={other} />
    </aside>
    """
  end

  attr :products, :list, required: true

  @doc "Products side by side: price with tax, sale price, stock, and price per 100 g."
  def compare_table(assigns) do
    assigns = assign(assigns, :rows, Catalog.compare(assigns.products))

    ~H"""
    <table class="compare" id="compare">
      <tr>
        <th></th>
        <th :for={row <- @rows}>{row.name}</th>
      </tr>
      <tr>
        <th>Price</th>
        <td :for={row <- @rows}><.price cents={row.price} /></td>
      </tr>
      <tr>
        <th>Sale</th>
        <td :for={row <- @rows}>
          <.price :if={row.sale_price < row.price} cents={row.sale_price} />
        </td>
      </tr>
      <tr>
        <th>Per 100 g</th>
        <td :for={row <- @rows}><.price cents={row.per_100g} /></td>
      </tr>
      <tr>
        <th>Stock</th>
        <td :for={row <- @rows}>{if row.in_stock, do: "Yes", else: "No"}</td>
      </tr>
    </table>
    """
  end

  # -- browsing -----------------------------------------------------------------------------------

  attr :current, :atom, default: nil

  @doc "The category links; the current one is marked, and \"All\" clears the filter."
  def category_nav(assigns) do
    assigns = assign(assigns, :categories, Catalog.categories())

    ~H"""
    <nav class="categories">
      <a
        href="#"
        phx-click="filter_category"
        phx-value-category=""
        class={is_nil(@current) && "current"}
      >
        All
      </a>
      <a
        :for={category <- @categories}
        href="#"
        phx-click="filter_category"
        phx-value-category={category}
        class={@current == category && "current"}
      >
        {Catalog.category_label(category)}
      </a>
    </nav>
    """
  end

  attr :query, :string, default: ""

  def search_form(assigns) do
    ~H"""
    <form id="search" phx-change="search" phx-submit="search">
      <input type="search" name="query" value={@query} placeholder="Search tea, mugs, pots" />
    </form>
    """
  end

  attr :current, :atom, default: :price_asc

  def sort_select(assigns) do
    ~H"""
    <form id="sort" phx-change="sort">
      <select name="sort">
        <option
          :for={{label, value} <- Catalog.sort_options()}
          value={value}
          selected={value == @current}
        >
          {label}
        </option>
      </select>
    </form>
    """
  end

  # -- the cart -----------------------------------------------------------------------------------

  attr :sku, :string, required: true
  attr :qty, :integer, required: true

  @doc "Minus, the quantity, plus: each button sends its event with the sku."
  def quantity_input(assigns) do
    ~H"""
    <span class="qty">
      <.button phx-click="dec" phx-value-sku={@sku} aria-label="One fewer">-</.button>
      <span class="qty-value">{@qty}</span>
      <.button
        phx-click="inc"
        phx-value-sku={@sku}
        aria-label="One more"
        disabled={@qty >= Cart.max_line_qty()}
      >
        +
      </.button>
    </span>
    """
  end

  attr :line, :any, required: true, doc: "a `{product, qty, amount}` from `Shop.Cart.lines/1`"

  def cart_line(assigns) do
    {product, qty, amount} = assigns.line
    assigns = assign(assigns, product: product, qty: qty, amount: amount)

    ~H"""
    <li class="line" id={"line-#{@product.sku}"}>
      <span class="name">{@product.name}</span>
      <.quantity_input sku={@product.sku} qty={@qty} />
      <.price cents={@amount} />
      <.button phx-click="remove" phx-value-sku={@product.sku} class="link">Remove</.button>
      <.button phx-click="save_for_later" phx-value-sku={@product.sku} class="link">
        Save for later
      </.button>
    </li>
    """
  end

  attr :cart, Cart, required: true

  def cart_lines(assigns) do
    ~H"""
    <ul :if={!Cart.empty?(@cart)} class="lines">
      <.cart_line :for={line <- Cart.lines(@cart)} line={line} />
    </ul>
    <.empty_state :if={Cart.empty?(@cart)} id="cart-empty">Your cart is empty.</.empty_state>
    """
  end

  attr :cart, Cart, required: true
  attr :region, :atom, default: :domestic

  @doc "The figures under the cart: subtotal, discount, shipping and what is charged."
  def cart_summary(assigns) do
    assigns = assign(assigns, :summary, Cart.summary(assigns.cart, assigns.region))

    ~H"""
    <dl class="summary" id="cart-summary">
      <dt>Subtotal ({@summary.count} items)</dt>
      <dd><.price cents={Cart.total(@cart)} /></dd>
      <dt :if={@summary.discount > 0}>Discount</dt>
      <dd :if={@summary.discount > 0}>-<.price cents={@summary.discount} /></dd>
      <dt>Shipping, {Cart.region_label(@region)}</dt>
      <dd>
        <.price :if={@summary.shipping > 0} cents={@summary.shipping} />
        <span :if={@summary.shipping == 0}>Free</span>
      </dd>
      <dt class="total">Total</dt>
      <dd class="total"><.price cents={@summary.total} /></dd>
    </dl>
    """
  end

  attr :cart, Cart, required: true

  @doc "How far the cart is from free domestic shipping, as a sentence and a bar."
  def free_shipping_bar(assigns) do
    threshold = Application.fetch_env!(:shop, :free_shipping_over)
    percent = min(div(Cart.total(assigns.cart) * 100, threshold), 100)
    assigns = assign(assigns, percent: percent, hint: Cart.free_shipping_hint(assigns.cart))

    ~H"""
    <div class="free-shipping">
      <p>{@hint || "Your order ships free."}</p>
      <progress max="100" value={@percent}>{@percent}%</progress>
    </div>
    """
  end

  attr :cart, Cart, required: true
  attr :error, :string, default: nil

  @doc "The promotion code box, or the applied code with a button to take it off."
  def promo_form(assigns) do
    ~H"""
    <form :if={is_nil(@cart.promo)} id="promo" phx-submit="apply_promo">
      <input type="text" name="code" placeholder="Promotion code" />
      <.button type="submit">Apply</.button>
      <.notice :if={@error} kind={:error} id="promo-error">{@error}</.notice>
    </form>
    <p :if={@cart.promo} id="promo-applied">
      {Cart.promo_label(@cart)}
      <.button phx-click="remove_promo" class="link">Remove</.button>
    </p>
    """
  end

  attr :current, :atom, default: :domestic

  def region_select(assigns) do
    ~H"""
    <form id="region" phx-change="set_region">
      <select name="region">
        <option :for={region <- Cart.regions()} value={region} selected={region == @current}>
          {Cart.region_label(region)} ({Cart.delivery_estimate(region)})
        </option>
      </select>
    </form>
    """
  end

  attr :errors, :list, required: true, doc: "errors from `Shop.Cart.validate/1`"

  def cart_errors(assigns) do
    ~H"""
    <ul :if={@errors != []} id="cart-errors" class="errors">
      <li :for={error <- @errors}>{Cart.error_message(error)}</li>
    </ul>
    """
  end
end
