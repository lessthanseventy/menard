# TODO

Found and not yet fixed. Fix it, or write it here, never just "noted". Delete a line when its
commit lands.

- [ ] Eval (eval/REPORT.md): with menard, a run spends 2–3 extra round trips before its first edit
      (Skill load, then ToolSearch for the deferred MCP schemas), each re-reading the whole
      context. Pilot, sonnet: ~1.7× the turns and context of no-menard on small tasks, +20% cost.
      Put what a verb needs into the tool descriptions so the skill isn't a prerequisite, and see
      whether the tools can load up front instead of deferred. `alwaysLoad: true` on the server
      (undocumented, works in the CLI, bench 2026-09-25) drops the ToolSearch turn for ~3.7k tokens
      of schemas on every turn: being measured in eval round 2.
- [ ] Eval: agents edit `.ex` with `sed -i` or a python heredoc in both arms (Bash is unguarded, by
      design); with menard it happened in 1 of 6 sonnet runs and in haiku's. Count stays in the
      report's "shell edit" column; decide whether the Bash PostToolUse hook should say something.
- [ ] Eval: in the 1,016-line-module case a menard run still `Read` the whole file; nothing steered
      it to `outline`/`find` first, which is where menard should save context.
- [ ] pi's guard doesn't pass the edit to `menard guard --edit`, so pi still blocks edits that only
      change text inside a string; Claude Code's hook does.
