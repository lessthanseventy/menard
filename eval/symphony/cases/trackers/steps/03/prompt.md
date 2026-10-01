Main has moved on since your last ticket: the team merged its own version of it, and other work landed.

**Ticket 3: validate the workflow before it takes effect**

The store now refuses workflows whose settings do not parse, but it still accepts ones that parse yet cannot work (a Linear tracker with no project slug), and the orchestrator happily starts scheduling on them. Blank values also slip through as if present.

- The checks `Config.validate!/0` already applies (tracker kind present and supported, Linear api key and project slug present) become part of admitting a workflow into `WorkflowStore`: a workflow that fails them is never cached. `WorkflowStore.force_reload/0` returns the same error those checks produce (e.g. `{:error, :missing_linear_project_slug}`), and the last good workflow, prompt and settings stay current. This holds for the store's startup, its polling, and for `WorkflowStore.settings/0` when the store is not running (that path returns the error too).
- `Config.validate!/0` returns what a forced reload returns.
- A Linear api key or project slug that is empty or only whitespace counts as missing: `{:error, :missing_linear_api_token}` / `{:error, :missing_linear_project_slug}`.
- A `codex.command` of only whitespace is invalid like an empty one: `{:error, {:invalid_workflow_config, message}}` with the message containing `codex.command` and `can't be blank`.
- `Orchestrator` must not start on bad settings: if the settings cannot be read, `init` stops with that reason before any startup cleanup or polling, so `Orchestrator.start_link(name: name)` returns `{:error, reason}` (e.g. `{:error, :missing_linear_project_slug}`). An ordinary restart of the orchestrator after a rejected reload starts fine on the last good settings.

The test suite must still boot with no `LINEAR_API_KEY` set. In the test environment, point the app at a minimal fixture workflow: in `config/config.exs`, for `:test`, set `:symphony_elixir, :workflow_file_path` to `test/fixtures/startup_workflow.md` (expanded to an absolute path), and add that file: front matter with `tracker.kind: memory` and `codex.command: codex app-server`, body `Test workflow.`. Fix any existing tests that relied on an unusable workflow being accepted.
