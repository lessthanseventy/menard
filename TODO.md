# TODO

Found and not yet fixed. Fix it, or write it here, never just "noted". Delete a line when its
commit lands.

- [ ] The installed plugin is a 2026-09-10 snapshot (`menard@ficciones` 0.1.0, hooks run under
      `sh`). The version never changed, so Claude Code never updated it. Bump the version on each
      release, and reinstall from menard's own marketplace.
- [ ] ficciones pins menard at e54b1d6; bump it to the current `main` once pushed.
- [ ] docs/live.md, phase 1: every verb replies with per-stage hunks.
- [ ] ficciones' `mise run menard` runs the LIVE ~/projects/menard checkout, so editing menard
      breaks other sessions' verbs mid-edit (seen 2026-09-25: they held its build lock). Run a
      pinned copy instead: a worktree at the ref the server's mix.lock pins, so the CLI and the
      library are one version, and it stays independent of the host's deps.
