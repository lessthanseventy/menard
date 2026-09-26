# TODO

Found and not yet fixed. Fix it, or write it here, never just "noted". Delete a line when its
commit lands.

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
- No verb puts a `@tag` above an existing test (2026-09-26, making two tests `@tag skip:`):
  `block replace` takes no `--tag`, and `stmt insert-before FILE "" "" 'test "…"'` answers "stmt
  insert_before needs name_arity", though `stmt` reaches a module's own statements. It took an Edit.
- `block replace FILE test --label L` with CODE that starts `@tag skip: …` and then the whole
  `test "L" … do … end` put all of it INSIDE the old test's body, a test nested in a test, where a
  CODE starting at `test` replaces the test (2026-09-26). Take a leading `@tag`/`@describetag` as
  the test's own, or refuse it.
- clause_test.exs still holds 39 `=~` assertions on edited source (replace_body/rewrite
  one-liners, the refusal-adjacent checks). The ones where placement or blank lines could hide a
  diff are whole-output `==` now (and found two blank-line bugs); convert the rest as they are
  touched.
- `run check` gives no `skipped` count: `run test` reads it from menard's ExUnit formatter, but
  `check` runs the host's precommit and reads ExUnit's prose (`gate/4` via `counts/1`), which
  drops `N skipped`. A check whose tests all skipped reads like one that ran them.
- hooks/format-report.sh:30 skips a Bash command only when it STARTS with `git`: `cd DIR && git
  worktree add …` (or a checkout after a `cd`) is taken for an edit of every file git wrote, and the
  hook formats each one; in a worktree whose eval fixture has no deps fetched, that was ~45
  "Unknown dependency :phoenix" errors back to the agent (2026-09-26). Matching `git` anywhere is
  wrong too (`git checkout x && sed -i a.ex` is a real edit): skip only files git itself wrote, e.g.
  those whose content matches the index/HEAD after the command.
