defmodule Acme.Support.Escalation do
  @moduledoc false

  alias Acme.Billing

  @spec run(String.t(), pos_integer()) :: Billing.t()
  def run(account, amount), do: account |> Billing.charge(amount) |> Billing.settle()
end
