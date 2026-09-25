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
    %{stage: :plugins,   plugins: ["Styler"], hunks: [...]}, # what the host's plugins rewrote after it
    %{stage: :credo,     issues: [...]}                     # only on the lines this edit touched
  ]
}
```

Each stage runs **separately**, so every change is attributed to whatever made it. Today the
formatter and Styler run as one pass, so their changes can't be told apart. The CLI prints this as
its one JSON line, the MCP door returns it as-is, and a hook can put a one-line summary into the
agent's context.

## Styler as a stage

Built without a Styler dependency. The first plan had menard carry its own Styler, so it would
always load, and use it on a version match with the host's `mix.lock`. Two things argued against:
the projects here lock Styler anywhere from 0.8 to 1.12, so a match would be rare, and menard's copy
would sit first on the code path and shadow the host's own. Instead the split uses the host's
plugins, whatever they are:

- `:formatter` is Elixir's formatter alone, with the host's options (its `import_deps` included).
- `:plugins` is what the host's plugins (Styler, the HEEx formatter) changed after that, and names
  them. Named `plugins` rather than `styler`, since there can be several and their changes cannot
  be told apart.
- What menard writes is always the host's full formatter output, as before, so the host's
  `format --check-formatted` agrees by construction.
- On the shell fallback (a plugin that will not load in menard's VM), `mix format` runs everything
  in one pass and there is one `:formatter` stage, as in phase 1.

Open: which Styler *rule* made each change. Styler runs its styles through `Styler.style/3`, which is
`@doc false`, and reaching into it would break with Styler releases.

Why keep Styler in the host at all: it rewrites whole files. Taken out of the host, the files drift
from its style, and then a one-line edit restyles the whole file. Kept there, the code stays
styled, and the `:plugins` stage of an edit is small and local.

## Stale state and several sessions

A verb takes an optional `version`. If the file no longer hashes to it, the verb refuses and
replies with the diff since that version, the way LiveView re-syncs a stale client. The hazard is
real: on 2026-09-25 three sessions shared one ficciones checkout, and an edit computed against a
file another session had just rewritten would land somewhere wrong or not at all.

## Phases

1. **The reply.** Every verb returns the structure above, with stages `patch` and `formatter`
   diffed separately. No new dependencies.
2. **Styler as a stage.** The host's plugins run as their own `:plugins` stage, apart from the
   formatter (built; see above).
3. **Versions.** `version` in, `version` out, stale edits refused.
4. **Diagnostics on touched lines.** Credo, and compile warnings, filtered to the lines this edit
   changed.

## Open questions — resolved

- **Credo in-process has the same OTP problem as Styler.** Run it in the host. `mix credo
  lib/file.ex` and `mix compile --warnings-as-errors` via `Menard.host_mix/3`, the same fallback
  pattern the formatter uses. Parse the output, filter to the lines the edit touched. No new
  deps, no OTP compatibility headache. ex_check was considered and rejected: it's a whole-project
  CI gate orchestrator (credo + dialyxir + doctor + sobelow + mix_audit + formatter + compiler +
  ex_unit in parallel), the wrong scope for per-edit, line-filtered diagnostics that run after
  every verb call.
- **Does the reply go into the agent's context in full?** Yes — the MCP tool result IS the
  reply, and that's the agent's context. The CLI prints one JSON line. A hook (Claude Code
  PostToolUse, pi tool_result) can extract `did` for a toast/status, but the model already sees
  the full structure. No separate "one-line summary" channel needed.
- **Is `version` required, and does a mismatch warn or refuse?** Optional, and a mismatch
  refuses (phase 3). A warning arrives after the edit has already overwritten the other session's
  change; a refusal costs one round trip, and carries the diff since the version the agent had.
  `--force` writes anyway. The check is on the whole file for now; menard addresses by name, so it
  could narrow to "refuse only when what changed overlaps what this edit touches" if unrelated
  edits cause too many refusals.

## Implementation plan

### What changes concretely

`Menard.checked_write/2` today: parse-check → `File.write!` → `format(file)` (in-place) → `:ok`.

It becomes `Menard.write/3` (the old name stays as a thin wrapper for callers that don't care
about the reply yet): read the original → keep the patched content → format in-memory (not
on-disk) → diff the three versions → write the formatted result → return `{:ok, reply}`.

The three versions are already in hand — no new I/O:

```
original   File.read!(file) in the verb task (before the edit)
patched    the `out` argument to checked_write (the verb's Sourceror patch)
formatted  formatter.(content) in in_process/2 — already computed, just not returned
```

### Phase 1: the reply (no new deps)

1. **`Menard.Diff`** — a line-level diff, ~50 lines of Myers. Returns hunks as
   `%{start: line, removed: [lines], added: [lines]}`. No deps; the algorithm is small and the
   hunks don't need to be minimal, just informative. For the `:patch` stage, prefer the
   Sourceror patch range (menard already knows which bytes it changed) — the line diff is the
   fallback for verbs that don't carry a range.

2. **`Menard.write/3`** — the staged pipeline:
   - parse-check (`Menard.Write.checked`)
   - format in-memory: `in_process/2` returns `{:ok, formatted}` instead of writing the file
   - diff `original → patched` = `:patch` hunks
   - diff `patched → formatted` = `:formatter` hunks (Styler included; phase 2 splits it out)
   - `File.write!(file, formatted)`
   - `version: sha256(formatted)`
   - return `{:ok, %{did, version, stages: [%{stage: :patch, hunks}, %{stage: :formatter, hunks}]}}`

3. **`did`** — a human-readable one-liner built from the verb + its args. Each verb task passes
   a `did:` string to `write/3`: `"replace go/1 `:b` in lib/a.ex"`.

4. **The CLI tasks** — print `JSON.encode!(reply)` instead of `"menard.clause: #{file} written"`.
   One line, the same shape the MCP door returns. The `--frozen` verbs and read-only verbs
   (`outline`, `find`, `deps`, `run`) are unchanged — they already answer in one line.

5. **The MCP door** — `ok(frame, reply)` instead of `ok(frame, %{"did" => ..., "file" => ...})`.
   The reply IS the tool result. Claude Code, pi, and opencode all see it the same way — it's
   just the MCP tool's return value, harness-agnostic.

6. **`rename`** — multi-file: the reply carries `stages` per file, or a list of per-file replies.
   The `:patch` hunks for a rename are the Sourceror ranges rename already patches.

### Phase 2: Styler as a stage

Built as described under "Styler as a stage" above.

### Phase 3: versions

1. **`version` parameter** — optional on every writing verb (CLI `--version SHA`, MCP `version`
   field). `sha256` of the file content after the last stage.

2. **Stale check.** Before the edit, hash the file on disk. If `version` is given and doesn't
   match, reply with `{:stale, %{version: current, diff: hunks(original, disk)}}` — the diff
   since the version the agent had, so it can re-sync. The edit does not run.

3. **Advisory.** A mismatch refuses by default (the safe choice — a stale edit can land wrong).
   `--force` overrides. Later: a project config for strict vs advisory.

### Phase 4: diagnostics on touched lines

1. **`mix compile`** via `Menard.host_mix/3` — already what `run compile` does. Parse warnings,
   filter to the file and line range the edit touched.

2. **`mix credo lib/file.ex`** via `Menard.host_mix/3` — parse issues, filter to touched lines.
   Only when the host has credo (`.credo.exs` or credo in its deps).

3. **The `:diagnostics` stage** — `%{stage: :diagnostics, issues: [%{line, severity, message,
   tool}]}`. Only on writing verbs. Filtered to the lines the `:patch` stage touched, so a
   pre-existing warning on line 10 doesn't surface when the edit was on line 40.

4. **Timeout.** Same `@format_timeout` pattern — diagnostics that don't finish in N seconds are
   dropped (the edit already landed; diagnostics are advisory, not a gate).

### Harness delivery

The reply is harness-agnostic — one JSON shape, three doors:

| harness | how the reply reaches the agent | guard |
|---|---|---|
| Claude Code | MCP tool result (the model sees it directly) | PreToolUse hook (menard-only.sh) |
| pi | MCP tool result (the model sees it directly) | tool_call extension (pi/extension.ts) |
| opencode | MCP tool result (any MCP client) | its pre-edit hook, or none |

No per-harness work for the reply itself — it's the MCP return value. The guard and the
format-on-save are the per-harness pieces (already built for Claude Code and pi). opencode gets
the MCP verbs and the reply for free; it just can't enforce the guard without its own hook.

A hook can extract `did` for a toast/status line, but the model already has the full reply in
its context via the tool result.

### What phase 1 does NOT do

- No Styler separation (formatter + Styler are one `:formatter` stage).
- No version/stale detection.
- No diagnostics.
- No new deps.

Phase 1 is: every writing verb returns `%{did, version, stages: [:patch, :formatter]}` instead
of `"written"`. The agent's picture of the file is the file, with no re-read needed — that's
the row that matters most, and it needs nothing new.
