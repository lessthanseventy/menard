In `Shop.Orders`, `open?/1` lists the open statuses inline. Add a module attribute
`@open_statuses`, derived from `@statuses` (every status except :delivered, :cancelled and
:refunded), and use it in `open?/1`.
