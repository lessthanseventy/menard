**Ticket 9: `Desk.Tickets` has grown**

Everything about tickets lives in one module now. Split it into modules under
`lib/desk/tickets/`, by what each part is about, so that `Desk.Tickets` is what ties them
together. Every public function of `Desk.Tickets` stays callable as it is, with the same arities
and returns: callers do not change. Nothing else about the app's behaviour changes.
