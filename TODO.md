# TODO

Found and not yet fixed. Fix it, or write it here, never just "noted". Delete a line when its
commit lands.

- `rename` of a module named in a multi-alias whose base the new name does not share
  (`alias Acme.{Billing, X}`, renamed to `Shop.Invoicing`) writes `alias Acme.{Invoicing, X}`: the
  entry has to leave the braces for its own `alias Shop.Invoicing`. Found building eval/ast.
- `rename` decides whether `alias Old` binds the bare `Last` per file, not per module: a file of two
  modules, one with `alias Acme.Billing` and one with `alias Acme.Reports.Billing`, has the second
  one's `Billing.x` calls renamed too.
