# menard eval report

Rounds: bench1. 25 runs. Arms: A no menard, B full menard (MCP, guard hook, skill), L = B with its MCP tools always loaded, C menard without its hooks.

`pass`: the case's check (hidden tests, compile with warnings as errors, task-specific greps). `clean`: passed, touched only the files the task needs, and `mix format --check-formatted` holds. `context tok`: input + cache read + cache write, summed over the run.

## By arm

|  | arm | n | pass | clean | cost $ | context tok | out tok | turns | wall s | failed calls |
|---|---|---|---|---|---|---|---|---|---|---|
| all | A | 13 | 100% | 62% | 0.066 | 239,065 | 2,637 | 9.8 | 28.3 | 0.1 |
| all | B | 12 | 83% | 75% | 0.078 | 330,897 | 2,826 | 11.6 | 97.3 | 0.5 |

## By model

| model | arm | n | pass | clean | cost $ | context tok | out tok | turns | wall s | failed calls |
|---|---|---|---|---|---|---|---|---|---|---|
| claude-haiku-4-5 | A | 13 | 100% | 62% | 0.066 | 239,065 | 2,637 | 9.8 | 28.3 | 0.1 |
| claude-haiku-4-5 | B | 12 | 83% | 75% | 0.078 | 330,897 | 2,826 | 11.6 | 97.3 | 0.5 |

## By task kind

| kind | arm | n | pass | clean | cost $ | context tok | out tok | turns | wall s | failed calls |
|---|---|---|---|---|---|---|---|---|---|---|
| bugfix | A | 2 | 100% | 100% | 0.074 | 318,453 | 3,244 | 13.0 | 39.0 | 0.5 |
| bugfix | B | 2 | 100% | 100% | 0.072 | 290,329 | 3,107 | 11.0 | 46.2 | 0.0 |
| hard | A | 2 | 100% | 50% | 0.065 | 212,446 | 2,030 | 8.5 | 25.6 | 0.0 |
| hard | B | 1 | 100% | 100% | 0.062 | 130,755 | 1,243 | 5.0 | 17.8 | 0.0 |
| new-work | A | 3 | 100% | 33% | 0.066 | 223,349 | 2,658 | 8.7 | 25.5 | 0.0 |
| new-work | B | 3 | 100% | 67% | 0.083 | 370,962 | 3,079 | 12.0 | 267.8 | 1.0 |
| reading | A | 2 | 100% | 100% | 0.057 | 176,068 | 1,368 | 6.5 | 17.0 | 0.0 |
| reading | B | 2 | 50% | 50% | 0.045 | 128,525 | 1,286 | 6.0 | 17.5 | 0.0 |
| refactor | A | 3 | 100% | 33% | 0.077 | 303,722 | 3,973 | 13.3 | 38.8 | 0.0 |
| refactor | B | 3 | 67% | 67% | 0.108 | 536,390 | 4,156 | 18.0 | 60.2 | 0.7 |
| tests | A | 1 | 100% | 100% | 0.035 | 112,691 | 1,109 | 5.0 | 12.4 | 0.0 |
| tests | B | 1 | 100% | 100% | 0.062 | 280,239 | 2,183 | 10.0 | 38.1 | 1.0 |

## By task kind and model

| kind · model | arm | n | pass | clean | cost $ | context tok | out tok | turns | wall s | failed calls |
|---|---|---|---|---|---|---|---|---|---|---|
| bugfix · claude-haiku-4-5 | A | 2 | 100% | 100% | 0.074 | 318,453 | 3,244 | 13.0 | 39.0 | 0.5 |
| bugfix · claude-haiku-4-5 | B | 2 | 100% | 100% | 0.072 | 290,329 | 3,107 | 11.0 | 46.2 | 0.0 |
| hard · claude-haiku-4-5 | A | 2 | 100% | 50% | 0.065 | 212,446 | 2,030 | 8.5 | 25.6 | 0.0 |
| hard · claude-haiku-4-5 | B | 1 | 100% | 100% | 0.062 | 130,755 | 1,243 | 5.0 | 17.8 | 0.0 |
| new-work · claude-haiku-4-5 | A | 3 | 100% | 33% | 0.066 | 223,349 | 2,658 | 8.7 | 25.5 | 0.0 |
| new-work · claude-haiku-4-5 | B | 3 | 100% | 67% | 0.083 | 370,962 | 3,079 | 12.0 | 267.8 | 1.0 |
| reading · claude-haiku-4-5 | A | 2 | 100% | 100% | 0.057 | 176,068 | 1,368 | 6.5 | 17.0 | 0.0 |
| reading · claude-haiku-4-5 | B | 2 | 50% | 50% | 0.045 | 128,525 | 1,286 | 6.0 | 17.5 | 0.0 |
| refactor · claude-haiku-4-5 | A | 3 | 100% | 33% | 0.077 | 303,722 | 3,973 | 13.3 | 38.8 | 0.0 |
| refactor · claude-haiku-4-5 | B | 3 | 67% | 67% | 0.108 | 536,390 | 4,156 | 18.0 | 60.2 | 0.7 |
| tests · claude-haiku-4-5 | A | 1 | 100% | 100% | 0.035 | 112,691 | 1,109 | 5.0 | 12.4 | 0.0 |
| tests · claude-haiku-4-5 | B | 1 | 100% | 100% | 0.062 | 280,239 | 2,183 | 10.0 | 38.1 | 1.0 |

## By case

| case | arm | n | pass | clean | cost $ | context tok | out tok | turns | wall s | failed calls |
|---|---|---|---|---|---|---|---|---|---|---|
| add-alias | A | 1 | 100% | 0% | 0.030 | 87,785 | 843 | 4.0 | 9.8 | 0.0 |
| add-alias | B | 1 | 100% | 100% | 0.036 | 106,839 | 1,232 | 5.0 | 17.8 | 1.0 |
| attrs | A | 1 | 100% | 100% | 0.068 | 184,761 | 1,389 | 6.0 | 17.5 | 0.0 |
| attrs | B | 1 | 100% | 100% | 0.062 | 130,755 | 1,243 | 5.0 | 17.8 | 0.0 |
| bug-matcherror | A | 1 | 100% | 100% | 0.080 | 332,012 | 3,645 | 13.0 | 42.6 | 1.0 |
| bug-matcherror | B | 1 | 100% | 100% | 0.078 | 296,341 | 3,773 | 10.0 | 50.6 | 0.0 |
| bug-receipt-total | A | 1 | 100% | 100% | 0.067 | 304,894 | 2,843 | 13.0 | 35.3 | 0.0 |
| bug-receipt-total | B | 1 | 100% | 100% | 0.065 | 284,317 | 2,441 | 12.0 | 41.9 | 0.0 |
| change-signature | A | 1 | 100% | 0% | 0.103 | 378,658 | 6,135 | 17.0 | 54.2 | 0.0 |
| change-signature | B | 1 | 100% | 100% | 0.148 | 757,625 | 5,801 | 26.0 | 82.8 | 0.0 |
| doctest-line | A | 1 | 100% | 100% | 0.035 | 112,691 | 1,109 | 5.0 | 12.4 | 0.0 |
| doctest-line | B | 1 | 100% | 100% | 0.062 | 280,239 | 2,183 | 10.0 | 38.1 | 1.0 |
| explore-callers | A | 1 | 100% | 100% | 0.080 | 241,333 | 1,668 | 8.0 | 20.0 | 0.0 |
| explore-callers | B | 1 | 0% | 0% | 0.049 | 120,478 | 1,113 | 5.0 | 15.8 | 0.0 |
| explore-config | A | 1 | 100% | 100% | 0.034 | 110,803 | 1,067 | 5.0 | 14.0 | 0.0 |
| explore-config | B | 1 | 100% | 100% | 0.041 | 136,572 | 1,460 | 7.0 | 19.1 | 0.0 |
| move-function | A | 1 | 100% | 100% | 0.099 | 444,723 | 4,941 | 19.0 | 52.3 | 0.0 |
| move-function | B | 1 | 0% | 0% | 0.140 | 744,707 | 5,435 | 23.0 | 80.0 | 1.0 |
| new-component | A | 1 | 100% | 0% | 0.064 | 258,678 | 2,858 | 11.0 | 28.2 | 0.0 |
| new-component | B | 1 | 100% | 0% | 0.090 | 408,796 | 4,092 | 14.0 | 681.3 | 3.0 |
| new-fn-large | A | 1 | 100% | 0% | 0.079 | 223,057 | 2,546 | 7.0 | 24.8 | 0.0 |
| new-fn-large | B | 1 | 100% | 100% | 0.099 | 449,252 | 2,843 | 13.0 | 55.7 | 0.0 |
| new-module | A | 1 | 100% | 100% | 0.054 | 188,313 | 2,571 | 8.0 | 23.6 | 0.0 |
| new-module | B | 1 | 100% | 100% | 0.061 | 254,838 | 2,302 | 9.0 | 66.5 | 0.0 |
| not-compiling | A | 1 | 100% | 0% | 0.062 | 240,131 | 2,670 | 11.0 | 33.6 | 0.0 |

## Failed runs

- `explore-callers.B.claude-haiku-4-5.1`: FAIL: callers: got [Shop.Cart.lines/1 Shop.Orders.total/1] want [Shop.Cart.lines/1 Shop.Orders.total/1 ShopWeb.CartLive.render/1 ShopWeb.CoreComponents.product_card/1]
- `move-function.B.claude-haiku-4-5.1`: FAIL: does not compile clean

## Tool use by arm

- **A** (13 runs): Read 3.3, Bash 3.0, Edit 2.2, Write 0.3
- **B** (12 runs): Read 3.8, Bash 1.5, menard:clause 1.1, menard:outline 1.1, menard:run 0.9, menard:block 0.6, menard:directive 0.3, menard:stmt 0.2, menard:attr 0.2, menard:write 0.2, Edit 0.2, Write 0.2, Skill 0.1, menard:find 0.1

## menard adoption (share of runs)

MCP: called a menard MCP tool. CLI: ran `menard …` or `mix menard.…` through Bash. Skill: loaded the menard skill. Shell edit: wrote a .ex/.exs with sed -i, a redirect or a script. Guard block: an Edit/Write on a .ex/.exs refused by the hook.

| arm · model | n | MCP | CLI | Skill | shell edit | guard block | Edit/Write on .ex |
|---|---|---|---|---|---|---|---|
| A · claude-haiku-4-5 | 13 | 0% | 0% | 0% | 0% | 0% | 85% |
| B · claude-haiku-4-5 | 12 | 92% | 0% | 8% | 0% | 0% | 17% |

## Gap signals (menard arms)


### whole_file_write (3)

- `new-component.B.claude-haiku-4-5.1`: ['test/shop_web/core_components_test.exs']
- `new-module.B.claude-haiku-4-5.1`: ['lib/shop/discounts.ex']
- `new-module.B.claude-haiku-4-5.1`: ['test/shop/discounts_test.exs']

## menard tool failures (menard arms)

- `add-alias.B.claude-haiku-4-5.1` menard:stmt: no statement `Catalog.price_with_tax(%Shop.Product{sku: "", name: "", price: Cart.shipping(@cart)}) > 0` in render/1 — have: `~H""" ⏎     <section id="catalog"> ⏎       <.product_card :for={product <- @products} product={pro
- `doctest-line.B.claude-haiku-4-5.1` menard:clause: key :head not found in: ⏎  ⏎     %{ ⏎       file: "lib/shop/money.ex", ⏎       text: "Formats cents for display.\n\n    iex> Shop.Money.format(1234)\n    \"$12.34\"\n\n    iex> Shop.Money.format(-1234)\n    \"-$12.34\"", ⏎       v
- `move-function.B.claude-haiku-4-5.1` menard:stmt: expected [Mod.]name/arity, got "format_a_line"
- `new-component.B.claude-haiku-4-5.1` menard:stmt: no statement `<p :if={!Catalog.in_stock?(@product)} class="out">Out of stock</p>` in product_card/1 — have: `~H""" ⏎     <div class="product" id={"product-#{@product.sku}"}> ⏎       <h3>{@product.name}</h3> ⏎       <.price cen
- `new-component.B.claude-haiku-4-5.1` menard:block: CODE is the block's BODY here, and this looks like a whole `test` block — pass what goes inside it
- `new-component.B.claude-haiku-4-5.1` menard:run: MCP server "plugin:menard:menard" tool "run" timed out after 620s
