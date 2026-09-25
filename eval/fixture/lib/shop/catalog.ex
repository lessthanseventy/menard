defmodule Shop.Catalog do
  @moduledoc "The products on sale, and what they cost."

  alias Shop.Product

  @products [
    %Product{sku: "TEA-1", name: "Green tea", price: 450, category: :drink, stock: 20},
    %Product{sku: "TEA-2", name: "Black tea", price: 400, category: :drink, stock: 0},
    %Product{sku: "MUG-1", name: "Mug", price: 1200, category: :kitchen, stock: 5},
    %Product{sku: "POT-1", name: "Teapot", price: 3500, category: :kitchen, stock: 2}
  ]

  def list_products, do: @products

  def get_product(sku), do: Enum.find(@products, &(&1.sku == sku))

  def get_product!(sku) do
    case get_product(sku) do
      nil -> raise ArgumentError, "no product with sku #{inspect(sku)}"
      product -> product
    end
  end

  def in_stock?(%Product{stock: stock}), do: stock > 0

  @doc "The price including tax, in cents, rounded to the nearest cent."
  def price_with_tax(%Product{price: price}, rate \\ tax_rate()) do
    round(price * (1 + rate))
  end

  def tax_rate, do: Application.fetch_env!(:shop, :tax_rate)

  def by_category(category), do: Enum.filter(@products, &(&1.category == category))
end
