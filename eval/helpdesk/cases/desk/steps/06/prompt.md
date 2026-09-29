**Ticket 6: the desk in the browser**

Three LiveView pages, no login. The acceptance suite drives them with `Phoenix.LiveViewTest` by
the ids below.

`/tickets` (the list):

- each ticket is an element `#ticket-<id>` holding its subject and its status, in
  `list_tickets/1`'s order
- a form `#filters` with a select named `status` (an empty value for all, else a status); changing
  it narrows the list
- a link to `/tickets/new`

`/tickets/new`:

- a form `#ticket-form` with fields `ticket[subject]`, `ticket[body]`, `ticket[requester_email]`
  and `ticket[priority]`; submitting it creates the ticket and navigates to its page; invalid, it
  stays and shows the errors

`/tickets/:id` (one ticket):

- `#ticket-status` holds the status; `#assignee` the assignee's name, or `Unassigned`
- a button `#transition-<status>` for each status the ticket may move to, and for no other;
  clicking it makes the move
- a button `#auto-assign`, which assigns the ticket with `auto_assign/1`
- `#comments` holds the comments, each an element `#comment-<id>` with its body, oldest first,
  internal notes included
- a form `#comment-form` with `comment[body]`, a select `comment[agent_id]` of the active agents,
  and a checkbox `comment[internal]`; submitting it adds the agent's comment, and the page shows
  the ticket as the comment left it
