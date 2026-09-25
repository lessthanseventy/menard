The cart page crashes with a MatchError in `Shop.Cart.lines/1` when a cart still holds a sku that
has since been removed from the catalog. Such items should be skipped (so `total/1` ignores them
too). Fix it and add a test.
