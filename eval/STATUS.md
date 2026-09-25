# eval status

Window: started 2026-09-25 13:26 MDT, stop by ~18:15 MDT.

## Now

Round 2 running since 14:16, on menard at 6f3382d (the fixes below). Arms: A no menard, B menard,
L = B with its MCP tools always loaded (`alwaysLoad`, no ToolSearch turn), C menard without hooks.
15 cases (explore-config and doctest-line dropped: trivial for every arm) × 4 models, runs
outermost; first pass is 240 runs, ~55 s each, due ~17:55; no run starts after 18:10.
Progress: `eval/results/round2/PROGRESS.txt`; `eval/REPORT.md` regenerates every 5 min.

Round 1 was stopped at 26 runs (haiku only) to fix what the pilot showed; its rows are kept in
`eval/results/r0-050-partial/` as a 0.5.0 reference.

Next, after round 2: the skill, tested the way writing-skills would (baseline vs variants on the
cases where it matters): the current CLI-first skill vs an MCP-first slim one vs none.

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
