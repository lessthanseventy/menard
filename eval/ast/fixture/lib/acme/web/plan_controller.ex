defmodule Acme.Web.PlanController do
  @moduledoc false

  alias Acme.Billing

  @spec run(String.t(), pos_integer()) :: Billing.t()
  def run(account, amount), do: account |> Billing.charge(amount) |> settle_pending()

  @spec settle_pending(Billing.t()) :: Billing.t()
  def settle_pending(%Billing{status: :pending} = charge), do: Billing.settle(charge)
  def settle_pending(%Billing{} = charge), do: charge
end
