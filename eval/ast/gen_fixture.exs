# Writes eval/ast/fixture (the project both cases start from) and each case's hidden test.
#
#     elixir eval/ast/gen_fixture.exs    (formats what it wrote with the fixture's formatter)
#
# Two parts. `Acme.Billing`, referred to from ~50 files in every spelling a module has (full name,
# alias, multi-alias, `as:`, import, struct, nested exception, typespec), beside three things a text
# rename hits and must not: `Acme.BillingAddress`, `Acme.Reports.Billing` (aliased as `Billing`), and
# the string "Acme.Billing" that stored event rows carry. And `Acme.Catalog`, ~2,000 lines in five
# concerns, with private helpers two concerns share, per-concern attributes, an alias and a require.
root = Path.expand("fixture", __DIR__)
cases = Path.expand("cases", __DIR__)
File.rm_rf!(root)

write = fn path, text ->
  File.mkdir_p!(Path.dirname(path))
  File.write!(path, text)
end

put = fn rel, text -> write.(Path.join(root, rel), text) end

put.("mix.exs", """
defmodule Acme.MixProject do
  use Mix.Project

  def project do
    [app: :acme, version: "0.1.0", elixir: "~> 1.17", start_permanent: Mix.env() == :prod, deps: []]
  end

  def application, do: [extra_applications: [:logger]]
end
""")

put.(".formatter.exs", ~s([inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]]\n))
put.(".gitignore", "/_build/\n/deps/\n/.expert/\nerl_crash.dump\n/tmp/\n")
put.("test/test_helper.exs", "ExUnit.start()\n")

put.("CLAUDE.md", """
# Acme

CI runs `mix compile --warnings-as-errors`, `mix format --check-formatted` and `mix test` on every
push. A change that fails any of them is not merged.
""")

# ---------------------------------------------------------------------------------------------
# Billing

put.("lib/acme/billing.ex", ~S'''
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
  def charge(_account, amount, _address) when amount <= 0, do: raise(Error, message: "amount must be positive")

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
''')

put.("lib/acme/billing_address.ex", ~S'''
defmodule Acme.BillingAddress do
  @moduledoc "Where an invoice is sent."

  defstruct [:street, :city]

  @type t :: %__MODULE__{street: String.t(), city: String.t()}

  @doc "An address."
  @spec new(String.t(), String.t()) :: t()
  def new(street, city), do: %__MODULE__{street: street, city: city}

  @doc "One line, as printed on an invoice."
  @spec format(t()) :: String.t()
  def format(%__MODULE__{street: street, city: city}), do: "#{street}, #{city}"
end
''')

put.("lib/acme/reports/billing.ex", ~S'''
defmodule Acme.Reports.Billing do
  @moduledoc "The billing report: what was charged, summed."

  @doc "The report's title."
  @spec title() :: String.t()
  def title, do: "Billing report"

  @doc "How many charges, and their total in cents."
  @spec summary([map()]) :: %{count: non_neg_integer(), total: integer()}
  def summary(charges), do: %{count: length(charges), total: charges |> Enum.map(& &1.amount) |> Enum.sum()}
end
''')

put.("lib/acme/reports/dashboard.ex", ~S'''
defmodule Acme.Reports.Dashboard do
  @moduledoc "The finance dashboard's headline numbers."

  alias Acme.BillingAddress
  alias Acme.Reports.Billing

  @doc "The headline: the report's title and its totals."
  @spec headline([map()]) :: String.t()
  def headline(charges) do
    %{count: count, total: total} = Billing.summary(charges)
    "#{Billing.title()}: #{count} charges, #{total} cents"
  end

  @doc "Where the first charge was billed."
  @spec first_address([map()]) :: String.t() | nil
  def first_address([%{address: %BillingAddress{} = address} | _]), do: BillingAddress.format(address)
  def first_address(_), do: nil
end
''')

put.("lib/acme/events.ex", ~S'''
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
  def record(%Acme.Billing{} = charge), do: %{"source" => @billing_source, "id" => charge.id, "amount" => charge.amount}

  @doc "A stored row, read back."
  @spec from_row(map()) :: {:charge, String.t(), integer()} | {:unknown, String.t()}
  def from_row(%{"source" => "Acme.Billing", "id" => id, "amount" => amount}), do: {:charge, id, amount}
  def from_row(%{"source" => source}), do: {:unknown, source}
end
''')

for {name, city} <- [{"Domestic", "Springfield"}, {"Freight", "Shelbyville"}, {"Pickup", "Ogdenville"}] do
  put.("lib/acme/shipping/#{Macro.underscore(name)}.ex", """
  defmodule Acme.Shipping.#{name} do
    @moduledoc false
    alias Acme.BillingAddress

    @doc "The label for a parcel sent to the billing address."
    @spec label(String.t()) :: String.t()
    def label(street), do: street |> BillingAddress.new("#{city}") |> BillingAddress.format()
  end
  """)
end

areas = [
  accounts: ~w(Signup Upgrade Closure Merge Audit),
  orders: ~w(Checkout Reorder Cancel Split Export),
  subscriptions: ~w(Renewal Pause Resume Trial Proration),
  workers: ~w(NightlySettle RetryFailed Reconcile Dunning Sweep),
  notifications: ~w(Receipt Reminder Overdue Digest Webhook),
  payouts: ~w(Transfer Schedule Hold Release Ledger),
  support: ~w(RefundDesk Dispute Goodwill Escalation Credit),
  web: ~w(CheckoutController InvoiceController PlanController ApiCharges PortalSession)
]

forms = [:qualified, :alias, :multi, :as, :import, :struct, :error, :reports]

caller = fn mod, form ->
  body =
    case form do
      :qualified ->
        """
          @spec run(String.t(), pos_integer()) :: Acme.Billing.t()
          def run(account, amount), do: Acme.Billing.charge(account, amount)
        """

      :alias ->
        """
          alias Acme.Billing

          @spec run(String.t(), pos_integer()) :: Billing.t()
          def run(account, amount), do: account |> Billing.charge(amount) |> Billing.settle()
        """

      :multi ->
        """
          alias Acme.{Billing, BillingAddress}

          @spec run(String.t(), pos_integer()) :: Billing.t()
          def run(account, amount) do
            address = BillingAddress.new("1 Main St", "Springfield")
            Billing.charge(account, amount, address)
          end
        """

      :as ->
        """
          alias Acme.Billing, as: Pay

          @spec run(String.t(), pos_integer()) :: {:ok, Pay.t()} | {:error, :not_settled}
          def run(account, amount), do: account |> Pay.charge(amount) |> Pay.settle() |> Pay.refund()
        """

      :import ->
        """
          import Acme.Billing, only: [currency: 0, invoice_total: 1]

          @spec run(String.t(), pos_integer()) :: {String.t(), integer()}
          def run(_account, amount), do: {currency(), invoice_total([{"base", amount}, {"fee", amount}])}
        """

      :struct ->
        """
          alias Acme.Billing

          @spec run(String.t(), pos_integer()) :: Billing.t()
          def run(account, amount), do: account |> Billing.charge(amount) |> settle_pending()

          @spec settle_pending(Billing.t()) :: Billing.t()
          def settle_pending(%Billing{status: :pending} = charge), do: Billing.settle(charge)
          def settle_pending(%Billing{} = charge), do: charge
        """

      :error ->
        """
          @spec run(String.t(), integer()) :: Acme.Billing.t() | {:error, String.t()}
          def run(account, amount) do
            Acme.Billing.charge(account, amount)
          rescue
            e in Acme.Billing.Error -> {:error, e.message}
          end
        """

      :reports ->
        """
          alias Acme.BillingAddress
          alias Acme.Reports.Billing

          @spec run(String.t(), pos_integer()) :: %{count: non_neg_integer(), total: integer()}
          def run(account, amount) do
            address = BillingAddress.new("2 Elm St", "Shelbyville")
            Billing.summary([Acme.Billing.charge(account, amount, address)])
          end
        """
    end

  "defmodule #{mod} do\n  @moduledoc false\n\n#{body}end\n"
end

assertion = fn mod, form, amount ->
  case form do
    :qualified ->
      ~s|assert %Acme.Billing{amount: #{amount}, status: :pending} = #{mod}.run("acct", #{amount})|

    :alias ->
      ~s|assert %Billing{amount: #{amount}, status: :settled} = #{mod}.run("acct", #{amount})|

    :multi ->
      ~s|assert %Billing{address: %Acme.BillingAddress{city: "Springfield"}} = #{mod}.run("acct", #{amount})|

    :as ->
      ~s|assert {:ok, %Billing{status: :refunded}} = #{mod}.run("acct", #{amount})|

    :import ->
      ~s|assert {"USD", #{2 * amount}} = #{mod}.run("acct", #{amount})|

    :struct ->
      ~s|assert %Billing{status: :settled, account: "acct"} = #{mod}.run("acct", #{amount})|

    :error ->
      ~s|assert {:error, "amount must be positive"} = #{mod}.run("acct", 0)|

    :reports ->
      ~s|assert %{count: 1, total: #{amount}} = #{mod}.run("acct", #{amount})|
  end
end

areas
|> Enum.with_index()
|> Enum.each(fn {{area, names}, a} ->
  area_mod = Macro.camelize(to_string(area))

  tests =
    names
    |> Enum.with_index()
    |> Enum.map(fn {name, k} ->
      i = a * 5 + k
      form = Enum.at(forms, rem(i, length(forms)))
      mod = "Acme.#{area_mod}.#{name}"
      put.("lib/acme/#{area}/#{Macro.underscore(name)}.ex", caller.(mod, form))

      """
        test "#{name}" do
          #{assertion.(mod, form, 100 + i)}
        end
      """
    end)

  put.("test/acme/#{area}_test.exs", """
  defmodule Acme.#{area_mod}Test do
    use ExUnit.Case, async: true

    alias Acme.Billing

  #{Enum.join(tests, "\n")}end
  """)
end)

put.("test/acme/billing_test.exs", ~S'''
defmodule Acme.BillingTest do
  use ExUnit.Case, async: true

  alias Acme.Billing
  alias Acme.BillingAddress

  test "a charge is pending, in USD" do
    assert %Billing{status: :pending, amount: 500} = Billing.charge("acct", 500)
    assert Billing.currency() == "USD"
  end

  test "a charge of nothing is refused" do
    assert_raise Billing.Error, "amount must be positive", fn -> Billing.charge("acct", 0) end
  end

  test "only a settled charge is refunded" do
    charge = Billing.charge("acct", 500, BillingAddress.new("1 Main St", "Springfield"))
    assert {:error, :not_settled} = Billing.refund(charge)
    assert {:ok, %Billing{status: :refunded}} = charge |> Billing.settle() |> Billing.refund()
  end

  test "an invoice's total" do
    assert Billing.invoice_total([{"a", 100}, {"b", 250}]) == 350
  end
end
''')

put.("test/acme/events_test.exs", ~S'''
defmodule Acme.EventsTest do
  use ExUnit.Case, async: true

  alias Acme.Events

  test "a charge's row names its source as it always has" do
    assert %{"source" => "Acme.Billing", "amount" => 700} = Events.record(Acme.Billing.charge("acct", 700))
  end

  test "a stored row reads back" do
    assert {:charge, "ch_1", 700} = Events.from_row(%{"source" => "Acme.Billing", "id" => "ch_1", "amount" => 700})
    assert {:unknown, "Acme.Other"} = Events.from_row(%{"source" => "Acme.Other"})
  end
end
''')

put.("test/acme/reports/billing_test.exs", ~S'''
defmodule Acme.Reports.BillingTest do
  use ExUnit.Case, async: true

  alias Acme.BillingAddress
  alias Acme.Reports.Billing
  alias Acme.Reports.Dashboard

  test "the summary counts and sums" do
    charges = [Acme.Billing.charge("a", 100), Acme.Billing.charge("b", 250)]
    assert %{count: 2, total: 350} = Billing.summary(charges)
    assert Dashboard.headline(charges) == "Billing report: 2 charges, 350 cents"
  end

  test "the dashboard names the first address" do
    charges = [Acme.Billing.charge("a", 100, BillingAddress.new("9 Oak", "Capital City"))]
    assert Dashboard.first_address(charges) == "9 Oak, Capital City"
  end

  test "shipping labels" do
    assert Acme.Shipping.Freight.label("4 Pine") == "4 Pine, Shelbyville"
  end
end
''')

write.(Path.join(cases, "rename-module/hidden/test/hidden/rename_test.exs"), ~S'''
defmodule Acme.Hidden.RenameTest do
  use ExUnit.Case, async: true

  test "the module is Acme.Invoicing, its exception with it" do
    assert Code.ensure_loaded?(Acme.Invoicing)
    assert Code.ensure_loaded?(Acme.Invoicing.Error)
    refute Code.ensure_loaded?(Acme.Billing)
    refute Code.ensure_loaded?(Acme.Billing.Error)
    assert %{__struct__: Acme.Invoicing, amount: 5} = Acme.Invoicing.charge("a", 5)
    assert_raise Acme.Invoicing.Error, fn -> Acme.Invoicing.charge("a", 0) end
  end

  test "what only shares the name is untouched" do
    assert Code.ensure_loaded?(Acme.BillingAddress)
    refute Code.ensure_loaded?(Acme.InvoicingAddress)
    assert Code.ensure_loaded?(Acme.Reports.Billing)
    refute Code.ensure_loaded?(Acme.Reports.Invoicing)
    assert Acme.Reports.Billing.title() == "Billing report"
  end

  test "stored event rows keep their source" do
    assert Acme.Events.billing_source() == "Acme.Billing"
    assert {:charge, "x", 5} = Acme.Events.from_row(%{"source" => "Acme.Billing", "id" => "x", "amount" => 5})
    assert %{"source" => "Acme.Billing"} = Acme.Events.record(Acme.Invoicing.charge("a", 5))
  end
end
''')

# ---------------------------------------------------------------------------------------------
# Catalog

put.("lib/acme/catalog/product.ex", ~S'''
defmodule Acme.Catalog.Product do
  @moduledoc "A product: its SKU, its list price in cents, its attributes and tags."

  defstruct [:sku, :price, attrs: %{}, tags: []]

  @type t :: %__MODULE__{sku: String.t(), price: non_neg_integer(), attrs: map(), tags: [String.t()]}
end
''')

fields = ~w(name description brand color size weight material origin finish care warranty model)

tiers = [
  bronze: 2,
  silver: 5,
  gold: 10,
  platinum: 15,
  retail: 0,
  wholesale: 25,
  staff: 30,
  partner: 20,
  student: 12,
  senior: 8,
  nonprofit: 18,
  family: 22
]

warehouses = ~w(north south east west central overflow returns transit airport harbor depot annex)
aspects = ~w(quality value delivery packaging support fit durability design comfort accuracy setup noise)

# each function: {concern, name, arity, source, test body with MOD for the module}
products =
  [
    {"new_product", 2,
     ~S'''
       @doc """
       A new product with no attributes and no tags.

       The SKU is normalized (trimmed, upper-cased) so that two spellings of one SKU are one
       product, and the price is the list price in cents, before any tier discount or tax.
       """
       @spec new_product(String.t(), non_neg_integer()) :: Product.t()
       def new_product(sku, price) when is_integer(price) and price >= 0 do
         %Product{sku: normalize_sku(sku), price: price, attrs: %{}, tags: []}
       end
     ''', ~S|assert %{sku: "AB-1", price: 1000} = MOD.new_product(" ab-1 ", 1000)|},
    {"product_slug", 1,
     ~S'''
       @doc """
       The product's URL slug: its name, or its SKU when it has no name, lower-cased with every
       run of characters other than letters and digits made one dash.
       """
       @spec product_slug(Product.t()) :: String.t()
       def product_slug(%Product{} = product), do: slug(Map.get(product.attrs, :name, product.sku))
     ''',
     ~S[assert "deep-red-mug" = "ab-1" |> MOD.new_product(1) |> MOD.put_product_name("Deep  Red Mug!") |> MOD.product_slug()]}
  ] ++
    Enum.flat_map(fields, fn f ->
      [
        {"product_#{f}", 1,
         """
           @doc \"\"\"
           The product's #{f}, or `nil` when it has none.

           Text attributes are cleaned when they are put, so what comes back is what a customer
           sees on the product page, with no stray whitespace around or inside it.

           The #{f} is read from the product's attributes, not from a lookup: a product built
           with `new_product/2` and never given a #{f} answers `nil`, which a page should show
           as blank rather than as the word "nil".
           \"\"\"
           @spec product_#{f}(Product.t()) :: String.t() | nil
           def product_#{f}(%Product{} = product), do: Map.get(product.attrs, :#{f})
         """,
         ~s|assert MOD.product_#{f}("x" \|> MOD.new_product(1) \|> MOD.put_product_#{f}("  a   b ")) == "a b"|},
        {"put_product_#{f}", 2,
         """
           @doc \"\"\"
           Puts the product's #{f}.

           The value is cleaned (trimmed, each inner run of whitespace made one space) before it is
           stored. An empty value, or one of whitespace alone, removes the #{f}.

           Nothing else of the product changes: its SKU, price and tags stay as they were, and
           the other attributes are kept. The product returned is a new struct; the one passed
           in is unchanged, as with every function here.
           \"\"\"
           @spec put_product_#{f}(Product.t(), String.t()) :: Product.t()
           def put_product_#{f}(%Product{} = product, value) do
             case clean_text(value) do
               "" -> %{product | attrs: Map.delete(product.attrs, :#{f})}
               text -> %{product | attrs: Map.put(product.attrs, :#{f}, text)}
             end
           end
         """,
         ~s|assert %{attrs: attrs} = "x" \|> MOD.new_product(1) \|> MOD.put_product_#{f}("v") \|> MOD.put_product_#{f}("  ")\n    refute Map.has_key?(attrs, :#{f})|}
      ]
    end)

pricing =
  Enum.flat_map(tiers, fn {t, pct} ->
    base = round(1000 * (100 - pct) / 100)
    taxed = round(base * (1 + 0.0825))

    [
      {"#{t}_price", 1,
       """
         @doc \"\"\"
         The #{t} tier's price for the product, in cents.

         The #{t} discount is #{pct}% off the list price, rounded to the nearest cent. Tax is not
         included: see `#{t}_price_with_tax/1` for what the customer pays.

         The discount comes from the catalog's tier table, so a change to the #{t} rate is made
         there and nowhere else. A product priced at 0 stays at 0 in every tier, and the result
         is never negative.
         \"\"\"
         @spec #{t}_price(Product.t()) :: non_neg_integer()
         def #{t}_price(%Product{price: price}), do: discounted(price, @tier_discounts.#{t})
       """, ~s|assert MOD.#{t}_price(%Acme.Catalog.Product{sku: "X", price: 1000}) == #{base}|},
      {"#{t}_price_with_tax", 1,
       """
         @doc \"\"\"
         The #{t} tier's price with sales tax, in cents: what a #{t} customer pays.

         Tax is charged on the discounted price at the catalog's one rate, and the result is
         rounded to the nearest cent once, at the end.

         Rounding once matters: rounding the discount and then the tax apart can be a cent off
         on some prices, and the invoice and the product page then disagree about what the
         customer was told.
         \"\"\"
         @spec #{t}_price_with_tax(Product.t()) :: non_neg_integer()
         def #{t}_price_with_tax(%Product{} = product), do: product |> #{t}_price() |> with_tax()
       """, ~s|assert MOD.#{t}_price_with_tax(%Acme.Catalog.Product{sku: "X", price: 1000}) == #{taxed}|}
    ]
  end)

inventory =
  Enum.flat_map(warehouses, fn w ->
    [
      {"stock_in_#{w}", 2,
       """
         @doc \"\"\"
         How many of the SKU the #{w} warehouse holds; 0 when it holds none.

         The SKU is normalized first, so `" ab-1"` and `"AB-1"` are one line of stock.

         Stock is a map of warehouse to a map of SKU to level. A warehouse that has never been
         restocked has no entry at all, and is read as holding nothing; it is not an error to
         ask about one.
         \"\"\"
         @spec stock_in_#{w}(map(), String.t()) :: non_neg_integer()
         def stock_in_#{w}(stock, sku), do: stock |> Map.get(:#{w}, %{}) |> Map.get(normalize_sku(sku), 0)
       """, ~s|assert MOD.stock_in_#{w}(%{#{w}: %{"AB-1" => 7}}, " ab-1") == 7|},
      {"restock_#{w}", 3,
       """
         @doc \"\"\"
         Adds `qty` of the SKU to the #{w} warehouse.

         A level still under the low-stock mark after the restock is logged as a warning, so that
         a restock too small to matter is seen.

         The quantity must be a positive integer: a negative restock is a sale or a write-off,
         and those go through their own functions so that the books can tell them apart. The
         stock map returned holds every other warehouse unchanged.
         \"\"\"
         @spec restock_#{w}(map(), String.t(), pos_integer()) :: map()
         def restock_#{w}(stock, sku, qty) when is_integer(qty) and qty > 0 do
           key = normalize_sku(sku)
           level = stock_in_#{w}(stock, key) + qty
           warn_if_low(:#{w}, key, level)
           Map.update(stock, :#{w}, %{key => level}, &Map.put(&1, key, level))
         end
       """,
       ~s|assert %{#{w}: %{"AB-1" => 12}} = %{} \|> MOD.restock_#{w}("ab-1", 6) \|> MOD.restock_#{w}("AB-1 ", 6)|}
    ]
  end)

search_products =
  ~S|[%Acme.Catalog.Product{sku: "A", price: 500, attrs: %{name: "Red Mug", brand: "Acme", color: "red", size: "large", weight: "heavy", material: "clay", origin: "Spain", description: "a red mug", finish: "matte", care: "hand wash", warranty: "one year", model: "MK2"}}, %Acme.Catalog.Product{sku: "B", price: 1500, attrs: %{name: "Blue Cup"}}]|

queries = %{
  "name" => "red",
  "description" => "red",
  "brand" => "acme",
  "color" => "red",
  "size" => "larg",
  "weight" => "heav",
  "material" => "cla",
  "origin" => "spa",
  "finish" => "matt",
  "care" => "hand",
  "warranty" => "year",
  "model" => "mk"
}

search =
  [
    {"find_by_sku", 2,
     ~S'''
       @doc """
       The product with the SKU, or `nil`. The SKU is normalized first.
       """
       @spec find_by_sku([Product.t()], String.t()) :: Product.t() | nil
       def find_by_sku(products, sku) do
         key = normalize_sku(sku)
         Enum.find(products, &(&1.sku == key))
       end
     ''', ~s|assert %{sku: "B"} = MOD.find_by_sku(#{search_products}, " b ")|},
    {"price_range", 3,
     ~S'''
       @doc """
       The products whose list price is from `low` to `high`, both included.

       The bounds may be given as floats (a price typed in by a customer, converted from dollars)
       and are rounded to the nearest cent before the comparison.
       """
       @spec price_range([Product.t()], number(), number()) :: [Product.t()]
       def price_range(products, low, high) do
         {low, high} = {cents(low), cents(high)}
         products |> Enum.filter(&(&1.price >= low and &1.price <= high)) |> Enum.take(@max_results)
       end
     ''', ~s|assert [%{sku: "B"}] = MOD.price_range(#{search_products}, 999.6, 2000)|}
  ] ++
    Enum.flat_map(fields, fn f ->
      [
        {"search_by_#{f}", 2,
         """
           @doc \"\"\"
           The products whose #{f} contains `query`, case-insensitively, at most #{50} of them.

           A product with no #{f} never matches, and neither does an empty query.

           The products come back in the order they were given, so a caller that sorted them
           (by price, by popularity) keeps its order. The cap keeps a broad query from sending
           the whole catalog to a page that shows a screenful.
           \"\"\"
           @spec search_by_#{f}([Product.t()], String.t()) :: [Product.t()]
           def search_by_#{f}(products, query) do
             products |> Enum.filter(&matches?(Map.get(&1.attrs, :#{f}), query)) |> Enum.take(@max_results)
           end
         """,
         ~s|assert [%{sku: "A"}] = MOD.search_by_#{f}(#{search_products}, "#{String.upcase(queries[f])}")\n    assert [] = MOD.search_by_#{f}(#{search_products}, "")|},
        {"count_by_#{f}", 2,
         """
           @doc \"\"\"
           How many products `search_by_#{f}/2` finds for `query`.

           The count is of what the search returns, so it is capped the same way: a page that
           says "50 results" for a broad query is saying "at least 50". A count of 0 means the
           query matched nothing, not that the products have no #{f}.
           \"\"\"
           @spec count_by_#{f}([Product.t()], String.t()) :: non_neg_integer()
           def count_by_#{f}(products, query), do: products |> search_by_#{f}(query) |> length()
         """, ~s|assert MOD.count_by_#{f}(#{search_products}, "zzz") == 0|}
      ]
    end)

reviews =
  Enum.flat_map(aspects, fn a ->
    [
      {"rate_#{a}", 2,
       """
         @doc \"\"\"
         Adds a rating of the product's #{a}, from 1 to the catalog's top mark.

         A rating outside that range is clamped into it rather than refused: a 0 from a form that
         lost its value is a 1, a 9 from an import is the top mark.

         The new rating goes at the head of the list. Ratings are kept as given, one entry per
         rating, so a mean can be taken over any aspect later; nothing is summed in advance.
         \"\"\"
         @spec rate_#{a}([{atom(), pos_integer()}], integer()) :: [{atom(), pos_integer()}]
         def rate_#{a}(reviews, stars), do: [{:#{a}, clamp(stars, 1, @max_stars)} | reviews]
       """, ~s|assert MOD.rate_#{a}([], 9) == [{:#{a}, 5}]|},
      {"average_#{a}", 1,
       """
         @doc \"\"\"
         The mean rating of the product's #{a} to one decimal place, or `nil` with no rating.

         Only the #{a} ratings count; the other aspects in the list are left out.

         Every rating weighs the same, old or new. A product with a handful of ratings has a
         mean that moves a lot with each one; a page may want to show the count beside it.
         \"\"\"
         @spec average_#{a}([{atom(), pos_integer()}]) :: float() | nil
         def average_#{a}(reviews) do
           case for {:#{a}, stars} <- reviews, do: stars do
             [] -> nil
             stars -> round_to(Enum.sum(stars) / length(stars), 1)
           end
         end
       """, ~s|assert MOD.average_#{a}([{:#{a}, 4}, {:#{a}, 5}, {:other, 1}]) == 4.5|}
    ]
  end)

concerns = [
  {"Products", "products", products, "the SKU, the attribute text a product page shows, the slug.", []},
  {"Pricing", "pricing", pricing, "what each customer tier pays, before and after tax.",
   [
     "@tax_rate 0.0825",
     "@tier_discounts %{" <> Enum.map_join(tiers, ", ", fn {t, p} -> "#{t}: #{p}" end) <> "}"
   ]},
  {"Inventory", "inventory", inventory, "stock per warehouse, by normalized SKU.", ["@low_stock 5"]},
  {"Search", "search", search, "finding products by SKU, price and attribute.", ["@max_results 50"]},
  {"Reviews", "reviews", reviews, "ratings per aspect of a product, and their means.", ["@max_stars 5"]}
]

privates = %{
  "products" => ~S'''
    defp clean_text(value), do: value |> String.trim() |> String.replace(~r/\s+/, " ")

    defp slug(text) do
      text |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "-") |> String.trim("-")
    end
  ''',
  "pricing" => ~S'''
    defp discounted(price, pct), do: cents(price * (100 - pct) / 100)

    defp with_tax(price), do: cents(price * (1 + @tax_rate))
  ''',
  "inventory" => ~S'''
    defp warn_if_low(warehouse, sku, level) when level < @low_stock do
      Logger.warning("#{sku} is low in #{warehouse}: #{level} left")
    end

    defp warn_if_low(_warehouse, _sku, _level), do: :ok
  ''',
  "search" => ~S'''
    defp matches?(nil, _query), do: false
    defp matches?(_text, ""), do: false
    defp matches?(text, query), do: String.contains?(String.downcase(text), String.downcase(query))
  ''',
  "reviews" => ~S'''
    defp clamp(n, low, high), do: n |> max(low) |> min(high)

    defp round_to(x, places), do: Float.round(x, places)
  '''
}

shared = ~S'''
  # shared by more than one concern
  defp normalize_sku(sku), do: sku |> String.trim() |> String.upcase()

  defp cents(amount) when is_float(amount), do: round(amount)
  defp cents(amount) when is_integer(amount), do: amount
'''

sections =
  Enum.map_join(concerns, "\n", fn {title, key, funs, about, attrs} ->
    attrs = Enum.map_join(attrs, "", &"  #{&1}\n")

    """
      # ---------------------------------------------------------------------------------------
      # #{title}: #{about}

    #{attrs}#{if attrs != "", do: "\n", else: ""}#{Enum.map_join(funs, "\n", fn {_, _, src, _} -> src end)}
    #{privates[key]}
    """
  end)

put.("lib/acme/catalog.ex", """
defmodule Acme.Catalog do
  @moduledoc \"\"\"
  The catalog: products and their attributes, what each customer tier pays, stock per warehouse,
  search, and reviews.
  \"\"\"

  alias Acme.Catalog.Product

  require Logger

#{sections}
#{shared}end
""")

put.("lib/acme/storefront.ex", ~S'''
defmodule Acme.Storefront do
  @moduledoc "The storefront's product card."

  alias Acme.Catalog

  @doc "A product card: its slug, the retail price with tax, and its mean quality rating."
  @spec card(Acme.Catalog.Product.t(), list()) :: map()
  def card(product, reviews) do
    %{
      slug: Catalog.product_slug(product),
      price: Catalog.retail_price_with_tax(product),
      quality: Catalog.average_quality(reviews)
    }
  end

  @doc "In stock anywhere a customer can be shipped from."
  @spec in_stock?(map(), String.t()) :: boolean()
  def in_stock?(stock, sku), do: Catalog.stock_in_north(stock, sku) + Catalog.stock_in_south(stock, sku) > 0
end
''')

tests_of = fn funs, mod ->
  Enum.map_join(funs, "\n", fn {name, arity, _src, body} ->
    """
        test "#{name}/#{arity}" do
          #{String.replace(body, "MOD", mod)}
        end
    """
  end)
end

put.("test/acme/catalog_test.exs", """
defmodule Acme.CatalogTest do
  use ExUnit.Case, async: true

  alias Acme.Catalog

#{Enum.map_join(concerns, "\n", fn {_, key, funs, _, _} -> "  describe \"#{key}\" do\n#{tests_of.(funs, "Catalog")}  end\n" end)}
  test "the storefront's card" do
    product = "mug" |> Catalog.new_product(1000) |> Catalog.put_product_name("Mug")
    assert %{slug: "mug", price: 1083, quality: 4.0} = Acme.Storefront.card(product, [{:quality, 4}])
    refute Acme.Storefront.in_stock?(%{}, "mug")
  end
end
""")

manifest =
  Enum.map_join(concerns, ",\n", fn {title, _, funs, _, _} ->
    "    {Acme.Catalog.#{title}, [" <> Enum.map_join(funs, ", ", fn {n, a, _, _} -> "#{n}: #{a}" end) <> "]}"
  end)

write.(Path.join(cases, "split-module/hidden/test/hidden/split_test.exs"), """
defmodule Acme.Hidden.SplitTest do
  use ExUnit.Case, async: true

  @plan [
#{manifest}
  ]

  test "each function is in its new module, with its @doc, and still on Acme.Catalog" do
    for {mod, funs} <- @plan, {fun, arity} <- funs do
      assert Code.ensure_loaded?(mod), "\#{inspect(mod)} does not exist"
      assert function_exported?(mod, fun, arity), "\#{inspect(mod)}.\#{fun}/\#{arity} is missing"
      {:docs_v1, _, _, _, _, _, docs} = Code.fetch_docs(mod)

      assert Enum.any?(docs, &match?({{:function, ^fun, ^arity}, _, _, %{"en" => _}, _}, &1)),
             "\#{inspect(mod)}.\#{fun}/\#{arity} lost its @doc"

      assert function_exported?(Acme.Catalog, fun, arity), "Acme.Catalog.\#{fun}/\#{arity} is gone"
    end
  end

#{Enum.map_join(concerns, "\n", fn {title, key, funs, _, _} -> "  describe \"#{key}, on Acme.Catalog.#{title}\" do\n#{tests_of.(funs, "Acme.Catalog." <> title)}  end\n" end)}end
""")

hidden = Path.wildcard(Path.join(cases, "*/hidden/**/*.exs"))
{_, 0} = System.cmd("mix", ["format" | hidden], cd: root)
{_, 0} = System.cmd("mix", ["format"], cd: root)

counts = Enum.map_join(concerns, " ", fn {_, key, funs, _, _} -> "#{key}=#{length(funs)}" end)
IO.puts("tests per concern: #{counts}")
