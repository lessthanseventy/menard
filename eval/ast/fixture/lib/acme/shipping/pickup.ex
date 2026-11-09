defmodule Acme.Shipping.Pickup do
  @moduledoc false
  alias Acme.BillingAddress

  @doc "The label for a parcel sent to the billing address."
  @spec label(String.t()) :: String.t()
  def label(street), do: street |> BillingAddress.new("Ogdenville") |> BillingAddress.format()
end
