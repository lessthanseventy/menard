In test/shop/mailer_test.exs, add a `describe "receipt file"` block with one test tagged
`@tag :tmp_dir` that writes `Shop.Mailer.receipt("Ada", "o1", 1320)` to a file in the test's tmp
dir, reads it back, and asserts it contains "Total: $13.20". (That assertion fails today because
of a bug in the mailer; fix the bug too.)
