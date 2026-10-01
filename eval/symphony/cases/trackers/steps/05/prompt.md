Main has moved on since your last ticket: the team merged its own version of it, and other work landed.

**Ticket 5: make terminal workspace cleanup safe**

Two problems when an issue reaches a terminal state:

1. Reconciliation runs the `before_remove` hook and deletes the workspace while the agent is still running in it, and only then stops the worker. Stop the worker first (and let it finish shutting down), then run the hook and remove the workspace.
2. Cleanup recomputes the workspace path from the current config. If `workspace.root` changed in a reload since the run started, it removes the wrong directory, possibly another live workspace, and leaves the real one behind. The orchestrator already records the run's `workspace_path` on running entries, retry entries and blocked entries: when one is recorded, clean up that path; fall back to the identifier-based cleanup only when none is.

The recorded path needs the same safety as a normal removal, but checked against where it was created, not today's root. Add `Workspace.remove_recorded(path, worker_host)`, same return shape as `Workspace.remove/2` (`{:ok, removed}` or `{:error, reason, output}`):

- local (`worker_host` nil): `path` must be absolute; it is validated against its own parent directory the way `remove/2` validates against the workspace root, with the same error tuples. A recorded workspace that is a symlink out of its parent gives `{:error, {:workspace_symlink_escape, path, canonical_parent}, ""}`, and neither the `before_remove` hook nor any deletion runs.
- remote (`worker_host` a string): behaves as `remove/2` on that host.

Use it for terminal cleanup of running, retrying and blocked issues.
