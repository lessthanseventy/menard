# menard eval report

Rounds: focus2. 2 runs. Arms: A no menard, all hook, plus run-cli, compile, big-read and stop together.

`pass`: the case's check (hidden tests, compile with warnings as errors, task-specific greps). `clean`: passed, touched only the files the task needs, and `mix format --check-formatted` holds. Tokens are per run, summed over its model calls: `new in` is input the model had not seen (uncached input + cache writes), `cached in` is input read from the prompt cache, `out` is output. `credo left`: credo issues in the project after the run, whose base has none; `ran gate`: runs where the agent ran precommit, credo or `run check` itself. `CI green 1st`: the project's CI passed as the agent left it; `tok to green`: new input + output until CI was green, the rounds of fixing it included.

## By arm

|  | arm | n | pass | clean | new in tok | cached in tok | out tok | turns | wall s | failed calls | credo left | reruns | ran gate | CI green 1st | tok to green |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| all | A | 1 | 100% | 100% | 118,043 | 3,198,875 | 20,140 | 44.0 | 672.2 | 0.0 | 0.0 | 1.0 | 100% | 100% | 138,183 |
| all | all | 1 | 100% | 100% | 97,941 | 2,226,924 | 16,848 | 37.0 | 1088.4 | 2.0 | 0.0 | 4.0 | 100% | 100% | 114,789 |

## By model

| model | arm | n | pass | clean | new in tok | cached in tok | out tok | turns | wall s | failed calls | credo left | reruns | ran gate | CI green 1st | tok to green |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| claude-sonnet-5 | A | 1 | 100% | 100% | 118,043 | 3,198,875 | 20,140 | 44.0 | 672.2 | 0.0 | 0.0 | 1.0 | 100% | 100% | 138,183 |
| claude-sonnet-5 | all | 1 | 100% | 100% | 97,941 | 2,226,924 | 16,848 | 37.0 | 1088.4 | 2.0 | 0.0 | 4.0 | 100% | 100% | 114,789 |

## By task kind

| kind | arm | n | pass | clean | new in tok | cached in tok | out tok | turns | wall s | failed calls | credo left | reruns | ran gate | CI green 1st | tok to green |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| long | A | 1 | 100% | 100% | 118,043 | 3,198,875 | 20,140 | 44.0 | 672.2 | 0.0 | 0.0 | 1.0 | 100% | 100% | 138,183 |
| long | all | 1 | 100% | 100% | 97,941 | 2,226,924 | 16,848 | 37.0 | 1088.4 | 2.0 | 0.0 | 4.0 | 100% | 100% | 114,789 |

## By task kind and model

| kind · model | arm | n | pass | clean | new in tok | cached in tok | out tok | turns | wall s | failed calls | credo left | reruns | ran gate | CI green 1st | tok to green |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| long · claude-sonnet-5 | A | 1 | 100% | 100% | 118,043 | 3,198,875 | 20,140 | 44.0 | 672.2 | 0.0 | 0.0 | 1.0 | 100% | 100% | 138,183 |
| long · claude-sonnet-5 | all | 1 | 100% | 100% | 97,941 | 2,226,924 | 16,848 | 37.0 | 1088.4 | 2.0 | 0.0 | 4.0 | 100% | 100% | 114,789 |

## By case

| case | arm | n | pass | clean | new in tok | cached in tok | out tok | turns | wall s | failed calls | credo left | reruns | ran gate | CI green 1st | tok to green |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| focus | A | 1 | 100% | 100% | 118,043 | 3,198,875 | 20,140 | 44.0 | 672.2 | 0.0 | 0.0 | 1.0 | 100% | 100% | 138,183 |
| focus | all | 1 | 100% | 100% | 97,941 | 2,226,924 | 16,848 | 37.0 | 1088.4 | 2.0 | 0.0 | 4.0 | 100% | 100% | 114,789 |

## Failed runs


## Tool use by arm

- **A** (1 runs): Bash 37.0, Read 2.0
- **all** (1 runs): Bash 28.0, Read 2.0, Edit 2.0

## menard adoption (share of runs)

MCP: called a menard MCP tool. CLI: ran `menard …` or `mix menard.…` through Bash. Skill: loaded the menard skill. Shell edit: wrote a .ex/.exs with sed -i, a redirect or a script. Guard block: an Edit/Write on a .ex/.exs refused by the hook.

| arm · model | n | MCP | CLI | Skill | shell edit | guard block | Edit/Write on .ex |
|---|---|---|---|---|---|---|---|
| A · claude-sonnet-5 | 1 | 0% | 0% | 0% | 100% | 0% | 0% |
| all · claude-sonnet-5 | 1 | 0% | 100% | 0% | 100% | 0% | 100% |

## Habits (from the traces)

Reads after last edit: Read calls after the run's last edit. Outline of a Read file: `outline` on a file the run had already Read whole. Peak context: the most one model call read.

| arm · model | n | Reads after last edit /run | outline of a Read file /run | peak context |
|---|---|---|---|---|
| A · claude-sonnet-5 | 1 | 0.00 | 0.00 | 130,370 |
| all · claude-sonnet-5 | 1 | 0.00 | 0.00 | 110,284 |

## Gap signals (menard arms)


### shell_edit_ex (10)

- `focus.all.claude-sonnet-5.1`: python3 - <<'EOF' ⏎ import re ⏎ p='lib/server/search.ex' ⏎ s=open(p).read() ⏎ s=s.replace('''  The raw query is never interpreted as query syntax: `plainto_tsquery` treats every token as a ⏎   literal term and ANDs them; `fact_rel
- `focus.all.claude-sonnet-5.1`: python3 - <<'EOF' ⏎ p='lib/server/search.ex' ⏎ s=open(p).read() ⏎ a=s.index('  defp parse(query) do') ⏎ b=s.index('  defp part(_, _, word) do') ⏎ s=s[:a]+'''  defp parse(query) do ⏎     for [_all | groups] <- Regex.scan(@query_part,
- `focus.all.claude-sonnet-5.1`: python3 - <<'EOF' ⏎ p='test/server/search_test.exs' ⏎ s=open(p).read() ⏎ s=s.replace('more: 2} = Search.history("deploy -rollback", 3)','more: 3} = Search.history("deploy -rollback", 3)') ⏎ open(p,'w').write(s) ⏎ p='lib/server/sea
- `focus.all.claude-sonnet-5.1`: python3 - <<'EOF' ⏎ p='lib/server/search.ex' ⏎ s=open(p).read() ⏎ blk='''  defp exclusion(""), do: nil ⏎   defp exclusion(word), do: {:out, word} ⏎  ⏎ ''' ⏎ s=s.replace(blk,'') ⏎ i=s.index('  # The same terms, OR-joined') ⏎ s=s[:i]+blk+s[
- `focus.all.claude-sonnet-5.1`: python3 - <<'EOF' ⏎ p='lib/server/staffing.ex' ⏎ s=open(p).read() ⏎ s=s.replace('''  `@funes_thread <id>`) that gets the thread's latest operator message as its opening turn — under''','''  `@funes_thread <id>`) that gets the 
- `focus.all.claude-sonnet-5.1`: python3 - <<'EOF' ⏎ p='lib/server/staffing.ex' ⏎ s=open(p).read() ⏎ s=s.replace('''        operator_post = Channel.latest_operator_message(thread.id) ⏎  ⏎ ''','') ⏎ a=s.index('          nil when not is_map(operator_post)') ⏎ b=s.index
- `focus.all.claude-sonnet-5.1`: python3 - <<'EOF' ⏎ p='lib/server/staffing.ex' ⏎ s=open(p).read() ⏎ a=s.index('          nil ->\n            cond do') ⏎ b=s.index('        end\n      end)\n\n    :ok\n  end',a) ⏎ s=s[:a]+'''          nil -> ⏎             start_leaf
- `focus.all.claude-sonnet-5.1`: python3 - <<'EOF' ⏎ p='test/server/staffing_test.exs' ⏎ s=open(p).read() ⏎ s=s.replace('''    assert [%{body: body}] = Channel.thread_messages(Channel.thread(thread.id)) ⏎     assert body =~ "parked"''','''    assert [%{body: "g
- `focus.all.claude-sonnet-5.1`: python3 - <<'EOF' ⏎ p='lib/server/commits.ex' ⏎ s=open(p).read() ⏎ s=s.replace('["log", "--grep=','["log", "--all", "--grep=') ⏎ open(p,'w').write(s) ⏎ p='test/server/commits_test.exs' ⏎ s=open(p).read() ⏎ s=s.replace('''  test "branc
- `focus.all.claude-sonnet-5.1`: cd /tmp/menard-eval-tlon/runs/focus2/focus.all.claude-sonnet-5.1/server && git mv lib/server/leaf_window.ex lib/server/window_name.ex && git mv test/server/leaf_window_test.exs test/server/window_name_test.exs && sed -i 

## menard tool failures (menard arms)

