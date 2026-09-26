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
