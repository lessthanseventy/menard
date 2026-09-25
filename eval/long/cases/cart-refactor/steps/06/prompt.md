Last: add a `stock_badge/1` function component to `ShopWeb.CoreComponents` that takes a `product`
attr and renders `<span class="badge">In stock</span>`, or `<span class="badge out">Sold out</span>`
when the product is out of stock. Use it in `product_card/1` in place of the "Out of stock"
paragraph, and update or add tests.
