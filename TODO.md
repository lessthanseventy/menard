# TODO

Found and not yet fixed. Fix it, or write it here, never just "noted". Delete a line when its
commit lands.

- [ ] `plugins` stage: which Styler rule made each change. Styler runs its styles through
      `Styler.style/3`, which is `@doc false`; reaching into it would break across releases.
- [ ] `rename` and `clause move` take no `version`: they write several files.
- [ ] An MCP `block replace` (plugin 0.3.0) ran past Claude Code's 120s once, and never again.
      The door can no longer go silent (every tool answers within its deadline, 90s for edits),
      but what blocked is still unknown. Suspect: this repo's `_build` lock during a compile.
- [ ] Reported by the cleanup agents (plugin 0.3.0), 2026-09-25:
  - [ ] `attr set` put a new attribute between a function's `@doc` and its `def` (console's
        router, route/1); `clause doc` then could not delete that `@doc`, and adding made two.
- [ ] `block add` cannot put a `@tag` above the test it adds (a `@tag :tmp_dir` test needs
      `@moduletag` instead, or a hand edit).
- [ ] A write whose format failed ("not formatted — [Quokka, DoctestFormatter] will not load from
      …/_build in this VM") says so on stderr only; the reply looks clean, so neither the agent
      nor a check notices the file was left unformatted (tlon/server).
- [ ] No verb for a test module's `doctest Mod` line: `directive add FILE doctest Mod`, placed
      after `use` and the aliases, where Quokka puts it.
