# Harnesses: one core, thin adapters

Status: direction, agreed 2026-09-25. Built so far: `menard guard`, the Claude Code adapter
declaring the MCP server and shipping the reference as a skill.

## Three layers

| layer | what | harness-specific? |
|---|---|---|
| core | the `Menard.*` library | no: plain Elixir functions |
| transport | `bin/menard` (the CLI) and `menard mcp` (stdio MCP) | no: any PATH, any MCP client |
| enforcement | the guard, the post-write format, the reference an agent reads | the logic isn't; the wiring is |

Everything harness-specific is wiring. The Claude Code plugin is one adapter, not the product.

## The shared pieces every adapter calls

- **The guard is a verb:** `menard guard FILE` exits 0 to allow, and 2 with the reason and the
  verbs to use instead when FILE is an Elixir module. Claude Code's `PreToolUse` hook is then only
  payload parsing: read `tool_input.file_path`, call the verb. Another harness's pre-edit hook calls
  the same verb.
- **Format after a write:** `menard run format --in DIR FILE`, which already works on a broken host.
- **MCP:** `menard mcp`, with `MENARD_ROOT` set to the project the harness is working in.
- **The reference:** one source, `skills/menard/SKILL.md`. Each harness gets it however it finds
  such things.

## Per harness

| harness | MCP | guard | reference |
|---|---|---|---|
| Claude Code | plugin.json `mcpServers` | `PreToolUse` → `menard guard` | the plugin's skill |
| pi | its MCP server config | its pre-edit hook → `menard guard` | pi reads the HOST repo's AGENTS.md, not menard's, so this needs its own delivery (a pi skill or extension); menard never writes into the host |
| Cursor, opencode, … | their MCP config | whatever pre-edit hook they have, or none | their rules mechanism |

A harness with no pre-edit hook still gets the MCP verbs and the reference; it just can't enforce
them.

## Not portable, deliberately

`prefer-menard-run.sh` (the nudge from a bare `mix test` to `menard run`) matches on Claude Code's
`Bash` tool text. It's advisory, stays Claude Code-only, and no other adapter needs it.
