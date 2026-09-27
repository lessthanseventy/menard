# TODO

Found and not yet fixed. Fix it, or write it here, never just "noted". Delete a line when its
commit lands.
- The stop gate never sees what manos' MCP tools write: its touched list is kept by the format hook
  (Edit/Write/Bash), and an MCP write goes through none of them. riverside2 events.all.fable.3 step 1
  changed code with `clause replace`, `block add` and `directive add` and the gate said "nothing written
  this session". Record the project a menard write lands in (the verb layer, or a PostToolUse hook on
  the MCP tools' names) so the gate checks it.
