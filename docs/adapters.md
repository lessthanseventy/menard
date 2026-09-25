# Harnesses: one core, thin adapters

Status: direction, agreed 2026-09-25. Built so far: `menard guard`, the Claude Code adapter
(.claude-plugin/), and the pi adapter (pi/extension.ts). Both ship from this repo — no host repo
required. `mise run install:pi` and `mise run install:claude` wire them.

## Three layers

| layer | what | harness-specific? |
|---|---|---|
| core | the `Menard.*` library | no: plain Elixir functions |
| transport | `bin/menard` (the CLI) and `menard mcp` (stdio MCP) | no: any PATH, any MCP client |
| enforcement | the guard, the post-write format, the reference an agent reads | the logic isn't; the wiring is |

Everything harness-specific is wiring. The Claude Code plugin is one adapter, not the product.

## The shared pieces every adapter calls

- **The guard is a verb:** `menard guard FILE --edit INPUT` exits 0 to allow, and 2 with the
  reason and the verbs to use instead when FILE is an Elixir module. `INPUT` is the harness's edit
  as JSON (Claude Code's `old_string`/`new_string`, `edits`, `content`; pi's `edits` of
  `oldText`/`newText`), so an edit that only changes text inside a string passes. Claude Code's
  `PreToolUse` hook is then only payload parsing; another harness's pre-edit hook calls the same
  verb.
- **The advice is two scripts:** `hooks/shell-edits.sh` (a module a shell command changed) and
  `hooks/read-hint.sh` (a big module read whole) read Claude Code's hook payload and say their piece
  on stderr with exit 2; `MENARD_TOOL_PREFIX` names the harness's MCP tools. pi feeds them the same
  payload shape.
- **Format after a write:** `menard run format --in DIR FILE`, which already works on a broken host.
- **MCP:** `menard mcp`, with `MENARD_ROOT` set to the project the harness is working in.
- **The reference:** one source, `skills/menard/SKILL.md`. Each harness gets it however it finds
  such things.

## Per harness

| harness | MCP | guard | advice | reference |
|---|---|---|---|---|
| Claude Code | plugin.json `mcpServers`, `alwaysLoad` | `PreToolUse` hook → `menard guard` (hooks/menard-only.sh) | `PreToolUse`/`PostToolUse` hooks | the plugin's skill |
| pi | `mcp.json` mcpServers.menard (`mise run install:pi`) | `tool_call` extension → `menard guard` (pi/extension.ts) | `tool_result` → the same scripts (pi/advice.ts) | the skill, wired by install:pi |
| Cursor, opencode, … | their MCP config | whatever pre-edit hook they have, or none | whatever post-tool hook they have | their rules mechanism |

A harness with no pre-edit hook still gets the MCP verbs and the reference; it just can't enforce
them.

pi loads an extension as a `data:` URL: `import.meta.dir` is that URL there, so paths come from
`import.meta.url`, and a 7 KB file failed to load (`NameTooLong`) where a 4.5 KB one loaded, which is why the
extension is three small files.

## Not portable, deliberately

`prefer-menard-run.sh` (the nudge from a bare `mix test` to `menard run`) matches on Claude Code's
`Bash` tool text. It's advisory, stays Claude Code-only, and no other adapter needs it.
