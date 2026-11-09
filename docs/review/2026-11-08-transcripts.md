# Transcript review, 2026-11-08: three weeks with the hook in every project

Mined: the 2,761 Claude Code transcripts on this machine, 2026-10-09 to 11-08 (77,032 tool calls
with their results and timestamps; 3,642 menard calls). Claude Code deletes a transcript after 30
days (`cleanupPeriodDays`), so 09-25 to 10-08, which the 10-19 review read, is gone: section 3.
Counts are regexes over commands and replies, ±5%. Four fixes landed with this review (section 2).

Since 2026-10-20, when the plugin went to user scope: 1,979 sessions, 581 of them called menard;
3,512 CLI calls and 130 MCP calls; 8.4 Gtok in (nearly all cache reads), 49 Mtok out.

## 1. Is it helping

**What is used.** CLI calls since 10-20, by verb: `edit` 1,545 (671 `.ex`, 582 `.exs`, 169 `.ts`,
88 `.sh`, 79 `.md`, 43 `.nix`), `run test` 1,159, `run check` 306, `clause get` 141, `outline` 60,
`run format` 44, `find` 20. The AST verbs: `block move` 6, `clause replace` 4, `block add` 3,
`write` 2; `rename`, `clause move`, `split`, `stmt`, `attr`, `directive`, `module`: 0. Fifteen
calls in three weeks against three thousand. menard in practice is `edit`, `run`, the hooks, and a
little reading.

**The hooks do what they were for.** Scripts in another language, per 100 shell calls: opus 7.9
and sonnet 11.7 in the bare arm, 0.0 and 1.1 hooked (34 attempts since 10-20, every one refused).
Of 335 filter refusals, the next call was the same command bare 244 times; since 0.8.3 (11-07) the
filter is dropped and the command run, no call lost. Of 989 green `edit` replies, 166 carry a
formatter or plugins stage: for `.ex`/`.exs`, 149 of 639, so about one Elixir edit in four left the
file unformatted and was fixed on the way in. That is the always-on value, and it is real.

**Tokens per landed commit say nothing either way.** `eval/pile/report.sh`, 2026-11-08:

| arm | model | sessions | commits | Mtok / commit | kout / commit | bash / commit | py / 100 bash |
|---|---|---|---|---|---|---|---|
| bare | opus 5.5 | 14 | 582 | 13.2 | 23.6 | 13.4 | 7.9 |
| hooked | opus 5.5 | 296 | 258 | 11.7 | 56.1 | 29.7 | 0.0 |
| bare | sonnet 5.5 | 359 | 195 | 6.2 | 26.8 | 19.0 | 11.7 |
| hooked | sonnet 5.5 | 193 | 76 | 7.1 | 29.3 | 17.4 | 1.1 |

The arms differ in shape more than in menard: bare opus is 14 marathon sessions averaging 41
commits each, hooked opus is 296 coworker seats averaging one. Output per commit doubled hooked,
and shell calls per commit too, which is the edits moving from `Edit` into `menard edit` through
Bash. Read it as parity, as the 10-01 evals did. Nothing in the pile shows a token win.

**Wall time is where it hurts.** From each `tool_use` to the message carrying its result, since
10-20 (hook time included, so a native `Edit` here includes the format hook):

| call | n | p50 s | p90 s | hours waited |
|---|---|---|---|---|
| `menard edit` (CLI) | 972 | 25 | 176 | 18.0 |
| `menard edit --then test` | 269 | 41 | 172 | 5.7 |
| `menard edit --then compile` | 120 | 29 | 135 | 1.7 |
| `menard run test` | 966 | 31 | 100 | 13.3 |
| `menard run check` | 287 | 127 | 602 | 18.6 |
| `clause get` / `outline` | 111 | 11 | 135 | 1.1 |
| native `Edit` on `.ex`/`.exs` | 362 | 1 | 5 | 0.3 |
| MCP `edit` | 49 | 1 | 121 | 0.3 |
| MCP `run` | 60 | 4 | 120 | 0.4 |
| `mix test` through Bash | 120 | 22 | 421 | 3.8 |

Sixty hours of waiting on menard in three weeks, 25 of them on edits. In tlon alone: CLI `edit`
24 s at the median over 584 calls, MCP `edit` 1 s over 43, native `Edit` 1 s. The same verb, the
same repo, the same weeks. Idle, the CLI is cheap (`--frozen version` 0.5 s, a frozen `edit` of
this repo 1.4-1.9 s, 3.3 s with the self-compile check, tlon's cold `mix format` 2 s), but every
CLI call boots two or three VMs (mise and mix, the host formatter's own, menard's compile check),
and the seats run at a load of 20-30 on 20 cores, where each boot stretches to seconds. The MCP
server keeps one warm formatter worker per project and boots nothing. The agents use the CLI
because the session-start text teaches the CLI heredoc, and nothing else.

`run check`: 48 of 287 ran to the 600 s cap (tlon's gate is 2,330 tests, credo and an eval). The
reply then has no failures to act on, and the gate is run again.

**Verdict.** Keep the hooks and `edit`/`run`: the interpreter ban held at 100%, a quarter of the
Elixir edits needed the formatter, and `run test`'s one-line reply ended the pipe-and-rerun habit.
Stop paying for the AST verbs' upkeep without an eval (section 3). And the one change with a
measured, large return is making the CLI's edits as warm as the MCP door's.

## 2. Fixed with this review

Each from the transcripts, a failing test first, its own commit.

1. **`menard … 2>/dev/null || fallback` was refused** as the reply thrown away: 13 times in tlon.
   Only stderr went there. `&>/dev/null`, which does throw the reply away, was not refused and is.
2. **A dependency's compiler warnings in a green `run test` reply**: 33 replies with `ok: true`
   over `failures` holding styler's and doctest_formatter's warnings under Elixir 1.20. A
   diagnostic whose file is not in the project is dropped.
3. **A write to a read-only file answered `File.write!`'s stack trace**: seven `edit`s in
   sandboxed seats whose scratch dir was read-only (10-22 to 11-08). One sentence now, and the files
   written before it put back.
4. **A build brief that says "find its callers with `menard find calls …`" was refused** as a
   subagent sent to search (tlon-57, 11-08). A prompt that names the tool knows it.
5. `eval/pile/report.sh` died at exit 128 on two repos with no commits yet, after its ten-minute
   pass.

## 3. Open

- **The CLI as a client of the running server.** The 10-01 review's "one warm VM" (its section 3)
  has its number now: 24 s against 1 s at the median, 25 hours in three weeks. Either the CLI
  talks to the hooks server already running for the session (a socket, as that review sketched),
  or the session-start text teaches the MCP `edit` and the heredoc stays for shells with no
  server. *Done the same day, the first way (`Menard.Door`, 0.8.7): the hooks server listens on
  localhost and `bin/menard` sends the verb there over bash's `/dev/tcp`; `run` and verbs from
  inside menard's checkout keep their own VM. The next review should see the CLI `edit` median
  near the MCP door's.*
- **The pile is 30 days deep.** `cleanupPeriodDays` in `~/.claude/settings.json` is unset, so the
  default 30 wiped September and the first week of October. The next review reads from 10-09.
  Set it (180 is 14 GB at today's rate) or run `eval/pile/report.sh` monthly and keep its cache.
- **The AST verbs.** About 5,000 lines of `lib/` (`clause`, `move`, `block`, `stmt`, `rename`,
  `attr`, `directive`, `split`, `module`) and 4,500 of tests, for fifteen calls in three weeks. The
  10-01 decision (frozen until one eval built to favour them) stands; this review adds that nothing
  in three weeks of real work reached for them unprompted. Build the eval, or cut them.
- `run check` at the cap: 48 of 287. The cap is menard's, the gate's length is tlon's. *Not
  menard's (2026-11-09): at 600 s Claude Code moves a command to the background and sends its
  reply when it ends; across tlon's transcripts 42 were moved and none killed.*
- The filter refusal does not say which it saw: a `| head` or a `>/dev/null`. One clause.
- Reading one function costs 11 s (`clause get`, p50) against a free `Read`; 80 of the 141 were
  piped into `head`. The reading aids earn their place on a module too big to read, not elsewhere.
  *Through the door (0.8.7), 60-85 ms in tlon at a load of 22 (2026-11-09).*
- Both MCP servers timed out connecting (30 s) in three sessions (10-12, 11-08 twice), under load:
  a session with no hooks server has no hooks at all, and nothing says so. *Said since 0.8.7
  (`hooks/server-up.sh`). The 11-08 timeouts fall on a toolchain rebuild and a new install's first
  boots; `bin/release` builds the installed copy now. A server Claude Code restarted was
  SIGKILLed, not stopped: fixed in 0.8.8.*
