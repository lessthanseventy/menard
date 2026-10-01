Main has moved on since your last ticket: the team merged its own version of it, and other work landed.

**Ticket 6: the listener registry in the Notifiers namespace**

Notifier modules live under `Oban.Notifiers`, except the listener registry. Rename `Oban.Notifier.Registry` to `Oban.Notifiers.Listeners` (file `lib/oban/notifiers/listeners.ex`), with the same functions: `register/2`, `unregister/2`, `channels/1`, `listeners/2`. The application starts it under the new name, every caller uses the new name, and nothing is left under the old one. Its tests move with it, to `test/oban/notifiers/listeners_test.exs`, module `Oban.Notifiers.ListenersTest`.
