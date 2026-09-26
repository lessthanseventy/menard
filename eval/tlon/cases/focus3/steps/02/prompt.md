Next, a feature: a digest of what happened in a workspace lately, for the operator and for agents.

Add `Server.Digest.for_workspace(workspace_id, since)`, `since` a `DateTime`. It answers
`%{threads: threads, facts: facts, tickets_filed: tickets}`, counting only what happened at or after
`since`, in that workspace alone:

- `threads`: every thread of the workspace with at least one message in the window, as
  `%{thread_id: id, title: title, messages: count}` (count = its messages in the window), busiest
  first, a tie going to the lower thread id;
- `facts`: how many facts were banked in the window on the workspace's threads, forgotten ones not
  counted;
- `tickets_filed`: how many tickets were filed in the workspace in the window.

And expose it as an MCP tool named `get_digest`, taking `workspace_id` and `days` (default 7), that
answers the digest of the last `days` days. Test both.
