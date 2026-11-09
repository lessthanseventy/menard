Rename the module `Acme.Billing` to `Acme.Invoicing` across the project: its `defmodule`, with the
nested `Acme.Billing.Error` becoming `Acme.Invoicing.Error`, and every alias, import, struct,
typespec and call that refers to it, in lib and test. Move its file to `lib/acme/invoicing.ex` and
its test to `test/acme/invoicing_test.exs`.

Only that module is renamed. `Acme.BillingAddress` and `Acme.Reports.Billing` are other modules
and keep their names. Stored event rows name their source by the string `"Acme.Billing"`, so that
string stays as it is wherever it appears.

The project must compile with `--warnings-as-errors`, be formatted, and its tests pass.
