defmodule Acme.Workers.NightlySettle do
  @moduledoc false

  alias Acme.BillingAddress
  alias Acme.Reports.Billing

  @spec run(String.t(), pos_integer()) :: %{count: non_neg_integer(), total: integer()}
  def run(account, amount) do
    address = BillingAddress.new("2 Elm St", "Shelbyville")
    Billing.summary([Acme.Billing.charge(account, amount, address)])
  end
end
