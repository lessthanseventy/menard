defmodule Shop.CatalogTest do
  use ExUnit.Case, async: true

  alias Shop.Catalog

  defp product(sku), do: Catalog.get_product!(sku)
  defp skus(products), do: Enum.map(products, & &1.sku)

  test "finds a product by sku" do
    assert %Shop.Product{name: "Mug"} = Catalog.get_product!("MUG-1")
  end

  test "raises on an unknown sku" do
    assert_raise ArgumentError, fn -> Catalog.get_product!("NOPE") end
  end

  test "price with tax uses the configured rate" do
    assert Catalog.price_with_tax(Catalog.get_product!("MUG-1")) == 1320
  end

  test "stock" do
    refute Catalog.in_stock?(Catalog.get_product!("TEA-2"))
  end

  describe "lookup" do
    test "fetch_product answers with a tuple" do
      assert {:ok, %Shop.Product{sku: "POT-1"}} = Catalog.fetch_product("POT-1")
      assert Catalog.fetch_product("NOPE") == {:error, :not_found}
    end

    test "get_products keeps the order given and skips unknown skus" do
      assert Catalog.get_products(["POT-1", "NOPE", "MUG-1"]) |> skus() == ["POT-1", "MUG-1"]
    end

    test "sku_exists?" do
      assert Catalog.sku_exists?("TEA-1")
      refute Catalog.sku_exists?("TEA-9")
    end
  end

  describe "prices" do
    test "price with tax takes an explicit rate" do
      assert Catalog.price_with_tax(product("MUG-1"), 0.2) == 1440
    end

    test "breaks a price into net, tax and gross" do
      assert Catalog.tax_amount(product("MUG-1")) == 120
      assert Catalog.price_breakdown(product("MUG-1")) == %{net: 1200, tax: 120, gross: 1320}
    end

    test "labels the price a customer sees" do
      assert Catalog.price_label(product("MUG-1")) == "$13.20"
    end

    test "price_change reports the change with tax" do
      assert Catalog.price_change(product("MUG-1"), 1000) == %{old: 1320, new: 1100, delta: -220}
    end

    test "percent_off rounds the discount down" do
      assert Catalog.percent_off(1320, 10) == 1188
      assert Catalog.percent_off(999, 5) == 950
      assert Catalog.percent_off(999, 0) == 999
    end
  end

  describe "categories" do
    test "lists and labels them" do
      assert Catalog.categories() == [:books, :drink, :gifts, :kitchen]
      assert Catalog.category_label(:drink) == "Tea & coffee"
      assert Catalog.category_label(:garden) == "Garden"
    end

    test "counts and price ranges" do
      assert Catalog.category_counts() == %{drink: 5, kitchen: 5, books: 1, gifts: 1}
      assert Catalog.category_price_range(:drink) == {418, 1540}
      assert Catalog.category_price_range(:garden) == nil
    end

    test "summary for the side menu" do
      assert Catalog.category_summary() == [
               "Books (1): $24.20",
               "Tea & coffee (5): $4.18 - $15.40",
               "Gifts (1): $60.50",
               "Kitchen (5): $13.20 - $46.20"
             ]
    end

    test "parses a category from a query string" do
      assert Catalog.parse_category("drink") == {:ok, :drink}
      assert Catalog.parse_category("") == {:ok, nil}
      assert Catalog.parse_category("garden") == {:error, :unknown_category}
    end
  end

  describe "search" do
    test "matches name and sku, cheapest first among equal matches" do
      assert Catalog.search("tea") |> skus() ==
               ["TEA-4", "TEA-2", "TEA-1", "TEA-3", "BOOK-1", "CUP-1", "POT-1", "GIFT-1"]
    end

    test "every word must match, in any case" do
      assert Catalog.search("green TEA") |> skus() == ["TEA-1"]
      assert Catalog.search("tea-3") |> skus() == ["TEA-3"]
    end

    test "a word start beats a match inside a word" do
      assert Catalog.search("of") |> skus() == ["BOOK-1", "CUP-1", "COF-1"]
    end

    test "a blank query matches nothing" do
      assert Catalog.search("  ") == []
    end

    test "searches a given list" do
      assert Catalog.search(Catalog.by_category(:kitchen), "mug") |> skus() == ["MUG-1", "MUG-2"]
    end

    test "suggests names by prefix" do
      assert Catalog.suggest("te") == ["Tea cups, set of four", "Tea gift box", "Teapot"]
      assert Catalog.suggest("te", 2) == ["Tea cups, set of four", "Tea gift box"]
      assert Catalog.suggest("") == []
    end
  end

  describe "filters" do
    test "combines options" do
      assert Catalog.filter(category: :kitchen, in_stock: true) |> skus() ==
               ["MUG-1", "POT-1", "POT-2", "CUP-1"]

      assert Catalog.filter(min_price: 1000, max_price: 2000) |> skus() ==
               ["MUG-1", "COF-1", "MUG-2"]

      assert Catalog.filter(category: [:books, :gifts]) |> skus() == ["BOOK-1", "GIFT-1"]
      assert Catalog.filter(on_sale: true) |> skus() == ["POT-1", "CUP-1"]
    end

    test "an unknown option raises" do
      assert_raise ArgumentError, ~r/unknown filter :colour/, fn ->
        Catalog.filter(colour: :red)
      end
    end

    test "price ranges are on the price with tax" do
      assert Catalog.priced_between(400, 500) |> skus() == ["TEA-1", "TEA-2", "TEA-4"]
      assert Catalog.under(450) |> skus() == ["TEA-2", "TEA-4"]
    end

    test "stock" do
      assert Catalog.out_of_stock() |> skus() == ["TEA-2", "MUG-2"]
      assert Catalog.low_stock() |> skus() == ["POT-1", "POT-2", "GIFT-1"]

      assert Catalog.low_stock(Catalog.list_products(), 5) |> skus() ==
               ["MUG-1", "POT-1", "POT-2", "BOOK-1", "GIFT-1"]
    end
  end

  describe "sorting" do
    test "by price, name and stock" do
      kitchen = Catalog.by_category(:kitchen)
      drink = Catalog.by_category(:drink)

      assert Catalog.sort(kitchen, :price_asc) |> skus() ==
               ["MUG-1", "MUG-2", "CUP-1", "POT-1", "POT-2"]

      assert Catalog.sort(kitchen, :price_desc) |> skus() ==
               ["POT-2", "POT-1", "CUP-1", "MUG-2", "MUG-1"]

      assert Catalog.sort(drink, :name) |> skus() == ["TEA-2", "TEA-4", "COF-1", "TEA-1", "TEA-3"]

      assert Catalog.sort(drink, :stock) |> skus() == [
               "TEA-4",
               "TEA-1",
               "TEA-3",
               "COF-1",
               "TEA-2"
             ]
    end

    test "parses a sort" do
      assert Catalog.parse_sort("price_desc") == {:ok, :price_desc}
      assert Catalog.parse_sort("cheapest") == {:error, :unknown_sort}
    end

    test "cheapest, dearest and average" do
      assert Catalog.cheapest().sku == "TEA-4"
      assert Catalog.most_expensive().sku == "GIFT-1"
      assert Catalog.cheapest([]) == nil
      assert Catalog.average_price(Catalog.by_category(:kitchen)) == 2882
      assert Catalog.average_price([]) == 0
    end
  end

  describe "pricing tiers" do
    test "discount by quantity" do
      assert Enum.map([1, 5, 6, 12, 30], &Catalog.tier_discount/1) == [0, 0, 5, 10, 15]
      assert Catalog.unit_price(product("TEA-1"), 12) == 446
    end

    test "the next tier" do
      assert Catalog.next_tier(1) == {6, 5}
      assert Catalog.next_tier(24) == nil
      assert Catalog.units_to_next_tier(4) == 2
      assert Catalog.units_to_next_tier(30) == nil
    end

    test "the tier table" do
      assert Catalog.tier_table(product("MUG-1")) |> Enum.map(& &1.unit_price) ==
               [1320, 1254, 1188, 1122]
    end
  end

  describe "bulk quotes" do
    test "quotes one product" do
      assert Catalog.bulk_quote(product("MUG-1"), 6) == %{
               sku: "MUG-1",
               qty: 6,
               unit_price: 1254,
               list_total: 7920,
               total: 7524,
               savings: 396
             }
    end

    test "merges lines of the same sku before pricing" do
      lines = [{"TEA-1", 4}, {"MUG-1", 1}, {"TEA-1", 2}]

      assert [%{sku: "MUG-1", qty: 1}, %{sku: "TEA-1", qty: 6, unit_price: 471}] =
               Catalog.quote_lines(lines)

      assert Catalog.quote_total(lines) == 4146
      assert Catalog.quote_savings(lines) == 144
    end

    test "formats a quote" do
      assert Catalog.format_quote([{"TEA-1", 6}]) == "6 x TEA-1 at $4.71: $28.26\nTotal: $28.26"
    end
  end

  describe "sales" do
    test "sale price and savings" do
      pot = product("POT-1")
      assert Catalog.on_sale?(pot)
      assert Catalog.sale_percent(pot) == 20
      assert Catalog.sale_price(pot) == 3080
      assert Catalog.sale_savings(pot) == 770
      assert Catalog.sale_label(pot) == "20% off: $30.80, was $38.50"
    end

    test "a product not on sale" do
      mug = product("MUG-1")
      refute Catalog.on_sale?(mug)
      assert Catalog.sale_price(mug) == 1320
      assert Catalog.sale_label(mug) == nil
    end
  end

  describe "stock" do
    test "reserves and restocks" do
      pot = product("POT-1")
      assert Catalog.available?(pot, 2)
      refute Catalog.available?(pot, 3)
      assert {:ok, %{stock: 0}} = Catalog.reserve(pot, 2)
      assert Catalog.reserve(pot, 3) == {:error, {:insufficient_stock, 2}}
      assert Catalog.restock(product("TEA-2"), 10).stock == 10
    end

    test "values the stock" do
      products = [product("MUG-1"), product("POT-1")]
      assert Catalog.stock_value(products) == 13_000
      assert Catalog.retail_value(products) == 14_300
    end

    test "the reorder sheet" do
      assert Catalog.stock_report([product("MUG-1"), product("TEA-2"), product("POT-1")]) == [
               "MUG-1 Mug: 5",
               "POT-1 Teapot: 2 LOW",
               "TEA-2 Black tea: 0 OUT"
             ]
    end
  end

  describe "weight" do
    test "per unit and in total" do
      assert Catalog.weight(product("POT-1")) == 1200
      assert Catalog.total_weight([{product("MUG-1"), 2}, {product("TEA-1"), 3}]) == 1000
    end

    test "price per 100 g" do
      assert Catalog.price_per_100g(product("TEA-1")) == 495
      assert Catalog.price_per_100g(product("COF-1")) == 308
    end
  end

  describe "related" do
    test "closest in price in the same category" do
      assert Catalog.related(product("MUG-1")) |> skus() == ["MUG-2", "CUP-1", "POT-1"]
      assert Catalog.related(product("BOOK-1")) == []
    end

    test "upgrades and pairings" do
      assert Catalog.upgrades(product("CUP-1")) |> skus() == ["POT-1", "POT-2"]

      assert Catalog.pairs_with(product("TEA-1")) |> skus() ==
               ["MUG-1", "BOOK-1", "CUP-1", "POT-1", "POT-2"]
    end
  end

  describe "bundles" do
    test "prices a bundle below its parts" do
      assert Catalog.bundle_price("TASTER") == {:ok, 1466}
      assert Catalog.bundle_savings("TASTER") == {:ok, 162}
      assert Catalog.bundle_price("BREW-SET") == {:ok, 5517}
      assert Catalog.bundle_price("NOPE") == {:error, :unknown_bundle}
    end

    test "availability and membership" do
      assert Catalog.bundle_available?("BREW-SET")
      refute Catalog.bundle_available?("NOPE")
      assert Catalog.bundles_with(product("TEA-1")) == ["DESK", "TASTER"]
    end
  end

  describe "price bands" do
    test "places products in bands" do
      assert Enum.map(["TEA-1", "MUG-1", "POT-1", "GIFT-1"], &Catalog.price_band(product(&1))) ==
               ["Under $10", "$10 to $25", "$25 to $50", "Over $50"]

      assert Catalog.band_counts() == [
               {"Under $10", 4},
               {"$10 to $25", 4},
               {"$25 to $50", 3},
               {"Over $50", 1}
             ]
    end

    test "filters by band" do
      assert Catalog.in_band("Over $50") |> skus() == ["GIFT-1"]
      assert_raise ArgumentError, fn -> Catalog.in_band("Cheap") end
    end
  end

  test "compares products and finds the best value" do
    assert Catalog.compare([product("TEA-1")]) == [
             %{
               sku: "TEA-1",
               name: "Green tea",
               price: 495,
               sale_price: 495,
               in_stock: true,
               per_100g: 495
             }
           ]

    assert Catalog.best_value([product("MUG-1"), product("COF-1")]).sku == "COF-1"
    assert Catalog.best_value([]) == nil
  end
end
