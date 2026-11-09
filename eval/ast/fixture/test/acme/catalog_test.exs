defmodule Acme.CatalogTest do
  use ExUnit.Case, async: true

  alias Acme.Catalog

  describe "products" do
    test "new_product/2" do
      assert %{sku: "AB-1", price: 1000} = Catalog.new_product(" ab-1 ", 1000)
    end

    test "product_slug/1" do
      assert "deep-red-mug" =
               "ab-1"
               |> Catalog.new_product(1)
               |> Catalog.put_product_name("Deep  Red Mug!")
               |> Catalog.product_slug()
    end

    test "product_name/1" do
      assert Catalog.product_name(
               "x"
               |> Catalog.new_product(1)
               |> Catalog.put_product_name("  a   b ")
             ) == "a b"
    end

    test "put_product_name/2" do
      assert %{attrs: attrs} =
               "x"
               |> Catalog.new_product(1)
               |> Catalog.put_product_name("v")
               |> Catalog.put_product_name("  ")

      refute Map.has_key?(attrs, :name)
    end

    test "product_description/1" do
      assert Catalog.product_description(
               "x"
               |> Catalog.new_product(1)
               |> Catalog.put_product_description("  a   b ")
             ) == "a b"
    end

    test "put_product_description/2" do
      assert %{attrs: attrs} =
               "x"
               |> Catalog.new_product(1)
               |> Catalog.put_product_description("v")
               |> Catalog.put_product_description("  ")

      refute Map.has_key?(attrs, :description)
    end

    test "product_brand/1" do
      assert Catalog.product_brand(
               "x"
               |> Catalog.new_product(1)
               |> Catalog.put_product_brand("  a   b ")
             ) == "a b"
    end

    test "put_product_brand/2" do
      assert %{attrs: attrs} =
               "x"
               |> Catalog.new_product(1)
               |> Catalog.put_product_brand("v")
               |> Catalog.put_product_brand("  ")

      refute Map.has_key?(attrs, :brand)
    end

    test "product_color/1" do
      assert Catalog.product_color(
               "x"
               |> Catalog.new_product(1)
               |> Catalog.put_product_color("  a   b ")
             ) == "a b"
    end

    test "put_product_color/2" do
      assert %{attrs: attrs} =
               "x"
               |> Catalog.new_product(1)
               |> Catalog.put_product_color("v")
               |> Catalog.put_product_color("  ")

      refute Map.has_key?(attrs, :color)
    end

    test "product_size/1" do
      assert Catalog.product_size(
               "x"
               |> Catalog.new_product(1)
               |> Catalog.put_product_size("  a   b ")
             ) == "a b"
    end

    test "put_product_size/2" do
      assert %{attrs: attrs} =
               "x"
               |> Catalog.new_product(1)
               |> Catalog.put_product_size("v")
               |> Catalog.put_product_size("  ")

      refute Map.has_key?(attrs, :size)
    end

    test "product_weight/1" do
      assert Catalog.product_weight(
               "x"
               |> Catalog.new_product(1)
               |> Catalog.put_product_weight("  a   b ")
             ) == "a b"
    end

    test "put_product_weight/2" do
      assert %{attrs: attrs} =
               "x"
               |> Catalog.new_product(1)
               |> Catalog.put_product_weight("v")
               |> Catalog.put_product_weight("  ")

      refute Map.has_key?(attrs, :weight)
    end

    test "product_material/1" do
      assert Catalog.product_material(
               "x"
               |> Catalog.new_product(1)
               |> Catalog.put_product_material("  a   b ")
             ) == "a b"
    end

    test "put_product_material/2" do
      assert %{attrs: attrs} =
               "x"
               |> Catalog.new_product(1)
               |> Catalog.put_product_material("v")
               |> Catalog.put_product_material("  ")

      refute Map.has_key?(attrs, :material)
    end

    test "product_origin/1" do
      assert Catalog.product_origin(
               "x"
               |> Catalog.new_product(1)
               |> Catalog.put_product_origin("  a   b ")
             ) == "a b"
    end

    test "put_product_origin/2" do
      assert %{attrs: attrs} =
               "x"
               |> Catalog.new_product(1)
               |> Catalog.put_product_origin("v")
               |> Catalog.put_product_origin("  ")

      refute Map.has_key?(attrs, :origin)
    end

    test "product_finish/1" do
      assert Catalog.product_finish(
               "x"
               |> Catalog.new_product(1)
               |> Catalog.put_product_finish("  a   b ")
             ) == "a b"
    end

    test "put_product_finish/2" do
      assert %{attrs: attrs} =
               "x"
               |> Catalog.new_product(1)
               |> Catalog.put_product_finish("v")
               |> Catalog.put_product_finish("  ")

      refute Map.has_key?(attrs, :finish)
    end

    test "product_care/1" do
      assert Catalog.product_care(
               "x"
               |> Catalog.new_product(1)
               |> Catalog.put_product_care("  a   b ")
             ) == "a b"
    end

    test "put_product_care/2" do
      assert %{attrs: attrs} =
               "x"
               |> Catalog.new_product(1)
               |> Catalog.put_product_care("v")
               |> Catalog.put_product_care("  ")

      refute Map.has_key?(attrs, :care)
    end

    test "product_warranty/1" do
      assert Catalog.product_warranty(
               "x"
               |> Catalog.new_product(1)
               |> Catalog.put_product_warranty("  a   b ")
             ) == "a b"
    end

    test "put_product_warranty/2" do
      assert %{attrs: attrs} =
               "x"
               |> Catalog.new_product(1)
               |> Catalog.put_product_warranty("v")
               |> Catalog.put_product_warranty("  ")

      refute Map.has_key?(attrs, :warranty)
    end

    test "product_model/1" do
      assert Catalog.product_model(
               "x"
               |> Catalog.new_product(1)
               |> Catalog.put_product_model("  a   b ")
             ) == "a b"
    end

    test "put_product_model/2" do
      assert %{attrs: attrs} =
               "x"
               |> Catalog.new_product(1)
               |> Catalog.put_product_model("v")
               |> Catalog.put_product_model("  ")

      refute Map.has_key?(attrs, :model)
    end
  end

  describe "pricing" do
    test "bronze_price/1" do
      assert Catalog.bronze_price(%Acme.Catalog.Product{sku: "X", price: 1000}) == 980
    end

    test "bronze_price_with_tax/1" do
      assert Catalog.bronze_price_with_tax(%Acme.Catalog.Product{sku: "X", price: 1000}) == 1061
    end

    test "silver_price/1" do
      assert Catalog.silver_price(%Acme.Catalog.Product{sku: "X", price: 1000}) == 950
    end

    test "silver_price_with_tax/1" do
      assert Catalog.silver_price_with_tax(%Acme.Catalog.Product{sku: "X", price: 1000}) == 1028
    end

    test "gold_price/1" do
      assert Catalog.gold_price(%Acme.Catalog.Product{sku: "X", price: 1000}) == 900
    end

    test "gold_price_with_tax/1" do
      assert Catalog.gold_price_with_tax(%Acme.Catalog.Product{sku: "X", price: 1000}) == 974
    end

    test "platinum_price/1" do
      assert Catalog.platinum_price(%Acme.Catalog.Product{sku: "X", price: 1000}) == 850
    end

    test "platinum_price_with_tax/1" do
      assert Catalog.platinum_price_with_tax(%Acme.Catalog.Product{sku: "X", price: 1000}) == 920
    end

    test "retail_price/1" do
      assert Catalog.retail_price(%Acme.Catalog.Product{sku: "X", price: 1000}) == 1000
    end

    test "retail_price_with_tax/1" do
      assert Catalog.retail_price_with_tax(%Acme.Catalog.Product{sku: "X", price: 1000}) == 1083
    end

    test "wholesale_price/1" do
      assert Catalog.wholesale_price(%Acme.Catalog.Product{sku: "X", price: 1000}) == 750
    end

    test "wholesale_price_with_tax/1" do
      assert Catalog.wholesale_price_with_tax(%Acme.Catalog.Product{sku: "X", price: 1000}) == 812
    end

    test "staff_price/1" do
      assert Catalog.staff_price(%Acme.Catalog.Product{sku: "X", price: 1000}) == 700
    end

    test "staff_price_with_tax/1" do
      assert Catalog.staff_price_with_tax(%Acme.Catalog.Product{sku: "X", price: 1000}) == 758
    end

    test "partner_price/1" do
      assert Catalog.partner_price(%Acme.Catalog.Product{sku: "X", price: 1000}) == 800
    end

    test "partner_price_with_tax/1" do
      assert Catalog.partner_price_with_tax(%Acme.Catalog.Product{sku: "X", price: 1000}) == 866
    end

    test "student_price/1" do
      assert Catalog.student_price(%Acme.Catalog.Product{sku: "X", price: 1000}) == 880
    end

    test "student_price_with_tax/1" do
      assert Catalog.student_price_with_tax(%Acme.Catalog.Product{sku: "X", price: 1000}) == 953
    end

    test "senior_price/1" do
      assert Catalog.senior_price(%Acme.Catalog.Product{sku: "X", price: 1000}) == 920
    end

    test "senior_price_with_tax/1" do
      assert Catalog.senior_price_with_tax(%Acme.Catalog.Product{sku: "X", price: 1000}) == 996
    end

    test "nonprofit_price/1" do
      assert Catalog.nonprofit_price(%Acme.Catalog.Product{sku: "X", price: 1000}) == 820
    end

    test "nonprofit_price_with_tax/1" do
      assert Catalog.nonprofit_price_with_tax(%Acme.Catalog.Product{sku: "X", price: 1000}) == 888
    end

    test "family_price/1" do
      assert Catalog.family_price(%Acme.Catalog.Product{sku: "X", price: 1000}) == 780
    end

    test "family_price_with_tax/1" do
      assert Catalog.family_price_with_tax(%Acme.Catalog.Product{sku: "X", price: 1000}) == 844
    end
  end

  describe "inventory" do
    test "stock_in_north/2" do
      assert Catalog.stock_in_north(%{north: %{"AB-1" => 7}}, " ab-1") == 7
    end

    test "restock_north/3" do
      assert %{north: %{"AB-1" => 12}} =
               %{} |> Catalog.restock_north("ab-1", 6) |> Catalog.restock_north("AB-1 ", 6)
    end

    test "stock_in_south/2" do
      assert Catalog.stock_in_south(%{south: %{"AB-1" => 7}}, " ab-1") == 7
    end

    test "restock_south/3" do
      assert %{south: %{"AB-1" => 12}} =
               %{} |> Catalog.restock_south("ab-1", 6) |> Catalog.restock_south("AB-1 ", 6)
    end

    test "stock_in_east/2" do
      assert Catalog.stock_in_east(%{east: %{"AB-1" => 7}}, " ab-1") == 7
    end

    test "restock_east/3" do
      assert %{east: %{"AB-1" => 12}} =
               %{} |> Catalog.restock_east("ab-1", 6) |> Catalog.restock_east("AB-1 ", 6)
    end

    test "stock_in_west/2" do
      assert Catalog.stock_in_west(%{west: %{"AB-1" => 7}}, " ab-1") == 7
    end

    test "restock_west/3" do
      assert %{west: %{"AB-1" => 12}} =
               %{} |> Catalog.restock_west("ab-1", 6) |> Catalog.restock_west("AB-1 ", 6)
    end

    test "stock_in_central/2" do
      assert Catalog.stock_in_central(%{central: %{"AB-1" => 7}}, " ab-1") == 7
    end

    test "restock_central/3" do
      assert %{central: %{"AB-1" => 12}} =
               %{} |> Catalog.restock_central("ab-1", 6) |> Catalog.restock_central("AB-1 ", 6)
    end

    test "stock_in_overflow/2" do
      assert Catalog.stock_in_overflow(%{overflow: %{"AB-1" => 7}}, " ab-1") == 7
    end

    test "restock_overflow/3" do
      assert %{overflow: %{"AB-1" => 12}} =
               %{} |> Catalog.restock_overflow("ab-1", 6) |> Catalog.restock_overflow("AB-1 ", 6)
    end

    test "stock_in_returns/2" do
      assert Catalog.stock_in_returns(%{returns: %{"AB-1" => 7}}, " ab-1") == 7
    end

    test "restock_returns/3" do
      assert %{returns: %{"AB-1" => 12}} =
               %{} |> Catalog.restock_returns("ab-1", 6) |> Catalog.restock_returns("AB-1 ", 6)
    end

    test "stock_in_transit/2" do
      assert Catalog.stock_in_transit(%{transit: %{"AB-1" => 7}}, " ab-1") == 7
    end

    test "restock_transit/3" do
      assert %{transit: %{"AB-1" => 12}} =
               %{} |> Catalog.restock_transit("ab-1", 6) |> Catalog.restock_transit("AB-1 ", 6)
    end

    test "stock_in_airport/2" do
      assert Catalog.stock_in_airport(%{airport: %{"AB-1" => 7}}, " ab-1") == 7
    end

    test "restock_airport/3" do
      assert %{airport: %{"AB-1" => 12}} =
               %{} |> Catalog.restock_airport("ab-1", 6) |> Catalog.restock_airport("AB-1 ", 6)
    end

    test "stock_in_harbor/2" do
      assert Catalog.stock_in_harbor(%{harbor: %{"AB-1" => 7}}, " ab-1") == 7
    end

    test "restock_harbor/3" do
      assert %{harbor: %{"AB-1" => 12}} =
               %{} |> Catalog.restock_harbor("ab-1", 6) |> Catalog.restock_harbor("AB-1 ", 6)
    end

    test "stock_in_depot/2" do
      assert Catalog.stock_in_depot(%{depot: %{"AB-1" => 7}}, " ab-1") == 7
    end

    test "restock_depot/3" do
      assert %{depot: %{"AB-1" => 12}} =
               %{} |> Catalog.restock_depot("ab-1", 6) |> Catalog.restock_depot("AB-1 ", 6)
    end

    test "stock_in_annex/2" do
      assert Catalog.stock_in_annex(%{annex: %{"AB-1" => 7}}, " ab-1") == 7
    end

    test "restock_annex/3" do
      assert %{annex: %{"AB-1" => 12}} =
               %{} |> Catalog.restock_annex("ab-1", 6) |> Catalog.restock_annex("AB-1 ", 6)
    end
  end

  describe "search" do
    test "find_by_sku/2" do
      assert %{sku: "B"} =
               Catalog.find_by_sku(
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
               Catalog.price_range(
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
               Catalog.search_by_name(
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
               Catalog.search_by_name(
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
      assert Catalog.count_by_name(
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
               Catalog.search_by_description(
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
               Catalog.search_by_description(
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
      assert Catalog.count_by_description(
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
               Catalog.search_by_brand(
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
               Catalog.search_by_brand(
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
      assert Catalog.count_by_brand(
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
               Catalog.search_by_color(
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
               Catalog.search_by_color(
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
      assert Catalog.count_by_color(
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
               Catalog.search_by_size(
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
               Catalog.search_by_size(
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
      assert Catalog.count_by_size(
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
               Catalog.search_by_weight(
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
               Catalog.search_by_weight(
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
      assert Catalog.count_by_weight(
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
               Catalog.search_by_material(
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
               Catalog.search_by_material(
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
      assert Catalog.count_by_material(
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
               Catalog.search_by_origin(
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
               Catalog.search_by_origin(
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
      assert Catalog.count_by_origin(
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
               Catalog.search_by_finish(
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
               Catalog.search_by_finish(
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
      assert Catalog.count_by_finish(
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
               Catalog.search_by_care(
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
               Catalog.search_by_care(
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
      assert Catalog.count_by_care(
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
               Catalog.search_by_warranty(
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
               Catalog.search_by_warranty(
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
      assert Catalog.count_by_warranty(
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
               Catalog.search_by_model(
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
               Catalog.search_by_model(
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
      assert Catalog.count_by_model(
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

  describe "reviews" do
    test "rate_quality/2" do
      assert Catalog.rate_quality([], 9) == [{:quality, 5}]
    end

    test "average_quality/1" do
      assert Catalog.average_quality([{:quality, 4}, {:quality, 5}, {:other, 1}]) == 4.5
    end

    test "rate_value/2" do
      assert Catalog.rate_value([], 9) == [{:value, 5}]
    end

    test "average_value/1" do
      assert Catalog.average_value([{:value, 4}, {:value, 5}, {:other, 1}]) == 4.5
    end

    test "rate_delivery/2" do
      assert Catalog.rate_delivery([], 9) == [{:delivery, 5}]
    end

    test "average_delivery/1" do
      assert Catalog.average_delivery([{:delivery, 4}, {:delivery, 5}, {:other, 1}]) == 4.5
    end

    test "rate_packaging/2" do
      assert Catalog.rate_packaging([], 9) == [{:packaging, 5}]
    end

    test "average_packaging/1" do
      assert Catalog.average_packaging([{:packaging, 4}, {:packaging, 5}, {:other, 1}]) == 4.5
    end

    test "rate_support/2" do
      assert Catalog.rate_support([], 9) == [{:support, 5}]
    end

    test "average_support/1" do
      assert Catalog.average_support([{:support, 4}, {:support, 5}, {:other, 1}]) == 4.5
    end

    test "rate_fit/2" do
      assert Catalog.rate_fit([], 9) == [{:fit, 5}]
    end

    test "average_fit/1" do
      assert Catalog.average_fit([{:fit, 4}, {:fit, 5}, {:other, 1}]) == 4.5
    end

    test "rate_durability/2" do
      assert Catalog.rate_durability([], 9) == [{:durability, 5}]
    end

    test "average_durability/1" do
      assert Catalog.average_durability([{:durability, 4}, {:durability, 5}, {:other, 1}]) == 4.5
    end

    test "rate_design/2" do
      assert Catalog.rate_design([], 9) == [{:design, 5}]
    end

    test "average_design/1" do
      assert Catalog.average_design([{:design, 4}, {:design, 5}, {:other, 1}]) == 4.5
    end

    test "rate_comfort/2" do
      assert Catalog.rate_comfort([], 9) == [{:comfort, 5}]
    end

    test "average_comfort/1" do
      assert Catalog.average_comfort([{:comfort, 4}, {:comfort, 5}, {:other, 1}]) == 4.5
    end

    test "rate_accuracy/2" do
      assert Catalog.rate_accuracy([], 9) == [{:accuracy, 5}]
    end

    test "average_accuracy/1" do
      assert Catalog.average_accuracy([{:accuracy, 4}, {:accuracy, 5}, {:other, 1}]) == 4.5
    end

    test "rate_setup/2" do
      assert Catalog.rate_setup([], 9) == [{:setup, 5}]
    end

    test "average_setup/1" do
      assert Catalog.average_setup([{:setup, 4}, {:setup, 5}, {:other, 1}]) == 4.5
    end

    test "rate_noise/2" do
      assert Catalog.rate_noise([], 9) == [{:noise, 5}]
    end

    test "average_noise/1" do
      assert Catalog.average_noise([{:noise, 4}, {:noise, 5}, {:other, 1}]) == 4.5
    end
  end

  test "the storefront's card" do
    product = "mug" |> Catalog.new_product(1000) |> Catalog.put_product_name("Mug")

    assert %{slug: "mug", price: 1083, quality: 4.0} =
             Acme.Storefront.card(product, [{:quality, 4}])

    refute Acme.Storefront.in_stock?(%{}, "mug")
  end
end
