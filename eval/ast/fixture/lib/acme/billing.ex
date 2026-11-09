defmodule Acme.Billing do
  @moduledoc """
  Charges, refunds and invoice totals. Amounts are integer cents.
  """

  alias Acme.BillingAddress

  defstruct [:id, :account, :amount, :address, status: :pending]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          account: String.t(),
          amount: pos_integer(),
          address: BillingAddress.t() | nil,
          status: :pending | :settled | :refunded
        }

  defmodule Error do
    @moduledoc "A charge that cannot be made."
    defexception [:message]
  end

  @currency "USD"

  @doc "The currency every charge is in."
  @spec currency() :: String.t()
  def currency, do: @currency

  @doc "A pending charge of `amount` cents to `account`, billed to `address`."
  @spec charge(String.t(), integer(), BillingAddress.t() | nil) :: t()
  def charge(account, amount, address \\ nil)

  def charge(_account, amount, _address) when amount <= 0,
    do: raise(Error, message: "amount must be positive")

  def charge(account, amount, address) do
    %__MODULE__{id: "ch_#{account}_#{amount}", account: account, amount: amount, address: address}
  end

  @doc "The charge, settled."
  @spec settle(t()) :: t()
  def settle(%__MODULE__{} = charge), do: %{charge | status: :settled}

  @doc "A settled charge, refunded."
  @spec refund(t()) :: {:ok, t()} | {:error, :not_settled}
  def refund(%__MODULE__{status: :settled} = charge), do: {:ok, %{charge | status: :refunded}}
  def refund(%__MODULE__{}), do: {:error, :not_settled}

  @doc "The sum of an invoice's `{label, cents}` lines."
  @spec invoice_total([{String.t(), integer()}]) :: integer()
  def invoice_total(lines), do: Enum.reduce(lines, 0, fn {_label, cents}, acc -> acc + cents end)
end
