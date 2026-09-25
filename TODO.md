# TODO

Found and not yet fixed. Fix it, or write it here, never just "noted". Delete a line when its
commit lands.

- [ ] docs/live.md, phase 1: every verb replies with per-stage hunks.
- [ ] A cold MCP start (a new pin or a fresh install: clone, deps fetch, compile, ~30s) outlasts
      Claude Code's MCP startup wait, so the server comes up "failed" and its tools are missing
      until a manual reconnect. Seen 2026-09-25 right after ficciones' pin bump. Warm the build
      before anything waits on it (SessionStart hook), or answer `initialize` before compiling.
- [ ] Formatting a host whose plugins were built by a newer OTP logs `[error] Error loading module
      'Elixir.Styler': corrupt atom table` on every call: menard handles it (falls back to the host's
      toolchain) but the VM logs the failed load first. Check a beam's compiler version before loading.
- [ ] `deps add|upgrade` (docs/scope.md): patch the deps list in mix.exs by range, fetch, answer with
      the lock diff and the compile result. Upgrade also runs the host's own `mix igniter.upgrade` when
      the host already has Igniter; its `<pkg>.upgrade` tasks need Igniter and the host. Do not depend
      on Igniter (it re-renders whole files and needs the host loaded; 2026-09-25 evaluation).
