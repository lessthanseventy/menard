defmodule Shop.Cart do
  @moduledoc """
  A cart: a map of sku to quantity, and at most one promotion code.

  Amounts are cents with tax, as `total/1` gives them. Shipping and discounts are worked out from
  the cart each time they are asked for, never stored on it, so a cart can always be rebuilt from
  its items and its code.
  """

  alias Shop.Catalog
  alias Shop.Money

  defstruct items: %{}, promo: nil

  # One line may not hold more than this many units: past it, it is a trade order.
  @max_line_qty 20

  # Below this total with tax, an order is not worth packing.
  @min_order 500

  # Promotions by code. `:percent` and `:fixed` come off the total with tax; `:buy_get` gives
  # `free` units of `sku` in every `buy + free` bought; `:free_shipping` waives shipping in any
  # region. A code only counts while the cart's total is at least `min_total`.
  @promotions %{
    "WELCOME10" => %{kind: :percent, percent: 10, min_total: 0},
    "FIVEOFF" => %{kind: :fixed, amount: 500, min_total: 2_500},
    "TEATIME" => %{kind: :buy_get, sku: "TEA-1", buy: 2, free: 1, min_total: 0},
    "SHIPFREE" => %{kind: :free_shipping, min_total: 2_000}
  }

  # Shipping by region: a flat base covers the first 500 g, then `per_500g` for each 500 g
  # started after it.
  @regions %{
    domestic: %{label: "Domestic", base: 499, per_500g: 150, days: 2..4},
    eu: %{label: "Europe", base: 1_299, per_500g: 300, days: 5..8},
    intl: %{label: "Rest of the world", base: 1_999, per_500g: 500, days: 7..14}
  }

  def new, do: %__MODULE__{}

  def add(%__MODULE__{items: items} = cart, sku, qty \\ 1) when qty > 0 do
    %{cart | items: Map.update(items, sku, qty, &(&1 + qty))}
  end

  def remove(%__MODULE__{items: items} = cart, sku) do
    %{cart | items: Map.delete(items, sku)}
  end

  def count(%__MODULE__{items: items}), do: items |> Map.values() |> Enum.sum()

  def lines(%__MODULE__{items: items}) do
    for {sku, qty} <- Enum.sort(items) do
      product = Catalog.get_product!(sku)
      {product, qty, Catalog.price_with_tax(product) * qty}
    end
  end

  def total(%__MODULE__{} = cart) do
    cart |> lines() |> Enum.map(fn {_product, _qty, amount} -> amount end) |> Enum.sum()
  end

  def shipping(%__MODULE__{} = cart) do
    if total(cart) >= Application.fetch_env!(:shop, :free_shipping_over), do: 0, else: 499
  end

  def format_line({product, qty, amount}) do
    "#{qty} x #{product.name}: #{Money.format(amount)}"
  end

  # -- items --------------------------------------------------------------------------------------

  @doc "Adds each `{sku, qty}` in `pairs`, as `add/3` would one at a time."
  def add_many(%__MODULE__{} = cart, pairs) do
    Enum.reduce(pairs, cart, fn {sku, qty}, acc -> add(acc, sku, qty) end)
  end

  @doc "Sets the quantity of `sku` outright. Zero removes the line."
  def set_quantity(%__MODULE__{} = cart, sku, 0), do: remove(cart, sku)

  def set_quantity(%__MODULE__{items: items} = cart, sku, qty) when is_integer(qty) and qty > 0 do
    %{cart | items: Map.put(items, sku, qty)}
  end

  def increment(%__MODULE__{} = cart, sku), do: add(cart, sku, 1)

  @doc "Takes one unit of `sku` out; the last unit removes the line."
  def decrement(%__MODULE__{} = cart, sku) do
    case quantity(cart, sku) do
      0 -> cart
      1 -> remove(cart, sku)
      qty -> set_quantity(cart, sku, qty - 1)
    end
  end

  @doc "Empties the cart, promotion code included."
  def clear(%__MODULE__{}), do: new()

  def empty?(%__MODULE__{items: items}), do: map_size(items) == 0

  def has?(%__MODULE__{items: items}, sku), do: Map.has_key?(items, sku)

  def quantity(%__MODULE__{items: items}, sku), do: Map.get(items, sku, 0)

  def skus(%__MODULE__{items: items}), do: items |> Map.keys() |> Enum.sort()

  @doc "The amount with tax for `sku`'s line, or `0` when the cart does not hold it."
  def line_total(%__MODULE__{} = cart, sku) do
    case quantity(cart, sku) do
      0 -> 0
      qty -> Catalog.price_with_tax(Catalog.get_product!(sku)) * qty
    end
  end

  @doc "The line that costs the most, or `nil` for an empty cart."
  def largest_line(%__MODULE__{} = cart) do
    cart
    |> lines()
    |> Enum.max_by(fn {_product, _qty, amount} -> amount end, fn -> nil end)
  end

  # -- merging ------------------------------------------------------------------------------------

  @doc """
  Merges `other` into `cart`, summing quantities of the same sku. Used on sign-in, when a guest's
  cart meets the one saved on the account: the account's promotion code wins, and the guest's
  only survives when the account had none.
  """
  def merge(%__MODULE__{} = cart, %__MODULE__{} = other) do
    items = Map.merge(cart.items, other.items, fn _sku, a, b -> a + b end)
    %{cart | items: items, promo: cart.promo || other.promo}
  end

  @doc "A cart from `{sku, qty}` pairs; repeated skus are summed."
  def from_lines(pairs), do: add_many(new(), pairs)

  @doc "The cart's `{sku, qty}` pairs, sorted by sku: the `:lines` of an order."
  def to_lines(%__MODULE__{items: items}), do: Enum.sort(items)

  @doc """
  Merges priced lines, as `lines/1` returns them, that name the same product: one line per sku,
  quantities and amounts summed. For lines gathered from several carts.
  """
  def merge_lines(lines) do
    lines
    |> Enum.group_by(fn {product, _qty, _amount} -> product.sku end)
    |> Enum.sort()
    |> Enum.map(fn {_sku, [{product, _qty, _amount} | _] = group} ->
      qty = group |> Enum.map(&elem(&1, 1)) |> Enum.sum()
      amount = group |> Enum.map(&elem(&1, 2)) |> Enum.sum()
      {product, qty, amount}
    end)
  end

  # -- validation ---------------------------------------------------------------------------------

  def max_line_qty, do: @max_line_qty

  def min_order, do: @min_order

  @doc """
  Checks a cart before checkout: `:ok`, or `{:error, errors}` listing every problem, lines first
  in sku order. An error is one of

    * `{:unknown_sku, sku}` - the product is gone from the catalog
    * `{:out_of_stock, sku}`
    * `{:insufficient_stock, sku, available}`
    * `{:too_many, sku, max}` - over `max_line_qty/0` of one product
    * `:empty`
    * `{:below_minimum, min}` - the total with tax is under `min_order/0`
  """
  def validate(%__MODULE__{} = cart) do
    line_errors = Enum.flat_map(to_lines(cart), fn {sku, qty} -> line_errors(sku, qty) end)

    case line_errors ++ order_errors(cart, line_errors) do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  def valid?(%__MODULE__{} = cart), do: validate(cart) == :ok

  defp line_errors(sku, qty) do
    case Catalog.fetch_product(sku) do
      {:error, :not_found} ->
        [{:unknown_sku, sku}]

      {:ok, product} ->
        cond do
          qty > @max_line_qty -> [{:too_many, sku, @max_line_qty}]
          not Catalog.in_stock?(product) -> [{:out_of_stock, sku}]
          not Catalog.available?(product, qty) -> [{:insufficient_stock, sku, product.stock}]
          true -> []
        end
    end
  end

  # The total cannot be priced while a line names an unknown sku, so the minimum waits for it.
  defp order_errors(cart, line_errors) do
    cond do
      empty?(cart) -> [:empty]
      Enum.any?(line_errors, &match?({:unknown_sku, _}, &1)) -> []
      total(cart) < @min_order -> [{:below_minimum, @min_order}]
      true -> []
    end
  end

  @doc "The sentence the cart page shows for a validation error."
  def error_message({:unknown_sku, sku}), do: "#{sku} is no longer sold"
  def error_message({:out_of_stock, sku}), do: "#{product_name(sku)} is out of stock"

  def error_message({:insufficient_stock, sku, available}) do
    "Only #{available} #{product_name(sku)} left"
  end

  def error_message({:too_many, sku, max}) do
    "At most #{max} #{product_name(sku)} per order; contact us for trade prices"
  end

  def error_message(:empty), do: "Your cart is empty"

  def error_message({:below_minimum, min}) do
    "The minimum order is #{Money.format(min)}"
  end

  defp product_name(sku), do: Catalog.get_product!(sku).name

  @doc """
  Makes a cart valid where it can without asking: drops unknown and sold-out skus, and cuts a
  quantity down to the stock and to `max_line_qty/0`. It cannot fix an empty cart or one under
  the minimum; `validate/1` still reports those.
  """
  def prune(%__MODULE__{} = cart) do
    items =
      for {sku, qty} <- cart.items,
          {:ok, product} <- [Catalog.fetch_product(sku)],
          Catalog.in_stock?(product),
          into: %{} do
        {sku, Enum.min([qty, product.stock, @max_line_qty])}
      end

    %{cart | items: items}
  end

  # -- promotions ---------------------------------------------------------------------------------

  @doc "The promotion behind `code`, ignoring case and spaces: `{:ok, promo}` or `:error`."
  def promotion(code) when is_binary(code), do: Map.fetch(@promotions, normalize_code(code))

  @doc """
  Puts promotion `code` on the cart, replacing any other: `{:ok, cart}`,
  `{:error, :unknown_promo}`, or `{:error, {:minimum_not_met, short_by}}` with the cents still
  to add.
  """
  def apply_promo(%__MODULE__{} = cart, code) when is_binary(code) do
    code = normalize_code(code)

    with {:ok, promo} <- Map.fetch(@promotions, code),
         total when total >= promo.min_total <- total(cart) do
      {:ok, %{cart | promo: code}}
    else
      :error -> {:error, :unknown_promo}
      total -> {:error, {:minimum_not_met, @promotions[code].min_total - total}}
    end
  end

  def remove_promo(%__MODULE__{} = cart), do: %{cart | promo: nil}

  defp normalize_code(code), do: code |> String.trim() |> String.upcase()

  @doc """
  The promotion that counts right now: the cart's code, while the total still meets its minimum.
  Taking items out can drop a cart under it, and then the code stays but does nothing.
  """
  def active_promotion(%__MODULE__{promo: nil}), do: nil

  def active_promotion(%__MODULE__{promo: code} = cart) do
    promo = Map.fetch!(@promotions, code)
    if total(cart) >= promo.min_total, do: promo
  end

  @doc "What the active promotion takes off the total with tax, in cents. Shipping is apart."
  def discount(%__MODULE__{} = cart) do
    case active_promotion(cart) do
      nil ->
        0

      %{kind: :percent, percent: percent} ->
        total(cart) - Catalog.percent_off(total(cart), percent)

      %{kind: :fixed, amount: amount} ->
        min(amount, total(cart))

      %{kind: :buy_get} = promo ->
        buy_get_discount(cart, promo)

      %{kind: :free_shipping} ->
        0
    end
  end

  # "Buy 2 get 1": in every 3 units of the sku, 1 is free.
  defp buy_get_discount(cart, %{sku: sku, buy: buy, free: free}) do
    free_units = div(quantity(cart, sku), buy + free) * free
    free_units * Catalog.price_with_tax(Catalog.get_product!(sku))
  end

  defp free_shipping_promo?(cart), do: match?(%{kind: :free_shipping}, active_promotion(cart))

  @doc "The total with tax less the active promotion's discount."
  def total_after_discount(%__MODULE__{} = cart), do: total(cart) - discount(cart)

  @doc "The promotion's line on the cart page, or `nil` when no code is on the cart."
  def promo_label(%__MODULE__{promo: nil}), do: nil

  def promo_label(%__MODULE__{promo: code} = cart) do
    case {active_promotion(cart), discount(cart)} do
      {nil, _} -> "#{code}: add #{Money.format(promo_shortfall(cart))} more to use it"
      {%{kind: :free_shipping}, _} -> "#{code}: free shipping"
      {_promo, cents} -> "#{code}: -#{Money.format(cents)}"
    end
  end

  defp promo_shortfall(%__MODULE__{promo: code} = cart) do
    max(@promotions[code].min_total - total(cart), 0)
  end

  # -- shipping -----------------------------------------------------------------------------------

  def regions, do: @regions |> Map.keys() |> Enum.sort()

  def region_label(region), do: Map.fetch!(@regions, region).label

  @doc "Parses a region from a form value; only the regions the shop ships to."
  def parse_region(value) when is_binary(value) do
    case Enum.find(regions(), &(Atom.to_string(&1) == value)) do
      nil -> {:error, :unknown_region}
      region -> {:ok, region}
    end
  end

  @doc "The packed weight of the cart, in grams."
  def weight(%__MODULE__{} = cart) do
    cart
    |> lines()
    |> Enum.map(fn {product, qty, _amount} -> {product, qty} end)
    |> Catalog.total_weight()
  end

  @doc """
  Shipping to `region`, in cents. Free for an empty cart, with the `SHIPFREE` promotion, and at
  home once the total with tax passes the free shipping threshold; otherwise by weight, as the
  region's base for the first 500 g and a rate for every 500 g started after that.
  """
  def shipping(%__MODULE__{} = cart, region) do
    cond do
      empty?(cart) -> 0
      free_shipping_promo?(cart) -> 0
      region == :domestic and total(cart) >= free_shipping_over() -> 0
      true -> weight_rate(weight(cart), Map.fetch!(@regions, region))
    end
  end

  defp weight_rate(grams, %{base: base, per_500g: per_500g}) do
    extra = max(grams - 500, 0)
    base + per_500g * div(extra + 499, 500)
  end

  defp free_shipping_over, do: Application.fetch_env!(:shop, :free_shipping_over)

  @doc "How much more to spend, with tax, for free domestic shipping; `0` once there."
  def free_shipping_remaining(%__MODULE__{} = cart) do
    max(free_shipping_over() - total(cart), 0)
  end

  @doc "The cart page's nudge toward free shipping, or `nil` once it is free."
  def free_shipping_hint(%__MODULE__{} = cart) do
    case free_shipping_remaining(cart) do
      0 -> nil
      cents -> "Add #{Money.format(cents)} more for free shipping"
    end
  end

  @doc "The delivery estimate for `region`, such as `\"2-4 working days\"`."
  def delivery_estimate(region) do
    first..last//_ = Map.fetch!(@regions, region).days
    "#{first}-#{last} working days"
  end

  # -- summary ------------------------------------------------------------------------------------

  @doc "What the customer pays for this cart shipped to `region`, in cents."
  def grand_total(%__MODULE__{} = cart, region \\ :domestic) do
    total_after_discount(cart) + shipping(cart, region)
  end

  @doc "The tax included in the total, in cents, before any discount."
  def tax(%__MODULE__{} = cart) do
    net =
      cart
      |> lines()
      |> Enum.map(fn {product, qty, _amount} -> product.price * qty end)
      |> Enum.sum()

    total(cart) - net
  end

  @doc """
  Every figure the checkout shows, in cents: item count, subtotal with tax, discount, shipping
  and what is charged.
  """
  def summary(%__MODULE__{} = cart, region \\ :domestic) do
    subtotal = total(cart)
    discount = discount(cart)
    shipping = shipping(cart, region)

    %{
      count: count(cart),
      subtotal: subtotal,
      discount: discount,
      shipping: shipping,
      total: subtotal - discount + shipping
    }
  end

  @doc "The cart as plain text: one line per item, then the figures from `summary/2`."
  def format_summary(%__MODULE__{} = cart, region \\ :domestic) do
    s = summary(cart, region)
    items = cart |> lines() |> Enum.map(&format_line/1)

    figures =
      [
        "Subtotal: #{Money.format(s.subtotal)}",
        s.discount > 0 && "Discount: -#{Money.format(s.discount)}",
        "Shipping (#{region_label(region)}): #{Money.format(s.shipping)}",
        "Total: #{Money.format(s.total)}"
      ]
      |> Enum.filter(& &1)

    Enum.join(items ++ figures, "\n")
  end

  # -- parcels ------------------------------------------------------------------------------------

  @doc """
  Splits the cart into parcels of at most `max_grams` each, heaviest units packed first. Each
  parcel is a list of `{sku, qty}`. A unit heavier than `max_grams` travels alone.
  """
  def packages(%__MODULE__{} = cart, max_grams \\ 5_000) when max_grams > 0 do
    cart
    |> lines()
    |> Enum.flat_map(fn {product, qty, _amount} ->
      List.duplicate({product.sku, Catalog.weight(product)}, qty)
    end)
    |> Enum.sort_by(fn {sku, grams} -> {-grams, sku} end)
    |> Enum.reduce([], &pack(&1, &2, max_grams))
    |> Enum.map(fn {_grams, units} -> units |> Enum.frequencies() |> Enum.sort() end)
  end

  # First fit: the unit goes in the first parcel with room, or starts a new one at the end.
  defp pack({sku, grams}, parcels, max_grams) do
    case Enum.find_index(parcels, fn {used, _units} -> used + grams <= max_grams end) do
      nil ->
        parcels ++ [{grams, [sku]}]

      index ->
        List.update_at(parcels, index, fn {used, units} -> {used + grams, [sku | units]} end)
    end
  end

  @doc """
  Shipping to every region side by side, for the cart page's \"where are you?\" table: each
  region with its shipping and the grand total there, cheapest first.
  """
  def compare_regions(%__MODULE__{} = cart) do
    regions()
    |> Enum.map(fn region ->
      %{region: region, shipping: shipping(cart, region), total: grand_total(cart, region)}
    end)
    |> Enum.sort_by(&{&1.total, &1.region})
  end

  # -- changes ------------------------------------------------------------------------------------

  @doc """
  What changed between two versions of a cart: skus `added` and `removed`, and `changed` as
  `{sku, old_qty, new_qty}`, each sorted by sku. The cart page shows it after a sign-in merge or
  a stock correction.
  """
  def diff(%__MODULE__{items: old}, %__MODULE__{items: new}) do
    old_skus = old |> Map.keys() |> MapSet.new()
    new_skus = new |> Map.keys() |> MapSet.new()

    changed =
      for sku <- old_skus |> MapSet.intersection(new_skus) |> Enum.sort(),
          old[sku] != new[sku],
          do: {sku, old[sku], new[sku]}

    %{
      added: new_skus |> MapSet.difference(old_skus) |> Enum.sort(),
      removed: old_skus |> MapSet.difference(new_skus) |> Enum.sort(),
      changed: changed
    }
  end

  @doc "A diff from `diff/2` as sentences, one per change; empty when nothing changed."
  def describe_diff(%{added: added, removed: removed, changed: changed}) do
    Enum.map(added, &"Added #{product_name(&1)}") ++
      Enum.map(removed, &"Removed #{product_name(&1)}") ++
      Enum.map(changed, fn {sku, from, to} -> "#{product_name(sku)}: #{from} -> #{to}" end)
  end

  @doc """
  Splits the cart in two: what can ship now from stock, and what has to wait. A line that is
  partly in stock is split between them.
  """
  def split_by_availability(%__MODULE__{} = cart) do
    Enum.reduce(to_lines(cart), {new(), new()}, fn {sku, qty}, {now, later} ->
      stock = Catalog.get_product!(sku).stock

      cond do
        stock >= qty -> {add(now, sku, qty), later}
        stock == 0 -> {now, add(later, sku, qty)}
        true -> {add(now, sku, stock), add(later, sku, qty - stock)}
      end
    end)
  end

  # -- breakdowns ---------------------------------------------------------------------------------

  @doc "The cart's total with tax by product category, as a map of category to cents."
  def total_by_category(%__MODULE__{} = cart) do
    cart
    |> lines()
    |> Enum.group_by(fn {product, _qty, _amount} -> product.category end, &elem(&1, 2))
    |> Map.new(fn {category, amounts} -> {category, Enum.sum(amounts)} end)
  end

  @doc "The share of the cart's total that `sku` makes up, in whole percent."
  def share_of_total(%__MODULE__{} = cart, sku) do
    case total(cart) do
      0 -> 0
      total -> div(line_total(cart, sku) * 100, total)
    end
  end

  @doc """
  Products to suggest under the cart: the related products of what it holds, in stock, not
  already in it, cheapest first, at most `limit`.
  """
  def suggestions(%__MODULE__{} = cart, limit \\ 3) do
    cart
    |> lines()
    |> Enum.flat_map(fn {product, _qty, _amount} -> Catalog.related(product) end)
    |> Enum.uniq_by(& &1.sku)
    |> Enum.reject(&has?(cart, &1.sku))
    |> Catalog.in_stock()
    |> Catalog.sort(:price_asc)
    |> Enum.take(limit)
  end

  # -- orders -------------------------------------------------------------------------------------

  @doc """
  Turns a valid cart into a pending order for `Shop.Orders`, placed on `date` and shipping to
  `region`. The promotion code rides along as `:coupon`, so the back office's coupon report
  sees it. An invalid cart comes back as `{:error, errors}` from `validate/1`.
  """
  def to_order(%__MODULE__{} = cart, id, %Date{} = date, region \\ :domestic) do
    with :ok <- validate(cart) do
      order = %{
        id: id,
        status: :pending,
        lines: to_lines(cart),
        placed_at: date,
        region: region,
        charged: grand_total(cart, region)
      }

      {:ok, if(cart.promo, do: Map.put(order, :coupon, cart.promo), else: order)}
    end
  end

  @doc """
  Puts a past order's lines back into `cart`, skipping products that are no longer sold: the
  \"buy again\" button. The skipped skus come back too, so the page can say so.
  """
  def reorder(%__MODULE__{} = cart, %{lines: lines}) do
    {known, unknown} = Enum.split_with(lines, fn {sku, _qty} -> Catalog.sku_exists?(sku) end)
    {add_many(cart, known), Enum.map(unknown, &elem(&1, 0))}
  end
end
