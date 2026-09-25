defmodule Shop.Cart do
  @moduledoc "A cart: a map of sku to quantity."

  alias Shop.Catalog
  alias Shop.Money

  defstruct items: %{}

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
end
