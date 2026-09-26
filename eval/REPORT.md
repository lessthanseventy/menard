# menard eval report

Rounds: focus1. 7 runs. Arms: A no menard, hook menard as it ships: the formatting hook (B from bench6 on), cli hook, plus a few lines at session start teaching menard's CLI (rename, find, outline), grep hook, plus each Elixir grep hit's enclosing function, map hook, plus a map of the project's modules and public functions at session start, lazy-mcp hook, plus manos with its tools loaded on demand (behind ToolSearch) and routing instructions, M menard's hook plus manos (the MCP tools and their skill).

`pass`: the case's check (hidden tests, compile with warnings as errors, task-specific greps). `clean`: passed, touched only the files the task needs, and `mix format --check-formatted` holds. Tokens are per run, summed over its model calls: `new in` is input the model had not seen (uncached input + cache writes), `cached in` is input read from the prompt cache, `out` is output. `credo left`: credo issues in the project after the run, whose base has none; `ran gate`: runs where the agent ran precommit, credo or `run check` itself. `CI green 1st`: the project's CI passed as the agent left it; `tok to green`: new input + output until CI was green, the rounds of fixing it included.

## By arm

|  | arm | n | pass | clean | new in tok | cached in tok | out tok | turns | wall s | failed calls | credo left | ran gate | CI green 1st | tok to green |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| all | A | 1 | 100% | 0% | 32,409 | 609,172 | 6,721 | 21.0 | 135.1 | 0.0 | 0.0 | 0% | – | – |
| all | hook | 1 | 100% | 100% | 27,170 | 590,573 | 6,183 | 22.0 | 209.3 | 1.0 | 0.0 | 0% | – | – |
| all | cli | 1 | 100% | 100% | 29,876 | 708,795 | 6,989 | 24.0 | 250.0 | 0.0 | 0.0 | 0% | – | – |
| all | grep | 1 | 100% | 100% | 32,601 | 734,354 | 6,812 | 23.0 | 247.9 | 0.0 | 0.0 | 0% | – | – |
| all | map | 1 | 100% | 100% | 30,122 | 677,884 | 6,097 | 24.0 | 176.9 | 0.0 | 0.0 | 0% | – | – |
| all | lazy-mcp | 1 | 100% | 100% | 33,777 | 742,233 | 6,324 | 27.0 | 228.4 | 0.0 | 0.0 | 100% | – | – |
| all | M | 1 | 100% | 100% | 45,681 | 727,014 | 6,449 | 23.0 | 247.6 | 0.0 | 0.0 | 0% | – | – |

## By model

| model | arm | n | pass | clean | new in tok | cached in tok | out tok | turns | wall s | failed calls | credo left | ran gate | CI green 1st | tok to green |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| claude-sonnet-5 | A | 1 | 100% | 0% | 32,409 | 609,172 | 6,721 | 21.0 | 135.1 | 0.0 | 0.0 | 0% | – | – |
| claude-sonnet-5 | hook | 1 | 100% | 100% | 27,170 | 590,573 | 6,183 | 22.0 | 209.3 | 1.0 | 0.0 | 0% | – | – |
| claude-sonnet-5 | cli | 1 | 100% | 100% | 29,876 | 708,795 | 6,989 | 24.0 | 250.0 | 0.0 | 0.0 | 0% | – | – |
| claude-sonnet-5 | grep | 1 | 100% | 100% | 32,601 | 734,354 | 6,812 | 23.0 | 247.9 | 0.0 | 0.0 | 0% | – | – |
| claude-sonnet-5 | map | 1 | 100% | 100% | 30,122 | 677,884 | 6,097 | 24.0 | 176.9 | 0.0 | 0.0 | 0% | – | – |
| claude-sonnet-5 | lazy-mcp | 1 | 100% | 100% | 33,777 | 742,233 | 6,324 | 27.0 | 228.4 | 0.0 | 0.0 | 100% | – | – |
| claude-sonnet-5 | M | 1 | 100% | 100% | 45,681 | 727,014 | 6,449 | 23.0 | 247.6 | 0.0 | 0.0 | 0% | – | – |

## By task kind

| kind | arm | n | pass | clean | new in tok | cached in tok | out tok | turns | wall s | failed calls | credo left | ran gate | CI green 1st | tok to green |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| long | A | 1 | 100% | 0% | 32,409 | 609,172 | 6,721 | 21.0 | 135.1 | 0.0 | 0.0 | 0% | – | – |
| long | hook | 1 | 100% | 100% | 27,170 | 590,573 | 6,183 | 22.0 | 209.3 | 1.0 | 0.0 | 0% | – | – |
| long | cli | 1 | 100% | 100% | 29,876 | 708,795 | 6,989 | 24.0 | 250.0 | 0.0 | 0.0 | 0% | – | – |
| long | grep | 1 | 100% | 100% | 32,601 | 734,354 | 6,812 | 23.0 | 247.9 | 0.0 | 0.0 | 0% | – | – |
| long | map | 1 | 100% | 100% | 30,122 | 677,884 | 6,097 | 24.0 | 176.9 | 0.0 | 0.0 | 0% | – | – |
| long | lazy-mcp | 1 | 100% | 100% | 33,777 | 742,233 | 6,324 | 27.0 | 228.4 | 0.0 | 0.0 | 100% | – | – |
| long | M | 1 | 100% | 100% | 45,681 | 727,014 | 6,449 | 23.0 | 247.6 | 0.0 | 0.0 | 0% | – | – |

## By task kind and model

| kind · model | arm | n | pass | clean | new in tok | cached in tok | out tok | turns | wall s | failed calls | credo left | ran gate | CI green 1st | tok to green |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| long · claude-sonnet-5 | A | 1 | 100% | 0% | 32,409 | 609,172 | 6,721 | 21.0 | 135.1 | 0.0 | 0.0 | 0% | – | – |
| long · claude-sonnet-5 | hook | 1 | 100% | 100% | 27,170 | 590,573 | 6,183 | 22.0 | 209.3 | 1.0 | 0.0 | 0% | – | – |
| long · claude-sonnet-5 | cli | 1 | 100% | 100% | 29,876 | 708,795 | 6,989 | 24.0 | 250.0 | 0.0 | 0.0 | 0% | – | – |
| long · claude-sonnet-5 | grep | 1 | 100% | 100% | 32,601 | 734,354 | 6,812 | 23.0 | 247.9 | 0.0 | 0.0 | 0% | – | – |
| long · claude-sonnet-5 | map | 1 | 100% | 100% | 30,122 | 677,884 | 6,097 | 24.0 | 176.9 | 0.0 | 0.0 | 0% | – | – |
| long · claude-sonnet-5 | lazy-mcp | 1 | 100% | 100% | 33,777 | 742,233 | 6,324 | 27.0 | 228.4 | 0.0 | 0.0 | 100% | – | – |
| long · claude-sonnet-5 | M | 1 | 100% | 100% | 45,681 | 727,014 | 6,449 | 23.0 | 247.6 | 0.0 | 0.0 | 0% | – | – |

## By case

| case | arm | n | pass | clean | new in tok | cached in tok | out tok | turns | wall s | failed calls | credo left | ran gate | CI green 1st | tok to green |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| cart-refactor | A | 1 | 100% | 0% | 32,409 | 609,172 | 6,721 | 21.0 | 135.1 | 0.0 | 0.0 | 0% | – | – |
| cart-refactor | hook | 1 | 100% | 100% | 27,170 | 590,573 | 6,183 | 22.0 | 209.3 | 1.0 | 0.0 | 0% | – | – |
| cart-refactor | cli | 1 | 100% | 100% | 29,876 | 708,795 | 6,989 | 24.0 | 250.0 | 0.0 | 0.0 | 0% | – | – |
| cart-refactor | grep | 1 | 100% | 100% | 32,601 | 734,354 | 6,812 | 23.0 | 247.9 | 0.0 | 0.0 | 0% | – | – |
| cart-refactor | map | 1 | 100% | 100% | 30,122 | 677,884 | 6,097 | 24.0 | 176.9 | 0.0 | 0.0 | 0% | – | – |
| cart-refactor | lazy-mcp | 1 | 100% | 100% | 33,777 | 742,233 | 6,324 | 27.0 | 228.4 | 0.0 | 0.0 | 100% | – | – |
| cart-refactor | M | 1 | 100% | 100% | 45,681 | 727,014 | 6,449 | 23.0 | 247.6 | 0.0 | 0.0 | 0% | – | – |

## Failed runs


## Tool use by arm

- **A** (1 runs): Bash 15.0
- **hook** (1 runs): Bash 15.0, bash 1.0
- **cli** (1 runs): Bash 18.0
- **grep** (1 runs): Bash 17.0
- **map** (1 runs): Bash 18.0
- **lazy-mcp** (1 runs): Bash 17.0, menard:run 2.0, ToolSearch 1.0, menard:rename 1.0
- **M** (1 runs): Bash 17.0

## menard adoption (share of runs)

MCP: called a menard MCP tool. CLI: ran `menard …` or `mix menard.…` through Bash. Skill: loaded the menard skill. Shell edit: wrote a .ex/.exs with sed -i, a redirect or a script. Guard block: an Edit/Write on a .ex/.exs refused by the hook.

| arm · model | n | MCP | CLI | Skill | shell edit | guard block | Edit/Write on .ex |
|---|---|---|---|---|---|---|---|
| A · claude-sonnet-5 | 1 | 0% | 0% | 0% | 100% | 0% | 0% |
| M · claude-sonnet-5 | 1 | 0% | 0% | 0% | 100% | 0% | 0% |
| cli · claude-sonnet-5 | 1 | 0% | 0% | 0% | 100% | 0% | 0% |
| grep · claude-sonnet-5 | 1 | 0% | 0% | 0% | 100% | 0% | 0% |
| hook · claude-sonnet-5 | 1 | 0% | 0% | 0% | 100% | 0% | 0% |
| lazy-mcp · claude-sonnet-5 | 1 | 100% | 0% | 0% | 100% | 0% | 0% |
| map · claude-sonnet-5 | 1 | 0% | 0% | 0% | 100% | 0% | 0% |

## Habits (from the traces)

Reads after last edit: Read calls after the run's last edit. Outline of a Read file: `outline` on a file the run had already Read whole. Peak context: the most one model call read.

| arm · model | n | Reads after last edit /run | outline of a Read file /run | peak context |
|---|---|---|---|---|

## Gap signals (menard arms)


### shell_edit_ex (32)

- `cart-refactor.hook.claude-sonnet-5.1`: python3 - <<'E' ⏎ import re ⏎ p='lib/shop/cart.ex' ⏎ s=open(p).read() ⏎ s=s.replace('''  def total(%__MODULE__{} = cart) do ⏎     cart |> lines() |> Enum.map(fn {_product, _qty, amount} -> amount end) |> Enum.sum() ⏎   end''','''  d
- `cart-refactor.hook.claude-sonnet-5.1`: python3 - <<'E' ⏎ p='lib/shop/cart.ex' ⏎ s=open(p).read() ⏎ s=s.replace('''  def format_line({product, qty, amount}) do ⏎     "#{qty} x #{product.name}: #{Money.format(amount)}" ⏎   end ⏎  ⏎ ''','') ⏎ s=s.replace('Enum.map(&format_line/
- `cart-refactor.hook.claude-sonnet-5.1`: python3 - <<'E' ⏎ p='lib/shop/orders.ex' ⏎ s=open(p).read() ⏎ a='  def by_status(orders, status), do: Enum.filter(orders, &(&1.status == status))\n' ⏎ s=s.replace(a,a+''' ⏎   @doc "How many of `orders` have each status; every stat
- `cart-refactor.hook.claude-sonnet-5.1`: sed -i 's/{{totl}}/{{total}}/' lib/shop/mailer.ex ⏎ python3 - <<'E' ⏎ p='test/shop/mailer_test.exs' ⏎ s=open(p).read() ⏎ s=s.replace('''  test "subject quotes''','''  test "shows the total and leaves no placeholder" do ⏎     mail 
- `cart-refactor.hook.claude-sonnet-5.1`: python3 - <<'E' ⏎ p='lib/shop_web/components/core_components.ex' ⏎ s=open(p).read() ⏎ s=s.replace('''      <p :if={!Catalog.in_stock?(@product)} class="out">Out of stock</p>''','''      <.availability product={@product} />''')
- `cart-refactor.cli.claude-sonnet-5.1`: sed -i -E 's/(^|[^_.a-zA-Z])total\(cart\)/\1total(cart, Catalog.tax_rate())/g' lib/shop/cart.ex ⏎ sed -i -E 's/Cart\.total\((cart|@cart|assigns\.cart|c)\)/Cart.total(\1, Shop.Catalog.tax_rate())/' lib/shop/mailer.ex lib/sh
- `cart-refactor.cli.claude-sonnet-5.1`: python3 - <<'E' ⏎ p='test/shop/mailer_test.exs';s=open(p).read() ⏎ s=s.replace('''  test "subject quotes''','''  test "receipt shows the total and leaves no placeholder" do ⏎     body = Mailer.receipt("Ada", "o1", 1320) ⏎     as
- `cart-refactor.grep.claude-sonnet-5.1`: python3 - <<'E' ⏎ import re ⏎ p='lib/shop/cart.ex' ⏎ s=open(p).read() ⏎ s=s.replace('''  def total(%__MODULE__{} = cart) do ⏎     cart |> lines() |> Enum.map(fn {_product, _qty, amount} -> amount end) |> Enum.sum() ⏎   end''','''  d
- `cart-refactor.grep.claude-sonnet-5.1`: sed -i 's/^  alias Shop.Cart$/  alias Shop.Cart\n  alias Shop.Catalog/' test/shop/cart_test.exs; grep -n "alias" lib/shop/mailer.ex lib/shop_web/live/cart_live.ex | head; mix format; mix test 2>&1 | tail -6; grep -rn "Ca
- `cart-refactor.grep.claude-sonnet-5.1`: python3 - <<'E' ⏎ p='lib/shop/cart.ex' ⏎ s=open(p).read() ⏎ s=s.replace('''  def format_line({product, qty, amount}) do ⏎     "#{qty} x #{product.name}: #{Money.format(amount)}" ⏎   end ⏎  ⏎ ''','') ⏎ s=s.replace('Enum.map(&format_line/
- `cart-refactor.grep.claude-sonnet-5.1`: sed -i 's/^  alias Shop.Catalog$/  alias Shop.Catalog\n  alias Shop.Money/' test/shop/cart_test.exs; mix format; mix test 2>&1 | tail -8
- `cart-refactor.grep.claude-sonnet-5.1`: python3 - <<'E' ⏎ p='lib/shop/orders.ex' ⏎ s=open(p).read() ⏎ a='  def by_status(orders, status), do: Enum.filter(orders, &(&1.status == status))\n' ⏎ s=s.replace(a,a+''' ⏎   @doc "How many of `orders` are in each status; statuses
- `cart-refactor.grep.claude-sonnet-5.1`: sed -i 's/{{totl}}/{{total}}/' lib/shop/mailer.ex ⏎ python3 - <<'E' ⏎ p='test/shop/mailer_test.exs' ⏎ s=open(p).read() ⏎ a='''  test "subject quotes''' ⏎ s=s.replace(a,'''  test "receipt shows the total and leaves no placeholder" 
- `cart-refactor.grep.claude-sonnet-5.1`: python3 - <<'E' ⏎ p='lib/shop_web/components/core_components.ex' ⏎ s=open(p).read() ⏎ s=s.replace('''      <p :if={!Catalog.in_stock?(@product)} class="out">Out of stock</p> ⏎     </div> ⏎     """ ⏎   end ⏎ ''','''      <.availability
- `cart-refactor.map.claude-sonnet-5.1`: python3 - <<'E' ⏎ import re ⏎ p='lib/shop/cart.ex' ⏎ s=open(p).read() ⏎ s=s.replace('''  def total(%__MODULE__{} = cart) do ⏎     cart |> lines() |> Enum.map(fn {_product, _qty, amount} -> amount end) |> Enum.sum() ⏎   end''','''  d
- `cart-refactor.map.claude-sonnet-5.1`: python3 - <<'E' ⏎ p='lib/shop/cart.ex' ⏎ s=open(p).read() ⏎ s=s.replace('''  def format_line({product, qty, amount}) do ⏎     "#{qty} x #{product.name}: #{Money.format(amount)}" ⏎   end ⏎  ⏎ ''','') ⏎ s=s.replace('&format_line/1','&Mone
- `cart-refactor.map.claude-sonnet-5.1`: sed -i 's/Shop\.Money\.format_line(/Money.format_line(/' lib/shop_web/live/cart_live.ex; mix test 2>&1 | tail -3; grep -rn format_line lib test
- `cart-refactor.map.claude-sonnet-5.1`: python3 - <<'E' ⏎ p='lib/shop/orders.ex' ⏎ s=open(p).read() ⏎ a='  def by_status(orders, status), do: Enum.filter(orders, &(&1.status == status))\n' ⏎ s=s.replace(a,a+''' ⏎   @doc "How many of `orders` have each status; every stat
- `cart-refactor.map.claude-sonnet-5.1`: sed -i 's/{{totl}}/{{total}}/' lib/shop/mailer.ex ⏎ python3 - <<'E' ⏎ p='test/shop/mailer_test.exs' ⏎ s=open(p).read() ⏎ a='''  test "subject quotes''' ⏎ s=s.replace(a,'''  test "shows the order id and the total, with no placehold
- `cart-refactor.map.claude-sonnet-5.1`: python3 - <<'E' ⏎ p='lib/shop_web/components/core_components.ex' ⏎ s=open(p).read() ⏎ s=s.replace('''      <p :if={!Catalog.in_stock?(@product)} class="out">Out of stock</p> ⏎     </div> ⏎     """ ⏎   end ⏎ ''','''      <.availability
- `cart-refactor.lazy-mcp.claude-sonnet-5.1`: perl -pi -e 's/(?<![\w.])total\(cart\)/total(cart, Catalog.tax_rate())/g' lib/shop/cart.ex ⏎ perl -pi -e 's/Cart\.total\((\@cart|assigns\.cart|cart)\)/Cart.total($1, Catalog.tax_rate())/g' lib/shop_web/live/cart_live.ex li
- `cart-refactor.lazy-mcp.claude-sonnet-5.1`: sed -i '4a\  alias Shop.Catalog' test/shop/cart_test.exs
- `cart-refactor.lazy-mcp.claude-sonnet-5.1`: python3 - <<'E' ⏎ import re ⏎ p='lib/shop/cart.ex'; s=open(p).read() ⏎ s=s.replace('''  def format_line({product, qty, amount}) do ⏎     "#{qty} x #{product.name}: #{Money.format(amount)}" ⏎   end ⏎  ⏎ ''','') ⏎ s=s.replace('&format_lin
- `cart-refactor.lazy-mcp.claude-sonnet-5.1`: python3 - <<'E' ⏎ p='test/shop/cart_test.exs'; s=open(p).read() ⏎ s=s.replace('''  test "formats a line" do ⏎     [line] = Cart.new() |> Cart.add("MUG-1") |> Cart.lines() ⏎     assert Money.format_line(line) == "1 x Mug: $13.20"
- `cart-refactor.lazy-mcp.claude-sonnet-5.1`: python3 - <<'E' ⏎ p='lib/shop/orders.ex'; s=open(p).read() ⏎ a='  def by_status(orders, status), do: Enum.filter(orders, &(&1.status == status))\n' ⏎ s=s.replace(a,a+''' ⏎   @doc "How many orders have each status; every status i
- `cart-refactor.lazy-mcp.claude-sonnet-5.1`: sed -i 's/{{totl}}/{{total}}/' lib/shop/mailer.ex ⏎ python3 - <<'E' ⏎ p='test/shop/mailer_test.exs'; s=open(p).read() ⏎ s=s.replace('''  test "subject quotes''','''  test "shows the total and leaves no placeholder" do ⏎     mail
- `cart-refactor.lazy-mcp.claude-sonnet-5.1`: python3 - <<'E' ⏎ p='lib/shop_web/components/core_components.ex'; s=open(p).read() ⏎ s=s.replace('''      <p :if={!Catalog.in_stock?(@product)} class="out">Out of stock</p> ⏎ ''','''      <.availability product={@product} /> ⏎ '
- `cart-refactor.M.claude-sonnet-5.1`: sed -i -E 's/(^|[^_a-z.])total\(cart\)/\1total(cart, Catalog.tax_rate())/g' lib/shop/cart.ex ⏎ sed -i -E 's/Cart\.total\((cart|@cart|assigns\.cart)\)/Cart.total(\1, Catalog.tax_rate())/g' lib/shop/mailer.ex lib/shop_web/li
- `cart-refactor.M.claude-sonnet-5.1`: python3 - <<'E' ⏎ import re ⏎ p='lib/shop/cart.ex' ⏎ s=open(p).read() ⏎ s=s.replace('''  def format_line({product, qty, amount}) do ⏎     "#{qty} x #{product.name}: #{Money.format(amount)}" ⏎   end ⏎  ⏎ ''','') ⏎ s=s.replace('Enum.map(&fo
- `cart-refactor.M.claude-sonnet-5.1`: python3 - <<'E' ⏎ p='lib/shop/orders.ex' ⏎ s=open(p).read() ⏎ a='  def by_status(orders, status), do: Enum.filter(orders, &(&1.status == status))\n' ⏎ s=s.replace(a,a+''' ⏎   @doc "How many of `orders` have each status; every stat
- `cart-refactor.M.claude-sonnet-5.1`: sed -i 's/{{totl}}/{{total}}/' lib/shop/mailer.ex ⏎ python3 - <<'E' ⏎ p='test/shop/mailer_test.exs' ⏎ s=open(p).read() ⏎ s=s.replace('''  test "subject quotes''','''  test "receipt shows the total and leaves no placeholder" do ⏎  
- `cart-refactor.M.claude-sonnet-5.1`: python3 - <<'E' ⏎ p='lib/shop_web/components/core_components.ex' ⏎ s=open(p).read() ⏎ s=s.replace('''      <p :if={!Catalog.in_stock?(@product)} class="out">Out of stock</p> ⏎     </div> ⏎     """ ⏎   end ⏎ ''','''      <.availability

## menard tool failures (menard arms)

