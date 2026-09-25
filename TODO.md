# TODO

Found and not yet fixed. Fix it, or write it here, never just "noted". Delete a line when its
commit lands.

- [ ] `plugins` stage: which Styler rule made each change. Styler runs its styles through
      `Styler.style/3`, which is `@doc false`; reaching into it would break across releases.
- [ ] `rename` and `clause move` take no `version`: they write several files.
- [ ] An MCP `block replace` (plugin 0.3.0, on test/menard/diff_test.exs) ran past Claude Code's
      120s while `bin/menard` was compiling this repo; the same call replayed later answered in
      seconds. Suspect waiting on this repo's `_build` lock (the formatter loads host plugins from
      it). Unconfirmed; a verb waiting on a lock should say so, not go silent.
