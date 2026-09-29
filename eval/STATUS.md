# eval status

Window: started 2026-09-25 13:26 MDT, stop by ~18:15 MDT.

## Now

Skill loop, iteration 2 (since 15:08), on menard 00cd8e1: arms A (no menard), B (current skill),
S-mcp-first (the draft), S-none (no skill), SL-mcp-first (the draft, MCP tools always loaded) ×
new-fn-large, bug-receipt-total, test-tmpdir, attrs, rename-across, change-signature × haiku and
sonnet, 1 run: 60 runs, ~55 min. One line per finished run: `eval/results/live.log`.

Iteration 1 (19 runs, haiku, pre-fix builds) was stopped once its lessons were in; rows in
`eval/results/skill1-prefix/`. What it taught, all acted on:
- the CLI-first skill sends haiku to menard through Bash (30 Bash calls, 9 failures in one run);
  the MCP-first draft stays on MCP; the guard's MCP refusal alone gets a no-skill agent onto MCP.
- menard bugs: a new attribute that reads another landed above it (fixed ddede5f).
- head confusion: nothing printed the head to copy. `outline` now prints each clause's head
  (4b3200c); heads are found the way agents guess them: with the def line's `do`, without the
  guard, and any head for a one-clause function (bff38a7); `block add` in a test file defaults
  to `test` (c477d42); the guard's refusal says finish on `run check` (00cd8e1).
- rule adopted (Andrew): the agent's first guess is the spec: make the tool meet it.

## Step 1 findings: `claude plugin eval` does not fit, so the fallback runner

`claude plugin eval init --bare smoke --eval-dir eval` writes `prompt.md` (frontmatter
`max_turns`, `allowed_tools`) and `graders/criteria.md` (an `llm` grader). Ran it on haiku:

1. **Per-run JSON** records score, pass, turns, costUsd, durationSeconds, grader verdicts and a
   `tracePath`, not tokens or tool calls. The trace (stream-json, with per-message usage and every
   tool call) is deleted after the run unless `--keep-temp`, and is then sealed mode 000.
2. **Graders**: regex, tool_used, tool_order, file_exists, llm, baseline. There is no shell or
   script grader, so "tests pass, diff touches only X" can't be a grader.
3. **Third arm**: no. Ablation is `none` or `with-without` only.
4. **Blocker**: the agent's Bash runs in a bwrap sandbox that doesn't mount `/lib64`, and Erlang's
   `erlexec` needs `/lib64/ld-linux-x86-64.so.2`, so `mix` fails in both arms ("erlexec: No such
   file or directory"). An Elixir agent that can't compile or test isn't a fair measure of either
   arm.

So the runner is the plan's fallback: headless `claude -p --output-format stream-json`, one fresh
copy of the fixture per run, a shell check afterwards. Isolation, tested in a bench:
`--setting-sources project` (the user's installed plugins, including menard 0.3.0, don't load),
`CLAUDE_CODE_DISABLE_CLAUDE_MDS=1`, `ENABLE_CLAUDEAI_MCP_SERVERS=false`. Arm A has no plugin, B
uses `--plugin-dir` on this repo, C uses `--plugin-dir` on a copy with `hooks/hooks.json` emptied.

## Log

- 13:26 start. Template written to `eval/smoke/`.
- 13:35 smoke and probe runs through `plugin eval`: findings above. Switched to headless runner.
- 13:38 fixture, runner, 3 cases built; pilot started.
- 13:43 pilot done (12/12 pass); round 1 started over the full matrix.
- 13:50 harness bug: an agent (haiku) `git commit`ed its work and the runner diffed against HEAD,
  so 2 runs were graded on an empty diff. Fixed (diff/checks against a tag `eval-base`), the 2 rows
  dropped and redone; runner restarted 13:52. Also: the bug cases now accept a new test anywhere
  under `test/`, which is what the prompt asks.
- 13:58 REPORT.md gained a "menard adoption" table (MCP vs CLI-through-Bash vs shell edits).
- 14:07 menard fixes from the pilot's gaps, gate green (596 tests): `block add` with no name is
  refused by name, and `block replace` fills an empty body instead of crashing (566f0d8); MCP
  `rename` takes globs (dac5afb); `attr` replies "@receipt", not "@@receipt" (9b2cec1). The
  structural gaps (Skill + ToolSearch round trips, the guard teaching the CLI, whole-file Reads)
  are in TODO.md (b928455). The eval runs from pinned plugin copies, so round 1 still measures
  the pre-fix 0.5.0.
- 14:07 round 1 at 24/204; expected to finish pass 1 around 17:00–17:30.
- 14:10 stopped round 1 (26/204 runs) at Andrew's call, to fix and rerun.
- 14:15 fixed: guard names the MCP tools under Claude Code (`--mcp`, 67b834a), block usage
  (6f3382d); earlier ones 566f0d8, dac5afb, 9b2cec1. Bench: `alwaysLoad: true` in plugin.json
  works in the CLI, drops the ToolSearch call and a turn, costs ~3.7k tokens of schemas per turn.
- 14:16 round 2 started.
- 14:23 round 2 stopped; skill loop iteration 1 started 14:24.
- 14:55 skill1 stopped; menard fixes above; 15:08 skill loop iteration 2 started.
- 15:40 skill2 stopped at 15/60 (Andrew: fix the obvious first). Harness bug found: the runner
  inherited its launching Claude Code shell's PATH, which held the installed menard 0.3.0's bin/,
  so every `menard` an agent ran through Bash was 0.3.0 (its errors reproduce word for word; the
  pinned build succeeds). MCP calls and the guard were the pinned build. Every CLI-through-Bash
  failure in rounds so far measured 0.3.0. Fixed: run.py strips plugin and repo bin/ dirs from the
  agent's PATH; probe: arm A sees no menard, B only its pinned copy.
- ~16:00 every TODO closed (b77c270..66a03bc): string edits pass the guard, block/clause refusals,
  MCP-first skill + alwaysLoad in the shipped plugin, shell-edit and big-Read advice hooks, pi's
  guard (never found menard before). B is now the shipped plugin, so L and the S-/SL- skill arms
  compare nothing new. skill2 (15 runs, kept in results/skill2/) measured 0.3.0 for every CLI
  call through Bash: read its B rows with that in mind.
- ~16:02 smoke1: B only, the 6 skill2 cases, haiku, 1 run, against skill2's A rows. The point is
  to find the next obvious thing, not a verdict.
- ~16:15 smoke1 done, 6/6 pass, 5 clean (the 6th: the fixture lacked /tmp/ in .gitignore). Fixed
  from it: replace/add take a whole clause or block (aa49875), stmt's template hint (d3063d2),
  empty globs (411c55a); then run's one failure shape and lean reply (5da7d20), a quiet self-build
  (ab17585).
- 16:46 smoke2: same six cases, B, haiku, on everything above.
- 17:12 bench1 started (17:12): all 17 cases × A, B (shipped plugin) × haiku, sonnet, 1 run
  = 68 runs, ~2–2.5 h, pinned with --rebuild, workspaces in /tmp/menard-eval (own dir). Runs past
  the window's 18:15 at Andrew's request.
- 17:20 bench1 at 12/68, all pass. Two menard bugs to TODO.md from doctest-line.B.haiku
  (clause doc without head crashes; run's tail hides mix's "Unknown option"). Drafting a long
  suite (eval/long/: multi-step sessions via --resume on a grown fixture) alongside, at Andrew's
  ask: bench1's 4–26-turn tasks can't show whether menard's up-front cost pays back over a session.
- 17:50 HARNESS BUG, bench1 B rows up to now: two toolchains in one _build. The runner's
  PATH (inherited from this repo's .tool-versions) is Elixir 1.19.4/OTP 27, and agents, check.sh
  and the template use it; menard's host mix ran under mise, whose global default was 1.20.4/OTP
  29, since the fixture pins nothing. Each switch rebuilt every dep (14 in dev, measured: 57 CPU-s).
  So every B run that called menard:run paid full dep rebuilds, twice per switch, A never did.
  B wall times are inflated, and new-component.B.haiku's 620s run timeout is this plus the CPU
  my concurrent menard gates took. Turns/cost/pass stand; B wall_s and the run timeouts do not.
  Fixed both ways at 17:50: mise global set to 1.19.4-otp-27/27.3.4.2 (Andrew), so the rest of
  bench1 runs one toolchain; and menard (7ddace6) now runs the PATH mix when the host pins
  nothing. Also my own gates ran on this machine during bench1: wall times from 17:25 on shared
  the CPU.
- 17:51 bench1 stopped at 25/68 (Andrew's call): haiku, add-alias..not-compiling.A; no
  sonnet row. The sonnet half would have measured the pinned 155211b, with five of the bugs it
  found already fixed. Next: the open bugs, then bench2 on the fixed build, one toolchain.

## bench1 verdict (haiku only, 12 paired cases, 1 run each: noisy, read as direction not proof)

| arm | pass | clean | turns | $/run | context tok | failed calls |
|---|---|---|---|---|---|---|
| A no menard | 12/12 | 8 | 9.7 | 0.066 | 239k | 1 |
| B menard (155211b) | 10/12 | 9 | 11.6 | 0.078 | 331k | 6 |

- B's two fails were menard bugs, both fixed: `explore-callers.B` (find missed calls in ~H,
  251f2fd) and `move-function.B` (run test hid the unused-alias warning the check failed on,
  7d4304e; the agent also finished on `run test`, not `run check`).
- Where B helps: formatting. A left 4 runs unformatted (add-alias, change-signature, new-fn-large,
  not-compiling), B only new-component (both arms). attrs, bug-matcherror, bug-receipt-total: B
  took 1-3 fewer turns and 7-29% less context.
- Where B costs: +1.9 turns, +$0.012 and +38% context per run on average. The clearest case is
  change-signature.B (26 turns vs 17, 758k context vs 379k): whole-file Reads, then the Skill load,
  then `outline` of the same files, one call per clause, 3 re-reads after a green check. Also
  doctest-line (10 vs 5), new-fn-large (13 vs 7). Every failed call in B was menard's: 6 bugs, all
  fixed (see git log 657fa7a..42bc8c7).
- Caveat: B's wall times are void (toolchain rebuild bug, above). Sonnet never ran.

## Handoff (18:00): bench2 is running

- Started 17:57, detached: `run.py bench2 --rebuild --arms A,B --models claude-haiku-4-5,claude-sonnet-5
  --runs 1`, workspaces in /tmp/menard-eval, runner output /tmp/menard-eval-bench2.out, pinned at
  db5277a (every bench1 fix in). 68 runs, ~2-2.5 h. One toolchain now (mise global = PATH = 1.19.4).
- Watch it: `results/bench2/runs.jsonl`, `results/live.log`. A formatter for rows that prints each
  failed call: see how bench1 was watched (a script tailing runs.jsonl with a seen-count, plus a
  Traceback grep on the .out and a check that the runner is alive).
- Don't run the full menard gate while it runs: it steals CPU and skews wall times.
- `report.py ROUND` writes REPORT.md itself; don't redirect its stdout into REPORT.md.
- Next after bench2: the long suite (eval/long/, drafted, not run). Runner support is in (steps +
  --resume, per-step checks on a copy, peak_ctx). The fixture is grown (4.6k lines, green). KNOWN
  ISSUE before its first run: the fixture already defines `stock_badge/1`, which step 06 asks the
  agent to add; change step 06 (or drop it from the fixture) and red-check every step's check.sh
  against the untouched fixture first. Then pilot: `MENARD_EVAL_WORK=/tmp/menard-eval-long run.py
  long1 --suite eval/long --arms A,B --models claude-haiku-4-5 --runs 1`.
- 18:06 bench2 restarted from zero (the 17:57 start stopped at 5 rows, at Andrew's call, to
  take two more fixes): pinned at dafd33e, which adds stmt replace inside ~H expressions (a3863e3)
  and whole-function delete with the calls left named (dafd33e). Same matrix, 68 runs.
- 18:20 HARNESS BUG: new-component's hidden test/hidden/badge_test.exs was not formatted, and
  the check copies it in before `mix format --check-formatted`: every new-component run, both
  arms, bench1 and bench2 (pinned before this fix), is `clean: false` whatever the agent did. B's
  own edits in bench2 new-component.B.haiku format clean (checked on its diff). Read those rows'
  clean as unknown. Fixed in the case (and the long suite's step 06 copy) for later rounds.
- 18:20 Fixing as bench2 runs (Andrew): cd9b403 (clause get; schema refusals say why),
  5598d8f (stmt replace on any ~H text; short miss lists). The gate runs at nice 19 meanwhile.
- 18:23 bench2 stopped at 25 rows (haiku, add-alias..not-compiling.A), pinned at dafd33e: kept as a
  partial record in results/bench2. Its failed calls drove cd9b403, 5598d8f, 8aeaa4f. Of note:
  explore-callers.B passed with find + outline and no Read (bench1 failed it); move-function.B
  passed (run test now shows the unused-alias warning); B's extra turns are mostly orientation twice
  (whole Reads, then outline of the same files) and Reads after a green run check. new-module.A
  failed: its own rounding bug (TENOFF), agent logic, not the harness.
- 18:23 bench3 started: pinned at 8aeaa4f (every fix so far), both models, 68 runs, one toolchain,
  the new-component hidden test formatted. Rule for this round (Andrew): fix as it runs, do not
  restart it; let it finish for one complete A/B round on both models.
- 18:39 Fixed from bench3's haiku half as it ran (bench3 itself stays on 8aeaa4f):
  8c4f051 write replies say "no need to Read the file back" + outline only for big, unread files
  (bench1+2 haiku: B read after its last edit 31x in 24 runs vs A 14x in 26; B outlined 17 files it
  had just Read whole), 5767d14 attr set takes a whole `@name value` (it wrote `@receipt @receipt`)
  + attr replace = set, b13709c stmt takes a test's label as name_arity + says when a by-start
  match took a whole statement, 0da39bf block get with no label returns every block.
  new-component.A is clean for the first time: the hidden-test fix works (cases are read live).
- 18:40 HARNESS BUG: not-compiling's setup.sh sed ran a catalog.ex line past the formatter's
  width, so every run started unformatted: A's "unformatted" on this case in bench1-3 is the setup,
  and bench3 not-compiling.B.haiku ran `run format` on catalog.ex, which made it noise. Clean on
  this case is void in every round so far, both arms. setup.sh now formats what it changed.
- 19:00 bench3's runner died at 30/68: styler.A's check had its `mix compile` wait forever
  on a build lock "held by" its own pid (a mix lock race; the same tree compiles in 1s), and the
  600s timeout escaped sh(). Fixed in the harness (e9e4688): checks and agents run in their own
  process group, killed whole at the deadline, recorded as a failed run. Resumed at 19:00 without
  --rebuild: same pinned plugin (8aeaa4f), the 30 finished rows kept, styler.A rerun.
  Also a63ec0b: stmt reaches module-level statements (defstruct, @type), from not-compiling.B;
  6ce5310: not-compiling's setup left catalog.ex unformatted, voiding clean on that case in every
  round so far, both arms.

## bench3 verdict (68 runs: 17 cases × A/B × haiku/sonnet, 1 run each; menard pinned at 8aeaa4f)

One run per cell is noisy: read per-case differences as direction, the totals as the finding.

| model | arm | pass | clean | turns | $/run | context/run | peak context | failed calls |
|---|---|---|---|---|---|---|---|---|
| haiku | A | 17/17 | 12/17 | 10.9 | 0.070 | 279k | 29.4k | 6 |
| haiku | B | 17/17 | 16/17 | 13.1 | 0.082 | 349k | 33.9k | 13 |
| sonnet | A | 17/17 | 14/17 | 4.9 | 0.053 | 69k | 18.2k | 0 |
| sonnet | B | 17/17 | 17/17 | 9.2 | 0.092 | 155k | 27.1k | 8 |

- **Correctness: a tie.** Every run passed in both arms and both models.
- **Where menard helps: clean output.** B was clean where A was not in 4 haiku cases (add-alias,
  change-signature, rename-across, styler) and 3 sonnet ones (add-alias, change-signature,
  rename-across); never the reverse. A leaves unformatted code or skips the project's Styler.
  And on a rename across files it is cheaper outright: rename-across.B.haiku 10 turns/$0.066 vs
  A 23/$0.142. For haiku, B took fewer turns and cost less on 5 of 17 cases (attrs,
  explore-callers, explore-config, new-fn-large, rename-across).
- **Where it costs, haiku: +2.2 turns, +17% cost, +25% context.** Its re-reads after the last edit
  (1.41/run vs A 0.47) and `outline` of files it had just Read (0.53/run); and 13 failed calls,
  all first guesses menard did not take (attr replace, a test line through stmt, defstruct,
  block get with no label, clause get): fixed since, after this pin.
- **Where it costs, sonnet: B was never cheaper or shorter on any case: +4.3 turns, +74% cost,
  2.3x context.** Sonnet without menard is already frugal (grep, sed, 2-3 Edits, no whole-file
  reads), so there is little for menard to save, and three costs remain:
  1. a fixed tax on every model call, ~9k tokens for sonnet (tool schemas, instructions):
     explore-config.B.sonnet made the same 3 Bash calls as A and read 22k more context;
  2. one tool call per edit site, each a full model turn: change-signature.B.sonnet 14 turns /
     $0.196 against A's 5 / $0.066, which changed every call site with shell commands in one go;
  3. the guard blocking Edits on test files (4 of 17 sonnet B runs), a turn each before `block`.
- **Totals:** haiku A $1.19 / B $1.39; sonnet A $0.89 / B $1.57.

Harness notes for this round: not-compiling's setup left catalog.ex unformatted (fixed 6ce5310
mid-round), so that case's `clean` is void for the haiku rows; the sonnet rows ran after the fix.
The runner crashed at 30 on a mix build-lock deadlock and resumed on the same pin (e9e4688). My
niced gates shared the CPU during the haiku half, so wall times there are soft.

Fixed after bench3's pin, not yet measured: 8c4f051 (writes say "no need to Read back"; outline
only big unread files), 5767d14 (attr whole value, attr replace), b13709c / a63ec0b / 420a26e
(stmt: test label as name, module-level statements, test-macro hint), 0da39bf / 9436625 (block get
all, label without name), plus the harness fixes.

Open, for Andrew:
- **Batch edits** (design): one call carrying several edits, across files, parse-checked and
  formatted together. The biggest remaining cost for a capable model is a turn per edit site.
- `Read` called with `file` (menard's name) in place of `file_path`: 3 failed calls, all in B.
  Candidate: accept `file_path` everywhere and document it, so the models' habit matches.
- The hooks_test flake (TODO.md), not reproduced.

## long1 verdict: the first long sessions (19:13-19:34)

One six-step session (eval/long, cart-refactor: rename, change a signature, move a function,
add a function, fix a bug, add a component; each step resumed in the same session) on a grown
fixture (4.6k lines, modules of 300-1000 lines), menard pinned at b5bd97b. 1 run per cell: a pilot.

| model | arm | final | steps (cumulative) | clean | turns | cost | peak context | Reads | failed calls |
|---|---|---|---|---|---|---|---|---|---|
| haiku | A | FAIL | 1/6 | no | 126 | $1.86 | 153k | 45 | 7 |
| haiku | B | PASS | 4/6 | yes | 179 | $2.25 | 166k | 41 | 13 |
| sonnet | A | PASS | 6/6 | no | 25 | $0.33 | 42k | 0 | 0 |
| sonnet | B | PASS | 6/6 | yes | 53 | $0.73 | 64k | 0 | 5 |

- **At length menard did not pay its cost back in this pilot.** B cost more for both models
  (haiku +21%, sonnet +118%) and read more context at its peak (+13k, +22k). The saving it exists
  for, fewer whole-file reads, did not appear: haiku B made 41 Reads to A's 45; sonnet made none
  in either arm (it greps and edits with shell commands).
- **Where it helped: correctness and clean output.** haiku A took a shortcut in step 02
  (`total(cart, rate \\ nil)`: the rate optional, so 13 callers need not change) and the check
  caught it; its final state fails. haiku B ended fully correct, all 150 tests green. Both B
  sessions end formatted; neither A session does.
- **What broke B's step 02 (haiku) was menard**, and is fixed: `clause replace` given a whole
  function with its `@doc` above nested the `@doc` inside the old body ("cannot set attribute @doc
  inside function/macro"; 5bfc41c), and `run check` answered that compile error with
  `failures: []` (032f5f4). Step 01's miss was rename leaving `price_with_tax/1` in a @moduledoc
  (7d5f5df, docs now renamed). Also fixed from sonnet B: rewrite that carries a new function after
  the clause (c4b41bb), block add naming a whole block by its own label (60eb80d, reverses part
  of aa49875: easy to revert).
- Harness: step 06's hidden test compared exact HTML (9be97c0 fixed); a cumulative check makes one
  early failure fail every later step: haiku A's own-step results are 5/6 (only step 02 wrong).

The question this leaves: for sonnet, menard costs about 2x on long work and saves nothing it can
measure here; its value is the guard's guarantees (parse-checked, formatted, never a sed gone
wrong) and correctness catches. Whether that is worth 2x is Andrew's call; batch edits would cut
the per-site turns that make up most of it.
- 19:44 bench4 started on 7d5f5df (every fix through the long pilot): same matrix as bench3,
  to measure the fixes against bench3's numbers.

## bench4 verdict (68 runs, menard pinned at 7d5f5df): what the fixes since bench3 changed

Same matrix as bench3, 1 run per cell; A is the control (no menard, nothing changed for it).

| model · arm | turns | $/run | context/run | failed calls | Reads after last edit | clean |
|---|---|---|---|---|---|---|
| haiku A | 10.9 → 11.1 | 0.070 → 0.070 | 279k → 249k | 6 → 6 | 0.47 → 0.35 | 12 → 13 /17 |
| haiku B | 13.1 → 13.0 | 0.082 → 0.086 | 349k → 380k | 13 → 11 | **1.41 → 0.47** | 16 → **17** /17 |
| sonnet A | 4.9 → 5.2 | 0.053 → 0.061 | 69k → 74k | 0 → 0 | 0 → 0 | 14 /17 |
| sonnet B | **9.2 → 7.7** | **0.092 → 0.086** | **155k → 135k** | **8 → 2** | 0 → 0 | 17 /17 |

- **Every run passed, in both rounds.** B is clean on all 34 runs; A on 27 of 34.
- **The "no need to Read it back" note worked**: haiku B's reads after its last edit fell 3x, to
  A's level. The `outline`-after-Read guidance did not (0.53 → 0.47 a run).
- **Sonnet: the gap to A roughly halved**: +2.5 turns and +41% cost (was +4.3 and +74%); failed
  calls 8 → 2. On bug-matcherror, doctest-line and explore-config B tied or beat A on turns.
- **Haiku: no net change in turns or cost**, because two new menard bugs cost what the fixes
  saved: stmt's module fallback (from a63ec0b) put a test inside a test in bug-receipt-total.B
  (20 turns), and Phoenix `attr` lines not moving with their def broke new-component.B (27 turns).
  Both fixed mid-round (90b3f6d, 43368f0), so bench4 does not measure them.
- **Still the biggest costs**: change-signature for haiku (26 turns in all four rounds against A's
  15-18: one clause edit per call site), and the guard blocking Edits on test files (6 haiku and
  2 sonnet B runs in bench4, a turn each).

Found and fixed during bench4 (not in its numbers): b206f91 (Sourceror ends an interpolated
string with escaped quotes one column short, so an insert after such a statement went INSIDE the
string: silent, parse-check-proof corruption), 90b3f6d, 43368f0, 6d19a61, ab25192, 0380006.

For Andrew: (1) batch edits, the one lever left on the per-site turn cost; (2) whether the guard
should cover test files (sonnet's first move for a new test is Edit); (3) `file` vs `file_path`.

## long2 verdict: the long session again, on 8119072 (20:15-20:35)

Same six-step cart-refactor session as long1, 1 run per cell (long1 in brackets).

| model | arm | final | steps | clean | turns | cost | peak context |
|---|---|---|---|---|---|---|---|
| haiku | A | PASS (FAIL) | 6/6 (1/6) | no | 131 (126) | $1.74 ($1.86) | 141k (153k) |
| haiku | B | FAIL (PASS) | 4/6 (4/6) | no (yes) | 194 (179) | $2.69 ($2.25) | 183k (166k) |
| sonnet | A | PASS | 6/6 | yes (no) | 25 (25) | $0.30 ($0.33) | 38k (42k) |
| sonnet | B | PASS | 6/6 | yes | **36 (53)** | **$0.40 ($0.73)** | 47k (64k) |

- **Sonnet: the fixes cut B's long-session cost nearly in half**, from 2.2x A's to 1.3x, every
  step passing and clean both times. That is the clearest effect of today's work.
- **Haiku B failed again, on menard again**: step 02 ended not compiling for the same reason as
  long1 in a new shape, a component replaced whole with its `attr` lines and `@doc` above the def,
  which the long1 fix (5bfc41c, @doc/@spec only) did not cover; the session then ran out of turns
  in step 06. Fixed after (2c4d345), with block's no-name whole block (a9e06ab).
- **One run per cell is noisy here**: haiku A went from 1/6 (the optional-rate shortcut) to 6/6.
  A verdict on haiku at length needs several runs per cell; sonnet's two runs agree.
- 21:02 bench5 started: arms A, B, H (only the format-and-parse-check hook) × haiku, sonnet
  × 17 cases, pinned at dc49e51. The question: is B's clean output the
  tools' or the formatting's, and what does it cost without the tools?

## bench5 verdict: is menard's clean output the tools', or the formatting's? (21:02-22:06)

Arms: A no menard; B menard as shipped (tools, skill, guard, hooks); **H only a hook** that formats
every Elixir file written, by Edit/Write or by a shell command, with the project's own formatter
and plugins, and names one that does not parse. 17 cases x haiku, sonnet, 1 run each; A and B from
bench5, H from bench5h (sonnet's two shell-edited cases from bench5h2, after two hook fixes).

| model | arm | pass | clean | turns | $/run | context/run | failed calls |
|---|---|---|---|---|---|---|---|
| haiku | A | 17/17 | 11/17 | 11.0 | 0.071 | 267k | 6 |
| haiku | B | 16/17 | 16/17 | 10.5 | 0.072 | 287k | 7 |
| haiku | **H** | 16/17 | 16/17 | **10.1** | **0.066** | 264k | **5** |
| sonnet | A | 17/17 | 14/17 | 4.9 | 0.057 | 72k | 2 |
| sonnet | B | 17/17 | 17/17 | 8.4 | 0.083 | 141k | 4 |
| sonnet | **H** | 16/17 | 16/17 | **4.5** | **0.055** | **70k** | **1** |

- **The clean output is the formatting's.** H was clean on every run that passed (16 of 16 on
  each model), at A's cost or a little under it. B was clean too, at +46% cost for sonnet.
- **Every failure is the agent's logic, in every arm**: new-module's "10% off, rounding down"
  read as rounding the discount down (both H runs, and A's own test caught it once), and
  change-signature made optional where the task said required (bench5 B). Formatting cannot
  catch either; only the case's hidden tests do.
- **Where the tools still pay**: structural edits and big files. rename-across for haiku: B 6
  turns / $0.046 against H's 18 / $0.132 (one `rename` call against a rename by hand). attrs
  for sonnet: B's targeted reads (`attr get`, `clause get`) $0.073 against H's $0.112 when H read
  the 1,016-line file (and $0.049 when it did not). explore-callers for haiku: `find` 7 turns
  against 9.
- **H's own cost**: the formatter changes text under the agent, so an Edit written against its
  earlier read can miss (`999999` became `999_999`; two such misses in bench5h). A hook that
  reports what it reformatted, as B's replies do, would close that.

What bench5 cost to find (all fixed, all harness or hook): the H plugin missed a script it
named; a stopped runner left its agent running, which wrote its fix into the rebuilt template
(bench5h's first start is void: results/bench5h-void; the template is read-only now); Claude
Code runs PostToolUse only when a tool succeeds (menard's own shell-edits hook had the same
blind spot, 5ce3a26); and the shell hook formatted only the first of the files a command
changed (mix read the loop's stdin).

**Recommendation**: ship H's hook as menard's default, with the MCP tools as an option for the
structural edits and large-file reads where they win, and drop the guard that forces them on
every edit (its blocks are a turn each and bought nothing measurable over H).
- 22:56 bench6 started on 4f7bb1e: menard is hook-only now (69059a4), the tools are manos.
  Arms A (none), B (menard as shipped: the hook), M (menard + manos). 102 runs.
- 23:38 bench6 finished: 102 runs, 101 pass.

### bench6 verdict (hook-only menard, 4f7bb1e)

| model | arm | pass | clean | turns | cost/run | vs A |
|---|---|---|---|---|---|---|
| haiku | A | 16/17 | 11/17 | 10.3 | 0.068 | |
| haiku | B | 17/17 | **17/17** | 11.0 | 0.074 | +9% |
| haiku | M | 17/17 | **17/17** | 10.4 | 0.070 | +4% |
| sonnet | A | 17/17 | 14/17 | 4.9 | 0.054 | |
| sonnet | B | 17/17 | **17/17** | 4.7 | 0.057 | +5% |
| sonnet | M | 17/17 | **17/17** | 6.2 | 0.073 | +35% |

- **The hook alone makes every run clean, for 5-9%.** B was clean on all 34; A left files
  unformatted in 8 of its 33 passes (haiku 5, sonnet 3), mostly where the agent edited by shell:
  sonnet's sed rename-across and change-signature, formatted by B's Bash hook at +$0.002-0.006.
  One bench, one run per cell: the 5-9% is within the case-to-case noise (sonnet's attrs was
  $0.048 in A and $0.112 in B for a whole-file read of the same 1,016 lines the hook never saw).
- **manos pays for haiku on a rename and costs sonnet a third more.** haiku rename-across: M $0.048
  in 7 turns (one `rename`) against A $0.135 / B $0.130 in ~20. Sonnet reached for the tools on
  small edits (`find` on a one-line change, `clause` for a component) and paid +35% overall for
  nothing the hook did not already give; on rename-across it used sed like the others.
- **Sonnet in M called tools that do not exist** (`Grep`, bare `find`, `bash`), 3 of 17 runs, none
  in A or B this round: a turn each. Open: whether manos' tool list or its skill text primes it.
- **The reformat report**: one Edit miss in 102 runs (bug-matcherror B haiku: its old_string kept
  the trailing whitespace the formatter had stripped from the test it wrote). Whether the hook's
  report reached it the trace cannot say: stream-json leaves hook output out unless asked
  (`--include-hook-events`, on in the runner from here). bench5h's H, with no report, had two
  misses in fewer runs. Thin evidence that the report helps.
- **The one failure is the agent's**: haiku A change-signature kept `total/1` next to the new
  `total/2`, which the task said to replace.

**Verdict**: hook-only is the right default. manos stays opt-in; it earns its keep for a weaker
model on renames across files, not for a capable one on everyday edits.
- 23:41 tlon1 started on 65bf545: Tlön tickets 2, 3, 6, 9 × A, B, M × opus, fable (24 sessions, sequential). Smoke (t2 A haiku) passed the gate: 729 tests, 74 turns, $0.94, 17 min.
- 00:01 tlon1 paused after t2.A.opus (runner SIGSTOPped, no agent running) and resumed: B and M re-pinned to 1fd7a91 (the format hook skips what git ignores; stmt ignores comments; block add takes a leading @tag). t2.A.opus ran with no menard, so nothing already run changed.
- 00:03 correction: t2.B.opus had started before the pause (my check for a running agent grepped for the run id, which is not in claude's command line). It ran through the pause (its wall, 923 s, is void) and its plugin was re-copied under it: every one of its 35 hook calls exited 0 with no output, so neither hook version had anything to say to it, and its pass, turns and cost stand.
- 00:3x tlon1 stopped by choice after 6 of 24 sessions (opus, tickets 2 and 3), to save credits
  for the experiments that follow. Stopped cleanly: no agent left, no eval database left.

### tlon1 (partial): opus on real Tlön tickets

| ticket | arm | gate | clean | turns | cost | manos calls |
|---|---|---|---|---|---|---|
| 2 | A | pass | yes | 17 | 0.512 | |
| 2 | B | pass | yes | 19 | 0.457 | |
| 2 | M | pass | yes | 20 | 0.636 | 0 |
| 3 | A | pass | yes | 14 | 0.558 | |
| 3 | B | pass | yes | 12 | 0.514 | |
| 3 | M | pass | yes | 16 | 0.555 | 2 (`run`) |

- Every session passed Tlön's own gate, clean. Opus writes formatted code on its own here, so
  the hook had nothing to report (every B hook call: exit 0, no output).
- B was the cheapest arm on both tickets; M paid manos' schema on every turn and used it twice.
- Not graded by the blind review: six passes of two tickets is too thin to rank solutions, and
  the round was cut before fable. The diffs are in results/tlon1/traces for later.

### focus1 (00:44–01:10): cart-refactor, six steps in one session, sonnet, one session per arm

| arm | clean | new in | cached in | out | turns | ran gate |
|---|---|---|---|---|---|---|
| A (no menard) | **no** | 32.4k | 609k | 6.7k | 21 | 0 |
| hook | yes | **27.2k** | **591k** | 6.2k | 22 | 0 |
| cli (hook + CLI note) | yes | 29.9k | 709k | 7.0k | 24 | 0 |
| grep (hook + each hit's function) | yes | 32.6k | 734k | 6.8k | 23 | 0 |
| map (hook + capped map) | yes | 30.1k | 678k | 6.1k | 24 | 0 |
| lazy-mcp (hook + manos deferred) | yes | 33.8k | 742k | 6.3k | 27 | 6 |
| M (hook + manos loaded) | yes | 45.7k | 727k | 6.4k | 23 | 0 |

- Every step passed in every arm; credo left no issue in any (the fixture's base has none).
- **hook is the cheapest clean arm**, and A the only unclean one. Every hint on top of the hook
  cost more: cli and lazy-mcp used what they offered (`rename`, `find calls`, `clause get`) and
  grepped to confirm anyway; grep's hook fired 7 times and saved no Read; M never called a manos
  tool and paid 24.5k tokens of schema in step 1 regardless.
- **The tasks name their targets** ("rename `Shop.Catalog.price_with_tax`"), so there was nothing to
  explore: the map answered where things are defined, and every step's question was who calls them.
  The capped map also showed a dozen of each module's 58-78 functions. Not a fair test of a map.
- **The gate**: 6 of 7 sessions never ran it. The one that did (lazy-mcp) was told to by manos'
  instructions ("Finish on run check").
- **Correction**: the runner set CLAUDE_CODE_DISABLE_CLAUDE_MDS, which kept the fixture's CLAUDE.md
  ("CI runs mix precommit") from every agent. `--setting-sources project` alone keeps the user's own
  CLAUDE.md out and the project's in (tried both ways in a bench); the flag is gone.
- One run per arm: the token gaps between the clean arms are within one run's noise.

### focus2 and focus3 (2026-09-26)

- 02:21 focus2 on Tlön (eval/tlon/cases/focus, sonnet): arms all (hook + run-cli + compile + big-read
  + stop) and A, one run each (runs 2-3 dropped: focus3 takes the repeats). Earlier starts are void
  (results/focus2-void, -void2, -void3): Tlön's sandbox kept /tmp read-only and its tmux tests failed
  inside every agent's session (fixed: a tmux dir per run), then the arms were rebuilt twice.
- all run 1: 5/5 steps once re-graded. Step 5's check matched a bare `leaf_window` and hit
  Server.Tmux.leaf_window?/1, a different function the agent rightly kept; fixed (dbd4519) and
  re-graded from the run's diff: 736 tests green. 37 turns, 98k new / 2.23M cached / 17k out.
  The run-cli note won over Tlön's cap.sh rule once AGENTS.md sent tests through menard; credo and
  the compiler hook each caught one issue at write time in step 2.
- A run 1 (02:40-02:51): 5/5, clean. Its step 2 said "I didn't run mise run server:check, so credo
  and the evals haven't run"; it ran the gate itself 3 times over the session, all 6.
- The runner started before cf21244 and scored credo at the repo root only (None in both rows):
  rescored from each run's saved diff over the template, both apps, 0 left in each (credo's JSON read,
  not a silent 0). all's row carries the step 5 re-grade (`rescored`, `check_first`).
- report.py read only `{id}.jsonl`, so a long run (a trace per step) showed CLI 0% and no habits
  whatever it did: fixed (it read all's `bin/menard run test` as no CLI).
- Before focus3: Tlön's console had 2 credo findings at its base; fixed in Tlön (7d09361) and in the
  template, so credo left counts only what an agent adds.
- 03:00 focus3 cancelled by choice before it started (the queue killed, no plugin re-pinned), to be
  started on purpose once there is more to add.
- 2026-09-26 16:45 focus3 step 1 re-planted: the old plant (the fuzzy filter dropping every match
  scoring 0 or below) was caught by Tlön's own picker_test.exs:82, so both arms would have started
  on a red test naming the fault. The new plant drops such a match only for a query of one or two
  bytes (`rr` against `Machine · Tlön · rail redesign` scores -5, +2 with no project). Validated
  with `cases/focus3/reference/validate.py` on the hidden-menard template, arm-A workspaces:
  planted tree, the case's `ci` (both apps' precommit) PASS, 922 console tests; planted, step 1
  check FAIL (the 2 hidden initials tests); `reference/01/fix.patch` (the guard gone, a filter test
  added) PASS, 926; `title-first.patch` (the title first in the row's text, so the switcher finds
  `rr` but the filter still drops it) FAIL (1 hidden test: the filter's). 4 of 4 as expected,
  3.8 min; no model run.

### focus2 (02:21-02:51): Tlön focus case, sonnet, all vs A, one run each

| step | all turns | all new / cached / out | A turns | A new / cached / out |
|---|---|---|---|---|
| 1 approval-wait bug | 10 | 26.4k / 227k / 2.2k | 9 | 27.8k / 233k / 2.3k |
| 2 search syntax | 8 | 19.2k / 386k / 6.4k | 9 | 17.2k / 443k / 4.7k |
| 3 ticket #4 | 10 | 30.0k / 727k / 5.5k | 17 | 54.4k / 1.45M / 10.1k |
| 4 brief commits | 5 | 14.2k / 462k / 1.4k | 5 | 9.2k / 571k / 1.6k |
| 5 rename | 4 | 8.1k / 425k / 1.4k | 4 | 9.5k / 498k / 1.4k |
| **session** | **37** | **97.9k / 2.23M / 16.8k** | **44** | **118.0k / 3.20M / 20.1k** |

| | all | A |
|---|---|---|
| steps passed | 5/5 (re-graded) | 5/5 |
| credo left | 0 | 0 |
| CI | green first, 0 more turns | green first, 0 more turns |
| test/gate runs, reruns with no edit between | 8, 4 | 5, 1 |
| hand `mix format` | 0 | 1 |
| hooks fired | credo 2, compile 1, stop refused 0, big-read 0 | – |
| wall | 1,088 s | 672 s |
| ticket #4, blind review | 1/5 | 4/5 |

- **all's token lead is step 3's, and step 3 is where it did the worse fix.** Outside step 3 the
  arms are even (all 67.9k new, A 63.7k). The blind review (ticket and the two diffs unlabelled):
  all gated the Staff cron's leaf spawn on "the operator has ever posted", so the reported threads,
  which have old posts, still spawn on the next tick and replay a stale message, and its test asserts
  that; A took leaf spawning out of the cron, leaving it to the spawn-on-post path that already did
  the opening turn, and moved the cap there (off for a parked note that still says "starts
  automatically" and console comments that still credit the pass). Both passed the step's check,
  which is compile plus the suite: it cannot tell them apart.
- **all ran slower**: 416 s more wall, and outside the model (all ~728 s, A ~289 s; model time all
  ~150 s, A ~184 s, from the traces). all ran the gate 7 times to A's 3 and its Stop hook runs it at
  each of five step ends; how much of the gap is that hook is unverified (menard's run logs carry
  only a start time).
- **The write-time hooks caught 3 issues, and CI would not have differed**: A also ended with 0 credo
  and a green CI.
- **Correction (the eval review, 2026-09-26)**: "4 reruns to 1" is a counting artifact. A command
  that edits and then runs the tests counted only as a run, so two in a row read as a rerun; 7 of
  all's 8 runs were that form, and a command with a heredoc in it (A's usual form) did not count
  at all. Recounted with the fixed counter (bb5db2e): all 8 runs / 0 reruns, A 11 / 2. all's 2
  "failed calls" were its red `bin/menard run check`s (a non-zero exit), which A's piped runs never
  register; read off the result text, red runs were all 3 and A 4, tool errors 0 and 0. A's hand
  `mix format`s were 5, not 1.
- **Verdict (one run each, thin):** all does not beat A here. Equal on passing, credo and CI; fewer
  tokens only where it solved less; slower. focus3's 3 runs a side are what can say more, and its
  refactor and feature steps want the blind review too; their checks no longer pass shallow fixes
  (step 2 needs the tool over the wire, step 3 a split measured in code lines moved).

### riverside (2026-09-26): the ex_riverside bench, built and validated, no round run

- Why: Tlön's server depends on menard's library, so its arm A can never fully not-know menard.
  ex_riverside (a Phoenix 1.8 app: 12.6k lines of lib, 58 test files, 594 tests, Postgres, Quokka
  as a formatter plugin, its own `precommit` alias) has no connection to menard: no mention in its
  tree or its 176-commit history (the only one, `.claude/settings.local.json`, is untracked and
  never cloned). `eval/riverside` is the suite: `--suite eval/riverside`, with
  `MENARD_EVAL_WORK=/tmp/riverside-eval` (a runs directory named after menard reaches arm A
  through its cwd and through what its tests render: excessibility's snapshots carried
  `file:///tmp/menard-eval-riverside/...`; build.sh and arm_setup.sh refuse such a path).
- The template: a clone at HEAD, history and remote dropped, deps and _build from the checkout,
  compiled on mise's Elixir 1.19.4 / OTP 27; its suite run once at build (594 tests, 0 failures,
  20-33 s, with AI_BASE_URL dead and no key: no test reaches the LLM or the network), the test
  database of that run dropped and its snapshots removed. mise.local.toml (the AI key) is
  gitignored, so the clone has none. Not fully warm: the app's own 93/107 files recompile once per
  workspace (~10 s an env, Mix's manifests are path-bound: a moved build recompiles too); the deps
  stay compiled.
- The wall is the eval's, the same in every arm: ex_riverside has no `.claude/settings.json`; the
  template gets one with the Bash sandbox on (no network but the package hosts, writes in the
  workspace and the toolchain caches), the same wall that keeps a run off the operator's
  databases, network and production. Probe (one haiku turn each, `mix test
  test/ex_riverside/tags_test.exs` in a prepared arm-A workspace): over TCP the sandbox refused
  Postgres (`tcp connect (localhost:5432): connection refused`); with the Repo on the unix socket
  (`socket_dir: "/run/postgresql"`, one line in config/dev.exs and test.exs, allowAllUnixSockets as
  Tlön needed) 15 tests green. The dev database takes its name from EX_RIVERSIDE_DEV_DB (one line
  in config/dev.exs); the test one from MIX_TEST_PARTITION, the project's own switch.
- Per run (agent_env.sh): `ex_riverside_test_<rid>` and `ex_riverside_dev_<rid>`, dropped before and
  after with --force, a failed drop reported; AI_BASE_URL=http://127.0.0.1:9/v1, AI_API_KEY empty;
  ssh, scp and podman stubbed first on PATH (the mise tasks deploy to myelin.us through them). No
  tmux or TMPDIR handling: the app's tests need neither. Arm A: the tree as the template has it,
  and arm_setup.sh fails the run if its workspace or path mentions menard;
  eval/tests/test_riverside_hidden.py holds that line and the run env. Menard arms need nothing
  beyond the plugin: the run-cli note names the plugin's own bin/menard, and the project's notes
  send the gate through `mix precommit`.
- The case, `cases/events` (long, 3 steps, `ci` = `mix precommit`, settings 200 turns / 3600 s a
  step as Tlön's): (1) a bug report: a moderator opening an item of the dashboard's review queue
  is bounced with "You don't have permission"; planted by setup.sh, the queue's level comparison
  `<` → `<=` in `list_pending_submissions_for/1`, so it lists a submission from the reviewer's own
  level that the review page (Permissions' strict-above rule, right) refuses. The project's own
  suite and precommit are green with it (594 tests, 0 failures, run on the planted tree); only the
  hidden test sees it. (2) a ticket: `GET /events/:id/calendar.ics`, an iCalendar file for a live
  event, with `Events.Calendar.ics/1` and an "Add to calendar" link on the event page. (3) a
  refactor ask: split `events.ex` (862 lines, 701 of code) into modules under
  `lib/ex_riverside/events/`, `ExRiverside.Events` keeping every public function.
- Graders, validated both ways in scratch workspaces through run.prepare / suite_env / check:
  - step 1: planted tree FAIL (hidden: the peer's submission in the queue); the fix (`<`) PASS,
    598 tests; Permissions loosened to at-or-above FAIL (hidden + the project's own permissions
    tests, 4 failures); the review page's check skipped so it never bounces FAIL (hidden: the
    peer still in the queue and on the dashboard). The dashboard assertion looks for the review
    links, not titles: the activity feed also names the event.
  - step 2: no feature FAIL (5); reference PASS, 604 tests, whether the 404 is raised
    (Ecto.NoResultsError) or sent; a stub answering a fixed field-less VCALENDAR with the link
    on every page FAIL (6); LF line ends and no escaping FAIL (4). Lines are unfolded before
    matching, and a DTSTAMP is allowed to differ between two renders.
  - step 3: reference split with menard's `clause move` (53 moves, 49 s; Listing 230, Review 229,
    Series 175 code lines, events.ex 134 of 701 as a facade of delegates plus what ties them) PASS:
    split.py, credo --strict, the API test, 605 tests. Untouched FAIL (keeps 701 of 701); docs,
    comments and blank lines purged FAIL (607 kept: a `@doc` heredoc counts as code, and it is
    still 87%); one dump module with Events delegating FAIL (1 module of substance, 2 needed); a
    public function nobody in the suite calls dropped from the facade FAIL (the API test and the
    hidden queue test). Lines conserved: at most 70 fewer than the base total, 210 more.
- Cost of the validation: two haiku probes ($0.08); no eval round was started. Every scratch
  workspace and database is gone (only ex_riverside_dev and ex_riverside_test remain, the
  operator's). `bin/menard run check` (802 tests) and `python3 -m unittest discover -s eval/tests`
  (33) green.

### Handoff (2026-09-26, out of credits)

Merged into main and green (850 tests, eval tests OK): all review fixes (hooks, clause, edit verbs,
run/deps, core and doors, eval harness, follow-ups), refactors 1 (one verb layer, prose verbs
deleted) and 3 (formatter out of menard's VM), menard hidden from Tlön's arm A, and the
ex_riverside bench (eval/riverside, case `events`, graders validated both ways; run with
`--suite eval/riverside`, MENARD_EVAL_WORK=/tmp/riverside-eval).
In flight when credits ran out, each in its worktree under .claude/worktrees (merge what is
committed, resume or redo the rest):
- refactor-ast: module walking and patch/range/parse into Menard.Source.
- fix-eval-resume: the runner survives usage-limit cutoffs (detect, wait, restore the step, redo;
  resume a killed round).
- build-riverside follow-up: reference solutions as patches under
  eval/riverside/cases/events/reference/ with a re-validation script; confirm no leftovers.
Then: the test-suite review's 12 findings (docs/review/2026-09-26-fable.md), TODO.md's focus3
re-plant, re-pin the plugins, and the round on ex_riverside (all vs A, Opus and Fable, 3 runs: the
project tier of PLAN.md's model split).

### Before the next rounds (2026-09-26, evening)

The handoff's in-flight work is merged (refactor-ast, fix-eval-resume, the riverside reference
patches), and so is everything after it: the gate's load-sensitive tests count work or retry
their deadline, the review's Tests findings, focus3's step-1 plant (Tlön's own suite green on it,
only the hidden tests catch it; validate.py 4 of 4), and every TODO.md entry, which is empty.
`bin/menard run check` 892 tests green; eval/tests 57 OK (2 skipped: focus2's traces are not on
this machine). Models now split by tier (PLAN.md): unit rounds (eval/cases) on haiku and sonnet,
project rounds (eval/long, eval/tlon, eval/riverside) on opus and fable. Next: both rounds, each
started with `--rebuild` so the arms are pinned to this main.
- ~18:50 riverside1 stopped after 2 sessions: `all` had been menard's hooks only, and manos' tools
  were loaded only by M, lazy-mcp and map-mcp. `all` is all of menard now (eval/tests/test_arms.py
  holds it). events.A.opus.1 kept; the hooks-only `all` rows moved to results/riverside1-void.
  Restarted as riverside1 (the runner skips the row it has), then focus3b.

### riverside1 (18:31-20:09): ex_riverside `events`, opus and fable, A vs all, 3 runs

- pass: all 6/6, A 5/6. The miss: events.A.fable.3, step 2's `.ics` escaped `,` but not `;`
  (the ticket names both); step 3 failed on the same hidden test. Everything else clean.
- all cost more: paired against A, new input +7.5k tokens (median; higher in 5 of 6 pairs),
  +7 turns, +87 s agent time (slower in 6 of 6). Out tokens about even.
- menard barely used. manos: `outline` 0.8 a run, nothing else; no `clause move` for the split,
  which every run did with a Python script over line ranges. The skill loaded in 1 run of 6. 38
  shell edits of .ex files in the all arm. The guard is not in the Claude Code plugin since
  69059a4 (bench5: its blocks cost a turn each), so nothing steers an edit to a verb.
- focus3b not started: paused after riverside1 by choice.

### Handoff (2026-09-26, ~20:40, limits again)

Main is green and clean (bin/menard run check 892 at 2060c46; eval/tests 60 OK at 15904ec); TODO.md is
empty; riverside1 is committed (9461959, results + REPORT.md).

Since riverside1: the `all` arm has the guard too (15904ec: eval/arms/all/menard-only.sh, wired
by build_plugins; the shipped plugin still has none). riverside2 (all only, fable first) was
started and stopped after one session to build the verb below first; its leftovers are removed.

**In flight: a split-shaped `clause move`**, in .claude/worktrees/agent-a72ce4ef1b8fd95c9 (branch
worktree-agent-a72ce4ef1b8fd95c9, off 15904ec; uncommitted work in lib/menard/clause.ex,
lib/menard/deps.ex and a new test/menard/move_split_test.exs when the limit hit). The job, from
riverside1: every agent split events.ex with a Python script because `clause move` takes one
function a call (the reference: 53), leaves no delegate and fixes no calls. Build, test-first, on
the one verb layer (both doors):
1. `name_arity` as a list (MCP array or "a/1,b/2"; CLI comma-separated), one write per file.
2. `delegate: true` / `--delegate`: each moved public function leaves a `defdelegate` (defaults
   kept), so the source's API is unchanged.
3. carried along: private helpers only moved code calls (reuse `deps`); a private also called by
   what stays is refused, named, with what to do; attributes the moved code reads copied; only the
   aliases/imports it uses added; calls from moved code back to the source's public functions
   qualified; without delegate, the reply names calls in the source left pointing at nothing.
4. the reply per docs/live.md; the skill's `clause move` row and trap note, the MCP description,
   CLI usage and the guard's refusal text say a split is one call per new module.
Acceptance, no model: on a riverside template copy (MENARD_EVAL_WORK=/tmp/riverside-eval; see
eval/riverside/cases/events/reference/validate.py), steps 01+02 reference patches applied, step 03's
split done with only `clause move … --delegate` calls (about one per new module) must pass step
03's check. Then CHANGELOG, `bin/menard run check`, eval/tests, merge.

**Next, in order:** finish and merge the verb (resume the worktree's work or redo it from the
above); then riverside2 = `--arms all --models claude-fable-5-1,claude-opus-5-5 --runs 3 --rebuild`
(compared against riverside1's A rows, same case and models); then focus3b (`--suite eval/tlon
--cases focus3 --arms A,all …`, MENARD_EVAL_WORK=/tmp/menard-eval-tlon), started only when Andrew
says. The unit tier (eval/cases on haiku and sonnet) is Andrew's to run overnight. Open question
for him: rename `all` to `full` after these rounds (older rounds used `all`).

### riverside2 (21:32-22:21): the all arm alone (+ guard, split-shaped clause move, stop-gate skip), fable and opus, 3 runs

Against riverside1's A and all (medians):

| set | opus pass | opus turns / agent s | fable pass | fable turns / agent s / new in |
|---|---|---|---|---|
| A (r1) | 3/3 | 42 / 370 | 2/3 | 27 / 315 / 98k |
| all (r1: hooks + manos) | 3/3 | 43 / 430 | 3/3 | 35 / 445 / 116k |
| all (r2: + guard, split, skip) | 3/3 | 44 / 433 | 2/3 | 40 / 462 / 159k |

- The one failure is fable's again: the `.ics` `;` unescaped (as A fable.3 in riverside1), its calendar
  written through Bash; menard neither helps nor hurts it.
- The split verb was used in 3 of 6 (all fable, never a script), opus scripted it every time. Used,
  step 3 doubled: median 20 turns / 171 s against A's 8 / 122. The path: outline, a move refused on
  the shared `broadcast` helpers, 2x `visibility`, 5-6 moves, fixups. The guard's blocks cost a turn
  each and moved the agent onto manos. The stop-gate skip fired in 2 of 18 steps: agents seldom run the
  gate after their last write.
- Reading: no quality bought on this bench, and every nudge costs turns. For the split to earn its
  place it has to be about one call, not twelve: the whole plan ({module => functions}) at once,
  shared helpers made public by the move itself, moduledocs in the same call.
- Found: the stop gate never sees manos' writes (TODO.md).

### focus3b restarted (2026-09-26, ~00:15)

Started 23:40 (A vs all, opus and fable, 3 runs, MENARD_EVAL_WORK=/tmp/tlon-eval: a work path
without "menard", which arm A would read). Stopped after one session: focus3.A.opus.1 split cockpit.ex
into 8 modules and failed step 03 on split.py's symmetric 10% line bound (1765 -> 2057, +16.5%: new
modules' headers, aliases and docs) before compile, credo and the tests ran, so it could not be
regraded. The bound is now at most 10% fewer, 30% more, as riverside's; the row is in
results/focus3b-void. Restarted fresh.

### focus3b (2026-09-27 00:00 - 09-28 09:25): Tlön focus3, A vs all, opus and fable, 3 runs

| arm, model | steps | sessions | turns | agent s | new in |
|---|---|---|---|---|---|
| A, opus | 8/9 | 3/3 | 71 | 688 | 234k |
| all, opus | 8/9 | 2/3 | 68 | 934 | 248k |
| A, fable | 8/9 | 3/3 | 50 | 968 | 239k |
| all, fable | 7/9 | 3/3 | 41 | 808 | 244k |

(A session passes on its last step; `steps` counts every step.)
- Missed steps. A: opus.3 step 02 (the feature's hidden tests), fable.3 step 01 (the plant). all:
  fable.2 and fable.3 step 01 (the plant: fable misses it in both arms, 3 of 6), opus.1 step 03, which
  failed `credo --strict` on its own step-1 fix (Console.Fuzzy.filter nested 3 deep). The console's
  .credo.exs is `strict: false` and its precommit runs no `--strict`, so neither the agent's gate nor
  menard's stop gate (the project's strictness) could see it; the grader is stricter than the project,
  for both arms alike.
- all.opus.1 was the outlier: 166 turns, 29 min (step 2 slept twice with ScheduleWakeup around two stop-
  gate refusals; step 3: 11 moves, 19 visibility calls, 17 Edits). Without it opus all is ~A.
- The split verb: used once or twice a session by fable (never for the whole split), and by opus only
  in run 1; the other splits went through Bash and Write/manos `write` of new files, which the guard
  passes. The stop-gate skip fired in 7 of 18 menard steps; its full run is ~70 s on Tlön.
- The usage-limit resume worked for real, twice (results/focus3b/waits.jsonl): at 01:33 the session
  limit stopped a step (9 min wait), at 03:17 the weekly limit (30 h wait, to 09:02 on 09-28); each
  time the runner waited to the reset, probed, redid the step, and it finished the round.
- Reading, with riverside1-2: no quality bought on either codebase (every miss is the model's), cost
  about even to a little higher with menard, and the verbs are used only in part.

### The two-arm runner and the helpdesk suite (2026-09-28)

menard changed shape, so the rounds above measured something that no longer ships: one plugin now
(manos merged in), its hooks `mcp_tool` calls into the server (6-9 ms a write once warm, from
0.8-1.0 s), its tools loaded on demand (+438 tokens at session start, against +4,685 up front),
and `clause split` for a whole split in one call.

- The runner has two arms, `without` and `with` (the plugin as a user installs it, nothing added).
- `eval/helpdesk`: a help desk built from `mix phx.new` (SQLite, credo in the installer's
  `precommit`), case `desk`, nine steps in one session. 01-07 build it (tickets, the status flow,
  staff and assignment, comments, response targets in business hours, three LiveView pages, a JSON
  API and a CSV export); 08 renames a function and adds a required argument across its callers;
  09 splits the context the session wrote. Each prompt pins the interface its acceptance tests call.
- Graders validated both ways, no model: `reference/validate.py`, 27 of 27 (9 right answers pass,
  18 wrong ones fail). The reference caught two graders that were wrong (a controller action named
  `transition` failed step 08; the split's facade limit of 40% was what the reference itself
  left) and two menard bugs (`insert_at top` under a `@spec`; a helper called without its default
  argument left behind by a move), all fixed.
- Smoke, step 01 only, haiku, one run an arm: both pass, clean, CI green first. In `with` the
  plugin's 42 hook calls all answered, 9 with a report for the agent; `without` has no word of
  menard in its trace. One run: its numbers say the plumbing works and nothing else.
- To run: `MENARD_EVAL_WORK=/tmp/desk-eval eval/run.py ROUND --suite eval/helpdesk --models
  claude-fable-5-1 --runs 5 --rebuild` (a work path that does not name menard: the arm without
  would read it).
- Known about the baseline: the installer's `precommit` runs `mix format`, and its AGENTS.md sends
  agents to `mix precommit` when done, so the arm without formats whenever it runs its gate.

### desk1 (2026-09-28 21:52 - 23:25): helpdesk, fable, without vs with, 3 runs

Menard pinned at a95c049. Six sessions, one at a time, no usage-limit wait. Paired by run.

| | without (runs 1, 2, 3) | with (runs 1, 2, 3) | with − without, median (range) |
|---|---|---|---|
| final state passes | 3/3 | 2/3 | |
| steps passed as graded | 9, 7, 9 | 8, 4, 9 | |
| new input + output tokens | 196k, 210k, 212k | 188k, 230k, 190k | −7.5k (−22k to +20k) |
| turns | 31, 37, 39 | 29, 36, 30 | −2 (−9 to −1) |
| agent seconds | 829, 924, 900 | 833, 1058, 804 | +4 (−96 to +134) |
| red test runs | 3, 1, 2 | 1, 2, 1 | |
| CI green first | 3/3 | 3/3 | |
| credo left | 0, 0, 0 | 0, 0, 0 | |

- **No difference this round can show.** With was lower on tokens in two pairs and higher in one,
  and the spread between runs of one arm (196k to 212k, 188k to 230k) is as wide as the gap
  between arms. Three pairs.
- **Menard had almost nothing to act on.** Fable wrote the whole app through Bash (20-28 calls a
  session, no Edit or Write, a Read or two), already formatted: of 130 hook calls in the three
  with sessions, all answered, 9 had anything to report (2,189 characters in all). No menard tool
  was called in any session, the rename of step 08 and the split of step 09 included.
- **The failures are the harness's and the model's, not menard's.** with.2 fails steps 05-09 on
  one acceptance assertion (list_breached asked about a time before a late response was made:
  the prompt defines it, and the question is unnatural), 199 of 200 tests green at step 09; set
  aside, with.2 passes every step. with.1's step 03 and without.2's steps 04 and 05 failed and
  passed from the next step on: the session's own tests, red at that step.
- To fix before another round: that assertion; a step graded on its own acceptance tests, so one
  miss does not fail every step after it; and whether the red-then-green steps are SQLite under
  async tests.

### After desk1: three fixes to the harness (2026-09-29)

- The assertion with.2 failed on is gone (`list_breached` asked about a time before a late
  response was made).
- A step is graded on the session's own tests and its own acceptance tests. The earlier steps'
  acceptance tests run after, and what they say is a note in the check's output; step 09, a
  refactor, still holds all of them to its verdict.
- The red-then-green steps were not flaky tests: three sessions' final trees, acceptance tests
  in, ran green 40 times of 40, at the installer's test pool of five and at one. They were the
  tree as it stood at that step, which desk1 did not keep: the runner now saves each step's diff
  (`traces/RID.NN.diff`). One session did meet SQLite's "Database busy" under async tests and set
  the test pool to one itself; the template has that now, the same for both arms.
- validate.py: 27 of 27 under the new grading.
