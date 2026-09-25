defmodule Shop.CartTest do
  use ExUnit.Case, async: true

  alias Shop.Cart

  defp cart(pairs), do: Cart.from_lines(pairs)

  defp with_promo(cart, code) do
    {:ok, cart} = Cart.apply_promo(cart, code)
    cart
  end

  test "adds and counts" do
    cart = Cart.new() |> Cart.add("MUG-1") |> Cart.add("MUG-1", 2) |> Cart.add("TEA-1")
    assert Cart.count(cart) == 4
  end

  test "total includes tax" do
    cart = Cart.new() |> Cart.add("MUG-1", 2)
    assert Cart.total(cart) == 2640
  end

  test "shipping is free over the threshold" do
    assert Cart.shipping(Cart.new() |> Cart.add("POT-1", 2)) == 0
    assert Cart.shipping(Cart.new() |> Cart.add("TEA-1")) == 499
  end

  test "formats a line" do
    [line] = Cart.new() |> Cart.add("MUG-1") |> Cart.lines()
    assert Cart.format_line(line) == "1 x Mug: $13.20"
  end

  describe "items" do
    test "sets, increments and decrements quantities" do
      c = cart([{"MUG-1", 2}])
      assert c |> Cart.set_quantity("MUG-1", 5) |> Cart.quantity("MUG-1") == 5
      refute c |> Cart.set_quantity("MUG-1", 0) |> Cart.has?("MUG-1")
      assert c |> Cart.increment("MUG-1") |> Cart.quantity("MUG-1") == 3
      assert c |> Cart.decrement("MUG-1") |> Cart.quantity("MUG-1") == 1
      refute c |> Cart.decrement("MUG-1") |> Cart.decrement("MUG-1") |> Cart.has?("MUG-1")
      assert Cart.decrement(c, "TEA-1") == c
    end

    test "clear drops the items and the promotion" do
      c = [{"MUG-1", 1}] |> cart() |> with_promo("WELCOME10") |> Cart.clear()
      assert Cart.empty?(c)
      assert c.promo == nil
    end

    test "skus, line totals and the largest line" do
      c = cart([{"TEA-1", 3}, {"MUG-1", 1}])
      assert Cart.skus(c) == ["MUG-1", "TEA-1"]
      assert Cart.line_total(c, "TEA-1") == 1485
      assert Cart.line_total(c, "POT-1") == 0
      assert {%{sku: "TEA-1"}, 3, 1485} = Cart.largest_line(c)
      assert Cart.largest_line(Cart.new()) == nil
    end
  end

  describe "merging" do
    test "sums quantities and keeps the account's promotion" do
      account = [{"MUG-1", 1}] |> cart() |> with_promo("WELCOME10")
      guest = %{cart([{"MUG-1", 2}, {"TEA-1", 1}]) | promo: "FIVEOFF"}

      merged = Cart.merge(account, guest)
      assert Cart.to_lines(merged) == [{"MUG-1", 3}, {"TEA-1", 1}]
      assert merged.promo == "WELCOME10"
      assert Cart.merge(Cart.new(), guest).promo == "FIVEOFF"
    end

    test "from_lines sums repeated skus, to_lines gives an order's lines" do
      c = cart([{"TEA-1", 1}, {"TEA-1", 2}, {"MUG-1", 1}])
      assert Cart.to_lines(c) == [{"MUG-1", 1}, {"TEA-1", 3}]
      assert Shop.Orders.total(%{lines: Cart.to_lines(c)}) == Cart.total(c)
    end

    test "merges priced lines of the same product" do
      lines = Cart.lines(cart([{"MUG-1", 1}])) ++ Cart.lines(cart([{"MUG-1", 2}, {"TEA-1", 1}]))

      assert [{%{sku: "MUG-1"}, 3, 3960}, {%{sku: "TEA-1"}, 1, 495}] = Cart.merge_lines(lines)
    end
  end

  describe "validation" do
    test "a good cart" do
      assert Cart.validate(cart([{"MUG-1", 1}])) == :ok
      assert Cart.valid?(cart([{"MUG-1", 1}]))
    end

    test "reports each problem" do
      assert Cart.validate(Cart.new()) == {:error, [:empty]}

      assert Cart.validate(cart([{"TEA-2", 1}, {"MUG-1", 1}])) ==
               {:error, [{:out_of_stock, "TEA-2"}]}

      assert Cart.validate(cart([{"POT-1", 3}])) == {:error, [{:insufficient_stock, "POT-1", 2}]}
      assert Cart.validate(cart([{"TEA-4", 21}])) == {:error, [{:too_many, "TEA-4", 20}]}
      assert Cart.validate(cart([{"TEA-4", 1}])) == {:error, [{:below_minimum, 500}]}
    end

    test "an unknown sku does not also fail the minimum" do
      assert Cart.validate(cart([{"GONE-1", 1}])) == {:error, [{:unknown_sku, "GONE-1"}]}
    end

    test "messages" do
      assert Cart.error_message({:unknown_sku, "GONE-1"}) == "GONE-1 is no longer sold"
      assert Cart.error_message({:out_of_stock, "TEA-2"}) == "Black tea is out of stock"
      assert Cart.error_message({:insufficient_stock, "POT-1", 2}) == "Only 2 Teapot left"
      assert Cart.error_message({:too_many, "TEA-4", 20}) =~ "At most 20 Chamomile tea"
      assert Cart.error_message(:empty) == "Your cart is empty"
      assert Cart.error_message({:below_minimum, 500}) == "The minimum order is $5.00"
    end

    test "prune fixes what it can" do
      c = cart([{"TEA-2", 1}, {"POT-1", 5}, {"GONE-1", 1}, {"TEA-4", 25}])
      assert Cart.prune(c).items == %{"POT-1" => 2, "TEA-4" => 20}
    end
  end

  describe "promotions" do
    test "codes ignore case and spaces" do
      assert {:ok, %{kind: :percent}} = Cart.promotion("  welcome10 ")
      assert Cart.promotion("NOPE") == :error
    end

    test "refuses an unknown code or a total under the minimum" do
      assert Cart.apply_promo(cart([{"TEA-1", 1}]), "NOPE") == {:error, :unknown_promo}

      assert Cart.apply_promo(cart([{"TEA-1", 1}]), "FIVEOFF") ==
               {:error, {:minimum_not_met, 2005}}
    end

    test "percent, fixed and buy-get discounts" do
      c = [{"MUG-1", 2}] |> cart() |> with_promo("welcome10")
      assert Cart.discount(c) == 264
      assert Cart.total_after_discount(c) == 2376
      assert Cart.promo_label(c) == "WELCOME10: -$2.64"

      assert [{"POT-1", 1}] |> cart() |> with_promo("FIVEOFF") |> Cart.discount() == 500
      assert [{"TEA-1", 7}] |> cart() |> with_promo("TEATIME") |> Cart.discount() == 990
    end

    test "a code stops counting when the total drops under its minimum" do
      c =
        [{"POT-1", 1}]
        |> cart()
        |> with_promo("FIVEOFF")
        |> Cart.remove("POT-1")
        |> Cart.add("TEA-1")

      assert Cart.active_promotion(c) == nil
      assert Cart.discount(c) == 0
      assert Cart.promo_label(c) == "FIVEOFF: add $20.05 more to use it"
    end

    test "free shipping and removal" do
      c = [{"MUG-1", 2}] |> cart() |> with_promo("SHIPFREE")
      assert Cart.shipping(c, :eu) == 0
      assert Cart.promo_label(c) == "SHIPFREE: free shipping"
      assert c |> Cart.remove_promo() |> Cart.promo_label() == nil
    end
  end

  describe "shipping" do
    test "regions" do
      assert Cart.regions() == [:domestic, :eu, :intl]
      assert Cart.region_label(:eu) == "Europe"
      assert Cart.parse_region("intl") == {:ok, :intl}
      assert Cart.parse_region("moon") == {:error, :unknown_region}
      assert Cart.delivery_estimate(:domestic) == "2-4 working days"
    end

    test "by weight and region" do
      assert Cart.weight(cart([{"MUG-1", 2}, {"TEA-1", 1}])) == 800
      assert Cart.shipping(cart([{"MUG-1", 1}]), :domestic) == 499
      assert Cart.shipping(cart([{"POT-2", 1}]), :domestic) == 799
      assert Cart.shipping(cart([{"POT-2", 1}]), :eu) == 1899
      assert Cart.shipping(cart([{"POT-1", 2}]), :domestic) == 0
      assert Cart.shipping(cart([{"POT-1", 2}]), :eu) == 2499
      assert Cart.shipping(Cart.new(), :intl) == 0
    end

    test "how far from free shipping" do
      assert Cart.free_shipping_remaining(cart([{"TEA-1", 1}])) == 4505
      assert Cart.free_shipping_hint(cart([{"TEA-1", 1}])) == "Add $45.05 more for free shipping"
      assert Cart.free_shipping_remaining(cart([{"POT-1", 2}])) == 0
      assert Cart.free_shipping_hint(cart([{"POT-1", 2}])) == nil
    end

    test "packs parcels by weight, heaviest first" do
      c = cart([{"POT-1", 2}, {"GIFT-1", 1}, {"MUG-1", 2}])

      assert Cart.packages(c, 3_000) == [
               [{"GIFT-1", 1}, {"MUG-1", 2}],
               [{"POT-1", 2}]
             ]
    end

    test "compares regions" do
      assert Cart.compare_regions(cart([{"MUG-1", 1}])) == [
               %{region: :domestic, shipping: 499, total: 1819},
               %{region: :eu, shipping: 1299, total: 2619},
               %{region: :intl, shipping: 1999, total: 3319}
             ]
    end
  end

  describe "summary" do
    test "grand total and tax" do
      assert Cart.grand_total(cart([{"MUG-1", 1}])) == 1819
      assert [{"MUG-1", 1}] |> cart() |> with_promo("WELCOME10") |> Cart.grand_total() == 1687
      assert Cart.tax(cart([{"MUG-1", 2}])) == 240
    end

    test "every figure" do
      c = [{"MUG-1", 2}] |> cart() |> with_promo("WELCOME10")

      assert Cart.summary(c, :eu) == %{
               count: 2,
               subtotal: 2640,
               discount: 264,
               shipping: 1599,
               total: 3975
             }
    end

    test "as text" do
      assert Cart.format_summary(cart([{"MUG-1", 1}])) ==
               "1 x Mug: $13.20\nSubtotal: $13.20\nShipping (Domestic): $4.99\nTotal: $18.19"
    end
  end

  describe "changes" do
    test "diffs two carts" do
      diff = Cart.diff(cart([{"MUG-1", 1}, {"TEA-1", 2}]), cart([{"TEA-1", 3}, {"POT-1", 1}]))
      assert diff == %{added: ["POT-1"], removed: ["MUG-1"], changed: [{"TEA-1", 2, 3}]}
      assert Cart.describe_diff(diff) == ["Added Teapot", "Removed Mug", "Green tea: 2 -> 3"]
    end

    test "splits what ships now from what waits" do
      {now, later} = Cart.split_by_availability(cart([{"POT-1", 3}, {"MUG-1", 1}, {"TEA-2", 2}]))
      assert Cart.to_lines(now) == [{"MUG-1", 1}, {"POT-1", 2}]
      assert Cart.to_lines(later) == [{"POT-1", 1}, {"TEA-2", 2}]
    end
  end

  describe "breakdowns" do
    test "by category and share" do
      c = cart([{"MUG-1", 1}, {"TEA-1", 2}])
      assert Cart.total_by_category(c) == %{kitchen: 1320, drink: 990}
      assert Cart.share_of_total(c, "MUG-1") == 57
      assert Cart.share_of_total(Cart.new(), "MUG-1") == 0
    end

    test "suggests related products in stock, not in the cart" do
      assert cart([{"MUG-1", 1}]) |> Cart.suggestions() |> Enum.map(& &1.sku) == [
               "CUP-1",
               "POT-1"
             ]
    end
  end

  describe "orders" do
    test "turns a valid cart into a pending order" do
      assert Cart.to_order(cart([{"MUG-1", 1}]), "o9", ~D[2026-02-01]) ==
               {:ok,
                %{
                  id: "o9",
                  status: :pending,
                  lines: [{"MUG-1", 1}],
                  placed_at: ~D[2026-02-01],
                  region: :domestic,
                  charged: 1819
                }}

      assert {:ok, %{coupon: "WELCOME10"}} =
               [{"MUG-1", 1}]
               |> cart()
               |> with_promo("WELCOME10")
               |> Cart.to_order("o9", ~D[2026-02-01])

      assert Cart.to_order(Cart.new(), "o9", ~D[2026-02-01]) == {:error, [:empty]}
    end

    test "buys an order again, skipping what is gone" do
      {c, skipped} = Cart.reorder(Cart.new(), %{lines: [{"MUG-1", 1}, {"GONE-1", 2}]})
      assert Cart.to_lines(c) == [{"MUG-1", 1}]
      assert skipped == ["GONE-1"]
    end
  end
end
