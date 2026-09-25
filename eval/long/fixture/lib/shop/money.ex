defmodule Shop.Money do
  @moduledoc "Amounts are integer cents in the shop's currency."

  @doc """
  Formats cents for display.

      iex> Shop.Money.format(1234)
      "$12.34"
  """
  def format(cents) when is_integer(cents) do
    sign = if cents < 0, do: "-", else: ""
    cents = abs(cents)
    whole = div(cents, 100)
    frac = cents |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")
    "#{sign}#{symbol()}#{whole}.#{frac}"
  end

  def symbol do
    case Application.get_env(:shop, :currency, "USD") do
      "USD" -> "$"
      "EUR" -> "€"
      "GBP" -> "£"
    end
  end
end
