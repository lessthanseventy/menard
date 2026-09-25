# TODO

Found and not yet fixed. Fix it, or write it here, never just "noted". Delete a line when its
commit lands.

- [ ] Eval: agents edit `.ex` with `sed -i` or a python heredoc in both arms (Bash is unguarded, by
      design); with menard it happened in 1 of 6 sonnet runs and in haiku's. Count stays in the
      report's "shell edit" column; decide whether the Bash PostToolUse hook should say something.
- [ ] Eval: in the 1,016-line-module case a menard run still `Read` the whole file; nothing steered
      it to `outline`/`find` first, which is where menard should save context.
