defmodule Acme.Reports.Billing do
  @moduledoc "The billing report: what was charged, summed."

  @doc "The report's title."
  @spec title() :: String.t()
  def title, do: "Billing report"

  @doc "How many charges, and their total in cents."
  @spec summary([map()]) :: %{count: non_neg_integer(), total: integer()}
  def summary(charges),
    do: %{count: length(charges), total: charges |> Enum.map(& &1.amount) |> Enum.sum()}
end
