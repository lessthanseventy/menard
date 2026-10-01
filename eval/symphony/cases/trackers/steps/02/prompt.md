Main has moved on since your last ticket: the team merged its own version of it, and other work landed.

**Ticket 2: keep the last good config on a typed-invalid reload**

`WorkflowStore` keeps the last good workflow when a reload fails to parse as YAML. But a file that is valid YAML with a value of the wrong type (say `polling.interval_ms: nope`) is taken as the new current workflow: its prompt replaces the good one, and from then on `Config.settings!/0` raises. A typo in `WORKFLOW.md` should never take down a running service.

- `WorkflowStore` parses the typed settings when it loads a workflow and caches them with it. A reload whose settings do not parse is rejected like a YAML error: the previous workflow, prompt and settings stay current.
- `WorkflowStore.force_reload/0` returns that error, `{:error, {:invalid_workflow_config, message}}`, the message naming the field (e.g. containing `polling.interval_ms`).
- New `WorkflowStore.settings/0` returns `{:ok, %SymphonyElixir.Config.Schema{}}` (the cached settings, after picking up any change on disk as `current/0` does) or `{:error, reason}`. When the store is not running it loads and parses the file at the current workflow path directly; a missing file gives `{:error, {:missing_workflow_file, path, :enoent}}`.
- `Config.settings/0` and `Config.settings!/0` read from the store, so after a bad edit they keep returning the last good values rather than raising.
- `Config.validate!/0` still reports what is on disk: it forces a reload and returns the error, so a typed-invalid file gives `{:error, {:invalid_workflow_config, message}}`.
