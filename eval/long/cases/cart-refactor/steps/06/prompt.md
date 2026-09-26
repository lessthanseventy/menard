Last: add an `availability/1` function component to `ShopWeb.CoreComponents` that takes a `product`
attr and renders `<span class="availability">In stock</span>`, or
`<span class="availability out">Sold out</span>` when the product is out of stock. Use it in
`product_card/1` in place of the "Out of stock" paragraph, and update or add tests.
