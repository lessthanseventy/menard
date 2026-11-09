defmodule Acme.Catalog.Product do
  @moduledoc "A product: its SKU, its list price in cents, its attributes and tags."

  defstruct [:sku, :price, attrs: %{}, tags: []]

  @type t :: %__MODULE__{
          sku: String.t(),
          price: non_neg_integer(),
          attrs: map(),
          tags: [String.t()]
        }
end
