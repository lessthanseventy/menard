defmodule Acme.Catalog do
  @moduledoc """
  The catalog: products and their attributes, what each customer tier pays, stock per warehouse,
  search, and reviews.
  """

  alias Acme.Catalog.Product

  require Logger

  # ---------------------------------------------------------------------------------------
  # Products: the SKU, the attribute text a product page shows, the slug.

  @doc """
  A new product with no attributes and no tags.

  The SKU is normalized (trimmed, upper-cased) so that two spellings of one SKU are one
  product, and the price is the list price in cents, before any tier discount or tax.
  """
  @spec new_product(String.t(), non_neg_integer()) :: Product.t()
  def new_product(sku, price) when is_integer(price) and price >= 0 do
    %Product{sku: normalize_sku(sku), price: price, attrs: %{}, tags: []}
  end

  @doc """
  The product's URL slug: its name, or its SKU when it has no name, lower-cased with every
  run of characters other than letters and digits made one dash.
  """
  @spec product_slug(Product.t()) :: String.t()
  def product_slug(%Product{} = product), do: slug(Map.get(product.attrs, :name, product.sku))

  @doc """
  The product's name, or `nil` when it has none.

  Text attributes are cleaned when they are put, so what comes back is what a customer
  sees on the product page, with no stray whitespace around or inside it.

  The name is read from the product's attributes, not from a lookup: a product built
  with `new_product/2` and never given a name answers `nil`, which a page should show
  as blank rather than as the word "nil".
  """
  @spec product_name(Product.t()) :: String.t() | nil
  def product_name(%Product{} = product), do: Map.get(product.attrs, :name)

  @doc """
  Puts the product's name.

  The value is cleaned (trimmed, each inner run of whitespace made one space) before it is
  stored. An empty value, or one of whitespace alone, removes the name.

  Nothing else of the product changes: its SKU, price and tags stay as they were, and
  the other attributes are kept. The product returned is a new struct; the one passed
  in is unchanged, as with every function here.
  """
  @spec put_product_name(Product.t(), String.t()) :: Product.t()
  def put_product_name(%Product{} = product, value) do
    case clean_text(value) do
      "" -> %{product | attrs: Map.delete(product.attrs, :name)}
      text -> %{product | attrs: Map.put(product.attrs, :name, text)}
    end
  end

  @doc """
  The product's description, or `nil` when it has none.

  Text attributes are cleaned when they are put, so what comes back is what a customer
  sees on the product page, with no stray whitespace around or inside it.

  The description is read from the product's attributes, not from a lookup: a product built
  with `new_product/2` and never given a description answers `nil`, which a page should show
  as blank rather than as the word "nil".
  """
  @spec product_description(Product.t()) :: String.t() | nil
  def product_description(%Product{} = product), do: Map.get(product.attrs, :description)

  @doc """
  Puts the product's description.

  The value is cleaned (trimmed, each inner run of whitespace made one space) before it is
  stored. An empty value, or one of whitespace alone, removes the description.

  Nothing else of the product changes: its SKU, price and tags stay as they were, and
  the other attributes are kept. The product returned is a new struct; the one passed
  in is unchanged, as with every function here.
  """
  @spec put_product_description(Product.t(), String.t()) :: Product.t()
  def put_product_description(%Product{} = product, value) do
    case clean_text(value) do
      "" -> %{product | attrs: Map.delete(product.attrs, :description)}
      text -> %{product | attrs: Map.put(product.attrs, :description, text)}
    end
  end

  @doc """
  The product's brand, or `nil` when it has none.

  Text attributes are cleaned when they are put, so what comes back is what a customer
  sees on the product page, with no stray whitespace around or inside it.

  The brand is read from the product's attributes, not from a lookup: a product built
  with `new_product/2` and never given a brand answers `nil`, which a page should show
  as blank rather than as the word "nil".
  """
  @spec product_brand(Product.t()) :: String.t() | nil
  def product_brand(%Product{} = product), do: Map.get(product.attrs, :brand)

  @doc """
  Puts the product's brand.

  The value is cleaned (trimmed, each inner run of whitespace made one space) before it is
  stored. An empty value, or one of whitespace alone, removes the brand.

  Nothing else of the product changes: its SKU, price and tags stay as they were, and
  the other attributes are kept. The product returned is a new struct; the one passed
  in is unchanged, as with every function here.
  """
  @spec put_product_brand(Product.t(), String.t()) :: Product.t()
  def put_product_brand(%Product{} = product, value) do
    case clean_text(value) do
      "" -> %{product | attrs: Map.delete(product.attrs, :brand)}
      text -> %{product | attrs: Map.put(product.attrs, :brand, text)}
    end
  end

  @doc """
  The product's color, or `nil` when it has none.

  Text attributes are cleaned when they are put, so what comes back is what a customer
  sees on the product page, with no stray whitespace around or inside it.

  The color is read from the product's attributes, not from a lookup: a product built
  with `new_product/2` and never given a color answers `nil`, which a page should show
  as blank rather than as the word "nil".
  """
  @spec product_color(Product.t()) :: String.t() | nil
  def product_color(%Product{} = product), do: Map.get(product.attrs, :color)

  @doc """
  Puts the product's color.

  The value is cleaned (trimmed, each inner run of whitespace made one space) before it is
  stored. An empty value, or one of whitespace alone, removes the color.

  Nothing else of the product changes: its SKU, price and tags stay as they were, and
  the other attributes are kept. The product returned is a new struct; the one passed
  in is unchanged, as with every function here.
  """
  @spec put_product_color(Product.t(), String.t()) :: Product.t()
  def put_product_color(%Product{} = product, value) do
    case clean_text(value) do
      "" -> %{product | attrs: Map.delete(product.attrs, :color)}
      text -> %{product | attrs: Map.put(product.attrs, :color, text)}
    end
  end

  @doc """
  The product's size, or `nil` when it has none.

  Text attributes are cleaned when they are put, so what comes back is what a customer
  sees on the product page, with no stray whitespace around or inside it.

  The size is read from the product's attributes, not from a lookup: a product built
  with `new_product/2` and never given a size answers `nil`, which a page should show
  as blank rather than as the word "nil".
  """
  @spec product_size(Product.t()) :: String.t() | nil
  def product_size(%Product{} = product), do: Map.get(product.attrs, :size)

  @doc """
  Puts the product's size.

  The value is cleaned (trimmed, each inner run of whitespace made one space) before it is
  stored. An empty value, or one of whitespace alone, removes the size.

  Nothing else of the product changes: its SKU, price and tags stay as they were, and
  the other attributes are kept. The product returned is a new struct; the one passed
  in is unchanged, as with every function here.
  """
  @spec put_product_size(Product.t(), String.t()) :: Product.t()
  def put_product_size(%Product{} = product, value) do
    case clean_text(value) do
      "" -> %{product | attrs: Map.delete(product.attrs, :size)}
      text -> %{product | attrs: Map.put(product.attrs, :size, text)}
    end
  end

  @doc """
  The product's weight, or `nil` when it has none.

  Text attributes are cleaned when they are put, so what comes back is what a customer
  sees on the product page, with no stray whitespace around or inside it.

  The weight is read from the product's attributes, not from a lookup: a product built
  with `new_product/2` and never given a weight answers `nil`, which a page should show
  as blank rather than as the word "nil".
  """
  @spec product_weight(Product.t()) :: String.t() | nil
  def product_weight(%Product{} = product), do: Map.get(product.attrs, :weight)

  @doc """
  Puts the product's weight.

  The value is cleaned (trimmed, each inner run of whitespace made one space) before it is
  stored. An empty value, or one of whitespace alone, removes the weight.

  Nothing else of the product changes: its SKU, price and tags stay as they were, and
  the other attributes are kept. The product returned is a new struct; the one passed
  in is unchanged, as with every function here.
  """
  @spec put_product_weight(Product.t(), String.t()) :: Product.t()
  def put_product_weight(%Product{} = product, value) do
    case clean_text(value) do
      "" -> %{product | attrs: Map.delete(product.attrs, :weight)}
      text -> %{product | attrs: Map.put(product.attrs, :weight, text)}
    end
  end

  @doc """
  The product's material, or `nil` when it has none.

  Text attributes are cleaned when they are put, so what comes back is what a customer
  sees on the product page, with no stray whitespace around or inside it.

  The material is read from the product's attributes, not from a lookup: a product built
  with `new_product/2` and never given a material answers `nil`, which a page should show
  as blank rather than as the word "nil".
  """
  @spec product_material(Product.t()) :: String.t() | nil
  def product_material(%Product{} = product), do: Map.get(product.attrs, :material)

  @doc """
  Puts the product's material.

  The value is cleaned (trimmed, each inner run of whitespace made one space) before it is
  stored. An empty value, or one of whitespace alone, removes the material.

  Nothing else of the product changes: its SKU, price and tags stay as they were, and
  the other attributes are kept. The product returned is a new struct; the one passed
  in is unchanged, as with every function here.
  """
  @spec put_product_material(Product.t(), String.t()) :: Product.t()
  def put_product_material(%Product{} = product, value) do
    case clean_text(value) do
      "" -> %{product | attrs: Map.delete(product.attrs, :material)}
      text -> %{product | attrs: Map.put(product.attrs, :material, text)}
    end
  end

  @doc """
  The product's origin, or `nil` when it has none.

  Text attributes are cleaned when they are put, so what comes back is what a customer
  sees on the product page, with no stray whitespace around or inside it.

  The origin is read from the product's attributes, not from a lookup: a product built
  with `new_product/2` and never given a origin answers `nil`, which a page should show
  as blank rather than as the word "nil".
  """
  @spec product_origin(Product.t()) :: String.t() | nil
  def product_origin(%Product{} = product), do: Map.get(product.attrs, :origin)

  @doc """
  Puts the product's origin.

  The value is cleaned (trimmed, each inner run of whitespace made one space) before it is
  stored. An empty value, or one of whitespace alone, removes the origin.

  Nothing else of the product changes: its SKU, price and tags stay as they were, and
  the other attributes are kept. The product returned is a new struct; the one passed
  in is unchanged, as with every function here.
  """
  @spec put_product_origin(Product.t(), String.t()) :: Product.t()
  def put_product_origin(%Product{} = product, value) do
    case clean_text(value) do
      "" -> %{product | attrs: Map.delete(product.attrs, :origin)}
      text -> %{product | attrs: Map.put(product.attrs, :origin, text)}
    end
  end

  @doc """
  The product's finish, or `nil` when it has none.

  Text attributes are cleaned when they are put, so what comes back is what a customer
  sees on the product page, with no stray whitespace around or inside it.

  The finish is read from the product's attributes, not from a lookup: a product built
  with `new_product/2` and never given a finish answers `nil`, which a page should show
  as blank rather than as the word "nil".
  """
  @spec product_finish(Product.t()) :: String.t() | nil
  def product_finish(%Product{} = product), do: Map.get(product.attrs, :finish)

  @doc """
  Puts the product's finish.

  The value is cleaned (trimmed, each inner run of whitespace made one space) before it is
  stored. An empty value, or one of whitespace alone, removes the finish.

  Nothing else of the product changes: its SKU, price and tags stay as they were, and
  the other attributes are kept. The product returned is a new struct; the one passed
  in is unchanged, as with every function here.
  """
  @spec put_product_finish(Product.t(), String.t()) :: Product.t()
  def put_product_finish(%Product{} = product, value) do
    case clean_text(value) do
      "" -> %{product | attrs: Map.delete(product.attrs, :finish)}
      text -> %{product | attrs: Map.put(product.attrs, :finish, text)}
    end
  end

  @doc """
  The product's care, or `nil` when it has none.

  Text attributes are cleaned when they are put, so what comes back is what a customer
  sees on the product page, with no stray whitespace around or inside it.

  The care is read from the product's attributes, not from a lookup: a product built
  with `new_product/2` and never given a care answers `nil`, which a page should show
  as blank rather than as the word "nil".
  """
  @spec product_care(Product.t()) :: String.t() | nil
  def product_care(%Product{} = product), do: Map.get(product.attrs, :care)

  @doc """
  Puts the product's care.

  The value is cleaned (trimmed, each inner run of whitespace made one space) before it is
  stored. An empty value, or one of whitespace alone, removes the care.

  Nothing else of the product changes: its SKU, price and tags stay as they were, and
  the other attributes are kept. The product returned is a new struct; the one passed
  in is unchanged, as with every function here.
  """
  @spec put_product_care(Product.t(), String.t()) :: Product.t()
  def put_product_care(%Product{} = product, value) do
    case clean_text(value) do
      "" -> %{product | attrs: Map.delete(product.attrs, :care)}
      text -> %{product | attrs: Map.put(product.attrs, :care, text)}
    end
  end

  @doc """
  The product's warranty, or `nil` when it has none.

  Text attributes are cleaned when they are put, so what comes back is what a customer
  sees on the product page, with no stray whitespace around or inside it.

  The warranty is read from the product's attributes, not from a lookup: a product built
  with `new_product/2` and never given a warranty answers `nil`, which a page should show
  as blank rather than as the word "nil".
  """
  @spec product_warranty(Product.t()) :: String.t() | nil
  def product_warranty(%Product{} = product), do: Map.get(product.attrs, :warranty)

  @doc """
  Puts the product's warranty.

  The value is cleaned (trimmed, each inner run of whitespace made one space) before it is
  stored. An empty value, or one of whitespace alone, removes the warranty.

  Nothing else of the product changes: its SKU, price and tags stay as they were, and
  the other attributes are kept. The product returned is a new struct; the one passed
  in is unchanged, as with every function here.
  """
  @spec put_product_warranty(Product.t(), String.t()) :: Product.t()
  def put_product_warranty(%Product{} = product, value) do
    case clean_text(value) do
      "" -> %{product | attrs: Map.delete(product.attrs, :warranty)}
      text -> %{product | attrs: Map.put(product.attrs, :warranty, text)}
    end
  end

  @doc """
  The product's model, or `nil` when it has none.

  Text attributes are cleaned when they are put, so what comes back is what a customer
  sees on the product page, with no stray whitespace around or inside it.

  The model is read from the product's attributes, not from a lookup: a product built
  with `new_product/2` and never given a model answers `nil`, which a page should show
  as blank rather than as the word "nil".
  """
  @spec product_model(Product.t()) :: String.t() | nil
  def product_model(%Product{} = product), do: Map.get(product.attrs, :model)

  @doc """
  Puts the product's model.

  The value is cleaned (trimmed, each inner run of whitespace made one space) before it is
  stored. An empty value, or one of whitespace alone, removes the model.

  Nothing else of the product changes: its SKU, price and tags stay as they were, and
  the other attributes are kept. The product returned is a new struct; the one passed
  in is unchanged, as with every function here.
  """
  @spec put_product_model(Product.t(), String.t()) :: Product.t()
  def put_product_model(%Product{} = product, value) do
    case clean_text(value) do
      "" -> %{product | attrs: Map.delete(product.attrs, :model)}
      text -> %{product | attrs: Map.put(product.attrs, :model, text)}
    end
  end

  defp clean_text(value), do: value |> String.trim() |> String.replace(~r/\s+/, " ")

  defp slug(text) do
    text |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "-") |> String.trim("-")
  end

  # ---------------------------------------------------------------------------------------
  # Pricing: what each customer tier pays, before and after tax.

  @tax_rate 0.0825
  @tier_discounts %{
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
  }

  @doc """
  The bronze tier's price for the product, in cents.

  The bronze discount is 2% off the list price, rounded to the nearest cent. Tax is not
  included: see `bronze_price_with_tax/1` for what the customer pays.

  The discount comes from the catalog's tier table, so a change to the bronze rate is made
  there and nowhere else. A product priced at 0 stays at 0 in every tier, and the result
  is never negative.
  """
  @spec bronze_price(Product.t()) :: non_neg_integer()
  def bronze_price(%Product{price: price}), do: discounted(price, @tier_discounts.bronze)

  @doc """
  The bronze tier's price with sales tax, in cents: what a bronze customer pays.

  Tax is charged on the discounted price at the catalog's one rate, and the result is
  rounded to the nearest cent once, at the end.

  Rounding once matters: rounding the discount and then the tax apart can be a cent off
  on some prices, and the invoice and the product page then disagree about what the
  customer was told.
  """
  @spec bronze_price_with_tax(Product.t()) :: non_neg_integer()
  def bronze_price_with_tax(%Product{} = product), do: product |> bronze_price() |> with_tax()

  @doc """
  The silver tier's price for the product, in cents.

  The silver discount is 5% off the list price, rounded to the nearest cent. Tax is not
  included: see `silver_price_with_tax/1` for what the customer pays.

  The discount comes from the catalog's tier table, so a change to the silver rate is made
  there and nowhere else. A product priced at 0 stays at 0 in every tier, and the result
  is never negative.
  """
  @spec silver_price(Product.t()) :: non_neg_integer()
  def silver_price(%Product{price: price}), do: discounted(price, @tier_discounts.silver)

  @doc """
  The silver tier's price with sales tax, in cents: what a silver customer pays.

  Tax is charged on the discounted price at the catalog's one rate, and the result is
  rounded to the nearest cent once, at the end.

  Rounding once matters: rounding the discount and then the tax apart can be a cent off
  on some prices, and the invoice and the product page then disagree about what the
  customer was told.
  """
  @spec silver_price_with_tax(Product.t()) :: non_neg_integer()
  def silver_price_with_tax(%Product{} = product), do: product |> silver_price() |> with_tax()

  @doc """
  The gold tier's price for the product, in cents.

  The gold discount is 10% off the list price, rounded to the nearest cent. Tax is not
  included: see `gold_price_with_tax/1` for what the customer pays.

  The discount comes from the catalog's tier table, so a change to the gold rate is made
  there and nowhere else. A product priced at 0 stays at 0 in every tier, and the result
  is never negative.
  """
  @spec gold_price(Product.t()) :: non_neg_integer()
  def gold_price(%Product{price: price}), do: discounted(price, @tier_discounts.gold)

  @doc """
  The gold tier's price with sales tax, in cents: what a gold customer pays.

  Tax is charged on the discounted price at the catalog's one rate, and the result is
  rounded to the nearest cent once, at the end.

  Rounding once matters: rounding the discount and then the tax apart can be a cent off
  on some prices, and the invoice and the product page then disagree about what the
  customer was told.
  """
  @spec gold_price_with_tax(Product.t()) :: non_neg_integer()
  def gold_price_with_tax(%Product{} = product), do: product |> gold_price() |> with_tax()

  @doc """
  The platinum tier's price for the product, in cents.

  The platinum discount is 15% off the list price, rounded to the nearest cent. Tax is not
  included: see `platinum_price_with_tax/1` for what the customer pays.

  The discount comes from the catalog's tier table, so a change to the platinum rate is made
  there and nowhere else. A product priced at 0 stays at 0 in every tier, and the result
  is never negative.
  """
  @spec platinum_price(Product.t()) :: non_neg_integer()
  def platinum_price(%Product{price: price}), do: discounted(price, @tier_discounts.platinum)

  @doc """
  The platinum tier's price with sales tax, in cents: what a platinum customer pays.

  Tax is charged on the discounted price at the catalog's one rate, and the result is
  rounded to the nearest cent once, at the end.

  Rounding once matters: rounding the discount and then the tax apart can be a cent off
  on some prices, and the invoice and the product page then disagree about what the
  customer was told.
  """
  @spec platinum_price_with_tax(Product.t()) :: non_neg_integer()
  def platinum_price_with_tax(%Product{} = product), do: product |> platinum_price() |> with_tax()

  @doc """
  The retail tier's price for the product, in cents.

  The retail discount is 0% off the list price, rounded to the nearest cent. Tax is not
  included: see `retail_price_with_tax/1` for what the customer pays.

  The discount comes from the catalog's tier table, so a change to the retail rate is made
  there and nowhere else. A product priced at 0 stays at 0 in every tier, and the result
  is never negative.
  """
  @spec retail_price(Product.t()) :: non_neg_integer()
  def retail_price(%Product{price: price}), do: discounted(price, @tier_discounts.retail)

  @doc """
  The retail tier's price with sales tax, in cents: what a retail customer pays.

  Tax is charged on the discounted price at the catalog's one rate, and the result is
  rounded to the nearest cent once, at the end.

  Rounding once matters: rounding the discount and then the tax apart can be a cent off
  on some prices, and the invoice and the product page then disagree about what the
  customer was told.
  """
  @spec retail_price_with_tax(Product.t()) :: non_neg_integer()
  def retail_price_with_tax(%Product{} = product), do: product |> retail_price() |> with_tax()

  @doc """
  The wholesale tier's price for the product, in cents.

  The wholesale discount is 25% off the list price, rounded to the nearest cent. Tax is not
  included: see `wholesale_price_with_tax/1` for what the customer pays.

  The discount comes from the catalog's tier table, so a change to the wholesale rate is made
  there and nowhere else. A product priced at 0 stays at 0 in every tier, and the result
  is never negative.
  """
  @spec wholesale_price(Product.t()) :: non_neg_integer()
  def wholesale_price(%Product{price: price}), do: discounted(price, @tier_discounts.wholesale)

  @doc """
  The wholesale tier's price with sales tax, in cents: what a wholesale customer pays.

  Tax is charged on the discounted price at the catalog's one rate, and the result is
  rounded to the nearest cent once, at the end.

  Rounding once matters: rounding the discount and then the tax apart can be a cent off
  on some prices, and the invoice and the product page then disagree about what the
  customer was told.
  """
  @spec wholesale_price_with_tax(Product.t()) :: non_neg_integer()
  def wholesale_price_with_tax(%Product{} = product),
    do: product |> wholesale_price() |> with_tax()

  @doc """
  The staff tier's price for the product, in cents.

  The staff discount is 30% off the list price, rounded to the nearest cent. Tax is not
  included: see `staff_price_with_tax/1` for what the customer pays.

  The discount comes from the catalog's tier table, so a change to the staff rate is made
  there and nowhere else. A product priced at 0 stays at 0 in every tier, and the result
  is never negative.
  """
  @spec staff_price(Product.t()) :: non_neg_integer()
  def staff_price(%Product{price: price}), do: discounted(price, @tier_discounts.staff)

  @doc """
  The staff tier's price with sales tax, in cents: what a staff customer pays.

  Tax is charged on the discounted price at the catalog's one rate, and the result is
  rounded to the nearest cent once, at the end.

  Rounding once matters: rounding the discount and then the tax apart can be a cent off
  on some prices, and the invoice and the product page then disagree about what the
  customer was told.
  """
  @spec staff_price_with_tax(Product.t()) :: non_neg_integer()
  def staff_price_with_tax(%Product{} = product), do: product |> staff_price() |> with_tax()

  @doc """
  The partner tier's price for the product, in cents.

  The partner discount is 20% off the list price, rounded to the nearest cent. Tax is not
  included: see `partner_price_with_tax/1` for what the customer pays.

  The discount comes from the catalog's tier table, so a change to the partner rate is made
  there and nowhere else. A product priced at 0 stays at 0 in every tier, and the result
  is never negative.
  """
  @spec partner_price(Product.t()) :: non_neg_integer()
  def partner_price(%Product{price: price}), do: discounted(price, @tier_discounts.partner)

  @doc """
  The partner tier's price with sales tax, in cents: what a partner customer pays.

  Tax is charged on the discounted price at the catalog's one rate, and the result is
  rounded to the nearest cent once, at the end.

  Rounding once matters: rounding the discount and then the tax apart can be a cent off
  on some prices, and the invoice and the product page then disagree about what the
  customer was told.
  """
  @spec partner_price_with_tax(Product.t()) :: non_neg_integer()
  def partner_price_with_tax(%Product{} = product), do: product |> partner_price() |> with_tax()

  @doc """
  The student tier's price for the product, in cents.

  The student discount is 12% off the list price, rounded to the nearest cent. Tax is not
  included: see `student_price_with_tax/1` for what the customer pays.

  The discount comes from the catalog's tier table, so a change to the student rate is made
  there and nowhere else. A product priced at 0 stays at 0 in every tier, and the result
  is never negative.
  """
  @spec student_price(Product.t()) :: non_neg_integer()
  def student_price(%Product{price: price}), do: discounted(price, @tier_discounts.student)

  @doc """
  The student tier's price with sales tax, in cents: what a student customer pays.

  Tax is charged on the discounted price at the catalog's one rate, and the result is
  rounded to the nearest cent once, at the end.

  Rounding once matters: rounding the discount and then the tax apart can be a cent off
  on some prices, and the invoice and the product page then disagree about what the
  customer was told.
  """
  @spec student_price_with_tax(Product.t()) :: non_neg_integer()
  def student_price_with_tax(%Product{} = product), do: product |> student_price() |> with_tax()

  @doc """
  The senior tier's price for the product, in cents.

  The senior discount is 8% off the list price, rounded to the nearest cent. Tax is not
  included: see `senior_price_with_tax/1` for what the customer pays.

  The discount comes from the catalog's tier table, so a change to the senior rate is made
  there and nowhere else. A product priced at 0 stays at 0 in every tier, and the result
  is never negative.
  """
  @spec senior_price(Product.t()) :: non_neg_integer()
  def senior_price(%Product{price: price}), do: discounted(price, @tier_discounts.senior)

  @doc """
  The senior tier's price with sales tax, in cents: what a senior customer pays.

  Tax is charged on the discounted price at the catalog's one rate, and the result is
  rounded to the nearest cent once, at the end.

  Rounding once matters: rounding the discount and then the tax apart can be a cent off
  on some prices, and the invoice and the product page then disagree about what the
  customer was told.
  """
  @spec senior_price_with_tax(Product.t()) :: non_neg_integer()
  def senior_price_with_tax(%Product{} = product), do: product |> senior_price() |> with_tax()

  @doc """
  The nonprofit tier's price for the product, in cents.

  The nonprofit discount is 18% off the list price, rounded to the nearest cent. Tax is not
  included: see `nonprofit_price_with_tax/1` for what the customer pays.

  The discount comes from the catalog's tier table, so a change to the nonprofit rate is made
  there and nowhere else. A product priced at 0 stays at 0 in every tier, and the result
  is never negative.
  """
  @spec nonprofit_price(Product.t()) :: non_neg_integer()
  def nonprofit_price(%Product{price: price}), do: discounted(price, @tier_discounts.nonprofit)

  @doc """
  The nonprofit tier's price with sales tax, in cents: what a nonprofit customer pays.

  Tax is charged on the discounted price at the catalog's one rate, and the result is
  rounded to the nearest cent once, at the end.

  Rounding once matters: rounding the discount and then the tax apart can be a cent off
  on some prices, and the invoice and the product page then disagree about what the
  customer was told.
  """
  @spec nonprofit_price_with_tax(Product.t()) :: non_neg_integer()
  def nonprofit_price_with_tax(%Product{} = product),
    do: product |> nonprofit_price() |> with_tax()

  @doc """
  The family tier's price for the product, in cents.

  The family discount is 22% off the list price, rounded to the nearest cent. Tax is not
  included: see `family_price_with_tax/1` for what the customer pays.

  The discount comes from the catalog's tier table, so a change to the family rate is made
  there and nowhere else. A product priced at 0 stays at 0 in every tier, and the result
  is never negative.
  """
  @spec family_price(Product.t()) :: non_neg_integer()
  def family_price(%Product{price: price}), do: discounted(price, @tier_discounts.family)

  @doc """
  The family tier's price with sales tax, in cents: what a family customer pays.

  Tax is charged on the discounted price at the catalog's one rate, and the result is
  rounded to the nearest cent once, at the end.

  Rounding once matters: rounding the discount and then the tax apart can be a cent off
  on some prices, and the invoice and the product page then disagree about what the
  customer was told.
  """
  @spec family_price_with_tax(Product.t()) :: non_neg_integer()
  def family_price_with_tax(%Product{} = product), do: product |> family_price() |> with_tax()

  defp discounted(price, pct), do: cents(price * (100 - pct) / 100)

  defp with_tax(price), do: cents(price * (1 + @tax_rate))

  # ---------------------------------------------------------------------------------------
  # Inventory: stock per warehouse, by normalized SKU.

  @low_stock 5

  @doc """
  How many of the SKU the north warehouse holds; 0 when it holds none.

  The SKU is normalized first, so `" ab-1"` and `"AB-1"` are one line of stock.

  Stock is a map of warehouse to a map of SKU to level. A warehouse that has never been
  restocked has no entry at all, and is read as holding nothing; it is not an error to
  ask about one.
  """
  @spec stock_in_north(map(), String.t()) :: non_neg_integer()
  def stock_in_north(stock, sku),
    do: stock |> Map.get(:north, %{}) |> Map.get(normalize_sku(sku), 0)

  @doc """
  Adds `qty` of the SKU to the north warehouse.

  A level still under the low-stock mark after the restock is logged as a warning, so that
  a restock too small to matter is seen.

  The quantity must be a positive integer: a negative restock is a sale or a write-off,
  and those go through their own functions so that the books can tell them apart. The
  stock map returned holds every other warehouse unchanged.
  """
  @spec restock_north(map(), String.t(), pos_integer()) :: map()
  def restock_north(stock, sku, qty) when is_integer(qty) and qty > 0 do
    key = normalize_sku(sku)
    level = stock_in_north(stock, key) + qty
    warn_if_low(:north, key, level)
    Map.update(stock, :north, %{key => level}, &Map.put(&1, key, level))
  end

  @doc """
  How many of the SKU the south warehouse holds; 0 when it holds none.

  The SKU is normalized first, so `" ab-1"` and `"AB-1"` are one line of stock.

  Stock is a map of warehouse to a map of SKU to level. A warehouse that has never been
  restocked has no entry at all, and is read as holding nothing; it is not an error to
  ask about one.
  """
  @spec stock_in_south(map(), String.t()) :: non_neg_integer()
  def stock_in_south(stock, sku),
    do: stock |> Map.get(:south, %{}) |> Map.get(normalize_sku(sku), 0)

  @doc """
  Adds `qty` of the SKU to the south warehouse.

  A level still under the low-stock mark after the restock is logged as a warning, so that
  a restock too small to matter is seen.

  The quantity must be a positive integer: a negative restock is a sale or a write-off,
  and those go through their own functions so that the books can tell them apart. The
  stock map returned holds every other warehouse unchanged.
  """
  @spec restock_south(map(), String.t(), pos_integer()) :: map()
  def restock_south(stock, sku, qty) when is_integer(qty) and qty > 0 do
    key = normalize_sku(sku)
    level = stock_in_south(stock, key) + qty
    warn_if_low(:south, key, level)
    Map.update(stock, :south, %{key => level}, &Map.put(&1, key, level))
  end

  @doc """
  How many of the SKU the east warehouse holds; 0 when it holds none.

  The SKU is normalized first, so `" ab-1"` and `"AB-1"` are one line of stock.

  Stock is a map of warehouse to a map of SKU to level. A warehouse that has never been
  restocked has no entry at all, and is read as holding nothing; it is not an error to
  ask about one.
  """
  @spec stock_in_east(map(), String.t()) :: non_neg_integer()
  def stock_in_east(stock, sku),
    do: stock |> Map.get(:east, %{}) |> Map.get(normalize_sku(sku), 0)

  @doc """
  Adds `qty` of the SKU to the east warehouse.

  A level still under the low-stock mark after the restock is logged as a warning, so that
  a restock too small to matter is seen.

  The quantity must be a positive integer: a negative restock is a sale or a write-off,
  and those go through their own functions so that the books can tell them apart. The
  stock map returned holds every other warehouse unchanged.
  """
  @spec restock_east(map(), String.t(), pos_integer()) :: map()
  def restock_east(stock, sku, qty) when is_integer(qty) and qty > 0 do
    key = normalize_sku(sku)
    level = stock_in_east(stock, key) + qty
    warn_if_low(:east, key, level)
    Map.update(stock, :east, %{key => level}, &Map.put(&1, key, level))
  end

  @doc """
  How many of the SKU the west warehouse holds; 0 when it holds none.

  The SKU is normalized first, so `" ab-1"` and `"AB-1"` are one line of stock.

  Stock is a map of warehouse to a map of SKU to level. A warehouse that has never been
  restocked has no entry at all, and is read as holding nothing; it is not an error to
  ask about one.
  """
  @spec stock_in_west(map(), String.t()) :: non_neg_integer()
  def stock_in_west(stock, sku),
    do: stock |> Map.get(:west, %{}) |> Map.get(normalize_sku(sku), 0)

  @doc """
  Adds `qty` of the SKU to the west warehouse.

  A level still under the low-stock mark after the restock is logged as a warning, so that
  a restock too small to matter is seen.

  The quantity must be a positive integer: a negative restock is a sale or a write-off,
  and those go through their own functions so that the books can tell them apart. The
  stock map returned holds every other warehouse unchanged.
  """
  @spec restock_west(map(), String.t(), pos_integer()) :: map()
  def restock_west(stock, sku, qty) when is_integer(qty) and qty > 0 do
    key = normalize_sku(sku)
    level = stock_in_west(stock, key) + qty
    warn_if_low(:west, key, level)
    Map.update(stock, :west, %{key => level}, &Map.put(&1, key, level))
  end

  @doc """
  How many of the SKU the central warehouse holds; 0 when it holds none.

  The SKU is normalized first, so `" ab-1"` and `"AB-1"` are one line of stock.

  Stock is a map of warehouse to a map of SKU to level. A warehouse that has never been
  restocked has no entry at all, and is read as holding nothing; it is not an error to
  ask about one.
  """
  @spec stock_in_central(map(), String.t()) :: non_neg_integer()
  def stock_in_central(stock, sku),
    do: stock |> Map.get(:central, %{}) |> Map.get(normalize_sku(sku), 0)

  @doc """
  Adds `qty` of the SKU to the central warehouse.

  A level still under the low-stock mark after the restock is logged as a warning, so that
  a restock too small to matter is seen.

  The quantity must be a positive integer: a negative restock is a sale or a write-off,
  and those go through their own functions so that the books can tell them apart. The
  stock map returned holds every other warehouse unchanged.
  """
  @spec restock_central(map(), String.t(), pos_integer()) :: map()
  def restock_central(stock, sku, qty) when is_integer(qty) and qty > 0 do
    key = normalize_sku(sku)
    level = stock_in_central(stock, key) + qty
    warn_if_low(:central, key, level)
    Map.update(stock, :central, %{key => level}, &Map.put(&1, key, level))
  end

  @doc """
  How many of the SKU the overflow warehouse holds; 0 when it holds none.

  The SKU is normalized first, so `" ab-1"` and `"AB-1"` are one line of stock.

  Stock is a map of warehouse to a map of SKU to level. A warehouse that has never been
  restocked has no entry at all, and is read as holding nothing; it is not an error to
  ask about one.
  """
  @spec stock_in_overflow(map(), String.t()) :: non_neg_integer()
  def stock_in_overflow(stock, sku),
    do: stock |> Map.get(:overflow, %{}) |> Map.get(normalize_sku(sku), 0)

  @doc """
  Adds `qty` of the SKU to the overflow warehouse.

  A level still under the low-stock mark after the restock is logged as a warning, so that
  a restock too small to matter is seen.

  The quantity must be a positive integer: a negative restock is a sale or a write-off,
  and those go through their own functions so that the books can tell them apart. The
  stock map returned holds every other warehouse unchanged.
  """
  @spec restock_overflow(map(), String.t(), pos_integer()) :: map()
  def restock_overflow(stock, sku, qty) when is_integer(qty) and qty > 0 do
    key = normalize_sku(sku)
    level = stock_in_overflow(stock, key) + qty
    warn_if_low(:overflow, key, level)
    Map.update(stock, :overflow, %{key => level}, &Map.put(&1, key, level))
  end

  @doc """
  How many of the SKU the returns warehouse holds; 0 when it holds none.

  The SKU is normalized first, so `" ab-1"` and `"AB-1"` are one line of stock.

  Stock is a map of warehouse to a map of SKU to level. A warehouse that has never been
  restocked has no entry at all, and is read as holding nothing; it is not an error to
  ask about one.
  """
  @spec stock_in_returns(map(), String.t()) :: non_neg_integer()
  def stock_in_returns(stock, sku),
    do: stock |> Map.get(:returns, %{}) |> Map.get(normalize_sku(sku), 0)

  @doc """
  Adds `qty` of the SKU to the returns warehouse.

  A level still under the low-stock mark after the restock is logged as a warning, so that
  a restock too small to matter is seen.

  The quantity must be a positive integer: a negative restock is a sale or a write-off,
  and those go through their own functions so that the books can tell them apart. The
  stock map returned holds every other warehouse unchanged.
  """
  @spec restock_returns(map(), String.t(), pos_integer()) :: map()
  def restock_returns(stock, sku, qty) when is_integer(qty) and qty > 0 do
    key = normalize_sku(sku)
    level = stock_in_returns(stock, key) + qty
    warn_if_low(:returns, key, level)
    Map.update(stock, :returns, %{key => level}, &Map.put(&1, key, level))
  end

  @doc """
  How many of the SKU the transit warehouse holds; 0 when it holds none.

  The SKU is normalized first, so `" ab-1"` and `"AB-1"` are one line of stock.

  Stock is a map of warehouse to a map of SKU to level. A warehouse that has never been
  restocked has no entry at all, and is read as holding nothing; it is not an error to
  ask about one.
  """
  @spec stock_in_transit(map(), String.t()) :: non_neg_integer()
  def stock_in_transit(stock, sku),
    do: stock |> Map.get(:transit, %{}) |> Map.get(normalize_sku(sku), 0)

  @doc """
  Adds `qty` of the SKU to the transit warehouse.

  A level still under the low-stock mark after the restock is logged as a warning, so that
  a restock too small to matter is seen.

  The quantity must be a positive integer: a negative restock is a sale or a write-off,
  and those go through their own functions so that the books can tell them apart. The
  stock map returned holds every other warehouse unchanged.
  """
  @spec restock_transit(map(), String.t(), pos_integer()) :: map()
  def restock_transit(stock, sku, qty) when is_integer(qty) and qty > 0 do
    key = normalize_sku(sku)
    level = stock_in_transit(stock, key) + qty
    warn_if_low(:transit, key, level)
    Map.update(stock, :transit, %{key => level}, &Map.put(&1, key, level))
  end

  @doc """
  How many of the SKU the airport warehouse holds; 0 when it holds none.

  The SKU is normalized first, so `" ab-1"` and `"AB-1"` are one line of stock.

  Stock is a map of warehouse to a map of SKU to level. A warehouse that has never been
  restocked has no entry at all, and is read as holding nothing; it is not an error to
  ask about one.
  """
  @spec stock_in_airport(map(), String.t()) :: non_neg_integer()
  def stock_in_airport(stock, sku),
    do: stock |> Map.get(:airport, %{}) |> Map.get(normalize_sku(sku), 0)

  @doc """
  Adds `qty` of the SKU to the airport warehouse.

  A level still under the low-stock mark after the restock is logged as a warning, so that
  a restock too small to matter is seen.

  The quantity must be a positive integer: a negative restock is a sale or a write-off,
  and those go through their own functions so that the books can tell them apart. The
  stock map returned holds every other warehouse unchanged.
  """
  @spec restock_airport(map(), String.t(), pos_integer()) :: map()
  def restock_airport(stock, sku, qty) when is_integer(qty) and qty > 0 do
    key = normalize_sku(sku)
    level = stock_in_airport(stock, key) + qty
    warn_if_low(:airport, key, level)
    Map.update(stock, :airport, %{key => level}, &Map.put(&1, key, level))
  end

  @doc """
  How many of the SKU the harbor warehouse holds; 0 when it holds none.

  The SKU is normalized first, so `" ab-1"` and `"AB-1"` are one line of stock.

  Stock is a map of warehouse to a map of SKU to level. A warehouse that has never been
  restocked has no entry at all, and is read as holding nothing; it is not an error to
  ask about one.
  """
  @spec stock_in_harbor(map(), String.t()) :: non_neg_integer()
  def stock_in_harbor(stock, sku),
    do: stock |> Map.get(:harbor, %{}) |> Map.get(normalize_sku(sku), 0)

  @doc """
  Adds `qty` of the SKU to the harbor warehouse.

  A level still under the low-stock mark after the restock is logged as a warning, so that
  a restock too small to matter is seen.

  The quantity must be a positive integer: a negative restock is a sale or a write-off,
  and those go through their own functions so that the books can tell them apart. The
  stock map returned holds every other warehouse unchanged.
  """
  @spec restock_harbor(map(), String.t(), pos_integer()) :: map()
  def restock_harbor(stock, sku, qty) when is_integer(qty) and qty > 0 do
    key = normalize_sku(sku)
    level = stock_in_harbor(stock, key) + qty
    warn_if_low(:harbor, key, level)
    Map.update(stock, :harbor, %{key => level}, &Map.put(&1, key, level))
  end

  @doc """
  How many of the SKU the depot warehouse holds; 0 when it holds none.

  The SKU is normalized first, so `" ab-1"` and `"AB-1"` are one line of stock.

  Stock is a map of warehouse to a map of SKU to level. A warehouse that has never been
  restocked has no entry at all, and is read as holding nothing; it is not an error to
  ask about one.
  """
  @spec stock_in_depot(map(), String.t()) :: non_neg_integer()
  def stock_in_depot(stock, sku),
    do: stock |> Map.get(:depot, %{}) |> Map.get(normalize_sku(sku), 0)

  @doc """
  Adds `qty` of the SKU to the depot warehouse.

  A level still under the low-stock mark after the restock is logged as a warning, so that
  a restock too small to matter is seen.

  The quantity must be a positive integer: a negative restock is a sale or a write-off,
  and those go through their own functions so that the books can tell them apart. The
  stock map returned holds every other warehouse unchanged.
  """
  @spec restock_depot(map(), String.t(), pos_integer()) :: map()
  def restock_depot(stock, sku, qty) when is_integer(qty) and qty > 0 do
    key = normalize_sku(sku)
    level = stock_in_depot(stock, key) + qty
    warn_if_low(:depot, key, level)
    Map.update(stock, :depot, %{key => level}, &Map.put(&1, key, level))
  end

  @doc """
  How many of the SKU the annex warehouse holds; 0 when it holds none.

  The SKU is normalized first, so `" ab-1"` and `"AB-1"` are one line of stock.

  Stock is a map of warehouse to a map of SKU to level. A warehouse that has never been
  restocked has no entry at all, and is read as holding nothing; it is not an error to
  ask about one.
  """
  @spec stock_in_annex(map(), String.t()) :: non_neg_integer()
  def stock_in_annex(stock, sku),
    do: stock |> Map.get(:annex, %{}) |> Map.get(normalize_sku(sku), 0)

  @doc """
  Adds `qty` of the SKU to the annex warehouse.

  A level still under the low-stock mark after the restock is logged as a warning, so that
  a restock too small to matter is seen.

  The quantity must be a positive integer: a negative restock is a sale or a write-off,
  and those go through their own functions so that the books can tell them apart. The
  stock map returned holds every other warehouse unchanged.
  """
  @spec restock_annex(map(), String.t(), pos_integer()) :: map()
  def restock_annex(stock, sku, qty) when is_integer(qty) and qty > 0 do
    key = normalize_sku(sku)
    level = stock_in_annex(stock, key) + qty
    warn_if_low(:annex, key, level)
    Map.update(stock, :annex, %{key => level}, &Map.put(&1, key, level))
  end

  defp warn_if_low(warehouse, sku, level) when level < @low_stock do
    Logger.warning("#{sku} is low in #{warehouse}: #{level} left")
  end

  defp warn_if_low(_warehouse, _sku, _level), do: :ok

  # ---------------------------------------------------------------------------------------
  # Search: finding products by SKU, price and attribute.

  @max_results 50

  @doc """
  The product with the SKU, or `nil`. The SKU is normalized first.
  """
  @spec find_by_sku([Product.t()], String.t()) :: Product.t() | nil
  def find_by_sku(products, sku) do
    key = normalize_sku(sku)
    Enum.find(products, &(&1.sku == key))
  end

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

  @doc """
  The products whose name contains `query`, case-insensitively, at most 50 of them.

  A product with no name never matches, and neither does an empty query.

  The products come back in the order they were given, so a caller that sorted them
  (by price, by popularity) keeps its order. The cap keeps a broad query from sending
  the whole catalog to a page that shows a screenful.
  """
  @spec search_by_name([Product.t()], String.t()) :: [Product.t()]
  def search_by_name(products, query) do
    products |> Enum.filter(&matches?(Map.get(&1.attrs, :name), query)) |> Enum.take(@max_results)
  end

  @doc """
  How many products `search_by_name/2` finds for `query`.

  The count is of what the search returns, so it is capped the same way: a page that
  says "50 results" for a broad query is saying "at least 50". A count of 0 means the
  query matched nothing, not that the products have no name.
  """
  @spec count_by_name([Product.t()], String.t()) :: non_neg_integer()
  def count_by_name(products, query), do: products |> search_by_name(query) |> length()

  @doc """
  The products whose description contains `query`, case-insensitively, at most 50 of them.

  A product with no description never matches, and neither does an empty query.

  The products come back in the order they were given, so a caller that sorted them
  (by price, by popularity) keeps its order. The cap keeps a broad query from sending
  the whole catalog to a page that shows a screenful.
  """
  @spec search_by_description([Product.t()], String.t()) :: [Product.t()]
  def search_by_description(products, query) do
    products
    |> Enum.filter(&matches?(Map.get(&1.attrs, :description), query))
    |> Enum.take(@max_results)
  end

  @doc """
  How many products `search_by_description/2` finds for `query`.

  The count is of what the search returns, so it is capped the same way: a page that
  says "50 results" for a broad query is saying "at least 50". A count of 0 means the
  query matched nothing, not that the products have no description.
  """
  @spec count_by_description([Product.t()], String.t()) :: non_neg_integer()
  def count_by_description(products, query),
    do: products |> search_by_description(query) |> length()

  @doc """
  The products whose brand contains `query`, case-insensitively, at most 50 of them.

  A product with no brand never matches, and neither does an empty query.

  The products come back in the order they were given, so a caller that sorted them
  (by price, by popularity) keeps its order. The cap keeps a broad query from sending
  the whole catalog to a page that shows a screenful.
  """
  @spec search_by_brand([Product.t()], String.t()) :: [Product.t()]
  def search_by_brand(products, query) do
    products
    |> Enum.filter(&matches?(Map.get(&1.attrs, :brand), query))
    |> Enum.take(@max_results)
  end

  @doc """
  How many products `search_by_brand/2` finds for `query`.

  The count is of what the search returns, so it is capped the same way: a page that
  says "50 results" for a broad query is saying "at least 50". A count of 0 means the
  query matched nothing, not that the products have no brand.
  """
  @spec count_by_brand([Product.t()], String.t()) :: non_neg_integer()
  def count_by_brand(products, query), do: products |> search_by_brand(query) |> length()

  @doc """
  The products whose color contains `query`, case-insensitively, at most 50 of them.

  A product with no color never matches, and neither does an empty query.

  The products come back in the order they were given, so a caller that sorted them
  (by price, by popularity) keeps its order. The cap keeps a broad query from sending
  the whole catalog to a page that shows a screenful.
  """
  @spec search_by_color([Product.t()], String.t()) :: [Product.t()]
  def search_by_color(products, query) do
    products
    |> Enum.filter(&matches?(Map.get(&1.attrs, :color), query))
    |> Enum.take(@max_results)
  end

  @doc """
  How many products `search_by_color/2` finds for `query`.

  The count is of what the search returns, so it is capped the same way: a page that
  says "50 results" for a broad query is saying "at least 50". A count of 0 means the
  query matched nothing, not that the products have no color.
  """
  @spec count_by_color([Product.t()], String.t()) :: non_neg_integer()
  def count_by_color(products, query), do: products |> search_by_color(query) |> length()

  @doc """
  The products whose size contains `query`, case-insensitively, at most 50 of them.

  A product with no size never matches, and neither does an empty query.

  The products come back in the order they were given, so a caller that sorted them
  (by price, by popularity) keeps its order. The cap keeps a broad query from sending
  the whole catalog to a page that shows a screenful.
  """
  @spec search_by_size([Product.t()], String.t()) :: [Product.t()]
  def search_by_size(products, query) do
    products |> Enum.filter(&matches?(Map.get(&1.attrs, :size), query)) |> Enum.take(@max_results)
  end

  @doc """
  How many products `search_by_size/2` finds for `query`.

  The count is of what the search returns, so it is capped the same way: a page that
  says "50 results" for a broad query is saying "at least 50". A count of 0 means the
  query matched nothing, not that the products have no size.
  """
  @spec count_by_size([Product.t()], String.t()) :: non_neg_integer()
  def count_by_size(products, query), do: products |> search_by_size(query) |> length()

  @doc """
  The products whose weight contains `query`, case-insensitively, at most 50 of them.

  A product with no weight never matches, and neither does an empty query.

  The products come back in the order they were given, so a caller that sorted them
  (by price, by popularity) keeps its order. The cap keeps a broad query from sending
  the whole catalog to a page that shows a screenful.
  """
  @spec search_by_weight([Product.t()], String.t()) :: [Product.t()]
  def search_by_weight(products, query) do
    products
    |> Enum.filter(&matches?(Map.get(&1.attrs, :weight), query))
    |> Enum.take(@max_results)
  end

  @doc """
  How many products `search_by_weight/2` finds for `query`.

  The count is of what the search returns, so it is capped the same way: a page that
  says "50 results" for a broad query is saying "at least 50". A count of 0 means the
  query matched nothing, not that the products have no weight.
  """
  @spec count_by_weight([Product.t()], String.t()) :: non_neg_integer()
  def count_by_weight(products, query), do: products |> search_by_weight(query) |> length()

  @doc """
  The products whose material contains `query`, case-insensitively, at most 50 of them.

  A product with no material never matches, and neither does an empty query.

  The products come back in the order they were given, so a caller that sorted them
  (by price, by popularity) keeps its order. The cap keeps a broad query from sending
  the whole catalog to a page that shows a screenful.
  """
  @spec search_by_material([Product.t()], String.t()) :: [Product.t()]
  def search_by_material(products, query) do
    products
    |> Enum.filter(&matches?(Map.get(&1.attrs, :material), query))
    |> Enum.take(@max_results)
  end

  @doc """
  How many products `search_by_material/2` finds for `query`.

  The count is of what the search returns, so it is capped the same way: a page that
  says "50 results" for a broad query is saying "at least 50". A count of 0 means the
  query matched nothing, not that the products have no material.
  """
  @spec count_by_material([Product.t()], String.t()) :: non_neg_integer()
  def count_by_material(products, query), do: products |> search_by_material(query) |> length()

  @doc """
  The products whose origin contains `query`, case-insensitively, at most 50 of them.

  A product with no origin never matches, and neither does an empty query.

  The products come back in the order they were given, so a caller that sorted them
  (by price, by popularity) keeps its order. The cap keeps a broad query from sending
  the whole catalog to a page that shows a screenful.
  """
  @spec search_by_origin([Product.t()], String.t()) :: [Product.t()]
  def search_by_origin(products, query) do
    products
    |> Enum.filter(&matches?(Map.get(&1.attrs, :origin), query))
    |> Enum.take(@max_results)
  end

  @doc """
  How many products `search_by_origin/2` finds for `query`.

  The count is of what the search returns, so it is capped the same way: a page that
  says "50 results" for a broad query is saying "at least 50". A count of 0 means the
  query matched nothing, not that the products have no origin.
  """
  @spec count_by_origin([Product.t()], String.t()) :: non_neg_integer()
  def count_by_origin(products, query), do: products |> search_by_origin(query) |> length()

  @doc """
  The products whose finish contains `query`, case-insensitively, at most 50 of them.

  A product with no finish never matches, and neither does an empty query.

  The products come back in the order they were given, so a caller that sorted them
  (by price, by popularity) keeps its order. The cap keeps a broad query from sending
  the whole catalog to a page that shows a screenful.
  """
  @spec search_by_finish([Product.t()], String.t()) :: [Product.t()]
  def search_by_finish(products, query) do
    products
    |> Enum.filter(&matches?(Map.get(&1.attrs, :finish), query))
    |> Enum.take(@max_results)
  end

  @doc """
  How many products `search_by_finish/2` finds for `query`.

  The count is of what the search returns, so it is capped the same way: a page that
  says "50 results" for a broad query is saying "at least 50". A count of 0 means the
  query matched nothing, not that the products have no finish.
  """
  @spec count_by_finish([Product.t()], String.t()) :: non_neg_integer()
  def count_by_finish(products, query), do: products |> search_by_finish(query) |> length()

  @doc """
  The products whose care contains `query`, case-insensitively, at most 50 of them.

  A product with no care never matches, and neither does an empty query.

  The products come back in the order they were given, so a caller that sorted them
  (by price, by popularity) keeps its order. The cap keeps a broad query from sending
  the whole catalog to a page that shows a screenful.
  """
  @spec search_by_care([Product.t()], String.t()) :: [Product.t()]
  def search_by_care(products, query) do
    products |> Enum.filter(&matches?(Map.get(&1.attrs, :care), query)) |> Enum.take(@max_results)
  end

  @doc """
  How many products `search_by_care/2` finds for `query`.

  The count is of what the search returns, so it is capped the same way: a page that
  says "50 results" for a broad query is saying "at least 50". A count of 0 means the
  query matched nothing, not that the products have no care.
  """
  @spec count_by_care([Product.t()], String.t()) :: non_neg_integer()
  def count_by_care(products, query), do: products |> search_by_care(query) |> length()

  @doc """
  The products whose warranty contains `query`, case-insensitively, at most 50 of them.

  A product with no warranty never matches, and neither does an empty query.

  The products come back in the order they were given, so a caller that sorted them
  (by price, by popularity) keeps its order. The cap keeps a broad query from sending
  the whole catalog to a page that shows a screenful.
  """
  @spec search_by_warranty([Product.t()], String.t()) :: [Product.t()]
  def search_by_warranty(products, query) do
    products
    |> Enum.filter(&matches?(Map.get(&1.attrs, :warranty), query))
    |> Enum.take(@max_results)
  end

  @doc """
  How many products `search_by_warranty/2` finds for `query`.

  The count is of what the search returns, so it is capped the same way: a page that
  says "50 results" for a broad query is saying "at least 50". A count of 0 means the
  query matched nothing, not that the products have no warranty.
  """
  @spec count_by_warranty([Product.t()], String.t()) :: non_neg_integer()
  def count_by_warranty(products, query), do: products |> search_by_warranty(query) |> length()

  @doc """
  The products whose model contains `query`, case-insensitively, at most 50 of them.

  A product with no model never matches, and neither does an empty query.

  The products come back in the order they were given, so a caller that sorted them
  (by price, by popularity) keeps its order. The cap keeps a broad query from sending
  the whole catalog to a page that shows a screenful.
  """
  @spec search_by_model([Product.t()], String.t()) :: [Product.t()]
  def search_by_model(products, query) do
    products
    |> Enum.filter(&matches?(Map.get(&1.attrs, :model), query))
    |> Enum.take(@max_results)
  end

  @doc """
  How many products `search_by_model/2` finds for `query`.

  The count is of what the search returns, so it is capped the same way: a page that
  says "50 results" for a broad query is saying "at least 50". A count of 0 means the
  query matched nothing, not that the products have no model.
  """
  @spec count_by_model([Product.t()], String.t()) :: non_neg_integer()
  def count_by_model(products, query), do: products |> search_by_model(query) |> length()

  defp matches?(nil, _query), do: false
  defp matches?(_text, ""), do: false
  defp matches?(text, query), do: String.contains?(String.downcase(text), String.downcase(query))

  # ---------------------------------------------------------------------------------------
  # Reviews: ratings per aspect of a product, and their means.

  @max_stars 5

  @doc """
  Adds a rating of the product's quality, from 1 to the catalog's top mark.

  A rating outside that range is clamped into it rather than refused: a 0 from a form that
  lost its value is a 1, a 9 from an import is the top mark.

  The new rating goes at the head of the list. Ratings are kept as given, one entry per
  rating, so a mean can be taken over any aspect later; nothing is summed in advance.
  """
  @spec rate_quality([{atom(), pos_integer()}], integer()) :: [{atom(), pos_integer()}]
  def rate_quality(reviews, stars), do: [{:quality, clamp(stars, 1, @max_stars)} | reviews]

  @doc """
  The mean rating of the product's quality to one decimal place, or `nil` with no rating.

  Only the quality ratings count; the other aspects in the list are left out.

  Every rating weighs the same, old or new. A product with a handful of ratings has a
  mean that moves a lot with each one; a page may want to show the count beside it.
  """
  @spec average_quality([{atom(), pos_integer()}]) :: float() | nil
  def average_quality(reviews) do
    case for {:quality, stars} <- reviews, do: stars do
      [] -> nil
      stars -> round_to(Enum.sum(stars) / length(stars), 1)
    end
  end

  @doc """
  Adds a rating of the product's value, from 1 to the catalog's top mark.

  A rating outside that range is clamped into it rather than refused: a 0 from a form that
  lost its value is a 1, a 9 from an import is the top mark.

  The new rating goes at the head of the list. Ratings are kept as given, one entry per
  rating, so a mean can be taken over any aspect later; nothing is summed in advance.
  """
  @spec rate_value([{atom(), pos_integer()}], integer()) :: [{atom(), pos_integer()}]
  def rate_value(reviews, stars), do: [{:value, clamp(stars, 1, @max_stars)} | reviews]

  @doc """
  The mean rating of the product's value to one decimal place, or `nil` with no rating.

  Only the value ratings count; the other aspects in the list are left out.

  Every rating weighs the same, old or new. A product with a handful of ratings has a
  mean that moves a lot with each one; a page may want to show the count beside it.
  """
  @spec average_value([{atom(), pos_integer()}]) :: float() | nil
  def average_value(reviews) do
    case for {:value, stars} <- reviews, do: stars do
      [] -> nil
      stars -> round_to(Enum.sum(stars) / length(stars), 1)
    end
  end

  @doc """
  Adds a rating of the product's delivery, from 1 to the catalog's top mark.

  A rating outside that range is clamped into it rather than refused: a 0 from a form that
  lost its value is a 1, a 9 from an import is the top mark.

  The new rating goes at the head of the list. Ratings are kept as given, one entry per
  rating, so a mean can be taken over any aspect later; nothing is summed in advance.
  """
  @spec rate_delivery([{atom(), pos_integer()}], integer()) :: [{atom(), pos_integer()}]
  def rate_delivery(reviews, stars), do: [{:delivery, clamp(stars, 1, @max_stars)} | reviews]

  @doc """
  The mean rating of the product's delivery to one decimal place, or `nil` with no rating.

  Only the delivery ratings count; the other aspects in the list are left out.

  Every rating weighs the same, old or new. A product with a handful of ratings has a
  mean that moves a lot with each one; a page may want to show the count beside it.
  """
  @spec average_delivery([{atom(), pos_integer()}]) :: float() | nil
  def average_delivery(reviews) do
    case for {:delivery, stars} <- reviews, do: stars do
      [] -> nil
      stars -> round_to(Enum.sum(stars) / length(stars), 1)
    end
  end

  @doc """
  Adds a rating of the product's packaging, from 1 to the catalog's top mark.

  A rating outside that range is clamped into it rather than refused: a 0 from a form that
  lost its value is a 1, a 9 from an import is the top mark.

  The new rating goes at the head of the list. Ratings are kept as given, one entry per
  rating, so a mean can be taken over any aspect later; nothing is summed in advance.
  """
  @spec rate_packaging([{atom(), pos_integer()}], integer()) :: [{atom(), pos_integer()}]
  def rate_packaging(reviews, stars), do: [{:packaging, clamp(stars, 1, @max_stars)} | reviews]

  @doc """
  The mean rating of the product's packaging to one decimal place, or `nil` with no rating.

  Only the packaging ratings count; the other aspects in the list are left out.

  Every rating weighs the same, old or new. A product with a handful of ratings has a
  mean that moves a lot with each one; a page may want to show the count beside it.
  """
  @spec average_packaging([{atom(), pos_integer()}]) :: float() | nil
  def average_packaging(reviews) do
    case for {:packaging, stars} <- reviews, do: stars do
      [] -> nil
      stars -> round_to(Enum.sum(stars) / length(stars), 1)
    end
  end

  @doc """
  Adds a rating of the product's support, from 1 to the catalog's top mark.

  A rating outside that range is clamped into it rather than refused: a 0 from a form that
  lost its value is a 1, a 9 from an import is the top mark.

  The new rating goes at the head of the list. Ratings are kept as given, one entry per
  rating, so a mean can be taken over any aspect later; nothing is summed in advance.
  """
  @spec rate_support([{atom(), pos_integer()}], integer()) :: [{atom(), pos_integer()}]
  def rate_support(reviews, stars), do: [{:support, clamp(stars, 1, @max_stars)} | reviews]

  @doc """
  The mean rating of the product's support to one decimal place, or `nil` with no rating.

  Only the support ratings count; the other aspects in the list are left out.

  Every rating weighs the same, old or new. A product with a handful of ratings has a
  mean that moves a lot with each one; a page may want to show the count beside it.
  """
  @spec average_support([{atom(), pos_integer()}]) :: float() | nil
  def average_support(reviews) do
    case for {:support, stars} <- reviews, do: stars do
      [] -> nil
      stars -> round_to(Enum.sum(stars) / length(stars), 1)
    end
  end

  @doc """
  Adds a rating of the product's fit, from 1 to the catalog's top mark.

  A rating outside that range is clamped into it rather than refused: a 0 from a form that
  lost its value is a 1, a 9 from an import is the top mark.

  The new rating goes at the head of the list. Ratings are kept as given, one entry per
  rating, so a mean can be taken over any aspect later; nothing is summed in advance.
  """
  @spec rate_fit([{atom(), pos_integer()}], integer()) :: [{atom(), pos_integer()}]
  def rate_fit(reviews, stars), do: [{:fit, clamp(stars, 1, @max_stars)} | reviews]

  @doc """
  The mean rating of the product's fit to one decimal place, or `nil` with no rating.

  Only the fit ratings count; the other aspects in the list are left out.

  Every rating weighs the same, old or new. A product with a handful of ratings has a
  mean that moves a lot with each one; a page may want to show the count beside it.
  """
  @spec average_fit([{atom(), pos_integer()}]) :: float() | nil
  def average_fit(reviews) do
    case for {:fit, stars} <- reviews, do: stars do
      [] -> nil
      stars -> round_to(Enum.sum(stars) / length(stars), 1)
    end
  end

  @doc """
  Adds a rating of the product's durability, from 1 to the catalog's top mark.

  A rating outside that range is clamped into it rather than refused: a 0 from a form that
  lost its value is a 1, a 9 from an import is the top mark.

  The new rating goes at the head of the list. Ratings are kept as given, one entry per
  rating, so a mean can be taken over any aspect later; nothing is summed in advance.
  """
  @spec rate_durability([{atom(), pos_integer()}], integer()) :: [{atom(), pos_integer()}]
  def rate_durability(reviews, stars), do: [{:durability, clamp(stars, 1, @max_stars)} | reviews]

  @doc """
  The mean rating of the product's durability to one decimal place, or `nil` with no rating.

  Only the durability ratings count; the other aspects in the list are left out.

  Every rating weighs the same, old or new. A product with a handful of ratings has a
  mean that moves a lot with each one; a page may want to show the count beside it.
  """
  @spec average_durability([{atom(), pos_integer()}]) :: float() | nil
  def average_durability(reviews) do
    case for {:durability, stars} <- reviews, do: stars do
      [] -> nil
      stars -> round_to(Enum.sum(stars) / length(stars), 1)
    end
  end

  @doc """
  Adds a rating of the product's design, from 1 to the catalog's top mark.

  A rating outside that range is clamped into it rather than refused: a 0 from a form that
  lost its value is a 1, a 9 from an import is the top mark.

  The new rating goes at the head of the list. Ratings are kept as given, one entry per
  rating, so a mean can be taken over any aspect later; nothing is summed in advance.
  """
  @spec rate_design([{atom(), pos_integer()}], integer()) :: [{atom(), pos_integer()}]
  def rate_design(reviews, stars), do: [{:design, clamp(stars, 1, @max_stars)} | reviews]

  @doc """
  The mean rating of the product's design to one decimal place, or `nil` with no rating.

  Only the design ratings count; the other aspects in the list are left out.

  Every rating weighs the same, old or new. A product with a handful of ratings has a
  mean that moves a lot with each one; a page may want to show the count beside it.
  """
  @spec average_design([{atom(), pos_integer()}]) :: float() | nil
  def average_design(reviews) do
    case for {:design, stars} <- reviews, do: stars do
      [] -> nil
      stars -> round_to(Enum.sum(stars) / length(stars), 1)
    end
  end

  @doc """
  Adds a rating of the product's comfort, from 1 to the catalog's top mark.

  A rating outside that range is clamped into it rather than refused: a 0 from a form that
  lost its value is a 1, a 9 from an import is the top mark.

  The new rating goes at the head of the list. Ratings are kept as given, one entry per
  rating, so a mean can be taken over any aspect later; nothing is summed in advance.
  """
  @spec rate_comfort([{atom(), pos_integer()}], integer()) :: [{atom(), pos_integer()}]
  def rate_comfort(reviews, stars), do: [{:comfort, clamp(stars, 1, @max_stars)} | reviews]

  @doc """
  The mean rating of the product's comfort to one decimal place, or `nil` with no rating.

  Only the comfort ratings count; the other aspects in the list are left out.

  Every rating weighs the same, old or new. A product with a handful of ratings has a
  mean that moves a lot with each one; a page may want to show the count beside it.
  """
  @spec average_comfort([{atom(), pos_integer()}]) :: float() | nil
  def average_comfort(reviews) do
    case for {:comfort, stars} <- reviews, do: stars do
      [] -> nil
      stars -> round_to(Enum.sum(stars) / length(stars), 1)
    end
  end

  @doc """
  Adds a rating of the product's accuracy, from 1 to the catalog's top mark.

  A rating outside that range is clamped into it rather than refused: a 0 from a form that
  lost its value is a 1, a 9 from an import is the top mark.

  The new rating goes at the head of the list. Ratings are kept as given, one entry per
  rating, so a mean can be taken over any aspect later; nothing is summed in advance.
  """
  @spec rate_accuracy([{atom(), pos_integer()}], integer()) :: [{atom(), pos_integer()}]
  def rate_accuracy(reviews, stars), do: [{:accuracy, clamp(stars, 1, @max_stars)} | reviews]

  @doc """
  The mean rating of the product's accuracy to one decimal place, or `nil` with no rating.

  Only the accuracy ratings count; the other aspects in the list are left out.

  Every rating weighs the same, old or new. A product with a handful of ratings has a
  mean that moves a lot with each one; a page may want to show the count beside it.
  """
  @spec average_accuracy([{atom(), pos_integer()}]) :: float() | nil
  def average_accuracy(reviews) do
    case for {:accuracy, stars} <- reviews, do: stars do
      [] -> nil
      stars -> round_to(Enum.sum(stars) / length(stars), 1)
    end
  end

  @doc """
  Adds a rating of the product's setup, from 1 to the catalog's top mark.

  A rating outside that range is clamped into it rather than refused: a 0 from a form that
  lost its value is a 1, a 9 from an import is the top mark.

  The new rating goes at the head of the list. Ratings are kept as given, one entry per
  rating, so a mean can be taken over any aspect later; nothing is summed in advance.
  """
  @spec rate_setup([{atom(), pos_integer()}], integer()) :: [{atom(), pos_integer()}]
  def rate_setup(reviews, stars), do: [{:setup, clamp(stars, 1, @max_stars)} | reviews]

  @doc """
  The mean rating of the product's setup to one decimal place, or `nil` with no rating.

  Only the setup ratings count; the other aspects in the list are left out.

  Every rating weighs the same, old or new. A product with a handful of ratings has a
  mean that moves a lot with each one; a page may want to show the count beside it.
  """
  @spec average_setup([{atom(), pos_integer()}]) :: float() | nil
  def average_setup(reviews) do
    case for {:setup, stars} <- reviews, do: stars do
      [] -> nil
      stars -> round_to(Enum.sum(stars) / length(stars), 1)
    end
  end

  @doc """
  Adds a rating of the product's noise, from 1 to the catalog's top mark.

  A rating outside that range is clamped into it rather than refused: a 0 from a form that
  lost its value is a 1, a 9 from an import is the top mark.

  The new rating goes at the head of the list. Ratings are kept as given, one entry per
  rating, so a mean can be taken over any aspect later; nothing is summed in advance.
  """
  @spec rate_noise([{atom(), pos_integer()}], integer()) :: [{atom(), pos_integer()}]
  def rate_noise(reviews, stars), do: [{:noise, clamp(stars, 1, @max_stars)} | reviews]

  @doc """
  The mean rating of the product's noise to one decimal place, or `nil` with no rating.

  Only the noise ratings count; the other aspects in the list are left out.

  Every rating weighs the same, old or new. A product with a handful of ratings has a
  mean that moves a lot with each one; a page may want to show the count beside it.
  """
  @spec average_noise([{atom(), pos_integer()}]) :: float() | nil
  def average_noise(reviews) do
    case for {:noise, stars} <- reviews, do: stars do
      [] -> nil
      stars -> round_to(Enum.sum(stars) / length(stars), 1)
    end
  end

  defp clamp(n, low, high), do: n |> max(low) |> min(high)

  defp round_to(x, places), do: Float.round(x, places)

  # shared by more than one concern
  defp normalize_sku(sku), do: sku |> String.trim() |> String.upcase()

  defp cents(amount) when is_float(amount), do: round(amount)
  defp cents(amount) when is_integer(amount), do: amount
end
