defmodule Acme.Hidden.SplitTest do
  use ExUnit.Case, async: true

  @plan [
    {Acme.Catalog.Products,
     [
       new_product: 2,
       product_slug: 1,
       product_name: 1,
       put_product_name: 2,
       product_description: 1,
       put_product_description: 2,
       product_brand: 1,
       put_product_brand: 2,
       product_color: 1,
       put_product_color: 2,
       product_size: 1,
       put_product_size: 2,
       product_weight: 1,
       put_product_weight: 2,
       product_material: 1,
       put_product_material: 2,
       product_origin: 1,
       put_product_origin: 2,
       product_finish: 1,
       put_product_finish: 2,
       product_care: 1,
       put_product_care: 2,
       product_warranty: 1,
       put_product_warranty: 2,
       product_model: 1,
       put_product_model: 2
     ]},
    {Acme.Catalog.Pricing,
     [
       bronze_price: 1,
       bronze_price_with_tax: 1,
       silver_price: 1,
       silver_price_with_tax: 1,
       gold_price: 1,
       gold_price_with_tax: 1,
       platinum_price: 1,
       platinum_price_with_tax: 1,
       retail_price: 1,
       retail_price_with_tax: 1,
       wholesale_price: 1,
       wholesale_price_with_tax: 1,
       staff_price: 1,
       staff_price_with_tax: 1,
       partner_price: 1,
       partner_price_with_tax: 1,
       student_price: 1,
       student_price_with_tax: 1,
       senior_price: 1,
       senior_price_with_tax: 1,
       nonprofit_price: 1,
       nonprofit_price_with_tax: 1,
       family_price: 1,
       family_price_with_tax: 1
     ]},
    {Acme.Catalog.Inventory,
     [
       stock_in_north: 2,
       restock_north: 3,
       stock_in_south: 2,
       restock_south: 3,
       stock_in_east: 2,
       restock_east: 3,
       stock_in_west: 2,
       restock_west: 3,
       stock_in_central: 2,
       restock_central: 3,
       stock_in_overflow: 2,
       restock_overflow: 3,
       stock_in_returns: 2,
       restock_returns: 3,
       stock_in_transit: 2,
       restock_transit: 3,
       stock_in_airport: 2,
       restock_airport: 3,
       stock_in_harbor: 2,
       restock_harbor: 3,
       stock_in_depot: 2,
       restock_depot: 3,
       stock_in_annex: 2,
       restock_annex: 3
     ]},
    {Acme.Catalog.Search,
     [
       find_by_sku: 2,
       price_range: 3,
       search_by_name: 2,
       count_by_name: 2,
       search_by_description: 2,
       count_by_description: 2,
       search_by_brand: 2,
       count_by_brand: 2,
       search_by_color: 2,
       count_by_color: 2,
       search_by_size: 2,
       count_by_size: 2,
       search_by_weight: 2,
       count_by_weight: 2,
       search_by_material: 2,
       count_by_material: 2,
       search_by_origin: 2,
       count_by_origin: 2,
       search_by_finish: 2,
       count_by_finish: 2,
       search_by_care: 2,
       count_by_care: 2,
       search_by_warranty: 2,
       count_by_warranty: 2,
       search_by_model: 2,
       count_by_model: 2
     ]},
    {Acme.Catalog.Reviews,
     [
       rate_quality: 2,
       average_quality: 1,
       rate_value: 2,
       average_value: 1,
       rate_delivery: 2,
       average_delivery: 1,
       rate_packaging: 2,
       average_packaging: 1,
       rate_support: 2,
       average_support: 1,
       rate_fit: 2,
       average_fit: 1,
       rate_durability: 2,
       average_durability: 1,
       rate_design: 2,
       average_design: 1,
       rate_comfort: 2,
       average_comfort: 1,
       rate_accuracy: 2,
       average_accuracy: 1,
       rate_setup: 2,
       average_setup: 1,
       rate_noise: 2,
       average_noise: 1
     ]}
  ]

  test "each function is in its new module, with its @doc, and still on Acme.Catalog" do
    for {mod, funs} <- @plan, {fun, arity} <- funs do
      assert Code.ensure_loaded?(mod), "#{inspect(mod)} does not exist"
      assert function_exported?(mod, fun, arity), "#{inspect(mod)}.#{fun}/#{arity} is missing"
      {:docs_v1, _, _, _, _, _, docs} = Code.fetch_docs(mod)

      assert Enum.any?(docs, &match?({{:function, ^fun, ^arity}, _, _, %{"en" => _}, _}, &1)),
             "#{inspect(mod)}.#{fun}/#{arity} lost its @doc"

      assert function_exported?(Acme.Catalog, fun, arity), "Acme.Catalog.#{fun}/#{arity} is gone"
    end
  end

  describe "products, on Acme.Catalog.Products" do
    test "new_product/2" do
      assert %{sku: "AB-1", price: 1000} = Acme.Catalog.Products.new_product(" ab-1 ", 1000)
    end

    test "product_slug/1" do
      assert "deep-red-mug" =
               "ab-1"
               |> Acme.Catalog.Products.new_product(1)
               |> Acme.Catalog.Products.put_product_name("Deep  Red Mug!")
               |> Acme.Catalog.Products.product_slug()
    end

    test "product_name/1" do
      assert Acme.Catalog.Products.product_name(
               "x"
               |> Acme.Catalog.Products.new_product(1)
               |> Acme.Catalog.Products.put_product_name("  a   b ")
             ) == "a b"
    end

    test "put_product_name/2" do
      assert %{attrs: attrs} =
               "x"
               |> Acme.Catalog.Products.new_product(1)
               |> Acme.Catalog.Products.put_product_name("v")
               |> Acme.Catalog.Products.put_product_name("  ")

      refute Map.has_key?(attrs, :name)
    end

    test "product_description/1" do
      assert Acme.Catalog.Products.product_description(
               "x"
               |> Acme.Catalog.Products.new_product(1)
               |> Acme.Catalog.Products.put_product_description("  a   b ")
             ) == "a b"
    end

    test "put_product_description/2" do
      assert %{attrs: attrs} =
               "x"
               |> Acme.Catalog.Products.new_product(1)
               |> Acme.Catalog.Products.put_product_description("v")
               |> Acme.Catalog.Products.put_product_description("  ")

      refute Map.has_key?(attrs, :description)
    end

    test "product_brand/1" do
      assert Acme.Catalog.Products.product_brand(
               "x"
               |> Acme.Catalog.Products.new_product(1)
               |> Acme.Catalog.Products.put_product_brand("  a   b ")
             ) == "a b"
    end

    test "put_product_brand/2" do
      assert %{attrs: attrs} =
               "x"
               |> Acme.Catalog.Products.new_product(1)
               |> Acme.Catalog.Products.put_product_brand("v")
               |> Acme.Catalog.Products.put_product_brand("  ")

      refute Map.has_key?(attrs, :brand)
    end

    test "product_color/1" do
      assert Acme.Catalog.Products.product_color(
               "x"
               |> Acme.Catalog.Products.new_product(1)
               |> Acme.Catalog.Products.put_product_color("  a   b ")
             ) == "a b"
    end

    test "put_product_color/2" do
      assert %{attrs: attrs} =
               "x"
               |> Acme.Catalog.Products.new_product(1)
               |> Acme.Catalog.Products.put_product_color("v")
               |> Acme.Catalog.Products.put_product_color("  ")

      refute Map.has_key?(attrs, :color)
    end

    test "product_size/1" do
      assert Acme.Catalog.Products.product_size(
               "x"
               |> Acme.Catalog.Products.new_product(1)
               |> Acme.Catalog.Products.put_product_size("  a   b ")
             ) == "a b"
    end

    test "put_product_size/2" do
      assert %{attrs: attrs} =
               "x"
               |> Acme.Catalog.Products.new_product(1)
               |> Acme.Catalog.Products.put_product_size("v")
               |> Acme.Catalog.Products.put_product_size("  ")

      refute Map.has_key?(attrs, :size)
    end

    test "product_weight/1" do
      assert Acme.Catalog.Products.product_weight(
               "x"
               |> Acme.Catalog.Products.new_product(1)
               |> Acme.Catalog.Products.put_product_weight("  a   b ")
             ) == "a b"
    end

    test "put_product_weight/2" do
      assert %{attrs: attrs} =
               "x"
               |> Acme.Catalog.Products.new_product(1)
               |> Acme.Catalog.Products.put_product_weight("v")
               |> Acme.Catalog.Products.put_product_weight("  ")

      refute Map.has_key?(attrs, :weight)
    end

    test "product_material/1" do
      assert Acme.Catalog.Products.product_material(
               "x"
               |> Acme.Catalog.Products.new_product(1)
               |> Acme.Catalog.Products.put_product_material("  a   b ")
             ) == "a b"
    end

    test "put_product_material/2" do
      assert %{attrs: attrs} =
               "x"
               |> Acme.Catalog.Products.new_product(1)
               |> Acme.Catalog.Products.put_product_material("v")
               |> Acme.Catalog.Products.put_product_material("  ")

      refute Map.has_key?(attrs, :material)
    end

    test "product_origin/1" do
      assert Acme.Catalog.Products.product_origin(
               "x"
               |> Acme.Catalog.Products.new_product(1)
               |> Acme.Catalog.Products.put_product_origin("  a   b ")
             ) == "a b"
    end

    test "put_product_origin/2" do
      assert %{attrs: attrs} =
               "x"
               |> Acme.Catalog.Products.new_product(1)
               |> Acme.Catalog.Products.put_product_origin("v")
               |> Acme.Catalog.Products.put_product_origin("  ")

      refute Map.has_key?(attrs, :origin)
    end

    test "product_finish/1" do
      assert Acme.Catalog.Products.product_finish(
               "x"
               |> Acme.Catalog.Products.new_product(1)
               |> Acme.Catalog.Products.put_product_finish("  a   b ")
             ) == "a b"
    end

    test "put_product_finish/2" do
      assert %{attrs: attrs} =
               "x"
               |> Acme.Catalog.Products.new_product(1)
               |> Acme.Catalog.Products.put_product_finish("v")
               |> Acme.Catalog.Products.put_product_finish("  ")

      refute Map.has_key?(attrs, :finish)
    end

    test "product_care/1" do
      assert Acme.Catalog.Products.product_care(
               "x"
               |> Acme.Catalog.Products.new_product(1)
               |> Acme.Catalog.Products.put_product_care("  a   b ")
             ) == "a b"
    end

    test "put_product_care/2" do
      assert %{attrs: attrs} =
               "x"
               |> Acme.Catalog.Products.new_product(1)
               |> Acme.Catalog.Products.put_product_care("v")
               |> Acme.Catalog.Products.put_product_care("  ")

      refute Map.has_key?(attrs, :care)
    end

    test "product_warranty/1" do
      assert Acme.Catalog.Products.product_warranty(
               "x"
               |> Acme.Catalog.Products.new_product(1)
               |> Acme.Catalog.Products.put_product_warranty("  a   b ")
             ) == "a b"
    end

    test "put_product_warranty/2" do
      assert %{attrs: attrs} =
               "x"
               |> Acme.Catalog.Products.new_product(1)
               |> Acme.Catalog.Products.put_product_warranty("v")
               |> Acme.Catalog.Products.put_product_warranty("  ")

      refute Map.has_key?(attrs, :warranty)
    end

    test "product_model/1" do
      assert Acme.Catalog.Products.product_model(
               "x"
               |> Acme.Catalog.Products.new_product(1)
               |> Acme.Catalog.Products.put_product_model("  a   b ")
             ) == "a b"
    end

    test "put_product_model/2" do
      assert %{attrs: attrs} =
               "x"
               |> Acme.Catalog.Products.new_product(1)
               |> Acme.Catalog.Products.put_product_model("v")
               |> Acme.Catalog.Products.put_product_model("  ")

      refute Map.has_key?(attrs, :model)
    end
  end

  describe "pricing, on Acme.Catalog.Pricing" do
    test "bronze_price/1" do
      assert Acme.Catalog.Pricing.bronze_price(%Acme.Catalog.Product{sku: "X", price: 1000}) ==
               980
    end

    test "bronze_price_with_tax/1" do
      assert Acme.Catalog.Pricing.bronze_price_with_tax(%Acme.Catalog.Product{
               sku: "X",
               price: 1000
             }) == 1061
    end

    test "silver_price/1" do
      assert Acme.Catalog.Pricing.silver_price(%Acme.Catalog.Product{sku: "X", price: 1000}) ==
               950
    end

    test "silver_price_with_tax/1" do
      assert Acme.Catalog.Pricing.silver_price_with_tax(%Acme.Catalog.Product{
               sku: "X",
               price: 1000
             }) == 1028
    end

    test "gold_price/1" do
      assert Acme.Catalog.Pricing.gold_price(%Acme.Catalog.Product{sku: "X", price: 1000}) == 900
    end

    test "gold_price_with_tax/1" do
      assert Acme.Catalog.Pricing.gold_price_with_tax(%Acme.Catalog.Product{
               sku: "X",
               price: 1000
             }) == 974
    end

    test "platinum_price/1" do
      assert Acme.Catalog.Pricing.platinum_price(%Acme.Catalog.Product{sku: "X", price: 1000}) ==
               850
    end

    test "platinum_price_with_tax/1" do
      assert Acme.Catalog.Pricing.platinum_price_with_tax(%Acme.Catalog.Product{
               sku: "X",
               price: 1000
             }) == 920
    end

    test "retail_price/1" do
      assert Acme.Catalog.Pricing.retail_price(%Acme.Catalog.Product{sku: "X", price: 1000}) ==
               1000
    end

    test "retail_price_with_tax/1" do
      assert Acme.Catalog.Pricing.retail_price_with_tax(%Acme.Catalog.Product{
               sku: "X",
               price: 1000
             }) == 1083
    end

    test "wholesale_price/1" do
      assert Acme.Catalog.Pricing.wholesale_price(%Acme.Catalog.Product{sku: "X", price: 1000}) ==
               750
    end

    test "wholesale_price_with_tax/1" do
      assert Acme.Catalog.Pricing.wholesale_price_with_tax(%Acme.Catalog.Product{
               sku: "X",
               price: 1000
             }) == 812
    end

    test "staff_price/1" do
      assert Acme.Catalog.Pricing.staff_price(%Acme.Catalog.Product{sku: "X", price: 1000}) == 700
    end

    test "staff_price_with_tax/1" do
      assert Acme.Catalog.Pricing.staff_price_with_tax(%Acme.Catalog.Product{
               sku: "X",
               price: 1000
             }) == 758
    end

    test "partner_price/1" do
      assert Acme.Catalog.Pricing.partner_price(%Acme.Catalog.Product{sku: "X", price: 1000}) ==
               800
    end

    test "partner_price_with_tax/1" do
      assert Acme.Catalog.Pricing.partner_price_with_tax(%Acme.Catalog.Product{
               sku: "X",
               price: 1000
             }) == 866
    end

    test "student_price/1" do
      assert Acme.Catalog.Pricing.student_price(%Acme.Catalog.Product{sku: "X", price: 1000}) ==
               880
    end

    test "student_price_with_tax/1" do
      assert Acme.Catalog.Pricing.student_price_with_tax(%Acme.Catalog.Product{
               sku: "X",
               price: 1000
             }) == 953
    end

    test "senior_price/1" do
      assert Acme.Catalog.Pricing.senior_price(%Acme.Catalog.Product{sku: "X", price: 1000}) ==
               920
    end

    test "senior_price_with_tax/1" do
      assert Acme.Catalog.Pricing.senior_price_with_tax(%Acme.Catalog.Product{
               sku: "X",
               price: 1000
             }) == 996
    end

    test "nonprofit_price/1" do
      assert Acme.Catalog.Pricing.nonprofit_price(%Acme.Catalog.Product{sku: "X", price: 1000}) ==
               820
    end

    test "nonprofit_price_with_tax/1" do
      assert Acme.Catalog.Pricing.nonprofit_price_with_tax(%Acme.Catalog.Product{
               sku: "X",
               price: 1000
             }) == 888
    end

    test "family_price/1" do
      assert Acme.Catalog.Pricing.family_price(%Acme.Catalog.Product{sku: "X", price: 1000}) ==
               780
    end

    test "family_price_with_tax/1" do
      assert Acme.Catalog.Pricing.family_price_with_tax(%Acme.Catalog.Product{
               sku: "X",
               price: 1000
             }) == 844
    end
  end

  describe "inventory, on Acme.Catalog.Inventory" do
    test "stock_in_north/2" do
      assert Acme.Catalog.Inventory.stock_in_north(%{north: %{"AB-1" => 7}}, " ab-1") == 7
    end

    test "restock_north/3" do
      assert %{north: %{"AB-1" => 12}} =
               %{}
               |> Acme.Catalog.Inventory.restock_north("ab-1", 6)
               |> Acme.Catalog.Inventory.restock_north("AB-1 ", 6)
    end

    test "stock_in_south/2" do
      assert Acme.Catalog.Inventory.stock_in_south(%{south: %{"AB-1" => 7}}, " ab-1") == 7
    end

    test "restock_south/3" do
      assert %{south: %{"AB-1" => 12}} =
               %{}
               |> Acme.Catalog.Inventory.restock_south("ab-1", 6)
               |> Acme.Catalog.Inventory.restock_south("AB-1 ", 6)
    end

    test "stock_in_east/2" do
      assert Acme.Catalog.Inventory.stock_in_east(%{east: %{"AB-1" => 7}}, " ab-1") == 7
    end

    test "restock_east/3" do
      assert %{east: %{"AB-1" => 12}} =
               %{}
               |> Acme.Catalog.Inventory.restock_east("ab-1", 6)
               |> Acme.Catalog.Inventory.restock_east("AB-1 ", 6)
    end

    test "stock_in_west/2" do
      assert Acme.Catalog.Inventory.stock_in_west(%{west: %{"AB-1" => 7}}, " ab-1") == 7
    end

    test "restock_west/3" do
      assert %{west: %{"AB-1" => 12}} =
               %{}
               |> Acme.Catalog.Inventory.restock_west("ab-1", 6)
               |> Acme.Catalog.Inventory.restock_west("AB-1 ", 6)
    end

    test "stock_in_central/2" do
      assert Acme.Catalog.Inventory.stock_in_central(%{central: %{"AB-1" => 7}}, " ab-1") == 7
    end

    test "restock_central/3" do
      assert %{central: %{"AB-1" => 12}} =
               %{}
               |> Acme.Catalog.Inventory.restock_central("ab-1", 6)
               |> Acme.Catalog.Inventory.restock_central("AB-1 ", 6)
    end

    test "stock_in_overflow/2" do
      assert Acme.Catalog.Inventory.stock_in_overflow(%{overflow: %{"AB-1" => 7}}, " ab-1") == 7
    end

    test "restock_overflow/3" do
      assert %{overflow: %{"AB-1" => 12}} =
               %{}
               |> Acme.Catalog.Inventory.restock_overflow("ab-1", 6)
               |> Acme.Catalog.Inventory.restock_overflow("AB-1 ", 6)
    end

    test "stock_in_returns/2" do
      assert Acme.Catalog.Inventory.stock_in_returns(%{returns: %{"AB-1" => 7}}, " ab-1") == 7
    end

    test "restock_returns/3" do
      assert %{returns: %{"AB-1" => 12}} =
               %{}
               |> Acme.Catalog.Inventory.restock_returns("ab-1", 6)
               |> Acme.Catalog.Inventory.restock_returns("AB-1 ", 6)
    end

    test "stock_in_transit/2" do
      assert Acme.Catalog.Inventory.stock_in_transit(%{transit: %{"AB-1" => 7}}, " ab-1") == 7
    end

    test "restock_transit/3" do
      assert %{transit: %{"AB-1" => 12}} =
               %{}
               |> Acme.Catalog.Inventory.restock_transit("ab-1", 6)
               |> Acme.Catalog.Inventory.restock_transit("AB-1 ", 6)
    end

    test "stock_in_airport/2" do
      assert Acme.Catalog.Inventory.stock_in_airport(%{airport: %{"AB-1" => 7}}, " ab-1") == 7
    end

    test "restock_airport/3" do
      assert %{airport: %{"AB-1" => 12}} =
               %{}
               |> Acme.Catalog.Inventory.restock_airport("ab-1", 6)
               |> Acme.Catalog.Inventory.restock_airport("AB-1 ", 6)
    end

    test "stock_in_harbor/2" do
      assert Acme.Catalog.Inventory.stock_in_harbor(%{harbor: %{"AB-1" => 7}}, " ab-1") == 7
    end

    test "restock_harbor/3" do
      assert %{harbor: %{"AB-1" => 12}} =
               %{}
               |> Acme.Catalog.Inventory.restock_harbor("ab-1", 6)
               |> Acme.Catalog.Inventory.restock_harbor("AB-1 ", 6)
    end

    test "stock_in_depot/2" do
      assert Acme.Catalog.Inventory.stock_in_depot(%{depot: %{"AB-1" => 7}}, " ab-1") == 7
    end

    test "restock_depot/3" do
      assert %{depot: %{"AB-1" => 12}} =
               %{}
               |> Acme.Catalog.Inventory.restock_depot("ab-1", 6)
               |> Acme.Catalog.Inventory.restock_depot("AB-1 ", 6)
    end

    test "stock_in_annex/2" do
      assert Acme.Catalog.Inventory.stock_in_annex(%{annex: %{"AB-1" => 7}}, " ab-1") == 7
    end

    test "restock_annex/3" do
      assert %{annex: %{"AB-1" => 12}} =
               %{}
               |> Acme.Catalog.Inventory.restock_annex("ab-1", 6)
               |> Acme.Catalog.Inventory.restock_annex("AB-1 ", 6)
    end
  end

  describe "search, on Acme.Catalog.Search" do
    test "find_by_sku/2" do
      assert %{sku: "B"} =
               Acme.Catalog.Search.find_by_sku(
                 [
                   %Acme.Catalog.Product{
                     sku: "A",
                     price: 500,
                     attrs: %{
                       name: "Red Mug",
                       brand: "Acme",
                       color: "red",
                       size: "large",
                       weight: "heavy",
                       material: "clay",
                       origin: "Spain",
                       description: "a red mug",
                       finish: "matte",
                       care: "hand wash",
                       warranty: "one year",
                       model: "MK2"
                     }
                   },
                   %Acme.Catalog.Product{sku: "B", price: 1500, attrs: %{name: "Blue Cup"}}
                 ],
                 " b "
               )
    end

    test "price_range/3" do
      assert [%{sku: "B"}] =
               Acme.Catalog.Search.price_range(
                 [
                   %Acme.Catalog.Product{
                     sku: "A",
                     price: 500,
                     attrs: %{
                       name: "Red Mug",
                       brand: "Acme",
                       color: "red",
                       size: "large",
                       weight: "heavy",
                       material: "clay",
                       origin: "Spain",
                       description: "a red mug",
                       finish: "matte",
                       care: "hand wash",
                       warranty: "one year",
                       model: "MK2"
                     }
                   },
                   %Acme.Catalog.Product{sku: "B", price: 1500, attrs: %{name: "Blue Cup"}}
                 ],
                 999.6,
                 2000
               )
    end

    test "search_by_name/2" do
      assert [%{sku: "A"}] =
               Acme.Catalog.Search.search_by_name(
                 [
                   %Acme.Catalog.Product{
                     sku: "A",
                     price: 500,
                     attrs: %{
                       name: "Red Mug",
                       brand: "Acme",
                       color: "red",
                       size: "large",
                       weight: "heavy",
                       material: "clay",
                       origin: "Spain",
                       description: "a red mug",
                       finish: "matte",
                       care: "hand wash",
                       warranty: "one year",
                       model: "MK2"
                     }
                   },
                   %Acme.Catalog.Product{sku: "B", price: 1500, attrs: %{name: "Blue Cup"}}
                 ],
                 "RED"
               )

      assert [] =
               Acme.Catalog.Search.search_by_name(
                 [
                   %Acme.Catalog.Product{
                     sku: "A",
                     price: 500,
                     attrs: %{
                       name: "Red Mug",
                       brand: "Acme",
                       color: "red",
                       size: "large",
                       weight: "heavy",
                       material: "clay",
                       origin: "Spain",
                       description: "a red mug",
                       finish: "matte",
                       care: "hand wash",
                       warranty: "one year",
                       model: "MK2"
                     }
                   },
                   %Acme.Catalog.Product{sku: "B", price: 1500, attrs: %{name: "Blue Cup"}}
                 ],
                 ""
               )
    end

    test "count_by_name/2" do
      assert Acme.Catalog.Search.count_by_name(
               [
                 %Acme.Catalog.Product{
                   sku: "A",
                   price: 500,
                   attrs: %{
                     name: "Red Mug",
                     brand: "Acme",
                     color: "red",
                     size: "large",
                     weight: "heavy",
                     material: "clay",
                     origin: "Spain",
                     description: "a red mug",
                     finish: "matte",
                     care: "hand wash",
                     warranty: "one year",
                     model: "MK2"
                   }
                 },
                 %Acme.Catalog.Product{sku: "B", price: 1500, attrs: %{name: "Blue Cup"}}
               ],
               "zzz"
             ) == 0
    end

    test "search_by_description/2" do
      assert [%{sku: "A"}] =
               Acme.Catalog.Search.search_by_description(
                 [
                   %Acme.Catalog.Product{
                     sku: "A",
                     price: 500,
                     attrs: %{
                       name: "Red Mug",
                       brand: "Acme",
                       color: "red",
                       size: "large",
                       weight: "heavy",
                       material: "clay",
                       origin: "Spain",
                       description: "a red mug",
                       finish: "matte",
                       care: "hand wash",
                       warranty: "one year",
                       model: "MK2"
                     }
                   },
                   %Acme.Catalog.Product{sku: "B", price: 1500, attrs: %{name: "Blue Cup"}}
                 ],
                 "RED"
               )

      assert [] =
               Acme.Catalog.Search.search_by_description(
                 [
                   %Acme.Catalog.Product{
                     sku: "A",
                     price: 500,
                     attrs: %{
                       name: "Red Mug",
                       brand: "Acme",
                       color: "red",
                       size: "large",
                       weight: "heavy",
                       material: "clay",
                       origin: "Spain",
                       description: "a red mug",
                       finish: "matte",
                       care: "hand wash",
                       warranty: "one year",
                       model: "MK2"
                     }
                   },
                   %Acme.Catalog.Product{sku: "B", price: 1500, attrs: %{name: "Blue Cup"}}
                 ],
                 ""
               )
    end

    test "count_by_description/2" do
      assert Acme.Catalog.Search.count_by_description(
               [
                 %Acme.Catalog.Product{
                   sku: "A",
                   price: 500,
                   attrs: %{
                     name: "Red Mug",
                     brand: "Acme",
                     color: "red",
                     size: "large",
                     weight: "heavy",
                     material: "clay",
                     origin: "Spain",
                     description: "a red mug",
                     finish: "matte",
                     care: "hand wash",
                     warranty: "one year",
                     model: "MK2"
                   }
                 },
                 %Acme.Catalog.Product{sku: "B", price: 1500, attrs: %{name: "Blue Cup"}}
               ],
               "zzz"
             ) == 0
    end

    test "search_by_brand/2" do
      assert [%{sku: "A"}] =
               Acme.Catalog.Search.search_by_brand(
                 [
                   %Acme.Catalog.Product{
                     sku: "A",
                     price: 500,
                     attrs: %{
                       name: "Red Mug",
                       brand: "Acme",
                       color: "red",
                       size: "large",
                       weight: "heavy",
                       material: "clay",
                       origin: "Spain",
                       description: "a red mug",
                       finish: "matte",
                       care: "hand wash",
                       warranty: "one year",
                       model: "MK2"
                     }
                   },
                   %Acme.Catalog.Product{sku: "B", price: 1500, attrs: %{name: "Blue Cup"}}
                 ],
                 "ACME"
               )

      assert [] =
               Acme.Catalog.Search.search_by_brand(
                 [
                   %Acme.Catalog.Product{
                     sku: "A",
                     price: 500,
                     attrs: %{
                       name: "Red Mug",
                       brand: "Acme",
                       color: "red",
                       size: "large",
                       weight: "heavy",
                       material: "clay",
                       origin: "Spain",
                       description: "a red mug",
                       finish: "matte",
                       care: "hand wash",
                       warranty: "one year",
                       model: "MK2"
                     }
                   },
                   %Acme.Catalog.Product{sku: "B", price: 1500, attrs: %{name: "Blue Cup"}}
                 ],
                 ""
               )
    end

    test "count_by_brand/2" do
      assert Acme.Catalog.Search.count_by_brand(
               [
                 %Acme.Catalog.Product{
                   sku: "A",
                   price: 500,
                   attrs: %{
                     name: "Red Mug",
                     brand: "Acme",
                     color: "red",
                     size: "large",
                     weight: "heavy",
                     material: "clay",
                     origin: "Spain",
                     description: "a red mug",
                     finish: "matte",
                     care: "hand wash",
                     warranty: "one year",
                     model: "MK2"
                   }
                 },
                 %Acme.Catalog.Product{sku: "B", price: 1500, attrs: %{name: "Blue Cup"}}
               ],
               "zzz"
             ) == 0
    end

    test "search_by_color/2" do
      assert [%{sku: "A"}] =
               Acme.Catalog.Search.search_by_color(
                 [
                   %Acme.Catalog.Product{
                     sku: "A",
                     price: 500,
                     attrs: %{
                       name: "Red Mug",
                       brand: "Acme",
                       color: "red",
                       size: "large",
                       weight: "heavy",
                       material: "clay",
                       origin: "Spain",
                       description: "a red mug",
                       finish: "matte",
                       care: "hand wash",
                       warranty: "one year",
                       model: "MK2"
                     }
                   },
                   %Acme.Catalog.Product{sku: "B", price: 1500, attrs: %{name: "Blue Cup"}}
                 ],
                 "RED"
               )

      assert [] =
               Acme.Catalog.Search.search_by_color(
                 [
                   %Acme.Catalog.Product{
                     sku: "A",
                     price: 500,
                     attrs: %{
                       name: "Red Mug",
                       brand: "Acme",
                       color: "red",
                       size: "large",
                       weight: "heavy",
                       material: "clay",
                       origin: "Spain",
                       description: "a red mug",
                       finish: "matte",
                       care: "hand wash",
                       warranty: "one year",
                       model: "MK2"
                     }
                   },
                   %Acme.Catalog.Product{sku: "B", price: 1500, attrs: %{name: "Blue Cup"}}
                 ],
                 ""
               )
    end

    test "count_by_color/2" do
      assert Acme.Catalog.Search.count_by_color(
               [
                 %Acme.Catalog.Product{
                   sku: "A",
                   price: 500,
                   attrs: %{
                     name: "Red Mug",
                     brand: "Acme",
                     color: "red",
                     size: "large",
                     weight: "heavy",
                     material: "clay",
                     origin: "Spain",
                     description: "a red mug",
                     finish: "matte",
                     care: "hand wash",
                     warranty: "one year",
                     model: "MK2"
                   }
                 },
                 %Acme.Catalog.Product{sku: "B", price: 1500, attrs: %{name: "Blue Cup"}}
               ],
               "zzz"
             ) == 0
    end

    test "search_by_size/2" do
      assert [%{sku: "A"}] =
               Acme.Catalog.Search.search_by_size(
                 [
                   %Acme.Catalog.Product{
                     sku: "A",
                     price: 500,
                     attrs: %{
                       name: "Red Mug",
                       brand: "Acme",
                       color: "red",
                       size: "large",
                       weight: "heavy",
                       material: "clay",
                       origin: "Spain",
                       description: "a red mug",
                       finish: "matte",
                       care: "hand wash",
                       warranty: "one year",
                       model: "MK2"
                     }
                   },
                   %Acme.Catalog.Product{sku: "B", price: 1500, attrs: %{name: "Blue Cup"}}
                 ],
                 "LARG"
               )

      assert [] =
               Acme.Catalog.Search.search_by_size(
                 [
                   %Acme.Catalog.Product{
                     sku: "A",
                     price: 500,
                     attrs: %{
                       name: "Red Mug",
                       brand: "Acme",
                       color: "red",
                       size: "large",
                       weight: "heavy",
                       material: "clay",
                       origin: "Spain",
                       description: "a red mug",
                       finish: "matte",
                       care: "hand wash",
                       warranty: "one year",
                       model: "MK2"
                     }
                   },
                   %Acme.Catalog.Product{sku: "B", price: 1500, attrs: %{name: "Blue Cup"}}
                 ],
                 ""
               )
    end

    test "count_by_size/2" do
      assert Acme.Catalog.Search.count_by_size(
               [
                 %Acme.Catalog.Product{
                   sku: "A",
                   price: 500,
                   attrs: %{
                     name: "Red Mug",
                     brand: "Acme",
                     color: "red",
                     size: "large",
                     weight: "heavy",
                     material: "clay",
                     origin: "Spain",
                     description: "a red mug",
                     finish: "matte",
                     care: "hand wash",
                     warranty: "one year",
                     model: "MK2"
                   }
                 },
                 %Acme.Catalog.Product{sku: "B", price: 1500, attrs: %{name: "Blue Cup"}}
               ],
               "zzz"
             ) == 0
    end

    test "search_by_weight/2" do
      assert [%{sku: "A"}] =
               Acme.Catalog.Search.search_by_weight(
                 [
                   %Acme.Catalog.Product{
                     sku: "A",
                     price: 500,
                     attrs: %{
                       name: "Red Mug",
                       brand: "Acme",
                       color: "red",
                       size: "large",
                       weight: "heavy",
                       material: "clay",
                       origin: "Spain",
                       description: "a red mug",
                       finish: "matte",
                       care: "hand wash",
                       warranty: "one year",
                       model: "MK2"
                     }
                   },
                   %Acme.Catalog.Product{sku: "B", price: 1500, attrs: %{name: "Blue Cup"}}
                 ],
                 "HEAV"
               )

      assert [] =
               Acme.Catalog.Search.search_by_weight(
                 [
                   %Acme.Catalog.Product{
                     sku: "A",
                     price: 500,
                     attrs: %{
                       name: "Red Mug",
                       brand: "Acme",
                       color: "red",
                       size: "large",
                       weight: "heavy",
                       material: "clay",
                       origin: "Spain",
                       description: "a red mug",
                       finish: "matte",
                       care: "hand wash",
                       warranty: "one year",
                       model: "MK2"
                     }
                   },
                   %Acme.Catalog.Product{sku: "B", price: 1500, attrs: %{name: "Blue Cup"}}
                 ],
                 ""
               )
    end

    test "count_by_weight/2" do
      assert Acme.Catalog.Search.count_by_weight(
               [
                 %Acme.Catalog.Product{
                   sku: "A",
                   price: 500,
                   attrs: %{
                     name: "Red Mug",
                     brand: "Acme",
                     color: "red",
                     size: "large",
                     weight: "heavy",
                     material: "clay",
                     origin: "Spain",
                     description: "a red mug",
                     finish: "matte",
                     care: "hand wash",
                     warranty: "one year",
                     model: "MK2"
                   }
                 },
                 %Acme.Catalog.Product{sku: "B", price: 1500, attrs: %{name: "Blue Cup"}}
               ],
               "zzz"
             ) == 0
    end

    test "search_by_material/2" do
      assert [%{sku: "A"}] =
               Acme.Catalog.Search.search_by_material(
                 [
                   %Acme.Catalog.Product{
                     sku: "A",
                     price: 500,
                     attrs: %{
                       name: "Red Mug",
                       brand: "Acme",
                       color: "red",
                       size: "large",
                       weight: "heavy",
                       material: "clay",
                       origin: "Spain",
                       description: "a red mug",
                       finish: "matte",
                       care: "hand wash",
                       warranty: "one year",
                       model: "MK2"
                     }
                   },
                   %Acme.Catalog.Product{sku: "B", price: 1500, attrs: %{name: "Blue Cup"}}
                 ],
                 "CLA"
               )

      assert [] =
               Acme.Catalog.Search.search_by_material(
                 [
                   %Acme.Catalog.Product{
                     sku: "A",
                     price: 500,
                     attrs: %{
                       name: "Red Mug",
                       brand: "Acme",
                       color: "red",
                       size: "large",
                       weight: "heavy",
                       material: "clay",
                       origin: "Spain",
                       description: "a red mug",
                       finish: "matte",
                       care: "hand wash",
                       warranty: "one year",
                       model: "MK2"
                     }
                   },
                   %Acme.Catalog.Product{sku: "B", price: 1500, attrs: %{name: "Blue Cup"}}
                 ],
                 ""
               )
    end

    test "count_by_material/2" do
      assert Acme.Catalog.Search.count_by_material(
               [
                 %Acme.Catalog.Product{
                   sku: "A",
                   price: 500,
                   attrs: %{
                     name: "Red Mug",
                     brand: "Acme",
                     color: "red",
                     size: "large",
                     weight: "heavy",
                     material: "clay",
                     origin: "Spain",
                     description: "a red mug",
                     finish: "matte",
                     care: "hand wash",
                     warranty: "one year",
                     model: "MK2"
                   }
                 },
                 %Acme.Catalog.Product{sku: "B", price: 1500, attrs: %{name: "Blue Cup"}}
               ],
               "zzz"
             ) == 0
    end

    test "search_by_origin/2" do
      assert [%{sku: "A"}] =
               Acme.Catalog.Search.search_by_origin(
                 [
                   %Acme.Catalog.Product{
                     sku: "A",
                     price: 500,
                     attrs: %{
                       name: "Red Mug",
                       brand: "Acme",
                       color: "red",
                       size: "large",
                       weight: "heavy",
                       material: "clay",
                       origin: "Spain",
                       description: "a red mug",
                       finish: "matte",
                       care: "hand wash",
                       warranty: "one year",
                       model: "MK2"
                     }
                   },
                   %Acme.Catalog.Product{sku: "B", price: 1500, attrs: %{name: "Blue Cup"}}
                 ],
                 "SPA"
               )

      assert [] =
               Acme.Catalog.Search.search_by_origin(
                 [
                   %Acme.Catalog.Product{
                     sku: "A",
                     price: 500,
                     attrs: %{
                       name: "Red Mug",
                       brand: "Acme",
                       color: "red",
                       size: "large",
                       weight: "heavy",
                       material: "clay",
                       origin: "Spain",
                       description: "a red mug",
                       finish: "matte",
                       care: "hand wash",
                       warranty: "one year",
                       model: "MK2"
                     }
                   },
                   %Acme.Catalog.Product{sku: "B", price: 1500, attrs: %{name: "Blue Cup"}}
                 ],
                 ""
               )
    end

    test "count_by_origin/2" do
      assert Acme.Catalog.Search.count_by_origin(
               [
                 %Acme.Catalog.Product{
                   sku: "A",
                   price: 500,
                   attrs: %{
                     name: "Red Mug",
                     brand: "Acme",
                     color: "red",
                     size: "large",
                     weight: "heavy",
                     material: "clay",
                     origin: "Spain",
                     description: "a red mug",
                     finish: "matte",
                     care: "hand wash",
                     warranty: "one year",
                     model: "MK2"
                   }
                 },
                 %Acme.Catalog.Product{sku: "B", price: 1500, attrs: %{name: "Blue Cup"}}
               ],
               "zzz"
             ) == 0
    end

    test "search_by_finish/2" do
      assert [%{sku: "A"}] =
               Acme.Catalog.Search.search_by_finish(
                 [
                   %Acme.Catalog.Product{
                     sku: "A",
                     price: 500,
                     attrs: %{
                       name: "Red Mug",
                       brand: "Acme",
                       color: "red",
                       size: "large",
                       weight: "heavy",
                       material: "clay",
                       origin: "Spain",
                       description: "a red mug",
                       finish: "matte",
                       care: "hand wash",
                       warranty: "one year",
                       model: "MK2"
                     }
                   },
                   %Acme.Catalog.Product{sku: "B", price: 1500, attrs: %{name: "Blue Cup"}}
                 ],
                 "MATT"
               )

      assert [] =
               Acme.Catalog.Search.search_by_finish(
                 [
                   %Acme.Catalog.Product{
                     sku: "A",
                     price: 500,
                     attrs: %{
                       name: "Red Mug",
                       brand: "Acme",
                       color: "red",
                       size: "large",
                       weight: "heavy",
                       material: "clay",
                       origin: "Spain",
                       description: "a red mug",
                       finish: "matte",
                       care: "hand wash",
                       warranty: "one year",
                       model: "MK2"
                     }
                   },
                   %Acme.Catalog.Product{sku: "B", price: 1500, attrs: %{name: "Blue Cup"}}
                 ],
                 ""
               )
    end

    test "count_by_finish/2" do
      assert Acme.Catalog.Search.count_by_finish(
               [
                 %Acme.Catalog.Product{
                   sku: "A",
                   price: 500,
                   attrs: %{
                     name: "Red Mug",
                     brand: "Acme",
                     color: "red",
                     size: "large",
                     weight: "heavy",
                     material: "clay",
                     origin: "Spain",
                     description: "a red mug",
                     finish: "matte",
                     care: "hand wash",
                     warranty: "one year",
                     model: "MK2"
                   }
                 },
                 %Acme.Catalog.Product{sku: "B", price: 1500, attrs: %{name: "Blue Cup"}}
               ],
               "zzz"
             ) == 0
    end

    test "search_by_care/2" do
      assert [%{sku: "A"}] =
               Acme.Catalog.Search.search_by_care(
                 [
                   %Acme.Catalog.Product{
                     sku: "A",
                     price: 500,
                     attrs: %{
                       name: "Red Mug",
                       brand: "Acme",
                       color: "red",
                       size: "large",
                       weight: "heavy",
                       material: "clay",
                       origin: "Spain",
                       description: "a red mug",
                       finish: "matte",
                       care: "hand wash",
                       warranty: "one year",
                       model: "MK2"
                     }
                   },
                   %Acme.Catalog.Product{sku: "B", price: 1500, attrs: %{name: "Blue Cup"}}
                 ],
                 "HAND"
               )

      assert [] =
               Acme.Catalog.Search.search_by_care(
                 [
                   %Acme.Catalog.Product{
                     sku: "A",
                     price: 500,
                     attrs: %{
                       name: "Red Mug",
                       brand: "Acme",
                       color: "red",
                       size: "large",
                       weight: "heavy",
                       material: "clay",
                       origin: "Spain",
                       description: "a red mug",
                       finish: "matte",
                       care: "hand wash",
                       warranty: "one year",
                       model: "MK2"
                     }
                   },
                   %Acme.Catalog.Product{sku: "B", price: 1500, attrs: %{name: "Blue Cup"}}
                 ],
                 ""
               )
    end

    test "count_by_care/2" do
      assert Acme.Catalog.Search.count_by_care(
               [
                 %Acme.Catalog.Product{
                   sku: "A",
                   price: 500,
                   attrs: %{
                     name: "Red Mug",
                     brand: "Acme",
                     color: "red",
                     size: "large",
                     weight: "heavy",
                     material: "clay",
                     origin: "Spain",
                     description: "a red mug",
                     finish: "matte",
                     care: "hand wash",
                     warranty: "one year",
                     model: "MK2"
                   }
                 },
                 %Acme.Catalog.Product{sku: "B", price: 1500, attrs: %{name: "Blue Cup"}}
               ],
               "zzz"
             ) == 0
    end

    test "search_by_warranty/2" do
      assert [%{sku: "A"}] =
               Acme.Catalog.Search.search_by_warranty(
                 [
                   %Acme.Catalog.Product{
                     sku: "A",
                     price: 500,
                     attrs: %{
                       name: "Red Mug",
                       brand: "Acme",
                       color: "red",
                       size: "large",
                       weight: "heavy",
                       material: "clay",
                       origin: "Spain",
                       description: "a red mug",
                       finish: "matte",
                       care: "hand wash",
                       warranty: "one year",
                       model: "MK2"
                     }
                   },
                   %Acme.Catalog.Product{sku: "B", price: 1500, attrs: %{name: "Blue Cup"}}
                 ],
                 "YEAR"
               )

      assert [] =
               Acme.Catalog.Search.search_by_warranty(
                 [
                   %Acme.Catalog.Product{
                     sku: "A",
                     price: 500,
                     attrs: %{
                       name: "Red Mug",
                       brand: "Acme",
                       color: "red",
                       size: "large",
                       weight: "heavy",
                       material: "clay",
                       origin: "Spain",
                       description: "a red mug",
                       finish: "matte",
                       care: "hand wash",
                       warranty: "one year",
                       model: "MK2"
                     }
                   },
                   %Acme.Catalog.Product{sku: "B", price: 1500, attrs: %{name: "Blue Cup"}}
                 ],
                 ""
               )
    end

    test "count_by_warranty/2" do
      assert Acme.Catalog.Search.count_by_warranty(
               [
                 %Acme.Catalog.Product{
                   sku: "A",
                   price: 500,
                   attrs: %{
                     name: "Red Mug",
                     brand: "Acme",
                     color: "red",
                     size: "large",
                     weight: "heavy",
                     material: "clay",
                     origin: "Spain",
                     description: "a red mug",
                     finish: "matte",
                     care: "hand wash",
                     warranty: "one year",
                     model: "MK2"
                   }
                 },
                 %Acme.Catalog.Product{sku: "B", price: 1500, attrs: %{name: "Blue Cup"}}
               ],
               "zzz"
             ) == 0
    end

    test "search_by_model/2" do
      assert [%{sku: "A"}] =
               Acme.Catalog.Search.search_by_model(
                 [
                   %Acme.Catalog.Product{
                     sku: "A",
                     price: 500,
                     attrs: %{
                       name: "Red Mug",
                       brand: "Acme",
                       color: "red",
                       size: "large",
                       weight: "heavy",
                       material: "clay",
                       origin: "Spain",
                       description: "a red mug",
                       finish: "matte",
                       care: "hand wash",
                       warranty: "one year",
                       model: "MK2"
                     }
                   },
                   %Acme.Catalog.Product{sku: "B", price: 1500, attrs: %{name: "Blue Cup"}}
                 ],
                 "MK"
               )

      assert [] =
               Acme.Catalog.Search.search_by_model(
                 [
                   %Acme.Catalog.Product{
                     sku: "A",
                     price: 500,
                     attrs: %{
                       name: "Red Mug",
                       brand: "Acme",
                       color: "red",
                       size: "large",
                       weight: "heavy",
                       material: "clay",
                       origin: "Spain",
                       description: "a red mug",
                       finish: "matte",
                       care: "hand wash",
                       warranty: "one year",
                       model: "MK2"
                     }
                   },
                   %Acme.Catalog.Product{sku: "B", price: 1500, attrs: %{name: "Blue Cup"}}
                 ],
                 ""
               )
    end

    test "count_by_model/2" do
      assert Acme.Catalog.Search.count_by_model(
               [
                 %Acme.Catalog.Product{
                   sku: "A",
                   price: 500,
                   attrs: %{
                     name: "Red Mug",
                     brand: "Acme",
                     color: "red",
                     size: "large",
                     weight: "heavy",
                     material: "clay",
                     origin: "Spain",
                     description: "a red mug",
                     finish: "matte",
                     care: "hand wash",
                     warranty: "one year",
                     model: "MK2"
                   }
                 },
                 %Acme.Catalog.Product{sku: "B", price: 1500, attrs: %{name: "Blue Cup"}}
               ],
               "zzz"
             ) == 0
    end
  end

  describe "reviews, on Acme.Catalog.Reviews" do
    test "rate_quality/2" do
      assert Acme.Catalog.Reviews.rate_quality([], 9) == [{:quality, 5}]
    end

    test "average_quality/1" do
      assert Acme.Catalog.Reviews.average_quality([{:quality, 4}, {:quality, 5}, {:other, 1}]) ==
               4.5
    end

    test "rate_value/2" do
      assert Acme.Catalog.Reviews.rate_value([], 9) == [{:value, 5}]
    end

    test "average_value/1" do
      assert Acme.Catalog.Reviews.average_value([{:value, 4}, {:value, 5}, {:other, 1}]) == 4.5
    end

    test "rate_delivery/2" do
      assert Acme.Catalog.Reviews.rate_delivery([], 9) == [{:delivery, 5}]
    end

    test "average_delivery/1" do
      assert Acme.Catalog.Reviews.average_delivery([{:delivery, 4}, {:delivery, 5}, {:other, 1}]) ==
               4.5
    end

    test "rate_packaging/2" do
      assert Acme.Catalog.Reviews.rate_packaging([], 9) == [{:packaging, 5}]
    end

    test "average_packaging/1" do
      assert Acme.Catalog.Reviews.average_packaging([
               {:packaging, 4},
               {:packaging, 5},
               {:other, 1}
             ]) == 4.5
    end

    test "rate_support/2" do
      assert Acme.Catalog.Reviews.rate_support([], 9) == [{:support, 5}]
    end

    test "average_support/1" do
      assert Acme.Catalog.Reviews.average_support([{:support, 4}, {:support, 5}, {:other, 1}]) ==
               4.5
    end

    test "rate_fit/2" do
      assert Acme.Catalog.Reviews.rate_fit([], 9) == [{:fit, 5}]
    end

    test "average_fit/1" do
      assert Acme.Catalog.Reviews.average_fit([{:fit, 4}, {:fit, 5}, {:other, 1}]) == 4.5
    end

    test "rate_durability/2" do
      assert Acme.Catalog.Reviews.rate_durability([], 9) == [{:durability, 5}]
    end

    test "average_durability/1" do
      assert Acme.Catalog.Reviews.average_durability([
               {:durability, 4},
               {:durability, 5},
               {:other, 1}
             ]) == 4.5
    end

    test "rate_design/2" do
      assert Acme.Catalog.Reviews.rate_design([], 9) == [{:design, 5}]
    end

    test "average_design/1" do
      assert Acme.Catalog.Reviews.average_design([{:design, 4}, {:design, 5}, {:other, 1}]) == 4.5
    end

    test "rate_comfort/2" do
      assert Acme.Catalog.Reviews.rate_comfort([], 9) == [{:comfort, 5}]
    end

    test "average_comfort/1" do
      assert Acme.Catalog.Reviews.average_comfort([{:comfort, 4}, {:comfort, 5}, {:other, 1}]) ==
               4.5
    end

    test "rate_accuracy/2" do
      assert Acme.Catalog.Reviews.rate_accuracy([], 9) == [{:accuracy, 5}]
    end

    test "average_accuracy/1" do
      assert Acme.Catalog.Reviews.average_accuracy([{:accuracy, 4}, {:accuracy, 5}, {:other, 1}]) ==
               4.5
    end

    test "rate_setup/2" do
      assert Acme.Catalog.Reviews.rate_setup([], 9) == [{:setup, 5}]
    end

    test "average_setup/1" do
      assert Acme.Catalog.Reviews.average_setup([{:setup, 4}, {:setup, 5}, {:other, 1}]) == 4.5
    end

    test "rate_noise/2" do
      assert Acme.Catalog.Reviews.rate_noise([], 9) == [{:noise, 5}]
    end

    test "average_noise/1" do
      assert Acme.Catalog.Reviews.average_noise([{:noise, 4}, {:noise, 5}, {:other, 1}]) == 4.5
    end
  end
end
