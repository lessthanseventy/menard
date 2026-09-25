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
- 16:45 every TODO closed (b77c270..66a03bc): string edits pass the guard, block/clause refusals,
  MCP-first skill + alwaysLoad in the shipped plugin, shell-edit and big-Read advice hooks, pi's
  guard (never found menard before). B is now the shipped plugin, so L and the S-/SL- skill arms
  compare nothing new. skill2 (15 runs, kept in results/skill2/) measured 0.3.0 for every CLI
  call through Bash: read its B rows with that in mind.
- 16:46 smoke: B only, the 6 skill2 cases, haiku, 1 run, against skill2's A rows. The point is
  to find the next obvious thing, not a verdict.
