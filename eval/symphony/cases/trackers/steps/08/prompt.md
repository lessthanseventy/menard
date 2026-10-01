Main has moved on since your last ticket: the team merged its own version of it, and other work landed.

**Ticket 8: block generic tool input; document idle turn timeouts**

**Tool input.** When Codex sends `item/tool/requestUserInput` and Symphony cannot auto-approve it, the app server currently replies with a made-up answer ("This is a non-interactive session…") and lets the turn continue. That fabricates operator input. Instead such a request ends the turn as needing an operator: `AppServer.run` returns `{:error, {:turn_input_required, payload}}`, `payload` being the request (its `"method"` is `"item/tool/requestUserInput"`), the same way other input-required requests already end. Drop the auto-answer path, including its `:tool_input_auto_answered` event and the status dashboard's formatting of it.

Auto-approval stays only for real MCP tool-call approval prompts: a question is one only if its `id` starts with `mcp_tool_call_approval_` (and it offers a recognized approval option, as today). Option labels alone are not enough: a generic question with options `Allow`/`Deny` is blocked, even with `codex.approval_policy: never`. Freeform questions are blocked too.

**Turn timeout.** `codex.turn_timeout_ms` is an idle limit, not a total cap: each update from the app server during a turn resets it, and `{:error, :turn_timeout}` comes only after that long with no update. Make sure the runtime behaves this way (a turn that keeps streaming updates more often than the timeout completes even if it runs longer in total), and say so in `README.md`.
