defmodule Shop.MailerTest do
  use ExUnit.Case, async: true

  alias Shop.Cart
  alias Shop.Catalog
  alias Shop.Mailer

  test "greets by name" do
    assert Mailer.receipt("Ada", "o1", 1320) =~ "Hello Ada,"
  end

  test "subject quotes the order id" do
    assert Mailer.subject("o1") == ~s(Your order "o1")
  end

  describe "rendering" do
    test "fills placeholders from a keyword list or a map" do
      assert Mailer.render("Hi {{name}}, {{n}} items", name: "Ada", n: 3) == "Hi Ada, 3 items"
      assert Mailer.render("Hi {{name}}", %{name: "Ada"}) == "Hi Ada"
    end

    test "refuses to leave a placeholder" do
      assert_raise ArgumentError, "unfilled placeholders: total, date", fn ->
        Mailer.render("{{name}}: {{total}} on {{date}}", name: "Ada")
      end
    end

    test "envelope and first names" do
      assert Mailer.envelope("ada@example.com", "Hi", "Body") == %{
               from: "orders@shop.test",
               to: "ada@example.com",
               subject: "Hi",
               body: "Body"
             }

      assert Mailer.first_name("Ada Lovelace") == "Ada"
      assert Mailer.first_name("  ") == "there"
      assert Mailer.first_name(nil) == "there"
    end
  end

  describe "itemised receipt" do
    test "lists the lines and the total with tax" do
      order = %{
        id: "o7",
        status: :paid,
        lines: [{"MUG-1", 2}, {"TEA-1", 1}],
        placed_at: ~D[2026-01-10]
      }

      mail = Mailer.itemised_receipt("Ada Lovelace", order)

      assert mail =~ "Hello Ada,"
      assert mail =~ "order o7, placed on 10 January 2026."
      assert mail =~ "2 x Mug: $26.40\n1 x Green tea: $4.95"
      assert mail =~ "Total: $31.35"
    end

    test "order lines" do
      assert Mailer.order_lines([{"POT-1", 1}]) == ["1 x Teapot: $38.50"]
    end
  end

  describe "shipping notice" do
    test "names the carrier and links to tracking" do
      mail = Mailer.shipping_notice("Ada", "o7", :ups, "1Z 999")

      assert mail =~ "on its way with UPS."
      assert mail =~ "Tracking number: 1Z 999"
      assert mail =~ "https://www.ups.com/track?tracknum=1Z+999"
      assert mail =~ "arrive in 2-4 working days."
    end

    test "the estimate follows the region" do
      assert Mailer.shipping_notice("Ada", "o7", :dhl, "JD01", :eu) =~ "5-8 working days"
    end

    test "carriers and subject" do
      assert Mailer.carriers() == [:dhl, :post, :ups]
      assert Mailer.carrier_name(:post) == "Royal Mail"
      assert Mailer.shipping_subject("o7") == ~s(Your order "o7" has shipped)
    end
  end

  describe "refund notice" do
    test "a known reason gets its sentence" do
      mail = Mailer.refund_notice("Ada", "o7", 1320, :damaged)
      assert mail =~ "We have refunded $13.20 for order o7."
      assert mail =~ "We are sorry it arrived damaged."
    end

    test "any other reason is used as written" do
      assert Mailer.refund_notice("Ada", "o7", 500, "Goodwill.") =~ "\nGoodwill.\n"
    end

    test "amount, reasons and subject" do
      assert Mailer.refund_amount([{"MUG-1", 1}, {"TEA-1", 2}]) == 2310
      assert :late in Mailer.refund_reasons()
      assert Mailer.refund_subject("o7") == ~s(Your refund for order "o7")
    end
  end

  describe "abandoned cart" do
    test "only worth a reminder with enough in it" do
      refute Mailer.worth_reminding?(Cart.new())
      refute Mailer.worth_reminding?(Cart.new() |> Cart.add("TEA-1"))
      assert Mailer.worth_reminding?(Cart.new() |> Cart.add("MUG-1"))
    end

    test "lists the cart and nudges toward free shipping" do
      mail =
        Mailer.abandoned_cart("Ada", Cart.new() |> Cart.add("MUG-1"), "https://shop.test/cart")

      assert mail =~ "1 x Mug: $13.20"
      assert mail =~ "Total: $13.20"
      assert mail =~ "Add $36.80 more for free shipping"
      assert mail =~ "Pick up where you left off: https://shop.test/cart"
    end

    test "says so when shipping is free" do
      cart = Cart.new() |> Cart.add("POT-1", 2)
      assert Mailer.abandoned_cart("Ada", cart, "/cart") =~ "Shipping is on us."
    end

    test "subject counts the items" do
      assert Mailer.abandoned_cart_subject(Cart.new() |> Cart.add("MUG-1")) ==
               "You left something in your cart"

      assert Mailer.abandoned_cart_subject(Cart.new() |> Cart.add("MUG-1", 3)) ==
               "You left 3 items in your cart"
    end
  end

  describe "stock and prices" do
    test "back in stock" do
      mail = Mailer.back_in_stock("Ada", Catalog.get_product!("TEA-1"), "/p/TEA-1")
      assert mail =~ "Green tea is back in stock, at $4.95."
      assert mail =~ "We only have 20 for now: /p/TEA-1"
      assert Mailer.back_in_stock_subject(Catalog.get_product!("TEA-1")) == "Green tea is back"
    end

    test "price drop, only when the price did drop" do
      mug = Catalog.get_product!("MUG-1")

      assert Mailer.price_drop("Ada", mug, 1500, "/p/MUG-1") =~
               "now $13.20: down from $15.00, a saving of $1.80"

      assert Mailer.price_drop("Ada", mug, 1000, "/p/MUG-1") == nil
      assert Mailer.price_drop_subject(mug) == "Mug just got cheaper"
    end
  end

  test "review request lists each product once" do
    order = %{id: "o7", lines: [{"MUG-1", 1}, {"TEA-1", 2}, {"MUG-1", 1}]}
    mail = Mailer.review_request("Ada", order, "/review/o7")

    assert mail =~ "  * Mug\n  * Green tea\n"
    assert mail =~ "One line helps the next customer choose: /review/o7"
    assert Mailer.review_subject("o7") == ~s(How was order "o7"?)
  end
end
