# TODO

Found and not yet fixed. Fix it, or write it here, never just "noted". Delete a line when its
commit lands.

- [ ] `plugins` stage: which Styler rule made each change. Styler runs its styles through
      `Styler.style/3`, which is `@doc false`; reaching into it would break across releases.
- [ ] An MCP `block replace` (plugin 0.3.0) ran past Claude Code's 120s once, and never again.
      The door can no longer go silent (every tool answers within its deadline, 90s for edits),
      but what blocked is still unknown. Not the build lock: the same call during a `mix compile
      --force` of this repo answered in 5s (tried 2026-09-25).
