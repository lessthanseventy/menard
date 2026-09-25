# TODO

Found and not yet fixed. Fix it, or write it here, never just "noted". Delete a line when its
commit lands.

- [ ] `plugins` stage: which Styler rule made each change. Styler runs its styles through
      `Styler.style/3`, which is `@doc false`; reaching into it would break across releases.
- [ ] `rename` and `clause move` take no `version`: they write several files.
- [ ] An MCP `block replace` (plugin 0.3.0) ran past Claude Code's 120s once, and never again.
      The door can no longer go silent (every tool answers within its deadline, 90s for edits),
      but what blocked is still unknown. Suspect: this repo's `_build` lock during a compile.
- [ ] `clause replace` keeps the comment above the old body's first statement; a new BODY that
      starts with that same comment leaves it in the file twice (plugin 0.3.0, seen on
      ex_compact's `lib/ex_compact/client.ex`). Unreproduced here.
- [ ] No verb edits a function's `@spec`: `attr` refuses it (it repeats per clause) and the clause
      verbs carry it without changing it, so a changed signature's spec needs `write` or
      `module replace`. Wants `clause spec FILE name/arity [SPEC]`, the twin of `clause doc`.
