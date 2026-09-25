# TODO

Found and not yet fixed. Fix it, or write it here, never just "noted". Delete a line when its
commit lands.

- [ ] docs/live.md, phase 1: every verb replies with per-stage hunks.
- [ ] Install is one step only for the verbs and hooks. The plugin should also declare the MCP
      server itself (`mcpServers` in plugin.json, `${CLAUDE_PLUGIN_ROOT}/bin/menard mcp`) instead
      of a hand-run `claude mcp add` with a version-stamped cache path.
- [ ] The plugin should ship the verb reference as a skill (`skills/menard/SKILL.md` from
      AGENTS.md), so an agent in a repo that never mentions menard still learns when to use which
      verb, not only from the guard's deny message.
- [ ] menard pins no toolchain of its own: bin/menard runs whatever `mix` is on PATH. On a machine
      whose default Elixir is < 1.18 it doesn't start, and two toolchains alternating rebuild its
      `_build` from scratch (seen 2026-09-25). Pin it (mise.toml / .tool-versions) and have
      bin/menard run under it.
