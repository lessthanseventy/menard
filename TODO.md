# TODO

Found and not yet fixed. Fix it, or write it here, never just "noted". Delete a line when its
commit lands.

- eval/tlon/cases/focus3's planted bug (setup.sh: the fuzzy filter's `score > 0` floor) is caught by
  Tlön's own suite: console/test/console/picker_test.exs:82 ("the palette's corpus finds a verb by
  what it DOES") goes red with the plant and green without (checked 2026-09-26 on the hidden-menard
  template). setup.sh says the plant slips past Tlön's tests; it does not, so both arms start on a
  red test that points at the fault, and step 1 is no misdirection. Re-plant so the project's own
  suite stays green and only the hidden tests catch it, then re-validate the step 1 grader.
- tlon pins menard 0.5.0 from hex (server/mix.lock), and `server/lib/server/source/tools.ex:56`
  hands `Menard.Clause.replace_body/5` whatever its caller gave as `code`. Since 0.5.0 a whole
  clause given there was taken as a `rewrite`; that fallback is removed (2026-09-26, with the
  prose verbs), so on upgrading tlon must send a whole clause to `Menard.Clause.rewrite/5` itself,
  or the call is refused toward `rewrite`. Not edited from here: tlon's change, when it upgrades.
- `indented/2` in lib/menard/block.ex and lib/menard/clause.ex (identical copies) prefixes EVERY line
  of the text with the indent: a blank line inside a block or definition comes out as trailing
  spaces, and the lines of a heredoc or multi-line string inside it are shifted, changing the
  string's value. `Menard.Source.reindent/2` already handles both (blank stays blank, literal lines
  stay put); `indent <> reindent(text, indent)` is the likely fix, with a test for each case. Left
  out of the Menard.Source consolidation because it changes behaviour.
- `bin/menard run check` in a fresh worktree: `BinTest` "a verb reading stdin gets it, even when
  menard compiles first" timed out at 60s. The `bintest` build is cold there (every dep compiles
  inside the test), and a second run was green. Give the cold-build tests a timeout that covers a
  cold worktree, or warm the `bintest` build first.
