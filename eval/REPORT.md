# menard eval report

Rounds: bench3. 68 runs. Arms: A no menard, B full menard (MCP, guard hook, skill), L = B with its MCP tools always loaded, C menard without its hooks.

`pass`: the case's check (hidden tests, compile with warnings as errors, task-specific greps). `clean`: passed, touched only the files the task needs, and `mix format --check-formatted` holds. `context tok`: input + cache read + cache write, summed over the run.

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

## By arm

|  | arm | n | pass | clean | cost $ | context tok | out tok | turns | wall s | failed calls |
|---|---|---|---|---|---|---|---|---|---|---|
| all | A | 34 | 100% | 76% | 0.061 | 174,076 | 1,771 | 7.9 | 19.2 | 0.2 |
| all | B | 34 | 100% | 97% | 0.087 | 251,915 | 2,156 | 11.2 | 29.2 | 0.6 |

## By model

| model | arm | n | pass | clean | cost $ | context tok | out tok | turns | wall s | failed calls |
|---|---|---|---|---|---|---|---|---|---|---|
| claude-haiku-4-5 | A | 17 | 100% | 71% | 0.070 | 279,389 | 2,613 | 10.9 | 28.1 | 0.4 |
| claude-haiku-4-5 | B | 17 | 100% | 94% | 0.082 | 348,814 | 2,917 | 13.1 | 38.7 | 0.8 |
| claude-sonnet-5 | A | 17 | 100% | 82% | 0.053 | 68,762 | 928 | 4.9 | 10.4 | 0.0 |
| claude-sonnet-5 | B | 17 | 100% | 100% | 0.092 | 155,016 | 1,395 | 9.2 | 19.7 | 0.5 |

## By task kind

| kind | arm | n | pass | clean | cost $ | context tok | out tok | turns | wall s | failed calls |
|---|---|---|---|---|---|---|---|---|---|---|
| bugfix | A | 4 | 100% | 100% | 0.059 | 157,858 | 2,010 | 7.0 | 20.7 | 0.2 |
| bugfix | B | 4 | 100% | 100% | 0.083 | 281,118 | 2,415 | 11.2 | 30.4 | 0.8 |
| hard | A | 6 | 100% | 67% | 0.058 | 166,164 | 1,596 | 7.3 | 18.8 | 0.2 |
| hard | B | 6 | 100% | 83% | 0.085 | 253,471 | 2,113 | 12.3 | 30.0 | 1.2 |
| new-work | A | 6 | 100% | 100% | 0.074 | 205,437 | 2,388 | 9.5 | 24.1 | 0.5 |
| new-work | B | 6 | 100% | 100% | 0.098 | 282,597 | 2,541 | 11.3 | 31.8 | 0.5 |
| overhead | A | 2 | 100% | 100% | 0.038 | 91,794 | 818 | 5.5 | 9.3 | 0.0 |
| overhead | B | 2 | 100% | 100% | 0.077 | 220,644 | 1,662 | 11.0 | 25.9 | 1.0 |
| reading | A | 4 | 100% | 100% | 0.057 | 144,840 | 1,124 | 6.0 | 13.2 | 0.0 |
| reading | B | 4 | 100% | 100% | 0.052 | 116,805 | 1,056 | 5.5 | 15.8 | 0.0 |
| refactor | A | 8 | 100% | 25% | 0.071 | 230,074 | 2,140 | 9.8 | 22.9 | 0.0 |
| refactor | B | 8 | 100% | 100% | 0.113 | 316,267 | 2,680 | 13.9 | 36.1 | 0.5 |
| tests | A | 4 | 100% | 100% | 0.047 | 113,499 | 1,250 | 6.5 | 14.7 | 0.2 |
| tests | B | 4 | 100% | 100% | 0.067 | 196,397 | 1,687 | 9.5 | 24.2 | 0.5 |

## By task kind and model

| kind · model | arm | n | pass | clean | cost $ | context tok | out tok | turns | wall s | failed calls |
|---|---|---|---|---|---|---|---|---|---|---|
| bugfix · claude-haiku-4-5 | A | 2 | 100% | 100% | 0.066 | 246,552 | 3,263 | 10.0 | 31.7 | 0.5 |
| bugfix · claude-haiku-4-5 | B | 2 | 100% | 100% | 0.091 | 423,110 | 3,703 | 15.0 | 44.2 | 1.0 |
| bugfix · claude-sonnet-5 | A | 2 | 100% | 100% | 0.051 | 69,164 | 757 | 4.0 | 9.7 | 0.0 |
| bugfix · claude-sonnet-5 | B | 2 | 100% | 100% | 0.074 | 139,126 | 1,127 | 7.5 | 16.6 | 0.5 |
| hard · claude-haiku-4-5 | A | 3 | 100% | 33% | 0.067 | 269,330 | 2,344 | 10.7 | 26.6 | 0.3 |
| hard · claude-haiku-4-5 | B | 3 | 100% | 67% | 0.082 | 351,652 | 2,847 | 13.7 | 40.6 | 1.7 |
| hard · claude-sonnet-5 | A | 3 | 100% | 100% | 0.050 | 62,998 | 847 | 4.0 | 10.9 | 0.0 |
| hard · claude-sonnet-5 | B | 3 | 100% | 100% | 0.088 | 155,289 | 1,379 | 11.0 | 19.4 | 0.7 |
| new-work · claude-haiku-4-5 | A | 3 | 100% | 100% | 0.082 | 323,901 | 3,191 | 11.7 | 33.6 | 1.0 |
| new-work · claude-haiku-4-5 | B | 3 | 100% | 100% | 0.092 | 392,627 | 3,360 | 13.0 | 43.3 | 0.7 |
| new-work · claude-sonnet-5 | A | 3 | 100% | 100% | 0.066 | 86,973 | 1,585 | 7.3 | 14.7 | 0.0 |
| new-work · claude-sonnet-5 | B | 3 | 100% | 100% | 0.104 | 172,567 | 1,722 | 9.7 | 20.2 | 0.3 |
| overhead · claude-haiku-4-5 | A | 1 | 100% | 100% | 0.040 | 134,831 | 1,375 | 8.0 | 13.9 | 0.0 |
| overhead · claude-haiku-4-5 | B | 1 | 100% | 100% | 0.056 | 226,610 | 1,724 | 10.0 | 25.2 | 1.0 |
| overhead · claude-sonnet-5 | A | 1 | 100% | 100% | 0.035 | 48,756 | 262 | 3.0 | 4.7 | 0.0 |
| overhead · claude-sonnet-5 | B | 1 | 100% | 100% | 0.097 | 214,678 | 1,599 | 12.0 | 26.5 | 1.0 |
| reading · claude-haiku-4-5 | A | 2 | 100% | 100% | 0.065 | 221,274 | 1,656 | 8.0 | 18.9 | 0.0 |
| reading · claude-haiku-4-5 | B | 2 | 100% | 100% | 0.049 | 143,176 | 1,453 | 6.5 | 21.1 | 0.0 |
| reading · claude-sonnet-5 | A | 2 | 100% | 100% | 0.048 | 68,406 | 592 | 4.0 | 7.5 | 0.0 |
| reading · claude-sonnet-5 | B | 2 | 100% | 100% | 0.055 | 90,434 | 658 | 4.5 | 10.4 | 0.0 |
| refactor · claude-haiku-4-5 | A | 4 | 100% | 25% | 0.090 | 395,121 | 3,312 | 15.0 | 35.4 | 0.0 |
| refactor · claude-haiku-4-5 | B | 4 | 100% | 100% | 0.104 | 458,681 | 3,651 | 17.0 | 48.0 | 0.5 |
| refactor · claude-sonnet-5 | A | 4 | 100% | 25% | 0.053 | 65,027 | 969 | 4.5 | 10.5 | 0.0 |
| refactor · claude-sonnet-5 | B | 4 | 100% | 100% | 0.123 | 173,853 | 1,709 | 10.8 | 24.3 | 0.5 |
| tests · claude-haiku-4-5 | A | 2 | 100% | 100% | 0.044 | 159,476 | 1,677 | 7.0 | 20.1 | 0.5 |
| tests · claude-haiku-4-5 | B | 2 | 100% | 100% | 0.059 | 251,546 | 2,168 | 11.0 | 29.1 | 0.5 |
| tests · claude-sonnet-5 | A | 2 | 100% | 100% | 0.049 | 67,522 | 823 | 6.0 | 9.3 | 0.0 |
| tests · claude-sonnet-5 | B | 2 | 100% | 100% | 0.075 | 141,248 | 1,206 | 8.0 | 19.2 | 0.5 |

## By case

| case | arm | n | pass | clean | cost $ | context tok | out tok | turns | wall s | failed calls |
|---|---|---|---|---|---|---|---|---|---|---|
| add-alias | A | 2 | 100% | 0% | 0.033 | 68,313 | 576 | 3.5 | 7.8 | 0.0 |
| add-alias | B | 2 | 100% | 100% | 0.098 | 115,707 | 1,251 | 7.0 | 18.6 | 0.0 |
| attrs | A | 2 | 100% | 100% | 0.061 | 165,224 | 1,268 | 6.5 | 16.2 | 0.0 |
| attrs | B | 2 | 100% | 100% | 0.068 | 169,844 | 1,342 | 7.5 | 20.6 | 0.0 |
| bug-matcherror | A | 2 | 100% | 100% | 0.069 | 188,668 | 2,806 | 8.0 | 27.1 | 0.5 |
| bug-matcherror | B | 2 | 100% | 100% | 0.081 | 270,690 | 2,500 | 10.0 | 32.4 | 0.0 |
| bug-receipt-total | A | 2 | 100% | 100% | 0.049 | 127,048 | 1,214 | 6.0 | 14.2 | 0.0 |
| bug-receipt-total | B | 2 | 100% | 100% | 0.084 | 291,546 | 2,330 | 12.5 | 28.4 | 1.5 |
| change-signature | A | 2 | 100% | 0% | 0.078 | 227,732 | 3,000 | 10.0 | 28.3 | 0.0 |
| change-signature | B | 2 | 100% | 100% | 0.174 | 551,724 | 4,313 | 20.0 | 52.7 | 0.5 |
| doctest-line | A | 2 | 100% | 100% | 0.039 | 89,050 | 778 | 5.0 | 10.1 | 0.0 |
| doctest-line | B | 2 | 100% | 100% | 0.050 | 151,778 | 1,016 | 6.5 | 17.5 | 0.0 |
| explore-callers | A | 2 | 100% | 100% | 0.070 | 175,404 | 1,336 | 6.5 | 14.6 | 0.0 |
| explore-callers | B | 2 | 100% | 100% | 0.057 | 107,500 | 1,236 | 6.0 | 15.4 | 0.0 |
| explore-config | A | 2 | 100% | 100% | 0.043 | 114,276 | 912 | 5.5 | 11.8 | 0.0 |
| explore-config | B | 2 | 100% | 100% | 0.046 | 126,110 | 876 | 5.0 | 16.2 | 0.0 |
| move-function | A | 2 | 100% | 100% | 0.082 | 277,846 | 2,644 | 12.5 | 28.7 | 0.0 |
| move-function | B | 2 | 100% | 100% | 0.120 | 409,425 | 3,534 | 21.0 | 44.2 | 1.0 |
| new-component | A | 2 | 100% | 100% | 0.072 | 203,767 | 2,394 | 11.0 | 24.8 | 0.0 |
| new-component | B | 2 | 100% | 100% | 0.113 | 381,948 | 3,495 | 16.5 | 36.3 | 1.5 |
| new-fn-large | A | 2 | 100% | 100% | 0.083 | 235,434 | 2,167 | 9.5 | 21.5 | 0.5 |
| new-fn-large | B | 2 | 100% | 100% | 0.110 | 263,872 | 1,788 | 9.0 | 24.5 | 0.0 |
| new-module | A | 2 | 100% | 100% | 0.067 | 177,110 | 2,603 | 8.0 | 26.1 | 1.0 |
| new-module | B | 2 | 100% | 100% | 0.071 | 201,972 | 2,339 | 8.5 | 34.5 | 0.0 |
| not-compiling | A | 2 | 100% | 50% | 0.062 | 182,994 | 1,880 | 8.5 | 20.6 | 0.0 |
| not-compiling | B | 2 | 100% | 50% | 0.103 | 340,481 | 3,030 | 17.5 | 40.9 | 3.0 |
| oneline | A | 2 | 100% | 100% | 0.038 | 91,794 | 818 | 5.5 | 9.3 | 0.0 |
| oneline | B | 2 | 100% | 100% | 0.077 | 220,644 | 1,662 | 11.0 | 25.9 | 1.0 |
| rename-across | A | 2 | 100% | 0% | 0.091 | 346,406 | 2,342 | 13.0 | 26.9 | 0.0 |
| rename-across | B | 2 | 100% | 100% | 0.060 | 188,212 | 1,623 | 7.5 | 29.0 | 0.5 |
| styler | A | 2 | 100% | 50% | 0.052 | 150,274 | 1,639 | 7.0 | 19.4 | 0.5 |
| styler | B | 2 | 100% | 100% | 0.084 | 250,088 | 1,966 | 12.0 | 28.4 | 0.5 |
| test-tmpdir | A | 2 | 100% | 100% | 0.054 | 137,948 | 1,722 | 8.0 | 19.4 | 0.5 |
| test-tmpdir | B | 2 | 100% | 100% | 0.084 | 241,016 | 2,357 | 12.5 | 30.9 | 1.0 |

## Failed runs


## Tool use by arm

- **A** (34 runs): Bash 3.2, Read 2.1, Edit 1.5, Write 0.1
- **B** (34 runs): Read 2.4, Bash 1.8, menard:run 1.1, menard:block 1.1, menard:outline 0.9, menard:clause 0.9, Edit 0.4, menard:find 0.4, menard:stmt 0.2, menard:attr 0.2, menard:directive 0.2, menard:write 0.1, Skill 0.1, Write 0.1, menard:rename 0.1, menard:module 0.0, menard:deps 0.0

## menard adoption (share of runs)

MCP: called a menard MCP tool. CLI: ran `menard …` or `mix menard.…` through Bash. Skill: loaded the menard skill. Shell edit: wrote a .ex/.exs with sed -i, a redirect or a script. Guard block: an Edit/Write on a .ex/.exs refused by the hook.

| arm · model | n | MCP | CLI | Skill | shell edit | guard block | Edit/Write on .ex |
|---|---|---|---|---|---|---|---|
| A · claude-haiku-4-5 | 17 | 0% | 0% | 0% | 0% | 0% | 88% |
| A · claude-sonnet-5 | 17 | 0% | 0% | 0% | 47% | 0% | 29% |
| B · claude-haiku-4-5 | 17 | 94% | 0% | 12% | 0% | 18% | 29% |
| B · claude-sonnet-5 | 17 | 94% | 0% | 6% | 6% | 24% | 29% |

## Habits (from the traces)

Reads after last edit: Read calls after the run's last edit. Outline of a Read file: `outline` on a file the run had already Read whole. Peak context: the most one model call read.

| arm · model | n | Reads after last edit /run | outline of a Read file /run | peak context |
|---|---|---|---|---|
| A · claude-haiku-4-5 | 17 | 0.47 | 0.00 | 29,388 |
| A · claude-sonnet-5 | 17 | 0.00 | 0.00 | 18,221 |
| B · claude-haiku-4-5 | 17 | 1.41 | 0.53 | 33,850 |
| B · claude-sonnet-5 | 17 | 0.00 | 0.00 | 27,123 |

## Gap signals (menard arms)


### guard_block (8)

- `bug-receipt-total.B.claude-haiku-4-5.1`: PreToolUse:Edit hook error: [bash "$PLUGINS/B/hooks/menard-only.sh"]: Blocked: lib/shop/mailer.ex is an Elixir module. ⏎  ⏎ A module is edited with menard's MCP tools — they parse the file, change the tree and parse-check ⏎ wh
- `not-compiling.B.claude-haiku-4-5.1`: PreToolUse:Edit hook error: [bash "$PLUGINS/B/hooks/menard-only.sh"]: Blocked: lib/shop/product.ex is an Elixir module. ⏎  ⏎ A module is edited with menard's MCP tools — they parse the file, change the tree and parse-check ⏎ w
- `not-compiling.B.claude-haiku-4-5.1`: PreToolUse:Edit hook error: [bash "$PLUGINS/B/hooks/menard-only.sh"]: Blocked: lib/shop/product.ex is an Elixir module. ⏎  ⏎ A module is edited with menard's MCP tools — they parse the file, change the tree and parse-check ⏎ w
- `test-tmpdir.B.claude-haiku-4-5.1`: PreToolUse:Edit hook error: [bash "$PLUGINS/B/hooks/menard-only.sh"]: Blocked: test/shop/mailer_test.exs is an Elixir module. ⏎  ⏎ A module is edited with menard's MCP tools — they parse the file, change the tree and parse-c
- `bug-receipt-total.B.claude-sonnet-5.1`: PreToolUse:Edit hook error: [bash "$PLUGINS/B/hooks/menard-only.sh"]: Blocked: test/shop/mailer_test.exs is an Elixir module. ⏎  ⏎ A module is edited with menard's MCP tools — they parse the file, change the tree and parse-c
- `change-signature.B.claude-sonnet-5.1`: PreToolUse:Edit hook error: [bash "$PLUGINS/B/hooks/menard-only.sh"]: Blocked: test/shop/cart_test.exs is an Elixir module. ⏎  ⏎ A module is edited with menard's MCP tools — they parse the file, change the tree and parse-che
- `oneline.B.claude-sonnet-5.1`: PreToolUse:Edit hook error: [bash "$PLUGINS/B/hooks/menard-only.sh"]: Blocked: test/shop/cart_test.exs is an Elixir module. ⏎  ⏎ A module is edited with menard's MCP tools — they parse the file, change the tree and parse-che
- `test-tmpdir.B.claude-sonnet-5.1`: PreToolUse:Edit hook error: [bash "$PLUGINS/B/hooks/menard-only.sh"]: Blocked: test/shop/mailer_test.exs is an Elixir module. ⏎  ⏎ A module is edited with menard's MCP tools — they parse the file, change the tree and parse-c

### shell_edit_ex (2)

- `move-function.B.claude-sonnet-5.1`: sed -i 's/Cart.format_line(line)/Money.format_line(line)/' lib/shop_web/live/cart_live.ex && sed -i 's/alias Shop.Catalog/alias Shop.Catalog\n  alias Shop.Money/' lib/shop_web/live/cart_live.ex && sed -n 1,12p lib/shop_w
- `move-function.B.claude-sonnet-5.1`: sed -i 's/test "formats a line", "formats a line" do/test "formats a line" do/' test/shop/money_test.exs && sed -n 12,20p test/shop/money_test.exs

### whole_file_write (5)

- `new-module.B.claude-haiku-4-5.1`: ['lib/shop/discounts.ex']
- `new-module.B.claude-haiku-4-5.1`: ['test/shop/discounts_test.exs']
- `new-module.B.claude-sonnet-5.1`: ['lib/shop/discounts.ex']
- `new-module.B.claude-sonnet-5.1`: ['test/shop/discounts_test.exs']
- `not-compiling.B.claude-sonnet-5.1`: ['lib/shop/product.ex']

## menard tool failures (menard arms)

- `bug-receipt-total.B.claude-haiku-4-5.1` menard:attr: attr: verb: expected one of ["get", "set", "delete", "list", "comment"] received "replace"
- `move-function.B.claude-haiku-4-5.1` menard:stmt: no function formats a line/0: `test "formats a line"` is a macro call, not a function — reach it with `block replace FILE test --label "formats a line"` (or get, delete)
- `new-component.B.claude-haiku-4-5.1` menard:block: 2 `test` blocks here — name one with a label: "price" (line 7) · "product card marks out of stock" (line 11)
- `not-compiling.B.claude-haiku-4-5.1` menard:clause: no clause t/0 with head `` — have: none
- `not-compiling.B.claude-haiku-4-5.1` menard:stmt: no clause t/0 with head `` — have: none
- `oneline.B.claude-haiku-4-5.1` menard:stmt: no function shipping is free over the threshold/0: `test "shipping is free over the threshold"` is a macro call, not a function — reach it with `block replace FILE test --label "shipping is free over the threshold"` (or 
- `move-function.B.claude-sonnet-5.1` menard:stmt: no clause test/2 with head `` — have: none
- `new-component.B.claude-sonnet-5.1` menard:block: no ` "product card marks out of stock" do` block here
