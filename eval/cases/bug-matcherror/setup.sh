python3 - <<'PY'
p = "lib/shop/catalog.ex"; s = open(p).read()
s = s.replace("  def get_product(sku), do: Enum.find(@products, &(&1.sku == sku))\n",
  "  def get_product(sku), do: Enum.find(@products, &(&1.sku == sku))\n\n"
  "  def fetch_product(sku) do\n    case get_product(sku) do\n      nil -> :error\n      product -> {:ok, product}\n    end\n  end\n")
open(p, "w").write(s)
p = "lib/shop/cart.ex"; s = open(p).read()
s = s.replace("      product = Catalog.get_product!(sku)\n", "      {:ok, product} = Catalog.fetch_product(sku)\n")
open(p, "w").write(s)
PY
