# eval status

Window: started 2026-09-25 13:26 MDT, stop by ~18:15 MDT.

## Now

Round 1 running since 13:43: all 17 cases × arms A, B, C × haiku, sonnet, opus, fable, up to 3
runs per cell (run 1 of every cell before any run 2). It starts no run after 17:50. Progress:
`eval/results/round1/log.txt`, one line per run. `mise run eval:report round1` rebuilds
`eval/REPORT.md` from whatever has finished; a background loop does that every 5 min, and
`eval/results/round1/PROGRESS.txt` has the count and the last run.

Pilot (13:38–13:42, 12 runs, sonnet, A vs B on 3 cases): all passed; the harness records what the
plan asks. First signals: A's rename used `sed` and left `cart_live.ex` unformatted (2/2); B formats
clean but takes ~1.7× the turns and context (Skill + ToolSearch + menard:run on top of the edit);
one B run edited `mailer.ex` with `sed -i` straight past the guard (Bash isn't guarded, by design).

Built: `eval/fixture/` (Shop: catalog, cart, a 1,016-line `Shop.Orders`, a mailer with a heredoc,
a `~H` component and LiveView; 18 tests, styler as a dep), `eval/run.py` (the runner),
`eval/report.py`, `eval/cases/*` (prompt, `check.sh`, hidden tests, an `allowed` list for the noise
metric, `setup.sh` for the broken/styler variants). Every check was run red on the untouched
fixture, and the grep-based ones green on a hand-made solution.

Cases (kind): new-module, new-fn-large, new-component (new-work); explore-callers,
explore-config (reading); rename-across, change-signature, move-function, add-alias (refactor);
bug-receipt-total, bug-matcherror (bugfix); test-tmpdir, doctest-line (tests); not-compiling,
styler, attrs (hard); oneline (overhead).

Plan vs. what fits: 17 × 3 × 4 × 3 = 612 runs at ~20–40 s each is more than the window holds, so
runs loop outermost: every cell gets 1 run, then 2, then 3, until 17:50. The "more runs for wide
cells, up to 8" phase won't fit this window.

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
