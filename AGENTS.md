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
- A verb's stdout is its answer (for `run`, one JSON line: `ok` and the counts when green, the
  `failures` when red) and stderr is only a refusal or a real error; menard building itself is
  silent unless the build fails. A reply piped through `jq`/`head`/`grep` is refused by the hook:
  it is read whole, and one too big or too noisy to read whole is a menard bug to fix.
- Found a bug and can't fix it now? It goes in `TODO.md`, not a chat message.

**This repo is where menard is dogfooded.** You work under the same hooks every user does: no
python/perl/ruby/node, and menard's replies read whole. Its reading aids (`outline`, `clause get`,
`find`) and its refactoring verbs are there when you want them, not the required path: reads by
grep and sed run. When menard gets in your way, that is the finding, not a detour:

- a refusal that is wrong, or points at a call that answers nothing: fix the refusal;
- a verb you skipped for a workaround (`edit` to delete four functions because `clause delete`
  takes one; a script because nothing moved a test): make the verb fit, so you would have used it;
- a reply you pipe through `cut`/`head`/`python` to read: change the reply;
- a bug a verb wrote into a file: a failing test first, then the fix.

Each as its own small commit, before the change you were making, so the fix is in the build that
the rest of your work runs on. What you can't fix now goes in `TODO.md`.
- Design direction: `docs/scope.md` (what earns a verb), `docs/live.md` (the reply every verb
  should give), `docs/adapters.md` (one core, a thin adapter per harness).
