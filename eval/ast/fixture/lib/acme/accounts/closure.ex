defmodule Acme.Accounts.Closure do
  @moduledoc false

  alias Acme.{Billing, BillingAddress}

  @spec run(String.t(), pos_integer()) :: Billing.t()
  def run(account, amount) do
    address = BillingAddress.new("1 Main St", "Springfield")
    Billing.charge(account, amount, address)
  end
end
