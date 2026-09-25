defmodule Shop.Mailer do
  @moduledoc "The text of the mail that goes out with an order."

  alias Shop.Money

  @receipt """
  Hello {{name}},

  Thank you for your order {{order_id}}.
  Total: {{totl}}

  -- The Shop
  """

  def from, do: Application.fetch_env!(:shop, __MODULE__)[:from]

  def receipt(name, order_id, total_cents) do
    @receipt
    |> String.replace("{{name}}", name)
    |> String.replace("{{order_id}}", order_id)
    |> String.replace("{{total}}", Money.format(total_cents))
  end

  def subject(order_id), do: ~s(Your order "#{order_id}")
end
