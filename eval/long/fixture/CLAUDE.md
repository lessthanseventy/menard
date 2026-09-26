# Shop

CI runs `mix precommit` on every push: compile with warnings as errors, unused deps unlocked,
`mix format --check-formatted`, `mix credo`, and the tests. A change that fails any of them is not
merged.
