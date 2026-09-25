# menard eval report

Rounds: round2. 5 runs. Arms: A no menard, B full menard (MCP, guard hook, skill), L = B with its MCP tools always loaded, C menard without its hooks.

`pass`: the case's check (hidden tests, compile with warnings as errors, task-specific greps). `clean`: passed, touched only the files the task needs, and `mix format --check-formatted` holds. `context tok`: input + cache read + cache write, summed over the run.

## By arm

|  | arm | n | pass | clean | cost $ | context tok | out tok | turns | wall s | failed calls |
|---|---|---|---|---|---|---|---|---|---|---|
| all | A | 2 | 100% | 50% | 0.050 | 137,336 | 1,288 | 5.0 | 16.4 | 0.0 |
| all | B | 1 | 100% | 100% | 0.094 | 404,840 | 4,116 | 16.0 | 57.4 | 6.0 |
| all | L | 1 | 100% | 100% | 0.087 | 194,948 | 1,833 | 8.0 | 28.1 | 2.0 |
| all | C | 1 | 100% | 0% | 0.031 | 89,746 | 918 | 4.0 | 13.7 | 0.0 |

## By model

| model | arm | n | pass | clean | cost $ | context tok | out tok | turns | wall s | failed calls |
|---|---|---|---|---|---|---|---|---|---|---|
| claude-haiku-4-5 | A | 2 | 100% | 50% | 0.050 | 137,336 | 1,288 | 5.0 | 16.4 | 0.0 |
| claude-haiku-4-5 | B | 1 | 100% | 100% | 0.094 | 404,840 | 4,116 | 16.0 | 57.4 | 6.0 |
| claude-haiku-4-5 | L | 1 | 100% | 100% | 0.087 | 194,948 | 1,833 | 8.0 | 28.1 | 2.0 |
| claude-haiku-4-5 | C | 1 | 100% | 0% | 0.031 | 89,746 | 918 | 4.0 | 13.7 | 0.0 |

## By task kind

| kind | arm | n | pass | clean | cost $ | context tok | out tok | turns | wall s | failed calls |
|---|---|---|---|---|---|---|---|---|---|---|
| hard | A | 1 | 100% | 100% | 0.070 | 186,114 | 1,556 | 6.0 | 22.5 | 0.0 |
| refactor | A | 1 | 100% | 0% | 0.031 | 88,559 | 1,019 | 4.0 | 10.2 | 0.0 |
| refactor | B | 1 | 100% | 100% | 0.094 | 404,840 | 4,116 | 16.0 | 57.4 | 6.0 |
| refactor | L | 1 | 100% | 100% | 0.087 | 194,948 | 1,833 | 8.0 | 28.1 | 2.0 |
| refactor | C | 1 | 100% | 0% | 0.031 | 89,746 | 918 | 4.0 | 13.7 | 0.0 |

## By task kind and model

| kind · model | arm | n | pass | clean | cost $ | context tok | out tok | turns | wall s | failed calls |
|---|---|---|---|---|---|---|---|---|---|---|
| hard · claude-haiku-4-5 | A | 1 | 100% | 100% | 0.070 | 186,114 | 1,556 | 6.0 | 22.5 | 0.0 |
| refactor · claude-haiku-4-5 | A | 1 | 100% | 0% | 0.031 | 88,559 | 1,019 | 4.0 | 10.2 | 0.0 |
| refactor · claude-haiku-4-5 | B | 1 | 100% | 100% | 0.094 | 404,840 | 4,116 | 16.0 | 57.4 | 6.0 |
| refactor · claude-haiku-4-5 | L | 1 | 100% | 100% | 0.087 | 194,948 | 1,833 | 8.0 | 28.1 | 2.0 |
| refactor · claude-haiku-4-5 | C | 1 | 100% | 0% | 0.031 | 89,746 | 918 | 4.0 | 13.7 | 0.0 |

## By case

| case | arm | n | pass | clean | cost $ | context tok | out tok | turns | wall s | failed calls |
|---|---|---|---|---|---|---|---|---|---|---|
| add-alias | A | 1 | 100% | 0% | 0.031 | 88,559 | 1,019 | 4.0 | 10.2 | 0.0 |
| add-alias | B | 1 | 100% | 100% | 0.094 | 404,840 | 4,116 | 16.0 | 57.4 | 6.0 |
| add-alias | L | 1 | 100% | 100% | 0.087 | 194,948 | 1,833 | 8.0 | 28.1 | 2.0 |
| add-alias | C | 1 | 100% | 0% | 0.031 | 89,746 | 918 | 4.0 | 13.7 | 0.0 |
| attrs | A | 1 | 100% | 100% | 0.070 | 186,114 | 1,556 | 6.0 | 22.5 | 0.0 |

## Failed runs


## Tool use by arm

- **A** (2 runs): Edit 2.0, Read 1.5, Bash 0.5
- **B** (1 runs): Bash 11.0, Read 2.0, Skill 1.0
- **L** (1 runs): ToolSearch 2.0, Read 1.0, Edit 1.0, menard:directive 1.0, menard:stmt 1.0, menard:clause 1.0
- **C** (1 runs): Edit 2.0, Read 1.0

## menard adoption (share of runs)

MCP: called a menard MCP tool. CLI: ran `menard …` or `mix menard.…` through Bash. Skill: loaded the menard skill. Shell edit: wrote a .ex/.exs with sed -i, a redirect or a script. Guard block: an Edit/Write on a .ex/.exs refused by the hook.

| arm · model | n | MCP | CLI | Skill | shell edit | guard block | Edit/Write on .ex |
|---|---|---|---|---|---|---|---|
| A · claude-haiku-4-5 | 2 | 0% | 0% | 0% | 0% | 0% | 100% |
| B · claude-haiku-4-5 | 1 | 0% | 100% | 100% | 0% | 0% | 0% |
| C · claude-haiku-4-5 | 1 | 0% | 0% | 0% | 0% | 0% | 100% |
| L · claude-haiku-4-5 | 1 | 100% | 0% | 0% | 0% | 100% | 100% |

## Gap signals (menard arms)


### guard_block (1)

- `add-alias.L.claude-haiku-4-5.1`: PreToolUse:Edit hook error: [bash "$PLUGINS/L/hooks/menard-only.sh"]: Blocked: lib/shop_web/live/cart_live.ex is an Elixir module. ⏎  ⏎ A module is edited with menard's MCP tools — they parse the file, change the tree and pa

## menard tool failures (menard arms)

- `add-alias.L.claude-haiku-4-5.1` menard:stmt: no statement `Catalog.price_with_tax(%Shop.Product{sku: "", name: "", price: Cart.shipping(@cart)}) > 0` in render/1 — have: `~H""" ⏎     <section id="catalog"> ⏎       <.product_card :for={product <- @products} product={pro
