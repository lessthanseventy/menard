defmodule Acme.Workers.Sweep do
  @moduledoc false

  alias Acme.Billing, as: Pay

  @spec run(String.t(), pos_integer()) :: {:ok, Pay.t()} | {:error, :not_settled}
  def run(account, amount), do: account |> Pay.charge(amount) |> Pay.settle() |> Pay.refund()
end
