defmodule Acme.Reports.Dashboard do
  @moduledoc "The finance dashboard's headline numbers."

  alias Acme.BillingAddress
  alias Acme.Reports.Billing

  @doc "The headline: the report's title and its totals."
  @spec headline([map()]) :: String.t()
  def headline(charges) do
    %{count: count, total: total} = Billing.summary(charges)
    "#{Billing.title()}: #{count} charges, #{total} cents"
  end

  @doc "Where the first charge was billed."
  @spec first_address([map()]) :: String.t() | nil
  def first_address([%{address: %BillingAddress{} = address} | _]),
    do: BillingAddress.format(address)

  def first_address(_), do: nil
end
