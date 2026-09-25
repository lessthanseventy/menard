# Working on menard

**Using menard** (which verb for which change, and the traps): `skills/menard/SKILL.md`. It ships
with the plugin as a skill, and it is the one copy of that reference.

**Working on menard itself**, this repo:

- Edit its Elixir with its own verbs, like any other project's. The guard applies here too.
- `bin/menard --frozen VERB …` runs the last build straight off `_build`, with no compile step. A
  half-applied edit (a clause calling a helper the next call adds) stops the project compiling, and
  without `--frozen` the tool locks itself out of finishing its own change.
- The gate is `bin/menard run check`: format, warnings-as-errors, and the tests, including the
  identity corpus (`test/menard/identity_test.exs` over this repo and `test/fixtures/weird.ex`).
- Found a bug and can't fix it now? It goes in `TODO.md`, not a chat message.
- Design direction: `docs/scope.md` (what earns a verb), `docs/live.md` (the reply every verb
  should give), `docs/adapters.md` (one core, a thin adapter per harness).
