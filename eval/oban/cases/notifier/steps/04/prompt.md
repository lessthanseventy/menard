Main has moved on since your last ticket: the team merged its own version of it, and other work landed.

**Ticket 4: plugin stop events when a run fails**

When a plugin run fails (the database is unavailable, say) it emits `[:oban, :plugin, :stop]` with `:error` in the metadata but without the plugin's usual keys. Handlers that match on those keys crash, and telemetry detaches them; that includes Oban's default logger, so one bad run silences all Oban logging on the node until restart.

- A failed run's `:stop` metadata carries every key a successful one does, empty or zeroed, plus `:error`:
  - `Oban.Stager`: `staged_count: 0`, `staged_jobs: []`
  - `Oban.Pruner`: `pruned_count: 0`, `pruned_jobs: []`
  - `Oban.Lifeline`: `rescued_jobs: []`, `discarded_jobs: []`
  - `Oban.Cron`: `jobs: []`
- `:error` is the error itself, not an `{:error, reason}` tuple. For `Oban.Reindexer`, whose failure is the list of the indexes that failed, `:error` is that list.
- The default logger (`Oban.Telemetry.attach_default_logger/1`) adds an `"error"` field to a `plugin:stop` log entry when the metadata has `:error`, alongside the plugin's own fields: the error formatted as Elixir prints a raised error's banner, e.g. `"** (RuntimeError) something went wrong"`. Without `:error` the entry is unchanged.

Document `:error` in `Oban.Telemetry`'s plugin events and logger output, and the failed-run metadata in each plugin's docs.
