defmodule Acme.Support.Goodwill do
  @moduledoc false

  @spec run(String.t(), pos_integer()) :: Acme.Billing.t()
  def run(account, amount), do: Acme.Billing.charge(account, amount)
end
