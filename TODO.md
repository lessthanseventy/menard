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
- docs/review/2026-09-26-fable.md, Tests, the sites left in files another agent was editing
  (2026-09-26): finding 2 at host_format_test.exs:56 and bin_test.exs:91 (a body inside
  `if mise && installed` is green with zero assertions on a box without them: make it a
  compile-time `@tag skip:`, as run_test/host_mix_test/host_toolchain_test now do); finding 3 at
  mcp_test.exs:318 (a wall-clock bound in an async suite: count work, as diff_test and source_test
  now count reductions); finding 5 (mcp_test.exs:116-120, 241-244, 363-366: three pre-builds and
  11 s of `sleep` to hold stdin open; a Port and `assert_receive` instead); finding 12's
  duplicated comments at mcp_test.exs:227-228 and host_format_test.exs:213-218 (its
  run_test.exs:260-261 site shows no duplicate at this base).
- clause_test.exs still holds 39 `=~` assertions on edited source (replace_body/rewrite
  one-liners, the refusal-adjacent checks). The ones where placement or blank lines could hide a
  diff are whole-output `==` now (and found two blank-line bugs); convert the rest as they are
  touched.
- hooks/format-report.sh skips a shell-written file whose content its repo already holds, which is
  what git writes, except a conflicted merge's (`git merge`, `stash pop`, `rebase`): the markers are
  new content, so the file is formatted and named back as not parsing. The agent knows the merge
  conflicted; skip what `git ls-files -u` lists if that noise shows up.
