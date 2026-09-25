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
- [ ] `attr delete` of an attribute that had a blank line after it and none before keeps the
      blank: deleting one set between a `@doc` and a `@spec` left them a blank line apart.
