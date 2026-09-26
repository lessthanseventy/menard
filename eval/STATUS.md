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
