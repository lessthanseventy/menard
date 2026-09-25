# menard vs. no menard: the eval plan

What we want to know: where menard helps an agent in Claude Code, where it hurts, and what is
missing. Measured, not argued. Budget: one fresh 5-hour window, runs one at a time.

## Runner: `claude plugin eval` (Claude Code 2.1.280)

It already does most of this: cases are `<eval dir>/**/case.yaml` (or `prompt.md` +
`graders/*.md`), `--ablation with-without` adds a no-plugin baseline arm and reports the delta,
`--model` overrides the model, `--runs N`, `--scaffold` runs a case's setup script (a fixture repo),
`--max-cost-usd` caps spend, `--json` writes per-run results, `--mocks off --allow-real-servers`
starts menard's real MCP server. `claude plugin eval init --bare NAME` writes a blank case template.

First step in the new session: `claude plugin eval init --bare smoke`, read the template, and find
out (1) what the per-run JSON records (tokens? tool calls? turns? cost?), (2) how graders are
written (a shell check we can run, not only an LLM judge), (3) whether a third arm is possible.
Where it records too little, read the run transcripts it keeps, or fall back to headless
`claude -p --output-format stream-json` per run, one fresh git worktree each.

## Arms

- A: no menard (the built-in baseline arm): Edit, Write, Bash.
- B: full menard: plugin, MCP tools, the guard hook, the skill.
- C: menard without the guard: tools and skill only. Does the agent choose it, or only use it
  when an Edit is blocked? If the runner cannot do a third arm, a copy of the plugin with
  `hooks/hooks.json` emptied, run as its own target.

## Models: the full matrix

claude-fable-5-1, claude-opus-5-5, claude-sonnet-5, claude-haiku-4-5. menard may matter most for
the smaller ones.

## Tasks: cover the kinds of work, each checked by a script

A fixture repo (a small Phoenix-ish Elixir project, compiled and tested, with a Styler or Quokka
formatter plugin in one variant), reset per run by the scaffold. Each task has a check that
passes or fails on its own: its tests pass, and `git diff` touches only what it should (diff
noise is a metric of its own, the one plain Edit and sed tend to lose on).

- **New work**: a new module with tests; a new function in a large module; a new LiveView
  component with `~H`.
- **Exploratory / reading**: "what calls X", "where is Y configured", answered in a file; tests
  the read side (outline, find, deps) against Read and grep.
- **Refactoring**: rename across files (and inside `~H`); move a function to another module;
  extract a helper; change a signature and every call site; add an alias and use it.
- **Bug fixing**: a failing test to make pass; a crash from a MatchError; a bug in a heredoc or
  sigil value.
- **Tests**: add a test with `@tag :tmp_dir`; add a describe; add a doctest line.
- **The hard cases menard claims**: an edit while the project does not compile; a 1,000-line
  file; a Styler project, where the formatter rewrites what you wrote; attributes that read each
  other.
- **Overhead**: a trivial one-line change, to measure menard's fixed cost (its tool schemas in
  every turn's context, the skill, the MCP cold start).

## What to record per run

Pass/fail and clean/noisy; tokens (input, output, cache read/write) and cost; turns; wall time;
tool calls by name; failed tool calls (Edit's "old_string not found", menard's refusals); re-reads
(a Read of a file just edited: the staged reply should remove those); retry loops (the same tool
again after a failure). And gap signals in B and C: an Edit the guard blocked, `sed`/`perl`/`python`
on a `.ex`, a whole-file `write` where a verb should have done: each one points at a missing verb.

## How many runs

Sequential. A pilot first: 3 tasks × 2 arms × 1 model × 2 runs, to check the harness records what
we need. Then rounds: 3 runs per cell over the whole matrix, then more runs only for cells where
the arms differ but the spread is wide, until the difference is clear or the cell hits 8 runs.
Watch the 5-hour window between rounds; stop before it runs out.

## Output

`eval/` in this repo: the cases, the fixture, a `mise run eval` task, and a report: per task kind
and model, A vs B vs C on pass rate, tokens, turns, failures; where menard helps, where it hurts,
and the list of gap signals, each turned into a TODO.md entry.
