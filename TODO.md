# TODO

Found and not yet fixed. Fix it, or write it here, never just "noted". Delete a line when its
commit lands.


- MCP verbs resolve a relative path from `MENARD_ROOT` (where the session started), the CLI from
  the shell's directory. A session started in `~/projects` and working in `~/projects/thatch`
  gets `lib/x.ex` wrong through MCP, and an `edit` with an empty `old` makes the new file in the
  wrong place without a word. The hooks server sees each call's `cwd`; the verbs could follow it.
