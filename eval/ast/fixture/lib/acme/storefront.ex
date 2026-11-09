defmodule Acme.Storefront do
  @moduledoc "The storefront's product card."

  alias Acme.Catalog

  @doc "A product card: its slug, the retail price with tax, and its mean quality rating."
  @spec card(Acme.Catalog.Product.t(), list()) :: map()
  def card(product, reviews) do
    %{
      slug: Catalog.product_slug(product),
      price: Catalog.retail_price_with_tax(product),
      quality: Catalog.average_quality(reviews)
    }
  end

  @doc "In stock anywhere a customer can be shipped from."
  @spec in_stock?(map(), String.t()) :: boolean()
  def in_stock?(stock, sku),
    do: Catalog.stock_in_north(stock, sku) + Catalog.stock_in_south(stock, sku) > 0
end
