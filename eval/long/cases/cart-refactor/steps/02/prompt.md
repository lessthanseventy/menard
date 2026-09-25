Next: change `Shop.Cart.total/1` into `Shop.Cart.total/2`, taking the tax rate as a required second
argument, and pass it on to the price calculation. Update every caller; where a caller has no rate
of its own, use `Shop.Catalog.tax_rate()`. The tests must still pass.
