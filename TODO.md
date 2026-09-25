# TODO

Found and not yet fixed. Fix it, or write it here, never just "noted". Delete a line when its
commit lands.

- [ ] `clause insert-after` with code for a DIFFERENT function, anchored on a multi-clause
      function's first clause, lands between its clauses. That splits the function, which fails
      under warnings-as-errors. It should go after the function's last clause.
- [ ] `hooks/format-elixir.sh` still runs the host's bare `mix format`: wrong toolchain, fails on
      unresolved deps. Route it through menard's formatter.
- [ ] The installed plugin is a 2026-09-10 snapshot (`menard@ficciones` 0.1.0, hooks run under
      `sh`). The version never changed, so Claude Code never updated it. Bump the version on each
      release, and reinstall from menard's own marketplace.
- [ ] ficciones pins menard at e54b1d6; bump it to the current `main` once pushed.
- [ ] History narration in comments ("used to…", "the first week of real use"), and
      `gaps_test.exs` / `verbs_gaps_test.exs` named after history instead of their subject.
- [ ] README tells people to install the library from hex. Hold off publishing: the mix tasks would
      run inside the host project, and `anubis_mcp` becomes everyone's runtime dependency.
- [ ] CHANGELOG `Unreleased` covers only the verb cut; add this session's fixes.
- [ ] docs/live.md, phase 1: every verb replies with per-stage hunks.
