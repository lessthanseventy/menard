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
- [ ] Reported by the cleanup agents (plugin 0.3.0), 2026-09-25:
  - [ ] `stmt` MATCH must be the statement's whole text; a leading fragment (`elixir_files =`)
        misses, though the skill says "by what is WRITTEN".
  - [ ] `stmt` cannot reach the steps of a `with` that has an `else`: `list` shows the whole `with`
        (Console.Staffing.spawn_center/2).
  - [ ] `block replace` doubles a leading comment the new body repeats; a second replace does not
        clear it.
  - [ ] `attr set` put a new attribute between a function's `@doc` and its `def` (console's
        router, route/1); `clause doc` then could not delete that `@doc`, and adding made two.
- [ ] `block add` cannot put a `@tag` above the test it adds (a `@tag :tmp_dir` test needs
      `@moduletag` instead, or a hand edit).
