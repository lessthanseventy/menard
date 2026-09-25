# Menard as a server: "LiveView for Claude Code, if you squint"

Status: design, not built. Written 2026-09-25 from a conversation with Andrew; open questions at
the bottom.

## The mapping

LiveView's rule is that the client never mutates the DOM. It sends an **event**, the server owns
the **state**, and the server replies with a **diff** plus whatever else the client should know.
Menard is already most of that for source code:

| LiveView | Menard today | missing |
|---|---|---|
| the client never touches the DOM | the `PreToolUse` guard: no `Edit`/`Write` on a module | — |
| event (`phx-click`) | a verb call (`clause replace …`) | — |
| server-side validation | `checked_write`: parse check, identity-safe patches | — |
| `mount` / first render | `outline` | the file's **version** (a hash) |
| the rendered diff | `"written"` | **what actually changed, and who changed it** |
| flash / `push_event` | stderr lines, sometimes | **a structured report from every stage that ran** |
| stale client state | Claude Code's "file changed on disk" notes | **refusing an edit made against a stale version** |
| PubSub | nothing | several sessions share a checkout, and today that goes silently wrong |

The row that matters most is the diff. Today a verb says "written". What the agent needs to hear
is closer to: *your patch was lines 40–44; the formatter reflowed 45; Styler moved your new alias
into the alias block and rewrote `Enum.map |> Enum.into` to `Map.new`; credo flags line 42.* Then
its picture of the file is the file, with no re-read needed.

## The reply: one shape for every verb

```elixir
%{
  did: "replace go/1 `:b` in lib/a.ex",
  version: "sha256:…",   # the file after every stage: pass it back on the next call
  stages: [
    %{stage: :patch,     hunks: [...]},                     # exactly what the verb wrote
    %{stage: :formatter, hunks: [...]},                     # what `mix format` changed after it
    %{stage: :styler,    hunks: [...], rewrites: [...]},    # what Styler rewrote, and which rule
    %{stage: :credo,     issues: [...]}                     # only on the lines this edit touched
  ]
}
```

Each stage runs **separately**, so every change is attributed to whatever made it. Today the
formatter and Styler run as one pass, so their changes can't be told apart. The CLI prints this as
its one JSON line, the MCP door returns it as-is, and a hook can put a one-line summary into the
agent's context.

## Styler inside menard

- **Why:** the host's Styler only loads in menard's VM when both were built on the same OTP (the
  `:badfile` from 2026-09-25). If menard depends on Styler itself, its own build always loads, the
  fallback shell-out becomes rare, and Styler can run as a separate stage whose rewrites menard can
  name.
- **When it applies:** only when the host's `.formatter.exs` lists `Styler`. Menard never forces a
  style onto a project that did not choose it.
- **Version drift:** if the host locks Styler at a different version than menard's (read from the
  host's `mix.lock`), their output can disagree, and the host's `format --check-formatted` gate would
  fail on menard's edits. So menard uses its own Styler only on a version match, and falls back to
  the host's toolchain otherwise.

## Stale state and several sessions

A verb takes an optional `version`. If the file no longer hashes to it, the verb refuses and
replies with the diff since that version, the way LiveView re-syncs a stale client. The hazard is
real: on 2026-09-25 three sessions shared one ficciones checkout, and an edit computed against a
file another session had just rewritten would land somewhere wrong or not at all.

## Phases

1. **The reply.** Every verb returns the structure above, with stages `patch` and `formatter`
   diffed separately. No new dependencies.
2. **Styler as a stage.** Menard depends on Styler, applied on a version match; its rewrites are
   reported per rule.
3. **Versions.** `version` in, `version` out, stale edits refused.
4. **Diagnostics on touched lines.** Credo, and compile warnings, filtered to the lines this edit
   changed.

## Open questions

- Credo in-process has the same OTP problem as Styler. Vendor it too, or run it in the host?
- Does the reply go into the agent's context in full, or as a one-line summary with the full JSON
  a verb away?
- Is `version` required (strict), or optional and advisory?
