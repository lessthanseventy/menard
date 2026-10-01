Main has moved on since your last ticket: the team merged its own version of it, and other work landed.

**Ticket 5: listeners that survive a notifier crash**

Each notifier tracks its listeners in its own process state, so when the notifier crashes every registration is lost, and `Oban.Queues` and `Oban.Sonar` carry monitor-and-resubscribe code to cope. Keep registrations somewhere that outlives the notifier instead.

- New module `Oban.Notifier.Registry`, an Elixir `Registry` started by the Oban application (`Oban.Application`), keyed per Oban instance and channel. Its functions take an `%Oban.Config{}`:
  - `register(conf, channel)` and `unregister(conf, channel)`, for the calling process, returning `:ok`. Registering a channel twice records one listener.
  - `listeners(conf, channel)`: the pids listening on that channel of that instance.
  - `channels(conf)`: the channels with at least one listener on that instance.
  A listener that exits is dropped from the registry with no work from anyone.
- `Oban.Notifier.listen/2` and `unlisten/2` record the registration there, then tell the notifier. `listen/2` returns `:ok` even when the notifier is down or restarting: the registration stands and the notifier picks it up when it comes back.
- Every notifier delivers to the listeners in the registry. Isolated and PG drop their own listener tracking. Postgres `LISTEN`s, on every connect including a reconnect after a crash, on all channels that have registered listeners, and `UNLISTEN`s a channel only once no listener is left on it.
- A process that listened before a notifier crash gets notifications after the restart without listening again. The resubscribe code in `Oban.Queues` and the re-listen on each ping in `Oban.Sonar` can go.
- `Oban.Notifier.relay/4`, which takes an explicit list of pids, stays for external notifiers that track their own listeners.
