defmodule Acme.Orders.Reorder do
  @moduledoc false

  @spec run(String.t(), integer()) :: Acme.Billing.t() | {:error, String.t()}
  def run(account, amount) do
    Acme.Billing.charge(account, amount)
  rescue
    e in Acme.Billing.Error -> {:error, e.message}
  end
end
