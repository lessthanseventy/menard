# TODO

Found and not yet fixed. Fix it, or write it here, never just "noted". Delete a line when its
commit lands.

- [ ] docs/live.md, phase 1: every verb replies with per-stage hunks.
- [ ] `deps add|upgrade` (docs/scope.md): patch the deps list in mix.exs by range, fetch, answer with
      the lock diff and the compile result. Upgrade also runs the host's own `mix igniter.upgrade` when
      the host already has Igniter; its `<pkg>.upgrade` tasks need Igniter and the host. Do not depend
      on Igniter (it re-renders whole files and needs the host loaded; 2026-09-25 evaluation).
