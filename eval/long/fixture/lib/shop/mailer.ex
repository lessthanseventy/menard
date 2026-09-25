defmodule Shop.Mailer do
  @moduledoc """
  The text of the mail that goes out with an order, and of the mail that brings a customer back.

  Templates are plain text with `{{key}}` placeholders. `receipt/3` fills its own; every other
  template goes through `render/2`, which refuses to leave a placeholder unfilled.
  """

  alias Shop.Cart
  alias Shop.Catalog
  alias Shop.Money
  alias Shop.Orders
  alias Shop.Product

  @receipt """
  Hello {{name}},

  Thank you for your order {{order_id}}.
  Total: {{totl}}

  -- The Shop
  """

  @itemised_receipt """
  Hello {{name}},

  Thank you for your order {{order_id}}, placed on {{placed_on}}.

  {{lines}}

  Total: {{total}}

  -- The Shop
  """

  @shipping_notice """
  Hello {{name}},

  Your order {{order_id}} is on its way with {{carrier}}.
  Tracking number: {{tracking}}
  Follow it at {{tracking_url}}

  It should arrive in {{estimate}}.

  -- The Shop
  """

  @refund_notice """
  Hello {{name}},

  We have refunded {{amount}} for order {{order_id}}.
  {{reason}}

  A refund can take up to 10 working days to show on your statement.

  -- The Shop
  """

  @abandoned_cart """
  Hello {{name}},

  You left these in your cart:

  {{lines}}

  Total: {{total}}
  {{shipping}}

  Pick up where you left off: {{cart_url}}

  -- The Shop
  """

  @back_in_stock """
  Hello {{name}},

  {{product}} is back in stock, at {{price}}.
  We only have {{stock}} for now: {{product_url}}

  -- The Shop
  """

  @price_drop """
  Hello {{name}},

  {{product}}, on your wishlist, is now {{price}}: down from {{old_price}}, a saving of {{saving}}.

  {{product_url}}

  -- The Shop
  """

  @review_request """
  Hello {{name}},

  Your order {{order_id}} arrived a week ago. How was it?

  {{products}}

  One line helps the next customer choose: {{review_url}}

  -- The Shop
  """

  @signature "-- The Shop"

  @carriers %{
    post: %{
      name: "Royal Mail",
      url: "https://www.royalmail.com/track-your-item#/tracking-results/"
    },
    ups: %{name: "UPS", url: "https://www.ups.com/track?tracknum="},
    dhl: %{name: "DHL", url: "https://www.dhl.com/track?tracking-id="}
  }

  @refund_reasons %{
    damaged: "We are sorry it arrived damaged.",
    late: "We are sorry it arrived late.",
    returned: "We have received your return.",
    cancelled: "The order was cancelled before it shipped.",
    out_of_stock: "We could not get it back in stock in time."
  }

  # Below this, a forgotten cart is not worth a reminder.
  @abandoned_cart_min 1_000

  def from, do: Application.fetch_env!(:shop, __MODULE__)[:from]

  def receipt(name, order_id, total_cents) do
    @receipt
    |> String.replace("{{name}}", name)
    |> String.replace("{{order_id}}", order_id)
    |> String.replace("{{total}}", Money.format(total_cents))
  end

  def subject(order_id), do: ~s(Your order "#{order_id}")

  # -- rendering ----------------------------------------------------------------------------------

  @doc """
  Fills `template`'s `{{key}}` placeholders from `bindings`, a keyword list or a map with atom
  keys. Raises `ArgumentError` naming any placeholder left without a value, so a mail never goes
  out with braces in it.
  """
  def render(template, bindings) do
    filled =
      Enum.reduce(bindings, template, fn {key, value}, acc ->
        String.replace(acc, "{{#{key}}}", to_string(value))
      end)

    case Regex.scan(~r/\{\{(\w+)\}\}/, filled, capture: :all_but_first) do
      [] ->
        filled

      missing ->
        raise ArgumentError, "unfilled placeholders: #{Enum.join(List.flatten(missing), ", ")}"
    end
  end

  @doc "A mail ready for the delivery service: sender, recipient, subject and body."
  def envelope(to, subject, body) when is_binary(to) do
    %{from: from(), to: to, subject: subject, body: body}
  end

  @doc "The first word of a customer's name, or `\"there\"` when there is no name."
  def first_name(nil), do: "there"

  def first_name(name) when is_binary(name) do
    case String.split(name) do
      [] -> "there"
      [first | _] -> first
    end
  end

  def signature, do: @signature

  # -- receipts -----------------------------------------------------------------------------------

  @doc """
  A receipt that lists what was bought: one line per `{sku, qty}` of `order`, each priced with
  tax, and the order's total.
  """
  def itemised_receipt(name, %{id: order_id, lines: lines, placed_at: placed_at} = order) do
    render(@itemised_receipt,
      name: first_name(name),
      order_id: order_id,
      placed_on: Calendar.strftime(placed_at, "%-d %B %Y"),
      lines: Enum.join(order_lines(lines), "\n"),
      total: Money.format(Orders.total(order))
    )
  end

  @doc "`{sku, qty}` lines as a receipt shows them: `\"2 x Mug: $26.40\"`."
  def order_lines(lines) do
    for {sku, qty} <- lines do
      product = Catalog.get_product!(sku)
      "#{qty} x #{product.name}: #{Money.format(Catalog.price_with_tax(product) * qty)}"
    end
  end

  # -- shipping -----------------------------------------------------------------------------------

  def carriers, do: @carriers |> Map.keys() |> Enum.sort()

  def carrier_name(carrier), do: Map.fetch!(@carriers, carrier).name

  @doc "Where the customer follows the parcel, on the carrier's own site."
  def tracking_url(carrier, tracking) when is_binary(tracking) do
    Map.fetch!(@carriers, carrier).url <> URI.encode_www_form(tracking)
  end

  @doc "Tells the customer their order has left, with whom, and when to expect it in `region`."
  def shipping_notice(name, order_id, carrier, tracking, region \\ :domestic) do
    render(@shipping_notice,
      name: first_name(name),
      order_id: order_id,
      carrier: carrier_name(carrier),
      tracking: tracking,
      tracking_url: tracking_url(carrier, tracking),
      estimate: Cart.delivery_estimate(region)
    )
  end

  def shipping_subject(order_id), do: ~s(Your order "#{order_id}" has shipped)

  # -- refunds ------------------------------------------------------------------------------------

  @doc """
  Confirms a refund of `amount_cents` on `order_id`. `reason` is one of the known reasons, which
  gets its standard sentence, or a sentence of its own for anything else.
  """
  def refund_notice(name, order_id, amount_cents, reason) when amount_cents > 0 do
    render(@refund_notice,
      name: first_name(name),
      order_id: order_id,
      amount: Money.format(amount_cents),
      reason: refund_reason(reason)
    )
  end

  def refund_reasons, do: @refund_reasons |> Map.keys() |> Enum.sort()

  defp refund_reason(reason) when is_atom(reason), do: Map.fetch!(@refund_reasons, reason)
  defp refund_reason(reason) when is_binary(reason), do: reason

  def refund_subject(order_id), do: ~s(Your refund for order "#{order_id}")

  @doc "A partial refund's amount for `lines` of an order, `{sku, qty}`, priced with tax."
  def refund_amount(lines) do
    lines
    |> Enum.map(fn {sku, qty} -> Catalog.price_with_tax(Catalog.get_product!(sku)) * qty end)
    |> Enum.sum()
  end

  # -- abandoned carts ----------------------------------------------------------------------------

  @doc "Whether a cart left behind is worth a reminder: it holds something, and enough of it."
  def worth_reminding?(%Cart{} = cart) do
    not Cart.empty?(cart) and Cart.total(cart) >= @abandoned_cart_min
  end

  @doc """
  Reminds a customer of the cart they left: its lines, its total with tax, a word on shipping,
  and the link back to it.
  """
  def abandoned_cart(name, %Cart{} = cart, cart_url) do
    render(@abandoned_cart,
      name: first_name(name),
      lines: cart |> Cart.lines() |> Enum.map_join("\n", &Cart.format_line/1),
      total: Money.format(Cart.total(cart)),
      shipping: Cart.free_shipping_hint(cart) || "Shipping is on us.",
      cart_url: cart_url
    )
  end

  def abandoned_cart_subject(%Cart{} = cart) do
    case Cart.count(cart) do
      1 -> "You left something in your cart"
      count -> "You left #{count} items in your cart"
    end
  end

  # -- stock and prices ---------------------------------------------------------------------------

  @doc "Tells a customer who asked that `product` can be bought again."
  def back_in_stock(name, %Product{} = product, product_url) do
    render(@back_in_stock,
      name: first_name(name),
      product: product.name,
      price: Catalog.price_label(product),
      stock: product.stock,
      product_url: product_url
    )
  end

  def back_in_stock_subject(%Product{name: name}), do: "#{name} is back"

  @doc """
  Tells a customer that `product`, on their wishlist, got cheaper than `old_price_cents` with tax.
  Returns `nil` when it did not, so the caller can skip the send.
  """
  def price_drop(name, %Product{} = product, old_price_cents, product_url) do
    price = Catalog.price_with_tax(product)

    if price < old_price_cents do
      render(@price_drop,
        name: first_name(name),
        product: product.name,
        price: Money.format(price),
        old_price: Money.format(old_price_cents),
        saving: Money.format(old_price_cents - price),
        product_url: product_url
      )
    end
  end

  def price_drop_subject(%Product{name: name}), do: "#{name} just got cheaper"

  # -- reviews ------------------------------------------------------------------------------------

  @doc "Asks for a review of the products in `order`, a week after delivery."
  def review_request(name, %{id: order_id, lines: lines}, review_url) do
    products =
      lines
      |> Enum.map(fn {sku, _qty} -> Catalog.get_product!(sku).name end)
      |> Enum.uniq()
      |> Enum.map_join("\n", &"  * #{&1}")

    render(@review_request,
      name: first_name(name),
      order_id: order_id,
      products: products,
      review_url: review_url
    )
  end

  def review_subject(order_id), do: ~s(How was order "#{order_id}"?)
end
