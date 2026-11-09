defmodule Acme.BillingAddress do
  @moduledoc "Where an invoice is sent."

  defstruct [:street, :city]

  @type t :: %__MODULE__{street: String.t(), city: String.t()}

  @doc "An address."
  @spec new(String.t(), String.t()) :: t()
  def new(street, city), do: %__MODULE__{street: street, city: city}

  @doc "One line, as printed on an invoice."
  @spec format(t()) :: String.t()
  def format(%__MODULE__{street: street, city: city}), do: "#{street}, #{city}"
end
