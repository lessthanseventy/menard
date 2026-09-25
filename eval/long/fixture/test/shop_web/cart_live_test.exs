defmodule ShopWeb.CartLiveTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias Phoenix.LiveView.Socket
  alias Shop.Cart
  alias ShopWeb.CartLive

  # The page is driven through its callbacks on a bare socket: the fixture has no endpoint or
  # router to mount it behind.
  defp mounted do
    {:ok, socket} = CartLive.mount(%{}, %{}, %Socket{})
    socket
  end

  defp event(socket, name, params \\ %{}) do
    {:noreply, socket} = CartLive.handle_event(name, params, socket)
    socket
  end

  defp skus(socket), do: Enum.map(socket.assigns.products, & &1.sku)

  defp html(socket), do: rendered_to_string(CartLive.render(socket.assigns))

  test "mounts with an empty cart and the catalog, cheapest first" do
    socket = mounted()
    assert Cart.empty?(socket.assigns.cart)
    assert hd(skus(socket)) == "TEA-4"
  end

  test "adds, changes and removes lines" do
    socket =
      mounted()
      |> event("add", %{"sku" => "MUG-1"})
      |> event("inc", %{"sku" => "MUG-1"})
      |> event("add", %{"sku" => "TEA-1"})
      |> event("dec", %{"sku" => "TEA-1"})

    assert Cart.to_lines(socket.assigns.cart) == [{"MUG-1", 2}]

    socket = event(socket, "set_qty", %{"sku" => "MUG-1", "qty" => "abc"})
    assert socket.assigns.notice == "Enter a quantity from 0 to 20"

    socket = event(socket, "remove", %{"sku" => "MUG-1"})
    assert Cart.empty?(socket.assigns.cart)
  end

  test "applies and removes a promotion" do
    socket =
      mounted()
      |> event("add", %{"sku" => "TEA-1"})
      |> event("apply_promo", %{"code" => "FIVEOFF"})

    assert socket.assigns.promo_error == "Add $20.05 more to use that code"

    socket = event(socket, "apply_promo", %{"code" => "welcome10"})
    assert socket.assigns.cart.promo == "WELCOME10"

    assert socket
           |> event("remove_promo")
           |> Map.get(:assigns)
           |> Map.get(:cart)
           |> Map.get(:promo) == nil
  end

  test "search, category and sort narrow the list" do
    socket = event(mounted(), "search", %{"query" => "mug"})
    assert skus(socket) == ["MUG-1", "MUG-2"]

    socket =
      mounted()
      |> event("filter_category", %{"category" => "kitchen"})
      |> event("sort", %{"sort" => "price_desc"})

    assert skus(socket) == ["POT-2", "POT-1", "CUP-1", "MUG-2", "MUG-1"]

    assert event(socket, "sort", %{"sort" => "bogus"}).assigns.sort == :price_desc
  end

  test "reads the browsing state from the URL" do
    {:noreply, socket} =
      CartLive.handle_params(%{"category" => "books", "sort" => "nope"}, "/", mounted())

    assert skus(socket) == ["BOOK-1"]
    assert socket.assigns.sort == :price_asc
  end

  test "checkout validates, then places the order" do
    socket = mounted() |> event("add", %{"sku" => "TEA-2"}) |> event("checkout")
    assert socket.assigns.errors == [{:out_of_stock, "TEA-2"}, {:below_minimum, 500}]

    socket =
      socket
      |> event("remove", %{"sku" => "TEA-2"})
      |> event("add", %{"sku" => "MUG-1"})
      |> event("checkout")

    assert socket.assigns.notice == "Order placed: $18.19"
    assert Cart.empty?(socket.assigns.cart)
  end

  test "saves a line for later and moves it back" do
    socket =
      mounted()
      |> event("add", %{"sku" => "MUG-1"})
      |> event("save_for_later", %{"sku" => "MUG-1"})

    assert Cart.empty?(socket.assigns.cart)
    assert socket.assigns.saved == [{"MUG-1", 1}]
    assert html(socket) =~ "Saved for later"

    socket = event(socket, "move_to_cart", %{"sku" => "MUG-1"})
    assert Cart.to_lines(socket.assigns.cart) == [{"MUG-1", 1}]
    assert socket.assigns.saved == []
  end

  test "renders the cart and the product detail" do
    socket =
      mounted()
      |> event("add", %{"sku" => "POT-2"})
      |> event("show", %{"sku" => "POT-1"})

    html = html(socket)
    assert html =~ ~r/Total: <span class="price ?">\$46\.20</
    assert html =~ "Parcel weight: 1.5 kg"
    assert html =~ "20% off: $30.80, was $38.50"
    assert html =~ "Pay $54.19"
  end
end
