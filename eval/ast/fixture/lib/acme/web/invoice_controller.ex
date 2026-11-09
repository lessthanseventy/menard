defmodule Acme.Web.InvoiceController do
  @moduledoc false

  import Acme.Billing, only: [currency: 0, invoice_total: 1]

  @spec run(String.t(), pos_integer()) :: {String.t(), integer()}
  def run(_account, amount), do: {currency(), invoice_total([{"base", amount}, {"fee", amount}])}
end
