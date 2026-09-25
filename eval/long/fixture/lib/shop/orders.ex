defmodule Shop.Orders do
  @moduledoc """
  Orders: their lifecycle, and the reports the back office runs over them.

  An order is a map with at least `:id`, `:status`, `:lines` (a list of `{sku, qty}`) and
  `:placed_at` (a `Date`). Reports take a list of orders and never touch the database.
  """

  alias Shop.Catalog
  alias Shop.Money

  @statuses [:pending, :paid, :shipped, :delivered, :cancelled, :refunded]

  @transitions %{
    pending: [:paid, :cancelled],
    paid: [:shipped, :refunded],
    shipped: [:delivered],
    delivered: [:refunded],
    cancelled: [],
    refunded: []
  }

  def statuses, do: @statuses

  @doc "Moves an order to `to`, if the lifecycle allows it."
  def transition(%{status: from} = order, to) when to in @statuses do
    if to in Map.fetch!(@transitions, from) do
      {:ok, %{order | status: to}}
    else
      {:error, {:invalid_transition, from, to}}
    end
  end

  def open?(%{status: status}), do: status in [:pending, :paid, :shipped]

  @doc "The order's total in cents, tax included."
  def total(%{lines: lines}) do
    lines
    |> Enum.map(fn {sku, qty} -> Catalog.price_with_tax(Catalog.get_product!(sku)) * qty end)
    |> Enum.sum()
  end

  def formatted_total(order), do: order |> total() |> Money.format()

  def by_status(orders, status), do: Enum.filter(orders, &(&1.status == status))

  def placed_between(orders, %Date{} = from, %Date{} = to) do
    Enum.filter(orders, fn %{placed_at: date} ->
      Date.compare(date, from) != :lt and Date.compare(date, to) != :gt
    end)
  end

  def revenue(orders) do
    orders
    |> Enum.filter(&(&1.status in [:paid, :shipped, :delivered]))
    |> Enum.map(&total/1)
    |> Enum.sum()
  end

  # -- by region ----------------------------------------------------------------------------------

  @doc "Groups orders by `:region`; orders without one go under `:unknown`."
  def group_by_region(orders) do
    Enum.group_by(orders, &Map.get(&1, :region, :unknown))
  end

  @doc "Revenue in cents for each `:region`."
  def revenue_by_region(orders) do
    orders
    |> group_by_region()
    |> Map.new(fn {key, group} -> {key, revenue(group)} end)
  end

  @doc "The `:region` with the most orders, or `nil` for no orders."
  def top_region(orders) do
    orders
    |> group_by_region()
    |> Enum.max_by(fn {_key, group} -> length(group) end, fn -> {nil, []} end)
    |> elem(0)
  end

  @doc "A one-line summary per `:region`, sorted by key."
  def summary_by_region(orders) do
    for {key, cents} <- orders |> revenue_by_region() |> Enum.sort() do
      "#{key}: #{Money.format(cents)}"
    end
  end

  # -- by channel ---------------------------------------------------------------------------------

  @doc "Groups orders by `:channel`; orders without one go under `:unknown`."
  def group_by_channel(orders) do
    Enum.group_by(orders, &Map.get(&1, :channel, :unknown))
  end

  @doc "Revenue in cents for each `:channel`."
  def revenue_by_channel(orders) do
    orders
    |> group_by_channel()
    |> Map.new(fn {key, group} -> {key, revenue(group)} end)
  end

  @doc "The `:channel` with the most orders, or `nil` for no orders."
  def top_channel(orders) do
    orders
    |> group_by_channel()
    |> Enum.max_by(fn {_key, group} -> length(group) end, fn -> {nil, []} end)
    |> elem(0)
  end

  @doc "A one-line summary per `:channel`, sorted by key."
  def summary_by_channel(orders) do
    for {key, cents} <- orders |> revenue_by_channel() |> Enum.sort() do
      "#{key}: #{Money.format(cents)}"
    end
  end

  # -- by carrier ---------------------------------------------------------------------------------

  @doc "Groups orders by `:carrier`; orders without one go under `:unknown`."
  def group_by_carrier(orders) do
    Enum.group_by(orders, &Map.get(&1, :carrier, :unknown))
  end

  @doc "Revenue in cents for each `:carrier`."
  def revenue_by_carrier(orders) do
    orders
    |> group_by_carrier()
    |> Map.new(fn {key, group} -> {key, revenue(group)} end)
  end

  @doc "The `:carrier` with the most orders, or `nil` for no orders."
  def top_carrier(orders) do
    orders
    |> group_by_carrier()
    |> Enum.max_by(fn {_key, group} -> length(group) end, fn -> {nil, []} end)
    |> elem(0)
  end

  @doc "A one-line summary per `:carrier`, sorted by key."
  def summary_by_carrier(orders) do
    for {key, cents} <- orders |> revenue_by_carrier() |> Enum.sort() do
      "#{key}: #{Money.format(cents)}"
    end
  end

  # -- by warehouse -------------------------------------------------------------------------------

  @doc "Groups orders by `:warehouse`; orders without one go under `:unknown`."
  def group_by_warehouse(orders) do
    Enum.group_by(orders, &Map.get(&1, :warehouse, :unknown))
  end

  @doc "Revenue in cents for each `:warehouse`."
  def revenue_by_warehouse(orders) do
    orders
    |> group_by_warehouse()
    |> Map.new(fn {key, group} -> {key, revenue(group)} end)
  end

  @doc "The `:warehouse` with the most orders, or `nil` for no orders."
  def top_warehouse(orders) do
    orders
    |> group_by_warehouse()
    |> Enum.max_by(fn {_key, group} -> length(group) end, fn -> {nil, []} end)
    |> elem(0)
  end

  @doc "A one-line summary per `:warehouse`, sorted by key."
  def summary_by_warehouse(orders) do
    for {key, cents} <- orders |> revenue_by_warehouse() |> Enum.sort() do
      "#{key}: #{Money.format(cents)}"
    end
  end

  # -- by coupon ----------------------------------------------------------------------------------

  @doc "Groups orders by `:coupon`; orders without one go under `:unknown`."
  def group_by_coupon(orders) do
    Enum.group_by(orders, &Map.get(&1, :coupon, :unknown))
  end

  @doc "Revenue in cents for each `:coupon`."
  def revenue_by_coupon(orders) do
    orders
    |> group_by_coupon()
    |> Map.new(fn {key, group} -> {key, revenue(group)} end)
  end

  @doc "The `:coupon` with the most orders, or `nil` for no orders."
  def top_coupon(orders) do
    orders
    |> group_by_coupon()
    |> Enum.max_by(fn {_key, group} -> length(group) end, fn -> {nil, []} end)
    |> elem(0)
  end

  @doc "A one-line summary per `:coupon`, sorted by key."
  def summary_by_coupon(orders) do
    for {key, cents} <- orders |> revenue_by_coupon() |> Enum.sort() do
      "#{key}: #{Money.format(cents)}"
    end
  end

  # -- by segment ---------------------------------------------------------------------------------

  @doc "Groups orders by `:segment`; orders without one go under `:unknown`."
  def group_by_segment(orders) do
    Enum.group_by(orders, &Map.get(&1, :segment, :unknown))
  end

  @doc "Revenue in cents for each `:segment`."
  def revenue_by_segment(orders) do
    orders
    |> group_by_segment()
    |> Map.new(fn {key, group} -> {key, revenue(group)} end)
  end

  @doc "The `:segment` with the most orders, or `nil` for no orders."
  def top_segment(orders) do
    orders
    |> group_by_segment()
    |> Enum.max_by(fn {_key, group} -> length(group) end, fn -> {nil, []} end)
    |> elem(0)
  end

  @doc "A one-line summary per `:segment`, sorted by key."
  def summary_by_segment(orders) do
    for {key, cents} <- orders |> revenue_by_segment() |> Enum.sort() do
      "#{key}: #{Money.format(cents)}"
    end
  end

  # -- by priority --------------------------------------------------------------------------------

  @doc "Groups orders by `:priority`; orders without one go under `:unknown`."
  def group_by_priority(orders) do
    Enum.group_by(orders, &Map.get(&1, :priority, :unknown))
  end

  @doc "Revenue in cents for each `:priority`."
  def revenue_by_priority(orders) do
    orders
    |> group_by_priority()
    |> Map.new(fn {key, group} -> {key, revenue(group)} end)
  end

  @doc "The `:priority` with the most orders, or `nil` for no orders."
  def top_priority(orders) do
    orders
    |> group_by_priority()
    |> Enum.max_by(fn {_key, group} -> length(group) end, fn -> {nil, []} end)
    |> elem(0)
  end

  @doc "A one-line summary per `:priority`, sorted by key."
  def summary_by_priority(orders) do
    for {key, cents} <- orders |> revenue_by_priority() |> Enum.sort() do
      "#{key}: #{Money.format(cents)}"
    end
  end

  # -- by source ----------------------------------------------------------------------------------

  @doc "Groups orders by `:source`; orders without one go under `:unknown`."
  def group_by_source(orders) do
    Enum.group_by(orders, &Map.get(&1, :source, :unknown))
  end

  @doc "Revenue in cents for each `:source`."
  def revenue_by_source(orders) do
    orders
    |> group_by_source()
    |> Map.new(fn {key, group} -> {key, revenue(group)} end)
  end

  @doc "The `:source` with the most orders, or `nil` for no orders."
  def top_source(orders) do
    orders
    |> group_by_source()
    |> Enum.max_by(fn {_key, group} -> length(group) end, fn -> {nil, []} end)
    |> elem(0)
  end

  @doc "A one-line summary per `:source`, sorted by key."
  def summary_by_source(orders) do
    for {key, cents} <- orders |> revenue_by_source() |> Enum.sort() do
      "#{key}: #{Money.format(cents)}"
    end
  end

  # -- by payment ---------------------------------------------------------------------------------

  @doc "Groups orders by `:payment`; orders without one go under `:unknown`."
  def group_by_payment(orders) do
    Enum.group_by(orders, &Map.get(&1, :payment, :unknown))
  end

  @doc "Revenue in cents for each `:payment`."
  def revenue_by_payment(orders) do
    orders
    |> group_by_payment()
    |> Map.new(fn {key, group} -> {key, revenue(group)} end)
  end

  @doc "The `:payment` with the most orders, or `nil` for no orders."
  def top_payment(orders) do
    orders
    |> group_by_payment()
    |> Enum.max_by(fn {_key, group} -> length(group) end, fn -> {nil, []} end)
    |> elem(0)
  end

  @doc "A one-line summary per `:payment`, sorted by key."
  def summary_by_payment(orders) do
    for {key, cents} <- orders |> revenue_by_payment() |> Enum.sort() do
      "#{key}: #{Money.format(cents)}"
    end
  end

  # -- by device ----------------------------------------------------------------------------------

  @doc "Groups orders by `:device`; orders without one go under `:unknown`."
  def group_by_device(orders) do
    Enum.group_by(orders, &Map.get(&1, :device, :unknown))
  end

  @doc "Revenue in cents for each `:device`."
  def revenue_by_device(orders) do
    orders
    |> group_by_device()
    |> Map.new(fn {key, group} -> {key, revenue(group)} end)
  end

  @doc "The `:device` with the most orders, or `nil` for no orders."
  def top_device(orders) do
    orders
    |> group_by_device()
    |> Enum.max_by(fn {_key, group} -> length(group) end, fn -> {nil, []} end)
    |> elem(0)
  end

  @doc "A one-line summary per `:device`, sorted by key."
  def summary_by_device(orders) do
    for {key, cents} <- orders |> revenue_by_device() |> Enum.sort() do
      "#{key}: #{Money.format(cents)}"
    end
  end

  # -- by locale ----------------------------------------------------------------------------------

  @doc "Groups orders by `:locale`; orders without one go under `:unknown`."
  def group_by_locale(orders) do
    Enum.group_by(orders, &Map.get(&1, :locale, :unknown))
  end

  @doc "Revenue in cents for each `:locale`."
  def revenue_by_locale(orders) do
    orders
    |> group_by_locale()
    |> Map.new(fn {key, group} -> {key, revenue(group)} end)
  end

  @doc "The `:locale` with the most orders, or `nil` for no orders."
  def top_locale(orders) do
    orders
    |> group_by_locale()
    |> Enum.max_by(fn {_key, group} -> length(group) end, fn -> {nil, []} end)
    |> elem(0)
  end

  @doc "A one-line summary per `:locale`, sorted by key."
  def summary_by_locale(orders) do
    for {key, cents} <- orders |> revenue_by_locale() |> Enum.sort() do
      "#{key}: #{Money.format(cents)}"
    end
  end

  # -- by referrer --------------------------------------------------------------------------------

  @doc "Groups orders by `:referrer`; orders without one go under `:unknown`."
  def group_by_referrer(orders) do
    Enum.group_by(orders, &Map.get(&1, :referrer, :unknown))
  end

  @doc "Revenue in cents for each `:referrer`."
  def revenue_by_referrer(orders) do
    orders
    |> group_by_referrer()
    |> Map.new(fn {key, group} -> {key, revenue(group)} end)
  end

  @doc "The `:referrer` with the most orders, or `nil` for no orders."
  def top_referrer(orders) do
    orders
    |> group_by_referrer()
    |> Enum.max_by(fn {_key, group} -> length(group) end, fn -> {nil, []} end)
    |> elem(0)
  end

  @doc "A one-line summary per `:referrer`, sorted by key."
  def summary_by_referrer(orders) do
    for {key, cents} <- orders |> revenue_by_referrer() |> Enum.sort() do
      "#{key}: #{Money.format(cents)}"
    end
  end

  # -- by campaign --------------------------------------------------------------------------------

  @doc "Groups orders by `:campaign`; orders without one go under `:unknown`."
  def group_by_campaign(orders) do
    Enum.group_by(orders, &Map.get(&1, :campaign, :unknown))
  end

  @doc "Revenue in cents for each `:campaign`."
  def revenue_by_campaign(orders) do
    orders
    |> group_by_campaign()
    |> Map.new(fn {key, group} -> {key, revenue(group)} end)
  end

  @doc "The `:campaign` with the most orders, or `nil` for no orders."
  def top_campaign(orders) do
    orders
    |> group_by_campaign()
    |> Enum.max_by(fn {_key, group} -> length(group) end, fn -> {nil, []} end)
    |> elem(0)
  end

  @doc "A one-line summary per `:campaign`, sorted by key."
  def summary_by_campaign(orders) do
    for {key, cents} <- orders |> revenue_by_campaign() |> Enum.sort() do
      "#{key}: #{Money.format(cents)}"
    end
  end

  # -- by team ------------------------------------------------------------------------------------

  @doc "Groups orders by `:team`; orders without one go under `:unknown`."
  def group_by_team(orders) do
    Enum.group_by(orders, &Map.get(&1, :team, :unknown))
  end

  @doc "Revenue in cents for each `:team`."
  def revenue_by_team(orders) do
    orders
    |> group_by_team()
    |> Map.new(fn {key, group} -> {key, revenue(group)} end)
  end

  @doc "The `:team` with the most orders, or `nil` for no orders."
  def top_team(orders) do
    orders
    |> group_by_team()
    |> Enum.max_by(fn {_key, group} -> length(group) end, fn -> {nil, []} end)
    |> elem(0)
  end

  @doc "A one-line summary per `:team`, sorted by key."
  def summary_by_team(orders) do
    for {key, cents} <- orders |> revenue_by_team() |> Enum.sort() do
      "#{key}: #{Money.format(cents)}"
    end
  end

  # -- by tier ------------------------------------------------------------------------------------

  @doc "Groups orders by `:tier`; orders without one go under `:unknown`."
  def group_by_tier(orders) do
    Enum.group_by(orders, &Map.get(&1, :tier, :unknown))
  end

  @doc "Revenue in cents for each `:tier`."
  def revenue_by_tier(orders) do
    orders
    |> group_by_tier()
    |> Map.new(fn {key, group} -> {key, revenue(group)} end)
  end

  @doc "The `:tier` with the most orders, or `nil` for no orders."
  def top_tier(orders) do
    orders
    |> group_by_tier()
    |> Enum.max_by(fn {_key, group} -> length(group) end, fn -> {nil, []} end)
    |> elem(0)
  end

  @doc "A one-line summary per `:tier`, sorted by key."
  def summary_by_tier(orders) do
    for {key, cents} <- orders |> revenue_by_tier() |> Enum.sort() do
      "#{key}: #{Money.format(cents)}"
    end
  end

  # -- by gift_wrap -------------------------------------------------------------------------------

  @doc "Groups orders by `:gift_wrap`; orders without one go under `:unknown`."
  def group_by_gift_wrap(orders) do
    Enum.group_by(orders, &Map.get(&1, :gift_wrap, :unknown))
  end

  @doc "Revenue in cents for each `:gift_wrap`."
  def revenue_by_gift_wrap(orders) do
    orders
    |> group_by_gift_wrap()
    |> Map.new(fn {key, group} -> {key, revenue(group)} end)
  end

  @doc "The `:gift_wrap` with the most orders, or `nil` for no orders."
  def top_gift_wrap(orders) do
    orders
    |> group_by_gift_wrap()
    |> Enum.max_by(fn {_key, group} -> length(group) end, fn -> {nil, []} end)
    |> elem(0)
  end

  @doc "A one-line summary per `:gift_wrap`, sorted by key."
  def summary_by_gift_wrap(orders) do
    for {key, cents} <- orders |> revenue_by_gift_wrap() |> Enum.sort() do
      "#{key}: #{Money.format(cents)}"
    end
  end

  # -- by insurance -------------------------------------------------------------------------------

  @doc "Groups orders by `:insurance`; orders without one go under `:unknown`."
  def group_by_insurance(orders) do
    Enum.group_by(orders, &Map.get(&1, :insurance, :unknown))
  end

  @doc "Revenue in cents for each `:insurance`."
  def revenue_by_insurance(orders) do
    orders
    |> group_by_insurance()
    |> Map.new(fn {key, group} -> {key, revenue(group)} end)
  end

  @doc "The `:insurance` with the most orders, or `nil` for no orders."
  def top_insurance(orders) do
    orders
    |> group_by_insurance()
    |> Enum.max_by(fn {_key, group} -> length(group) end, fn -> {nil, []} end)
    |> elem(0)
  end

  @doc "A one-line summary per `:insurance`, sorted by key."
  def summary_by_insurance(orders) do
    for {key, cents} <- orders |> revenue_by_insurance() |> Enum.sort() do
      "#{key}: #{Money.format(cents)}"
    end
  end

  # -- by bundle ----------------------------------------------------------------------------------

  @doc "Groups orders by `:bundle`; orders without one go under `:unknown`."
  def group_by_bundle(orders) do
    Enum.group_by(orders, &Map.get(&1, :bundle, :unknown))
  end

  @doc "Revenue in cents for each `:bundle`."
  def revenue_by_bundle(orders) do
    orders
    |> group_by_bundle()
    |> Map.new(fn {key, group} -> {key, revenue(group)} end)
  end

  @doc "The `:bundle` with the most orders, or `nil` for no orders."
  def top_bundle(orders) do
    orders
    |> group_by_bundle()
    |> Enum.max_by(fn {_key, group} -> length(group) end, fn -> {nil, []} end)
    |> elem(0)
  end

  @doc "A one-line summary per `:bundle`, sorted by key."
  def summary_by_bundle(orders) do
    for {key, cents} <- orders |> revenue_by_bundle() |> Enum.sort() do
      "#{key}: #{Money.format(cents)}"
    end
  end

  # -- by season ----------------------------------------------------------------------------------

  @doc "Groups orders by `:season`; orders without one go under `:unknown`."
  def group_by_season(orders) do
    Enum.group_by(orders, &Map.get(&1, :season, :unknown))
  end

  @doc "Revenue in cents for each `:season`."
  def revenue_by_season(orders) do
    orders
    |> group_by_season()
    |> Map.new(fn {key, group} -> {key, revenue(group)} end)
  end

  @doc "The `:season` with the most orders, or `nil` for no orders."
  def top_season(orders) do
    orders
    |> group_by_season()
    |> Enum.max_by(fn {_key, group} -> length(group) end, fn -> {nil, []} end)
    |> elem(0)
  end

  @doc "A one-line summary per `:season`, sorted by key."
  def summary_by_season(orders) do
    for {key, cents} <- orders |> revenue_by_season() |> Enum.sort() do
      "#{key}: #{Money.format(cents)}"
    end
  end

  # -- by vendor ----------------------------------------------------------------------------------

  @doc "Groups orders by `:vendor`; orders without one go under `:unknown`."
  def group_by_vendor(orders) do
    Enum.group_by(orders, &Map.get(&1, :vendor, :unknown))
  end

  @doc "Revenue in cents for each `:vendor`."
  def revenue_by_vendor(orders) do
    orders
    |> group_by_vendor()
    |> Map.new(fn {key, group} -> {key, revenue(group)} end)
  end

  @doc "The `:vendor` with the most orders, or `nil` for no orders."
  def top_vendor(orders) do
    orders
    |> group_by_vendor()
    |> Enum.max_by(fn {_key, group} -> length(group) end, fn -> {nil, []} end)
    |> elem(0)
  end

  @doc "A one-line summary per `:vendor`, sorted by key."
  def summary_by_vendor(orders) do
    for {key, cents} <- orders |> revenue_by_vendor() |> Enum.sort() do
      "#{key}: #{Money.format(cents)}"
    end
  end

  # -- by country ---------------------------------------------------------------------------------

  @doc "Groups orders by `:country`; orders without one go under `:unknown`."
  def group_by_country(orders) do
    Enum.group_by(orders, &Map.get(&1, :country, :unknown))
  end

  @doc "Revenue in cents for each `:country`."
  def revenue_by_country(orders) do
    orders
    |> group_by_country()
    |> Map.new(fn {key, group} -> {key, revenue(group)} end)
  end

  @doc "The `:country` with the most orders, or `nil` for no orders."
  def top_country(orders) do
    orders
    |> group_by_country()
    |> Enum.max_by(fn {_key, group} -> length(group) end, fn -> {nil, []} end)
    |> elem(0)
  end

  @doc "A one-line summary per `:country`, sorted by key."
  def summary_by_country(orders) do
    for {key, cents} <- orders |> revenue_by_country() |> Enum.sort() do
      "#{key}: #{Money.format(cents)}"
    end
  end

  # -- by city ------------------------------------------------------------------------------------

  @doc "Groups orders by `:city`; orders without one go under `:unknown`."
  def group_by_city(orders) do
    Enum.group_by(orders, &Map.get(&1, :city, :unknown))
  end

  @doc "Revenue in cents for each `:city`."
  def revenue_by_city(orders) do
    orders
    |> group_by_city()
    |> Map.new(fn {key, group} -> {key, revenue(group)} end)
  end

  @doc "The `:city` with the most orders, or `nil` for no orders."
  def top_city(orders) do
    orders
    |> group_by_city()
    |> Enum.max_by(fn {_key, group} -> length(group) end, fn -> {nil, []} end)
    |> elem(0)
  end

  @doc "A one-line summary per `:city`, sorted by key."
  def summary_by_city(orders) do
    for {key, cents} <- orders |> revenue_by_city() |> Enum.sort() do
      "#{key}: #{Money.format(cents)}"
    end
  end

  # -- by store -----------------------------------------------------------------------------------

  @doc "Groups orders by `:store`; orders without one go under `:unknown`."
  def group_by_store(orders) do
    Enum.group_by(orders, &Map.get(&1, :store, :unknown))
  end

  @doc "Revenue in cents for each `:store`."
  def revenue_by_store(orders) do
    orders
    |> group_by_store()
    |> Map.new(fn {key, group} -> {key, revenue(group)} end)
  end

  @doc "The `:store` with the most orders, or `nil` for no orders."
  def top_store(orders) do
    orders
    |> group_by_store()
    |> Enum.max_by(fn {_key, group} -> length(group) end, fn -> {nil, []} end)
    |> elem(0)
  end

  @doc "A one-line summary per `:store`, sorted by key."
  def summary_by_store(orders) do
    for {key, cents} <- orders |> revenue_by_store() |> Enum.sort() do
      "#{key}: #{Money.format(cents)}"
    end
  end

  # -- by courier ---------------------------------------------------------------------------------

  @doc "Groups orders by `:courier`; orders without one go under `:unknown`."
  def group_by_courier(orders) do
    Enum.group_by(orders, &Map.get(&1, :courier, :unknown))
  end

  @doc "Revenue in cents for each `:courier`."
  def revenue_by_courier(orders) do
    orders
    |> group_by_courier()
    |> Map.new(fn {key, group} -> {key, revenue(group)} end)
  end

  @doc "The `:courier` with the most orders, or `nil` for no orders."
  def top_courier(orders) do
    orders
    |> group_by_courier()
    |> Enum.max_by(fn {_key, group} -> length(group) end, fn -> {nil, []} end)
    |> elem(0)
  end

  @doc "A one-line summary per `:courier`, sorted by key."
  def summary_by_courier(orders) do
    for {key, cents} <- orders |> revenue_by_courier() |> Enum.sort() do
      "#{key}: #{Money.format(cents)}"
    end
  end

  # -- by promo -----------------------------------------------------------------------------------

  @doc "Groups orders by `:promo`; orders without one go under `:unknown`."
  def group_by_promo(orders) do
    Enum.group_by(orders, &Map.get(&1, :promo, :unknown))
  end

  @doc "Revenue in cents for each `:promo`."
  def revenue_by_promo(orders) do
    orders
    |> group_by_promo()
    |> Map.new(fn {key, group} -> {key, revenue(group)} end)
  end

  @doc "The `:promo` with the most orders, or `nil` for no orders."
  def top_promo(orders) do
    orders
    |> group_by_promo()
    |> Enum.max_by(fn {_key, group} -> length(group) end, fn -> {nil, []} end)
    |> elem(0)
  end

  @doc "A one-line summary per `:promo`, sorted by key."
  def summary_by_promo(orders) do
    for {key, cents} <- orders |> revenue_by_promo() |> Enum.sort() do
      "#{key}: #{Money.format(cents)}"
    end
  end

  # -- by affiliate -------------------------------------------------------------------------------

  @doc "Groups orders by `:affiliate`; orders without one go under `:unknown`."
  def group_by_affiliate(orders) do
    Enum.group_by(orders, &Map.get(&1, :affiliate, :unknown))
  end

  @doc "Revenue in cents for each `:affiliate`."
  def revenue_by_affiliate(orders) do
    orders
    |> group_by_affiliate()
    |> Map.new(fn {key, group} -> {key, revenue(group)} end)
  end

  @doc "The `:affiliate` with the most orders, or `nil` for no orders."
  def top_affiliate(orders) do
    orders
    |> group_by_affiliate()
    |> Enum.max_by(fn {_key, group} -> length(group) end, fn -> {nil, []} end)
    |> elem(0)
  end

  @doc "A one-line summary per `:affiliate`, sorted by key."
  def summary_by_affiliate(orders) do
    for {key, cents} <- orders |> revenue_by_affiliate() |> Enum.sort() do
      "#{key}: #{Money.format(cents)}"
    end
  end

  # -- by language --------------------------------------------------------------------------------

  @doc "Groups orders by `:language`; orders without one go under `:unknown`."
  def group_by_language(orders) do
    Enum.group_by(orders, &Map.get(&1, :language, :unknown))
  end

  @doc "Revenue in cents for each `:language`."
  def revenue_by_language(orders) do
    orders
    |> group_by_language()
    |> Map.new(fn {key, group} -> {key, revenue(group)} end)
  end

  @doc "The `:language` with the most orders, or `nil` for no orders."
  def top_language(orders) do
    orders
    |> group_by_language()
    |> Enum.max_by(fn {_key, group} -> length(group) end, fn -> {nil, []} end)
    |> elem(0)
  end

  @doc "A one-line summary per `:language`, sorted by key."
  def summary_by_language(orders) do
    for {key, cents} <- orders |> revenue_by_language() |> Enum.sort() do
      "#{key}: #{Money.format(cents)}"
    end
  end

  # -- by platform --------------------------------------------------------------------------------

  @doc "Groups orders by `:platform`; orders without one go under `:unknown`."
  def group_by_platform(orders) do
    Enum.group_by(orders, &Map.get(&1, :platform, :unknown))
  end

  @doc "Revenue in cents for each `:platform`."
  def revenue_by_platform(orders) do
    orders
    |> group_by_platform()
    |> Map.new(fn {key, group} -> {key, revenue(group)} end)
  end

  @doc "The `:platform` with the most orders, or `nil` for no orders."
  def top_platform(orders) do
    orders
    |> group_by_platform()
    |> Enum.max_by(fn {_key, group} -> length(group) end, fn -> {nil, []} end)
    |> elem(0)
  end

  @doc "A one-line summary per `:platform`, sorted by key."
  def summary_by_platform(orders) do
    for {key, cents} <- orders |> revenue_by_platform() |> Enum.sort() do
      "#{key}: #{Money.format(cents)}"
    end
  end

  # -- by packaging -------------------------------------------------------------------------------

  @doc "Groups orders by `:packaging`; orders without one go under `:unknown`."
  def group_by_packaging(orders) do
    Enum.group_by(orders, &Map.get(&1, :packaging, :unknown))
  end

  @doc "Revenue in cents for each `:packaging`."
  def revenue_by_packaging(orders) do
    orders
    |> group_by_packaging()
    |> Map.new(fn {key, group} -> {key, revenue(group)} end)
  end

  @doc "The `:packaging` with the most orders, or `nil` for no orders."
  def top_packaging(orders) do
    orders
    |> group_by_packaging()
    |> Enum.max_by(fn {_key, group} -> length(group) end, fn -> {nil, []} end)
    |> elem(0)
  end

  @doc "A one-line summary per `:packaging`, sorted by key."
  def summary_by_packaging(orders) do
    for {key, cents} <- orders |> revenue_by_packaging() |> Enum.sort() do
      "#{key}: #{Money.format(cents)}"
    end
  end

  # -- by fulfilment ------------------------------------------------------------------------------

  @doc "Groups orders by `:fulfilment`; orders without one go under `:unknown`."
  def group_by_fulfilment(orders) do
    Enum.group_by(orders, &Map.get(&1, :fulfilment, :unknown))
  end

  @doc "Revenue in cents for each `:fulfilment`."
  def revenue_by_fulfilment(orders) do
    orders
    |> group_by_fulfilment()
    |> Map.new(fn {key, group} -> {key, revenue(group)} end)
  end

  @doc "The `:fulfilment` with the most orders, or `nil` for no orders."
  def top_fulfilment(orders) do
    orders
    |> group_by_fulfilment()
    |> Enum.max_by(fn {_key, group} -> length(group) end, fn -> {nil, []} end)
    |> elem(0)
  end

  @doc "A one-line summary per `:fulfilment`, sorted by key."
  def summary_by_fulfilment(orders) do
    for {key, cents} <- orders |> revenue_by_fulfilment() |> Enum.sort() do
      "#{key}: #{Money.format(cents)}"
    end
  end

  # -- by cohort ----------------------------------------------------------------------------------

  @doc "Groups orders by `:cohort`; orders without one go under `:unknown`."
  def group_by_cohort(orders) do
    Enum.group_by(orders, &Map.get(&1, :cohort, :unknown))
  end

  @doc "Revenue in cents for each `:cohort`."
  def revenue_by_cohort(orders) do
    orders
    |> group_by_cohort()
    |> Map.new(fn {key, group} -> {key, revenue(group)} end)
  end

  @doc "The `:cohort` with the most orders, or `nil` for no orders."
  def top_cohort(orders) do
    orders
    |> group_by_cohort()
    |> Enum.max_by(fn {_key, group} -> length(group) end, fn -> {nil, []} end)
    |> elem(0)
  end

  @doc "A one-line summary per `:cohort`, sorted by key."
  def summary_by_cohort(orders) do
    for {key, cents} <- orders |> revenue_by_cohort() |> Enum.sort() do
      "#{key}: #{Money.format(cents)}"
    end
  end

  # -- by plan ------------------------------------------------------------------------------------

  @doc "Groups orders by `:plan`; orders without one go under `:unknown`."
  def group_by_plan(orders) do
    Enum.group_by(orders, &Map.get(&1, :plan, :unknown))
  end

  @doc "Revenue in cents for each `:plan`."
  def revenue_by_plan(orders) do
    orders
    |> group_by_plan()
    |> Map.new(fn {key, group} -> {key, revenue(group)} end)
  end

  @doc "The `:plan` with the most orders, or `nil` for no orders."
  def top_plan(orders) do
    orders
    |> group_by_plan()
    |> Enum.max_by(fn {_key, group} -> length(group) end, fn -> {nil, []} end)
    |> elem(0)
  end

  @doc "A one-line summary per `:plan`, sorted by key."
  def summary_by_plan(orders) do
    for {key, cents} <- orders |> revenue_by_plan() |> Enum.sort() do
      "#{key}: #{Money.format(cents)}"
    end
  end

  # -- by origin ----------------------------------------------------------------------------------

  @doc "Groups orders by `:origin`; orders without one go under `:unknown`."
  def group_by_origin(orders) do
    Enum.group_by(orders, &Map.get(&1, :origin, :unknown))
  end

  @doc "Revenue in cents for each `:origin`."
  def revenue_by_origin(orders) do
    orders
    |> group_by_origin()
    |> Map.new(fn {key, group} -> {key, revenue(group)} end)
  end

  @doc "The `:origin` with the most orders, or `nil` for no orders."
  def top_origin(orders) do
    orders
    |> group_by_origin()
    |> Enum.max_by(fn {_key, group} -> length(group) end, fn -> {nil, []} end)
    |> elem(0)
  end

  @doc "A one-line summary per `:origin`, sorted by key."
  def summary_by_origin(orders) do
    for {key, cents} <- orders |> revenue_by_origin() |> Enum.sort() do
      "#{key}: #{Money.format(cents)}"
    end
  end
end
