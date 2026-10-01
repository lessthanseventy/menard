Main has moved on since your last ticket: the team merged its own version of it, and other work landed.

**Ticket 2: per-entry timezones in the crontab**

Every crontab entry is evaluated in the one `:timezone` given to `Oban.Cron`, so an app with schedules in two zones needs two Cron instances. Let an entry override it with a `:timezone` option:

```elixir
crontab: [{"0 9 * * *", MyApp.LocalWorker, timezone: "America/Chicago"}]
```

- An entry with `:timezone` is matched against the current time in that zone; entries without it use the plugin's `:timezone` (default `"Etc/UTC"`), as now.
- The job's `meta["cron_tz"]` is the zone the entry was evaluated in (the entry's own, or the plugin's).
- `:timezone` is a cron option, not a job option: it must not reach the job changeset.
- `Oban.Cron.validate/1` checks an entry's `:timezone` the way it checks the plugin's: an unknown zone (e.g. `"america/chicago"`, wrong case) is `{:error, message}` with the same message the plugin-level option gives, `expected :timezone to be a known timezone, got: "america/chicago"`.

Document the option in `Oban.Cron` and the periodic jobs guide.
