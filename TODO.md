# TODO

Found and not yet fixed. Fix it, or write it here, never just "noted". Delete a line when its
commit lands.

- [ ] `plugins` stage: which Styler rule made each change. Styler runs its styles through
      `Styler.style/3`, which is `@doc false`; reaching into it would break across releases.
- [ ] An MCP `block replace` (plugin 0.3.0) ran past Claude Code's 120s once, and never again.
      The door can no longer go silent (every tool answers within its deadline, 90s for edits),
      but what blocked is still unknown. Not the build lock: the same call during a `mix compile
      --force` of this repo answered in 5s (tried 2026-09-25).
- [ ] Eval (eval/REPORT.md): with menard, a run spends 2–3 extra round trips before its first edit
      (Skill load, then ToolSearch for the deferred MCP schemas), each re-reading the whole
      context. Pilot, sonnet: ~1.7× the turns and context of no-menard on small tasks, +20% cost.
      Put what a verb needs into the tool descriptions so the skill isn't a prerequisite, and see
      whether the tools can load up front instead of deferred.
- [ ] Eval: the guard's refusal lists `bin/menard …` CLI lines, so a blocked agent reaches for Bash
      rather than the MCP tools (haiku: CLI in 2 of 3 menard runs, with shell-quoting mistakes, e.g.
      a clause BODY passed as HEAD). Under Claude Code, name the MCP tool and the call to make.
- [ ] Eval: agents edit `.ex` with `sed -i` or a python heredoc in both arms (Bash is unguarded, by
      design); with menard it happened in 1 of 6 sonnet runs and in haiku's. Count stays in the
      report's "shell edit" column; decide whether the Bash PostToolUse hook should say something.
- [ ] Eval: in the 1,016-line-module case a menard run still `Read` the whole file; nothing steered
      it to `outline`/`find` first, which is where menard should save context.
- [ ] `clause replace FILE call/2 …` in a file with several modules is refused listing the modules
      but not the way out: `Mod.Name.call/2` works as the name/arity. Say so in the refusal.
- [ ] `mix menard.block` usage omits `--module` for add, though add refuses "several modules here —
      name one" without it.
