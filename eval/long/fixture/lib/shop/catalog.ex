defmodule Shop.Catalog do
  @moduledoc """
  The products on sale, and what they cost.

  A product's stored `:price` is net, in cents. Every price a customer sees goes through
  `price_with_tax/1`, so filters, sorts and quotes all work on the price with tax.

  Search, filters and sorts take a list of products and return one, so they compose with a pipe;
  the forms without a list run over the whole catalog.
  """

  alias Shop.Money
  alias Shop.Product

  @products [
    %Product{sku: "TEA-1", name: "Green tea", price: 450, category: :drink, stock: 20},
    %Product{sku: "TEA-2", name: "Black tea", price: 400, category: :drink, stock: 0},
    %Product{sku: "MUG-1", name: "Mug", price: 1200, category: :kitchen, stock: 5},
    %Product{sku: "POT-1", name: "Teapot", price: 3500, category: :kitchen, stock: 2},
    %Product{sku: "TEA-3", name: "Oolong tea", price: 650, category: :drink, stock: 12},
    %Product{sku: "TEA-4", name: "Chamomile tea", price: 380, category: :drink, stock: 30},
    %Product{sku: "COF-1", name: "Coffee beans", price: 1400, category: :drink, stock: 8},
    %Product{sku: "MUG-2", name: "Travel mug", price: 1800, category: :kitchen, stock: 0},
    %Product{sku: "POT-2", name: "Kettle", price: 4200, category: :kitchen, stock: 3},
    %Product{
      sku: "CUP-1",
      name: "Tea cups, set of four",
      price: 2400,
      category: :kitchen,
      stock: 6
    },
    %Product{sku: "BOOK-1", name: "The book of tea", price: 2200, category: :books, stock: 4},
    %Product{sku: "GIFT-1", name: "Tea gift box", price: 5500, category: :gifts, stock: 1}
  ]

  # Shipping weight in grams, packed.
  @weights %{
    "TEA-1" => 100,
    "TEA-2" => 100,
    "TEA-3" => 100,
    "TEA-4" => 80,
    "COF-1" => 500,
    "MUG-1" => 350,
    "MUG-2" => 400,
    "POT-1" => 1200,
    "POT-2" => 1500,
    "CUP-1" => 900,
    "BOOK-1" => 600,
    "GIFT-1" => 2000
  }

  @category_labels %{
    drink: "Tea & coffee",
    kitchen: "Kitchen",
    books: "Books",
    gifts: "Gifts"
  }

  # Quantity pricing: from `min` units of one product, `percent` off each unit.
  @tiers [{1, 0}, {6, 5}, {12, 10}, {24, 15}]

  # The current sale: sku to percent off.
  @sales %{"POT-1" => 20, "CUP-1" => 10}

  # Sold together for a percent off the sum of the prices with tax.
  @bundles %{
    "TASTER" => %{name: "Tea taster", skus: ["TEA-1", "TEA-3", "TEA-4"], percent: 10},
    "BREW-SET" => %{name: "Brewing set", skus: ["POT-1", "CUP-1"], percent: 15},
    "DESK" => %{name: "Desk set", skus: ["MUG-1", "TEA-1"], percent: 5}
  }

  @price_bands [
    {"Under $10", 0, 999},
    {"$10 to $25", 1_000, 2_500},
    {"$25 to $50", 2_501, 5_000},
    {"Over $50", 5_001, nil}
  ]

  @low_stock 3

  @sorts [
    {"Price, low to high", :price_asc},
    {"Price, high to low", :price_desc},
    {"Name", :name},
    {"Most in stock", :stock}
  ]

  def list_products, do: @products

  def get_product(sku), do: Enum.find(@products, &(&1.sku == sku))

  def get_product!(sku) do
    case get_product(sku) do
      nil -> raise ArgumentError, "no product with sku #{inspect(sku)}"
      product -> product
    end
  end

  @doc "Looks a product up by sku: `{:ok, product}` or `{:error, :not_found}`."
  def fetch_product(sku) do
    case get_product(sku) do
      nil -> {:error, :not_found}
      product -> {:ok, product}
    end
  end

  @doc "The products for `skus`, in the order given. Unknown skus are skipped."
  def get_products(skus) do
    skus
    |> Enum.map(&get_product/1)
    |> Enum.reject(&is_nil/1)
  end

  def sku_exists?(sku), do: get_product(sku) != nil

  def in_stock?(%Product{stock: stock}), do: stock > 0

  @doc "The price including tax, in cents, rounded to the nearest cent."
  def price_with_tax(%Product{price: price}, rate \\ tax_rate()) do
    round(price * (1 + rate))
  end

  def tax_rate, do: Application.fetch_env!(:shop, :tax_rate)

  def by_category(category), do: Enum.filter(@products, &(&1.category == category))

  # -- prices -------------------------------------------------------------------------------------

  @doc "The tax part of the product's price, in cents."
  def tax_amount(%Product{price: price} = product), do: price_with_tax(product) - price

  @doc "Net price, tax and gross price in cents, as an invoice line shows them."
  def price_breakdown(%Product{price: price} = product) do
    gross = price_with_tax(product)
    %{net: price, tax: gross - price, gross: gross}
  end

  @doc "The price a customer sees, formatted, such as `\"$13.20\"`."
  def price_label(%Product{} = product), do: product |> price_with_tax() |> Money.format()

  @doc """
  What a change of net price to `new_price` does to the price a customer sees: the old and new
  prices with tax, and the difference (negative for a drop).
  """
  def price_change(%Product{} = product, new_price) when is_integer(new_price) do
    old = price_with_tax(product)
    new = price_with_tax(%{product | price: new_price})
    %{old: old, new: new, delta: new - old}
  end

  @doc "Takes `percent` off `cents`, rounding the discount down so the shop never gives away a cent."
  def percent_off(cents, 0), do: cents

  def percent_off(cents, percent) when percent in 1..100 do
    cents - div(cents * percent, 100)
  end

  # -- categories ---------------------------------------------------------------------------------

  @doc "Every category with at least one product, sorted."
  def categories do
    @products
    |> Enum.map(& &1.category)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc "The name a category goes by on the site."
  def category_label(category) when is_atom(category) do
    Map.get_lazy(@category_labels, category, fn ->
      category |> Atom.to_string() |> String.capitalize()
    end)
  end

  @doc "How many products each category holds."
  def category_counts, do: Enum.frequencies_by(@products, & &1.category)

  @doc """
  The cheapest and dearest price with tax in `category`, as `{min, max}`, or `nil` when the
  category is empty.
  """
  def category_price_range(category) do
    case category |> by_category() |> Enum.map(&price_with_tax/1) do
      [] -> nil
      prices -> Enum.min_max(prices)
    end
  end

  @doc "One line per category for the shop's side menu: label, count and price range."
  def category_summary do
    counts = category_counts()

    for category <- categories() do
      {min, max} = category_price_range(category)

      range =
        if min == max, do: Money.format(min), else: "#{Money.format(min)} - #{Money.format(max)}"

      "#{category_label(category)} (#{Map.fetch!(counts, category)}): #{range}"
    end
  end

  @doc "Parses a category from a query string, only accepting categories that exist."
  def parse_category(""), do: {:ok, nil}

  def parse_category(value) when is_binary(value) do
    case Enum.find(categories(), &(Atom.to_string(&1) == value)) do
      nil -> {:error, :unknown_category}
      category -> {:ok, category}
    end
  end

  # -- search -------------------------------------------------------------------------------------

  @doc """
  Products whose name or sku contains every word of `query`, ignoring case, best match first and
  then cheapest first. A blank query matches nothing.
  """
  def search(query), do: search(@products, query)

  def search(products, query) when is_binary(query) do
    case terms(query) do
      [] ->
        []

      terms ->
        products
        |> Enum.filter(&matches_all?(&1, terms))
        |> Enum.sort_by(&{-match_score(&1, terms), price_with_tax(&1)})
    end
  end

  @doc "Product names starting with `prefix`, for the search box's suggestions."
  def suggest(prefix, limit \\ 5) when is_binary(prefix) do
    prefix = prefix |> String.trim() |> String.downcase()

    if prefix == "" do
      []
    else
      @products
      |> Enum.filter(&(&1.name |> String.downcase() |> String.starts_with?(prefix)))
      |> Enum.map(& &1.name)
      |> Enum.sort()
      |> Enum.take(limit)
    end
  end

  defp terms(query) do
    query
    |> String.downcase()
    |> String.split(~r/[^a-z0-9-]+/u, trim: true)
  end

  defp haystack(%Product{name: name, sku: sku}), do: String.downcase(name <> " " <> sku)

  defp matches_all?(product, terms) do
    haystack = haystack(product)
    Enum.all?(terms, &String.contains?(haystack, &1))
  end

  # An exact sku beats a word that starts with the term, which beats a match anywhere.
  defp match_score(%Product{name: name, sku: sku}, terms) do
    words = name |> String.downcase() |> String.split()
    sku = String.downcase(sku)

    Enum.reduce(terms, 0, fn term, score ->
      cond do
        term == sku -> score + 3
        Enum.any?(words, &String.starts_with?(&1, term)) -> score + 2
        true -> score + 1
      end
    end)
  end

  # -- filters ------------------------------------------------------------------------------------

  @doc """
  Filters `products` by `opts`:

    * `:category` - a category, or a list of them
    * `:min_price`, `:max_price` - inclusive bounds on the price with tax, in cents
    * `:in_stock` - `true` keeps products with stock, `false` those without
    * `:on_sale` - `true` keeps products in the current sale, `false` the rest

  An unknown option raises, so a typo does not quietly match everything.
  """
  def filter(products \\ @products, opts) do
    Enum.reduce(opts, products, fn
      {:category, categories}, acc -> in_categories(acc, List.wrap(categories))
      {:min_price, min}, acc -> Enum.filter(acc, &(price_with_tax(&1) >= min))
      {:max_price, max}, acc -> Enum.filter(acc, &(price_with_tax(&1) <= max))
      {:in_stock, true}, acc -> in_stock(acc)
      {:in_stock, false}, acc -> out_of_stock(acc)
      {:on_sale, true}, acc -> Enum.filter(acc, &on_sale?/1)
      {:on_sale, false}, acc -> Enum.reject(acc, &on_sale?/1)
      {key, _value}, _acc -> raise ArgumentError, "unknown filter #{inspect(key)}"
    end)
  end

  @doc "The products in any of `categories`."
  def in_categories(products, categories), do: Enum.filter(products, &(&1.category in categories))

  @doc "The products whose price with tax is between `min` and `max` cents, inclusive."
  def priced_between(products \\ @products, min, max) when min <= max do
    Enum.filter(products, fn product ->
      price = price_with_tax(product)
      price >= min and price <= max
    end)
  end

  @doc "The products under `max` cents with tax: the gift finder's \"under $20\" and so on."
  def under(products \\ @products, max), do: Enum.filter(products, &(price_with_tax(&1) < max))

  def in_stock(products \\ @products), do: Enum.filter(products, &in_stock?/1)

  def out_of_stock(products \\ @products), do: Enum.reject(products, &in_stock?/1)

  @doc "Products still in stock but at or under `threshold` units: time to reorder."
  def low_stock(products \\ @products, threshold \\ @low_stock) do
    Enum.filter(products, &(&1.stock > 0 and &1.stock <= threshold))
  end

  # -- sorting ------------------------------------------------------------------------------------

  @doc "The sorts the product list offers, as `{label, value}` for a select."
  def sort_options, do: @sorts

  @doc """
  Sorts `products` by `:price_asc`, `:price_desc`, `:name` or `:stock` (most first). Ties fall
  back to the sku, so the order is stable from one page load to the next.
  """
  def sort(products, :price_asc), do: Enum.sort_by(products, &{price_with_tax(&1), &1.sku})
  def sort(products, :price_desc), do: Enum.sort_by(products, &{-price_with_tax(&1), &1.sku})
  def sort(products, :name), do: Enum.sort_by(products, &{String.downcase(&1.name), &1.sku})
  def sort(products, :stock), do: Enum.sort_by(products, &{-&1.stock, &1.sku})

  @doc "Parses a sort from a query string; anything unknown is an error, not a default."
  def parse_sort(value) when is_binary(value) do
    case Enum.find(@sorts, fn {_label, sort} -> Atom.to_string(sort) == value end) do
      nil -> {:error, :unknown_sort}
      {_label, sort} -> {:ok, sort}
    end
  end

  @doc "The cheapest product with tax, or `nil` for none."
  def cheapest(products \\ @products), do: Enum.min_by(products, &price_with_tax/1, fn -> nil end)

  @doc "The dearest product with tax, or `nil` for none."
  def most_expensive(products \\ @products) do
    Enum.max_by(products, &price_with_tax/1, fn -> nil end)
  end

  @doc "The mean price with tax of `products`, rounded, or `0` for none."
  def average_price([]), do: 0

  def average_price(products) do
    products
    |> Enum.map(&price_with_tax/1)
    |> Enum.sum()
    |> div(length(products))
  end

  # -- pricing tiers ------------------------------------------------------------------------------

  @doc "The quantity tiers as `{min_qty, percent_off}`, smallest first."
  def tiers, do: @tiers

  @doc "The percent off each unit when buying `qty` of one product."
  def tier_discount(qty) when is_integer(qty) and qty > 0 do
    @tiers
    |> Enum.filter(fn {min, _percent} -> qty >= min end)
    |> List.last()
    |> elem(1)
  end

  @doc "The price with tax of one unit when buying `qty` of `product`."
  def unit_price(%Product{} = product, qty) do
    product
    |> price_with_tax()
    |> percent_off(tier_discount(qty))
  end

  @doc "The tier a quantity of `qty` would reach next, as `{min_qty, percent_off}`, or `nil`."
  def next_tier(qty) when is_integer(qty) do
    Enum.find(@tiers, fn {min, _percent} -> min > qty end)
  end

  @doc "How many more units reach the next tier, or `nil` at the top tier."
  def units_to_next_tier(qty) do
    case next_tier(qty) do
      nil -> nil
      {min, _percent} -> min - qty
    end
  end

  @doc "The product page's quantity table: each tier's minimum, discount and unit price."
  def tier_table(%Product{} = product) do
    price = price_with_tax(product)

    for {min, percent} <- @tiers do
      %{min_qty: min, percent_off: percent, unit_price: percent_off(price, percent)}
    end
  end

  # -- bulk quotes --------------------------------------------------------------------------------

  @doc """
  A quote for `qty` of `product` at its tier price: the unit price, what the units would cost at
  the list price with tax, the quoted total and the saving.
  """
  def bulk_quote(%Product{} = product, qty) when is_integer(qty) and qty > 0 do
    unit = unit_price(product, qty)
    list_total = price_with_tax(product) * qty
    total = unit * qty

    %{
      sku: product.sku,
      qty: qty,
      unit_price: unit,
      list_total: list_total,
      total: total,
      savings: list_total - total
    }
  end

  @doc """
  Quotes a list of `{sku, qty}` lines. Lines for the same sku are merged first, so splitting an
  order across lines does not lose a tier.
  """
  def quote_lines(lines) do
    lines
    |> Enum.group_by(fn {sku, _qty} -> sku end, fn {_sku, qty} -> qty end)
    |> Enum.sort()
    |> Enum.map(fn {sku, qtys} -> bulk_quote(get_product!(sku), Enum.sum(qtys)) end)
  end

  @doc "The quoted total of `lines`, in cents."
  def quote_total(lines) do
    lines
    |> quote_lines()
    |> Enum.map(& &1.total)
    |> Enum.sum()
  end

  @doc "What the tiers save across `lines` against the list price with tax."
  def quote_savings(lines) do
    lines
    |> quote_lines()
    |> Enum.map(& &1.savings)
    |> Enum.sum()
  end

  @doc "A quote as text for a trade customer's email, one line per sku and a total."
  def format_quote(lines) do
    quotes = quote_lines(lines)

    body =
      for q <- quotes do
        "#{q.qty} x #{q.sku} at #{Money.format(q.unit_price)}: #{Money.format(q.total)}"
      end

    total = quotes |> Enum.map(& &1.total) |> Enum.sum()
    Enum.join(body ++ ["Total: #{Money.format(total)}"], "\n")
  end

  # -- sales --------------------------------------------------------------------------------------

  def on_sale?(%Product{sku: sku}), do: Map.has_key?(@sales, sku)

  @doc "The percent off `product` in the current sale, `0` when it is not on sale."
  def sale_percent(%Product{sku: sku}), do: Map.get(@sales, sku, 0)

  @doc "The advertised sale price with tax: the full price with tax less the sale's percent."
  def sale_price(%Product{} = product) do
    product
    |> price_with_tax()
    |> percent_off(sale_percent(product))
  end

  @doc "How much the sale takes off the price with tax, in cents."
  def sale_savings(%Product{} = product), do: price_with_tax(product) - sale_price(product)

  def on_sale(products \\ @products), do: Enum.filter(products, &on_sale?/1)

  @doc "The sale banner's text for `product`, or `nil` when it is not on sale."
  def sale_label(%Product{} = product) do
    if on_sale?(product) do
      "#{sale_percent(product)}% off: #{Money.format(sale_price(product))}, " <>
        "was #{Money.format(price_with_tax(product))}"
    end
  end

  # -- stock --------------------------------------------------------------------------------------

  @doc "Whether `qty` units of `product` can be sold from stock."
  def available?(%Product{stock: stock}, qty) when is_integer(qty), do: qty <= stock

  @doc """
  Takes `qty` units out of `product`'s stock: `{:ok, product}` with the stock reduced, or
  `{:error, {:insufficient_stock, available}}`.
  """
  def reserve(%Product{stock: stock} = product, qty) when is_integer(qty) and qty > 0 do
    if qty <= stock do
      {:ok, %{product | stock: stock - qty}}
    else
      {:error, {:insufficient_stock, stock}}
    end
  end

  @doc "Puts `qty` units back into `product`'s stock."
  def restock(%Product{stock: stock} = product, qty) when is_integer(qty) and qty > 0 do
    %{product | stock: stock + qty}
  end

  @doc "The net value of the stock on hand, in cents: what the books carry."
  def stock_value(products \\ @products) do
    products
    |> Enum.map(&(&1.price * &1.stock))
    |> Enum.sum()
  end

  @doc "The stock on hand valued at the price with tax: what it would take at the till."
  def retail_value(products \\ @products) do
    products
    |> Enum.map(&(price_with_tax(&1) * &1.stock))
    |> Enum.sum()
  end

  @doc "The warehouse's reorder sheet: one line per product, flagged when low or out."
  def stock_report(products \\ @products) do
    for product <- Enum.sort_by(products, & &1.sku) do
      flag =
        cond do
          product.stock == 0 -> " OUT"
          product.stock <= @low_stock -> " LOW"
          true -> ""
        end

      "#{product.sku} #{product.name}: #{product.stock}#{flag}"
    end
  end

  # -- weight -------------------------------------------------------------------------------------

  @doc "The packed weight of one unit of `product`, in grams."
  def weight(%Product{sku: sku}), do: Map.fetch!(@weights, sku)

  @doc "The packed weight of `{product, qty}` pairs, in grams."
  def total_weight(pairs) do
    pairs
    |> Enum.map(fn {product, qty} -> weight(product) * qty end)
    |> Enum.sum()
  end

  @doc "Price with tax per 100 grams, for the tea shelf's unit pricing."
  def price_per_100g(%Product{} = product) do
    div(price_with_tax(product) * 100, weight(product))
  end

  # -- related ------------------------------------------------------------------------------------

  @doc """
  Up to `limit` other products in `product`'s category, closest in price with tax first: the
  \"you may also like\" row.
  """
  def related(%Product{} = product, limit \\ 3) do
    price = price_with_tax(product)

    product.category
    |> by_category()
    |> Enum.reject(&(&1.sku == product.sku))
    |> Enum.sort_by(&{abs(price_with_tax(&1) - price), &1.sku})
    |> Enum.take(limit)
  end

  @doc "Products in the same category that cost more with tax, cheapest first: the upsell."
  def upgrades(%Product{} = product) do
    price = price_with_tax(product)

    product.category
    |> by_category()
    |> Enum.filter(&(price_with_tax(&1) > price))
    |> sort(:price_asc)
  end

  @doc "Products that sell alongside `product` from other categories, in stock only."
  def pairs_with(%Product{category: :drink}), do: filter_pairs([:kitchen, :books])
  def pairs_with(%Product{category: :kitchen}), do: filter_pairs([:drink])
  def pairs_with(%Product{}), do: filter_pairs([:drink, :kitchen])

  defp filter_pairs(categories) do
    @products
    |> in_categories(categories)
    |> in_stock()
    |> sort(:price_asc)
  end

  # -- bundles ------------------------------------------------------------------------------------

  @doc "The bundles on offer, by code, each a list of skus sold together."
  def bundles, do: @bundles

  @doc "The products in bundle `code`, or `{:error, :unknown_bundle}`."
  def bundle_products(code) do
    case Map.fetch(@bundles, code) do
      {:ok, %{skus: skus}} -> {:ok, Enum.map(skus, &get_product!/1)}
      :error -> {:error, :unknown_bundle}
    end
  end

  @doc """
  What bundle `code` costs: the prices with tax of its products, summed, less the bundle's
  percent off. `{:ok, cents}` or `{:error, :unknown_bundle}`.
  """
  def bundle_price(code) do
    with {:ok, products} <- bundle_products(code) do
      {:ok, products |> separate_price() |> percent_off(@bundles[code].percent)}
    end
  end

  @doc "How much bundle `code` saves against buying its products one by one."
  def bundle_savings(code) do
    with {:ok, products} <- bundle_products(code),
         {:ok, price} <- bundle_price(code) do
      {:ok, separate_price(products) - price}
    end
  end

  defp separate_price(products) do
    products
    |> Enum.map(&price_with_tax/1)
    |> Enum.sum()
  end

  @doc "Whether every product in bundle `code` is in stock, so the bundle can be sold."
  def bundle_available?(code) do
    case bundle_products(code) do
      {:ok, products} -> Enum.all?(products, &in_stock?/1)
      {:error, :unknown_bundle} -> false
    end
  end

  @doc "The bundles that hold `product`, as codes, sorted."
  def bundles_with(%Product{sku: sku}) do
    for {code, %{skus: skus}} <- Enum.sort(@bundles), sku in skus, do: code
  end

  # -- price bands --------------------------------------------------------------------------------

  @doc """
  The price bands the product list filters by, as `{label, min, max}` in cents with tax, both
  ends inclusive. The last band has no top, written as `nil`.
  """
  def price_bands, do: @price_bands

  @doc "The label of the band `product`'s price with tax falls in."
  def price_band(%Product{} = product) do
    price = price_with_tax(product)

    {label, _min, _max} =
      Enum.find(@price_bands, fn {_label, min, max} ->
        price >= min and (max == nil or price <= max)
      end)

    label
  end

  @doc "How many of `products` fall in each price band, in band order, empty bands included."
  def band_counts(products \\ @products) do
    counts = Enum.frequencies_by(products, &price_band/1)

    for {label, _min, _max} <- @price_bands do
      {label, Map.get(counts, label, 0)}
    end
  end

  @doc "The products in the band labelled `label`."
  def in_band(products \\ @products, label) do
    case List.keyfind(@price_bands, label, 0) do
      nil -> raise ArgumentError, "no price band #{inspect(label)}"
      {^label, min, nil} -> Enum.filter(products, &(price_with_tax(&1) >= min))
      {^label, min, max} -> priced_between(products, min, max)
    end
  end

  # -- comparison ---------------------------------------------------------------------------------

  @doc """
  The rows of the compare table for `products`, in the order given: name, price with tax, sale
  price, stock and unit price per 100 g.
  """
  def compare(products) do
    for product <- products do
      %{
        sku: product.sku,
        name: product.name,
        price: price_with_tax(product),
        sale_price: sale_price(product),
        in_stock: in_stock?(product),
        per_100g: price_per_100g(product)
      }
    end
  end

  @doc "The best value of `products` by price with tax per 100 g, or `nil` for none."
  def best_value([]), do: nil
  def best_value(products), do: Enum.min_by(products, &price_per_100g/1)
end
