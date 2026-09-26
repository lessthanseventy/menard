# menard eval report

Rounds: bench5. 102 runs. Arms: A no menard, B full menard (MCP, guard hook, skill), H only the format-and-parse-check hook, L = B with its MCP tools always loaded, C menard without its hooks.

`pass`: the case's check (hidden tests, compile with warnings as errors, task-specific greps). `clean`: passed, touched only the files the task needs, and `mix format --check-formatted` holds. `context tok`: input + cache read + cache write, summed over the run.

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

## By arm

|  | arm | n | pass | clean | cost $ | context tok | out tok | turns | wall s | failed calls |
|---|---|---|---|---|---|---|---|---|---|---|
| all | A | 34 | 100% | 74% | 0.064 | 169,380 | 1,854 | 7.9 | 20.5 | 0.2 |
| all | B | 34 | 97% | 97% | 0.077 | 214,431 | 1,912 | 9.4 | 24.1 | 0.3 |
| all | H | 34 | 94% | 88% | 0.064 | 160,058 | 1,735 | 7.7 | 19.8 | 0.1 |

## By model

| model | arm | n | pass | clean | cost $ | context tok | out tok | turns | wall s | failed calls |
|---|---|---|---|---|---|---|---|---|---|---|
| claude-haiku-4-5 | A | 17 | 100% | 65% | 0.071 | 267,165 | 2,776 | 11.0 | 30.7 | 0.4 |
| claude-haiku-4-5 | B | 17 | 94% | 94% | 0.072 | 287,498 | 2,458 | 10.5 | 30.4 | 0.4 |
| claude-haiku-4-5 | H | 17 | 88% | 88% | 0.066 | 245,617 | 2,469 | 9.9 | 28.5 | 0.1 |
| claude-sonnet-5 | A | 17 | 100% | 82% | 0.057 | 71,595 | 931 | 4.9 | 10.3 | 0.1 |
| claude-sonnet-5 | B | 17 | 100% | 100% | 0.083 | 141,363 | 1,367 | 8.4 | 17.8 | 0.2 |
| claude-sonnet-5 | H | 17 | 100% | 88% | 0.062 | 74,499 | 1,001 | 5.5 | 11.0 | 0.1 |

## By task kind

| kind | arm | n | pass | clean | cost $ | context tok | out tok | turns | wall s | failed calls |
|---|---|---|---|---|---|---|---|---|---|---|
| bugfix | A | 4 | 100% | 100% | 0.057 | 153,150 | 1,751 | 7.8 | 20.6 | 0.2 |
| bugfix | B | 4 | 100% | 100% | 0.071 | 231,364 | 1,953 | 8.8 | 27.1 | 0.5 |
| bugfix | H | 4 | 100% | 100% | 0.055 | 147,846 | 1,630 | 6.8 | 18.9 | 0.2 |
| hard | A | 6 | 100% | 67% | 0.073 | 173,579 | 1,728 | 7.5 | 20.8 | 0.2 |
| hard | B | 6 | 100% | 100% | 0.085 | 218,515 | 1,798 | 10.0 | 23.9 | 0.2 |
| hard | H | 6 | 100% | 100% | 0.072 | 160,973 | 1,756 | 7.2 | 19.9 | 0.2 |
| new-work | A | 6 | 100% | 83% | 0.074 | 202,238 | 2,630 | 9.2 | 26.2 | 0.7 |
| new-work | B | 6 | 100% | 100% | 0.112 | 308,076 | 2,858 | 13.0 | 31.5 | 0.8 |
| new-work | H | 6 | 83% | 83% | 0.075 | 157,895 | 1,901 | 8.0 | 20.5 | 0.2 |
| overhead | A | 2 | 100% | 100% | 0.039 | 93,213 | 846 | 5.0 | 9.7 | 0.0 |
| overhead | B | 2 | 100% | 100% | 0.056 | 154,604 | 1,195 | 7.0 | 15.8 | 0.0 |
| overhead | H | 2 | 100% | 100% | 0.040 | 103,884 | 881 | 6.0 | 12.1 | 0.0 |
| reading | A | 4 | 100% | 100% | 0.057 | 144,038 | 1,212 | 6.0 | 14.8 | 0.0 |
| reading | B | 4 | 100% | 100% | 0.052 | 117,288 | 1,073 | 5.5 | 13.9 | 0.0 |
| reading | H | 4 | 100% | 100% | 0.051 | 103,721 | 976 | 5.5 | 11.7 | 0.0 |
| refactor | A | 8 | 100% | 25% | 0.071 | 215,538 | 2,315 | 10.1 | 25.0 | 0.2 |
| refactor | B | 8 | 88% | 88% | 0.078 | 235,914 | 2,109 | 10.6 | 26.8 | 0.1 |
| refactor | H | 8 | 88% | 62% | 0.076 | 235,392 | 2,522 | 10.9 | 27.9 | 0.0 |
| tests | A | 4 | 100% | 100% | 0.045 | 101,132 | 1,202 | 6.0 | 13.8 | 0.0 |
| tests | B | 4 | 100% | 100% | 0.055 | 134,994 | 1,429 | 6.8 | 19.1 | 0.5 |
| tests | H | 4 | 100% | 100% | 0.044 | 107,897 | 1,173 | 5.8 | 14.9 | 0.0 |

## By task kind and model

| kind · model | arm | n | pass | clean | cost $ | context tok | out tok | turns | wall s | failed calls |
|---|---|---|---|---|---|---|---|---|---|---|
| bugfix · claude-haiku-4-5 | A | 2 | 100% | 100% | 0.058 | 228,030 | 2,530 | 9.5 | 30.4 | 0.0 |
| bugfix · claude-haiku-4-5 | B | 2 | 100% | 100% | 0.077 | 346,512 | 3,018 | 12.0 | 40.4 | 0.5 |
| bugfix · claude-haiku-4-5 | H | 2 | 100% | 100% | 0.057 | 226,980 | 2,362 | 9.5 | 27.5 | 0.0 |
| bugfix · claude-sonnet-5 | A | 2 | 100% | 100% | 0.056 | 78,271 | 972 | 6.0 | 10.8 | 0.5 |
| bugfix · claude-sonnet-5 | B | 2 | 100% | 100% | 0.066 | 116,216 | 888 | 5.5 | 13.8 | 0.5 |
| bugfix · claude-sonnet-5 | H | 2 | 100% | 100% | 0.052 | 68,713 | 898 | 4.0 | 10.2 | 0.5 |
| hard · claude-haiku-4-5 | A | 3 | 100% | 33% | 0.072 | 267,990 | 2,603 | 10.7 | 30.8 | 0.3 |
| hard · claude-haiku-4-5 | B | 3 | 100% | 100% | 0.089 | 298,144 | 2,330 | 10.7 | 30.8 | 0.3 |
| hard · claude-haiku-4-5 | H | 3 | 100% | 100% | 0.070 | 242,940 | 2,620 | 10.0 | 28.5 | 0.3 |
| hard · claude-sonnet-5 | A | 3 | 100% | 100% | 0.074 | 79,168 | 853 | 4.3 | 10.8 | 0.0 |
| hard · claude-sonnet-5 | B | 3 | 100% | 100% | 0.082 | 138,886 | 1,266 | 9.3 | 17.1 | 0.0 |
| hard · claude-sonnet-5 | H | 3 | 100% | 100% | 0.074 | 79,006 | 891 | 4.3 | 11.4 | 0.0 |
| new-work · claude-haiku-4-5 | A | 3 | 100% | 67% | 0.087 | 323,667 | 3,903 | 12.3 | 39.1 | 1.3 |
| new-work · claude-haiku-4-5 | B | 3 | 100% | 100% | 0.083 | 363,030 | 3,110 | 12.7 | 34.6 | 1.0 |
| new-work · claude-haiku-4-5 | H | 3 | 67% | 67% | 0.063 | 219,148 | 2,263 | 8.3 | 26.0 | 0.3 |
| new-work · claude-sonnet-5 | A | 3 | 100% | 100% | 0.061 | 80,809 | 1,356 | 6.0 | 13.3 | 0.0 |
| new-work · claude-sonnet-5 | B | 3 | 100% | 100% | 0.141 | 253,123 | 2,606 | 13.3 | 28.4 | 0.7 |
| new-work · claude-sonnet-5 | H | 3 | 100% | 100% | 0.087 | 96,642 | 1,538 | 7.7 | 14.9 | 0.0 |
| overhead · claude-haiku-4-5 | A | 1 | 100% | 100% | 0.040 | 137,369 | 1,249 | 6.0 | 14.0 | 0.0 |
| overhead · claude-haiku-4-5 | B | 1 | 100% | 100% | 0.048 | 194,459 | 1,369 | 7.0 | 17.3 | 0.0 |
| overhead · claude-haiku-4-5 | H | 1 | 100% | 100% | 0.043 | 158,854 | 1,474 | 9.0 | 18.5 | 0.0 |
| overhead · claude-sonnet-5 | A | 1 | 100% | 100% | 0.038 | 49,057 | 443 | 4.0 | 5.3 | 0.0 |
| overhead · claude-sonnet-5 | B | 1 | 100% | 100% | 0.065 | 114,748 | 1,021 | 7.0 | 14.2 | 0.0 |
| overhead · claude-sonnet-5 | H | 1 | 100% | 100% | 0.036 | 48,913 | 288 | 3.0 | 5.7 | 0.0 |
| reading · claude-haiku-4-5 | A | 2 | 100% | 100% | 0.066 | 228,184 | 1,789 | 8.5 | 21.6 | 0.0 |
| reading · claude-haiku-4-5 | B | 2 | 100% | 100% | 0.049 | 143,964 | 1,497 | 6.5 | 17.6 | 0.0 |
| reading · claude-haiku-4-5 | H | 2 | 100% | 100% | 0.053 | 138,977 | 1,378 | 7.0 | 15.8 | 0.0 |
| reading · claude-sonnet-5 | A | 2 | 100% | 100% | 0.047 | 59,892 | 636 | 3.5 | 8.0 | 0.0 |
| reading · claude-sonnet-5 | B | 2 | 100% | 100% | 0.054 | 90,612 | 650 | 4.5 | 10.2 | 0.0 |
| reading · claude-sonnet-5 | H | 2 | 100% | 100% | 0.048 | 68,466 | 574 | 4.0 | 7.6 | 0.0 |
| refactor · claude-haiku-4-5 | A | 4 | 100% | 25% | 0.090 | 361,912 | 3,656 | 15.8 | 39.3 | 0.2 |
| refactor · claude-haiku-4-5 | B | 4 | 75% | 75% | 0.076 | 348,673 | 2,814 | 12.5 | 34.5 | 0.2 |
| refactor · claude-haiku-4-5 | H | 4 | 75% | 75% | 0.092 | 395,794 | 3,774 | 14.2 | 43.4 | 0.0 |
| refactor · claude-sonnet-5 | A | 4 | 100% | 25% | 0.053 | 69,165 | 974 | 4.5 | 10.6 | 0.2 |
| refactor · claude-sonnet-5 | B | 4 | 100% | 100% | 0.079 | 123,154 | 1,403 | 8.8 | 19.2 | 0.0 |
| refactor · claude-sonnet-5 | H | 4 | 100% | 50% | 0.060 | 74,990 | 1,271 | 7.5 | 12.4 | 0.0 |
| tests · claude-haiku-4-5 | A | 2 | 100% | 100% | 0.040 | 134,692 | 1,584 | 6.5 | 18.8 | 0.0 |
| tests · claude-haiku-4-5 | B | 2 | 100% | 100% | 0.048 | 166,922 | 1,902 | 7.5 | 24.6 | 0.5 |
| tests · claude-haiku-4-5 | H | 2 | 100% | 100% | 0.043 | 157,638 | 1,636 | 7.0 | 21.4 | 0.0 |
| tests · claude-sonnet-5 | A | 2 | 100% | 100% | 0.049 | 67,572 | 820 | 5.5 | 8.8 | 0.0 |
| tests · claude-sonnet-5 | B | 2 | 100% | 100% | 0.061 | 103,066 | 956 | 6.0 | 13.7 | 0.5 |
| tests · claude-sonnet-5 | H | 2 | 100% | 100% | 0.045 | 58,156 | 710 | 4.5 | 8.4 | 0.0 |

## By case

| case | arm | n | pass | clean | cost $ | context tok | out tok | turns | wall s | failed calls |
|---|---|---|---|---|---|---|---|---|---|---|
| add-alias | A | 2 | 100% | 0% | 0.039 | 77,741 | 774 | 4.5 | 10.2 | 0.5 |
| add-alias | B | 2 | 100% | 100% | 0.044 | 85,455 | 842 | 5.0 | 13.9 | 0.0 |
| add-alias | H | 2 | 100% | 100% | 0.038 | 76,978 | 756 | 4.5 | 10.4 | 0.0 |
| attrs | A | 2 | 100% | 100% | 0.090 | 141,110 | 1,069 | 5.5 | 12.9 | 0.0 |
| attrs | B | 2 | 100% | 100% | 0.100 | 206,927 | 1,554 | 8.0 | 23.7 | 0.0 |
| attrs | H | 2 | 100% | 100% | 0.091 | 142,840 | 1,030 | 5.5 | 13.5 | 0.0 |
| bug-matcherror | A | 2 | 100% | 100% | 0.060 | 157,522 | 2,020 | 8.0 | 22.9 | 0.0 |
| bug-matcherror | B | 2 | 100% | 100% | 0.074 | 222,253 | 2,206 | 8.5 | 27.6 | 0.5 |
| bug-matcherror | H | 2 | 100% | 100% | 0.059 | 157,172 | 1,939 | 7.0 | 22.0 | 0.5 |
| bug-receipt-total | A | 2 | 100% | 100% | 0.054 | 148,778 | 1,482 | 7.5 | 18.4 | 0.5 |
| bug-receipt-total | B | 2 | 100% | 100% | 0.069 | 240,474 | 1,700 | 9.0 | 26.5 | 0.5 |
| bug-receipt-total | H | 2 | 100% | 100% | 0.050 | 138,521 | 1,322 | 6.5 | 15.8 | 0.0 |
| change-signature | A | 2 | 100% | 0% | 0.094 | 332,440 | 3,450 | 13.0 | 37.0 | 0.0 |
| change-signature | B | 2 | 50% | 50% | 0.083 | 196,774 | 2,890 | 11.5 | 36.8 | 0.0 |
| change-signature | H | 2 | 50% | 0% | 0.079 | 231,115 | 3,076 | 10.5 | 29.6 | 0.0 |
| doctest-line | A | 2 | 100% | 100% | 0.039 | 99,058 | 766 | 5.0 | 10.1 | 0.0 |
| doctest-line | B | 2 | 100% | 100% | 0.049 | 126,860 | 1,110 | 5.5 | 17.2 | 0.0 |
| doctest-line | H | 2 | 100% | 100% | 0.039 | 98,970 | 754 | 5.0 | 10.4 | 0.0 |
| explore-callers | A | 2 | 100% | 100% | 0.073 | 194,338 | 1,502 | 7.5 | 18.2 | 0.0 |
| explore-callers | B | 2 | 100% | 100% | 0.057 | 107,690 | 1,322 | 6.0 | 13.9 | 0.0 |
| explore-callers | H | 2 | 100% | 100% | 0.060 | 105,244 | 1,222 | 6.0 | 13.4 | 0.0 |
| explore-config | A | 2 | 100% | 100% | 0.040 | 93,740 | 922 | 4.5 | 11.3 | 0.0 |
| explore-config | B | 2 | 100% | 100% | 0.046 | 126,886 | 824 | 5.0 | 13.9 | 0.0 |
| explore-config | H | 2 | 100% | 100% | 0.041 | 102,198 | 731 | 5.0 | 9.9 | 0.0 |
| move-function | A | 2 | 100% | 100% | 0.081 | 269,972 | 2,880 | 12.0 | 30.7 | 0.5 |
| move-function | B | 2 | 100% | 100% | 0.133 | 532,896 | 3,590 | 20.5 | 40.4 | 0.5 |
| move-function | H | 2 | 100% | 100% | 0.097 | 293,015 | 3,780 | 17.0 | 40.9 | 0.0 |
| new-component | A | 2 | 100% | 100% | 0.077 | 225,702 | 2,816 | 10.5 | 27.3 | 1.0 |
| new-component | B | 2 | 100% | 100% | 0.126 | 353,288 | 3,824 | 17.5 | 37.9 | 1.0 |
| new-component | H | 2 | 100% | 100% | 0.061 | 148,110 | 2,060 | 8.5 | 22.1 | 0.0 |
| new-fn-large | A | 2 | 100% | 50% | 0.071 | 156,025 | 1,748 | 7.5 | 17.1 | 0.0 |
| new-fn-large | B | 2 | 100% | 100% | 0.135 | 371,222 | 2,544 | 12.5 | 31.4 | 1.0 |
| new-fn-large | H | 2 | 100% | 100% | 0.107 | 199,318 | 1,712 | 8.0 | 20.9 | 0.0 |
| new-module | A | 2 | 100% | 100% | 0.075 | 224,987 | 3,325 | 9.5 | 34.1 | 1.0 |
| new-module | B | 2 | 100% | 100% | 0.077 | 199,720 | 2,206 | 9.0 | 25.1 | 0.5 |
| new-module | H | 2 | 50% | 50% | 0.056 | 126,258 | 1,930 | 7.5 | 18.5 | 0.5 |
| not-compiling | A | 2 | 100% | 50% | 0.063 | 195,741 | 1,846 | 9.0 | 23.2 | 0.0 |
| not-compiling | B | 2 | 100% | 100% | 0.090 | 300,732 | 2,336 | 13.0 | 28.1 | 0.5 |
| not-compiling | H | 2 | 100% | 100% | 0.063 | 183,422 | 1,909 | 9.0 | 22.7 | 0.0 |
| oneline | A | 2 | 100% | 100% | 0.039 | 93,213 | 846 | 5.0 | 9.7 | 0.0 |
| oneline | B | 2 | 100% | 100% | 0.056 | 154,604 | 1,195 | 7.0 | 15.8 | 0.0 |
| oneline | H | 2 | 100% | 100% | 0.040 | 103,884 | 881 | 6.0 | 12.1 | 0.0 |
| rename-across | A | 2 | 100% | 0% | 0.071 | 182,000 | 2,154 | 11.0 | 22.0 | 0.0 |
| rename-across | B | 2 | 100% | 100% | 0.051 | 128,529 | 1,114 | 5.5 | 16.3 | 0.0 |
| rename-across | H | 2 | 100% | 50% | 0.090 | 340,461 | 2,478 | 11.5 | 30.8 | 0.0 |
| styler | A | 2 | 100% | 50% | 0.065 | 183,887 | 2,268 | 8.0 | 26.1 | 0.5 |
| styler | B | 2 | 100% | 100% | 0.066 | 147,886 | 1,504 | 9.0 | 20.0 | 0.0 |
| styler | H | 2 | 100% | 100% | 0.061 | 156,657 | 2,327 | 7.0 | 23.6 | 0.5 |
| test-tmpdir | A | 2 | 100% | 100% | 0.050 | 103,206 | 1,638 | 7.0 | 17.5 | 0.0 |
| test-tmpdir | B | 2 | 100% | 100% | 0.061 | 143,128 | 1,748 | 8.0 | 21.1 | 1.0 |
| test-tmpdir | H | 2 | 100% | 100% | 0.049 | 116,824 | 1,592 | 6.5 | 19.4 | 0.0 |

## Failed runs

- `change-signature.B.claude-haiku-4-5.1`: FAIL: mix test
- `change-signature.H.claude-haiku-4-5.1`: FAIL: mix test
- `new-module.H.claude-haiku-4-5.1`: FAIL: mix test

## Tool use by arm

- **A** (34 runs): Bash 2.8, Read 2.1, Edit 1.9, Write 0.1, bash 0.0
- **B** (34 runs): Read 2.1, Bash 1.6, menard:run 1.0, menard:clause 0.9, menard:block 0.6, menard:outline 0.5, menard:stmt 0.4, Edit 0.3, menard:find 0.3, menard:directive 0.2, menard:write 0.2, menard:attr 0.1, Skill 0.1, Write 0.1, menard:rename 0.1, Agent 0.0, SendMessage 0.0
- **H** (34 runs): Bash 2.6, Read 2.2, Edit 1.7, Write 0.2

## menard adoption (share of runs)

MCP: called a menard MCP tool. CLI: ran `menard …` or `mix menard.…` through Bash. Skill: loaded the menard skill. Shell edit: wrote a .ex/.exs with sed -i, a redirect or a script. Guard block: an Edit/Write on a .ex/.exs refused by the hook.

| arm · model | n | MCP | CLI | Skill | shell edit | guard block | Edit/Write on .ex |
|---|---|---|---|---|---|---|---|
| A · claude-haiku-4-5 | 17 | 0% | 0% | 0% | 0% | 0% | 88% |
| A · claude-sonnet-5 | 17 | 0% | 0% | 0% | 41% | 6% | 47% |
| B · claude-haiku-4-5 | 17 | 94% | 0% | 0% | 0% | 12% | 18% |
| B · claude-sonnet-5 | 17 | 94% | 0% | 18% | 12% | 18% | 29% |
| H · claude-haiku-4-5 | 17 | 0% | 0% | 0% | 0% | 0% | 88% |
| H · claude-sonnet-5 | 17 | 0% | 0% | 0% | 35% | 0% | 47% |

## Habits (from the traces)

Reads after last edit: Read calls after the run's last edit. Outline of a Read file: `outline` on a file the run had already Read whole. Peak context: the most one model call read.

| arm · model | n | Reads after last edit /run | outline of a Read file /run | peak context |
|---|---|---|---|---|
| A · claude-haiku-4-5 | 17 | 0.53 | 0.00 | 29,744 |
| A · claude-sonnet-5 | 17 | 0.00 | 0.00 | 19,121 |
| B · claude-haiku-4-5 | 17 | 0.71 | 0.29 | 32,790 |
| B · claude-sonnet-5 | 17 | 0.00 | 0.00 | 26,530 |
| H · claude-haiku-4-5 | 17 | 0.53 | 0.00 | 28,967 |
| H · claude-sonnet-5 | 17 | 0.00 | 0.00 | 20,134 |

## Gap signals (menard arms)


### guard_block (5)

- `bug-receipt-total.B.claude-haiku-4-5.1`: PreToolUse:Edit hook error: [bash "$PLUGINS/B/hooks/menard-only.sh"]: Blocked: test/shop/mailer_test.exs is an Elixir module. ⏎  ⏎ A module is edited with menard's MCP tools — they parse the file, change the tree and parse-c
- `not-compiling.B.claude-haiku-4-5.1`: PreToolUse:Edit hook error: [bash "$PLUGINS/B/hooks/menard-only.sh"]: Blocked: lib/shop/product.ex is an Elixir module. ⏎  ⏎ A module is edited with menard's MCP tools — they parse the file, change the tree and parse-check ⏎ w
- `new-component.B.claude-sonnet-5.1`: PreToolUse:Edit hook error: [bash "$PLUGINS/B/hooks/menard-only.sh"]: Blocked: lib/shop_web/components/core_components.ex is an Elixir module. ⏎  ⏎ A module is edited with menard's MCP tools — they parse the file, change the
- `new-fn-large.B.claude-sonnet-5.1`: PreToolUse:Edit hook error: [bash "$PLUGINS/B/hooks/menard-only.sh"]: Blocked: test/shop/orders_test.exs is an Elixir module. ⏎  ⏎ A module is edited with menard's MCP tools — they parse the file, change the tree and parse-c
- `test-tmpdir.B.claude-sonnet-5.1`: PreToolUse:Edit hook error: [bash "$PLUGINS/B/hooks/menard-only.sh"]: Blocked: test/shop/mailer_test.exs is an Elixir module. ⏎  ⏎ A module is edited with menard's MCP tools — they parse the file, change the tree and parse-c

### shell_edit_ex (8)

- `bug-matcherror.H.claude-sonnet-5.1`: python3 - <<'E' ⏎ p='lib/shop/cart.ex' ⏎ s=open(p).read() ⏎ s=s.replace('''    for {sku, qty} <- Enum.sort(items) do ⏎       {:ok, product} = Catalog.fetch_product(sku) ⏎       {product, qty, Catalog.price_with_tax(product) * qty}
- `bug-receipt-total.B.claude-sonnet-5.1`: sed -i 's/{{totl}}/{{total}}/' lib/shop/mailer.ex ⏎ python3 - <<'E' ⏎ p='test/shop/mailer_test.exs' ⏎ s=open(p).read() ⏎ s=s.replace('''  test "subject''','''  test "shows the formatted total, with no placeholder left" do ⏎     bo
- `bug-receipt-total.H.claude-sonnet-5.1`: sed -i 's/{{totl}}/{{total}}/' lib/shop/mailer.ex ⏎ python3 - <<'E' ⏎ p='test/shop/mailer_test.exs' ⏎ s=open(p).read() ⏎ s=s.replace('''  test "subject''','''  test "shows the formatted total with no placeholder left over" do ⏎   
- `change-signature.B.claude-sonnet-5.1`: sed -i 's/Cart.total(@cart)/Cart.total(@cart, Catalog.tax_rate())/' lib/shop_web/live/cart_live.ex && sed -i 's/Cart.total(cart) ==/Cart.total(cart, Shop.Catalog.tax_rate()) ==/' test/shop/cart_test.exs && grep -n "alias
- `change-signature.H.claude-sonnet-5.1`: python3 - <<'E' ⏎ import re ⏎ p='lib/shop/cart.ex' ⏎ s=open(p).read() ⏎ s=s.replace("def lines(%__MODULE__{items: items}) do","def lines(%__MODULE__{items: items}, rate \\\\ Catalog.tax_rate()) do") ⏎ s=s.replace("Catalog.price_wi
- `not-compiling.H.claude-sonnet-5.1`: python3 - <<'E' ⏎ p='lib/shop/product.ex' ⏎ s=open(p).read() ⏎ s=s.replace("stock: 0]","stock: 0, weight: 0]").replace("stock: non_neg_integer()\n","stock: non_neg_integer(),\n          weight: non_neg_integer()\n") ⏎ open(p,'w'
- `oneline.H.claude-sonnet-5.1`: sed -i '33s/499/599/' lib/shop/cart.ex && sed -i '18s/499/599/' test/shop/cart_test.exs && git diff --stat && mix test 2>&1 | tail -5
- `styler.H.claude-sonnet-5.1`: python3 - <<'E' ⏎ p='lib/shop/catalog.ex' ⏎ s=open(p).read() ⏎ s=s.rstrip()[:-3].rstrip()+''' ⏎  ⏎   @doc "The cheapest in-stock product in the category, or nil when there is none." ⏎   def cheapest_in_stock(category) do ⏎     categor

### whole_file_write (6)

- `new-module.B.claude-haiku-4-5.1`: ['lib/shop/discounts.ex']
- `new-module.B.claude-haiku-4-5.1`: ['test/shop/discounts_test.exs']
- `not-compiling.B.claude-haiku-4-5.1`: ['lib/shop/product.ex']
- `new-module.B.claude-sonnet-5.1`: ['lib/shop/discounts.ex']
- `new-module.B.claude-sonnet-5.1`: ['test/shop/discounts_test.exs']
- `not-compiling.B.claude-sonnet-5.1`: ['lib/shop/product.ex']

## menard tool failures (menard arms)

- `move-function.B.claude-haiku-4-5.1` menard:stmt: expected [Mod.]name/arity, got ""
- `new-component.B.claude-haiku-4-5.1` menard:stmt: no statement `  test "product card marks out of stock" do ⏎     html = render_component(&product_card/1, product: Shop.Catalog.get_product!("TEA-2")) ⏎     assert html =~ "Out of stock" ⏎   end` in product card marks out of st
