# TODO

Found and not yet fixed. Fix it, or write it here, never just "noted". Delete a line when its
commit lands.

- [ ] docs/live.md, phase 1: every verb replies with per-stage hunks.
- [ ] A cold MCP start (a new pin or a fresh install: clone, deps fetch, compile, ~30s) outlasts
      Claude Code's MCP startup wait, so the server comes up "failed" and its tools are missing
      until a manual reconnect. Seen 2026-09-25 right after ficciones' pin bump. Warm the build
      before anything waits on it (SessionStart hook), or answer `initialize` before compiling.
- [ ] Flake hunting: `run test` drops every flag but `--in` (OptionParser strict), so
      `--repeat-until-failure N` never reaches mix test. Pass unknown flags through, and put the
      `seed` (and the number of runs) in the answer: the seed is how any failure is reproduced.
