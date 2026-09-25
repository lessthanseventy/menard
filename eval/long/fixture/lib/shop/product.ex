defmodule Shop.Product do
  @moduledoc "A thing for sale."

  @enforce_keys [:sku, :name, :price]
  defstruct [:sku, :name, :price, category: :general, stock: 0]

  @type t :: %__MODULE__{
          sku: String.t(),
          name: String.t(),
          price: non_neg_integer(),
          category: atom(),
          stock: non_neg_integer()
        }
end
