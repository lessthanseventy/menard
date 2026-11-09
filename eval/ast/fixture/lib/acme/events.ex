defmodule Acme.Events do
  @moduledoc """
  Events as stored. A row's `source` names what wrote it, and rows already stored keep the name
  they were written with.
  """

  @billing_source "Acme.Billing"

  @doc "The `source` a charge's event row carries."
  @spec billing_source() :: String.t()
  def billing_source, do: @billing_source

  @doc "The row a charge is stored as."
  @spec record(Acme.Billing.t()) :: map()
  def record(%Acme.Billing{} = charge),
    do: %{"source" => @billing_source, "id" => charge.id, "amount" => charge.amount}

  @doc "A stored row, read back."
  @spec from_row(map()) :: {:charge, String.t(), integer()} | {:unknown, String.t()}
  def from_row(%{"source" => "Acme.Billing", "id" => id, "amount" => amount}),
    do: {:charge, id, amount}

  def from_row(%{"source" => source}), do: {:unknown, source}
end
