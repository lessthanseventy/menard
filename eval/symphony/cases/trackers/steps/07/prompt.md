Main has moved on since your last ticket: the team merged its own version of it, and other work landed.

**Ticket 7: retry failed workspace setup, anchor relative roots**

Two workspace bugs.

**A failed `after_create` is never retried.** When `Workspace.create_for_issue` creates a new directory and the `after_create` hook fails, it returns the error (`{:error, {:workspace_hook_failed, "after_create", status, output}}`) but leaves the half-built directory behind. Next attempt the directory exists, so it is not "new", `after_create` is skipped, and the agent runs in a workspace that was never bootstrapped. When the hook fails on a directory this call created, remove that directory (locally, or on the worker host for remote workspaces) and still return the hook's error, so the next call creates it afresh and runs `after_create` again. A workspace that already existed is left alone; a failed cleanup is logged, not raised.

**Relative local roots follow the launcher's cwd.** A relative `workspace.root` such as `relative-workspaces` is resolved against whatever directory Symphony was started from. Resolve a relative local root against the directory of the selected workflow file instead (so `symphony /path/to/WORKFLOW.md` with `root: relative-workspaces` uses `/path/to/relative-workspaces`, wherever you launch from). Everything local that builds or checks paths against the root (workspace creation and removal, the app-server's cwd check) uses the same resolved root. Remote roots stay as written, since they are paths on the worker host.
