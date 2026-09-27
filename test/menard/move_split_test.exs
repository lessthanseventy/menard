defmodule Menard.MoveSplitTest do
  # `clause move` as the tool for splitting a module: several functions in one call, a `defdelegate`
  # left behind for each public one, and what the moved code needs carried with it — its private
  # helpers, the attributes and directives it reads, a call back to the source qualified. Every
  # result is compiled: a split that parses and does not compile, or compiles and warns (an unused
  # alias is a failed --warnings-as-errors build), or compiles and means something else, is the bug.
  use ExUnit.Case, async: true

  @moduletag :tmp_dir

  # The modules the moved code calls out to, compiled once for the whole file.
  setup_all do
    Code.compile_string("""
    defmodule Split1.Tax do
      def add(price, rate), do: price + price * rate
    end

    defmodule Split1.Shop.Stock do
      def take(n), do: n
    end

    defmodule Split1.Greeter.Fns do
      def greet(x), do: "hi " <> x
    end

    defmodule Split1.Greeter do
      defmacro __using__(_opts), do: quote(do: import(Split1.Greeter.Fns))
    end
    """)

    :ok
  end

  # compiled as one file, as the two call each other, with every warning the compiler gave
  defp compile(sources) do
    Code.with_diagnostics(fn -> Code.compile_string(Enum.join(sources, "\n")) end) |> elem(1)
  end

  @shop """
  defmodule Split1.Shop do
    @moduledoc "A shop."

    import Bitwise, only: [band: 2]

    alias Split1.Shop.Stock
    alias Split1.Tax

    # the kinds a tax applies to
    @taxed [:food, :drink]
    @limit 10

    def list(opts \\\\ []), do: Stock.take(Keyword.get(opts, :limit, @limit))

    @doc "The total of `items`, taxed at `rate`."
    @spec total([map()], number()) :: number()
    def total(items, rate \\\\ 0.25) do
      items |> Enum.map(&price(&1, rate)) |> Enum.sum()
    end

    # the tag a receipt carries
    def receipt(items), do: {__MODULE__, count(items), total(items), band(count(items), 1)}

    def count(items), do: length(items)

    defp price(%{kind: kind, price: p}, rate) when kind in @taxed, do: Tax.add(p, rate)
    defp price(%{price: p}, _rate), do: p
  end
  """

  test "a split in one call: two functions out, delegates left, what they need carried", %{tmp_dir: dir} do
    file = Path.join(dir, "shop.ex")
    File.write!(file, @shop)
    dest = Path.join(dir, "shop/pricing.ex")

    assert {:ok, reply} =
             Menard.Move.run(file, dest, ["total/2", "receipt/1"],
               as: "Split1.Shop.Pricing",
               moduledoc: "Prices and receipts.",
               delegate: true
             )

    # the source keeps its API: a delegate where each public function was, its default kept; the
    # alias, import and attribute only the moved code read are gone from it, as they would warn
    assert File.read!(file) == """
           defmodule Split1.Shop do
             @moduledoc "A shop."

             alias Split1.Shop.Pricing
             alias Split1.Shop.Stock

             @limit 10

             def list(opts \\\\ []), do: Stock.take(Keyword.get(opts, :limit, @limit))

             defdelegate total(items, rate \\\\ 0.25), to: Pricing

             defdelegate receipt(items), to: Pricing

             def count(items), do: length(items)
           end
           """

    # the helper only total/2 called came along; the import, alias and attribute (with its comment) it
    # reads, and no
    # other (Stock stays behind); a call back to count/1 and __MODULE__ now name the source
    assert File.read!(dest) == """
           defmodule Split1.Shop.Pricing do
             @moduledoc "Prices and receipts."

             import Bitwise, only: [band: 2]

             alias Split1.Shop
             alias Split1.Tax

             # the kinds a tax applies to
             @taxed [:food, :drink]

             @doc "The total of `items`, taxed at `rate`."
             @spec total([map()], number()) :: number()
             def total(items, rate \\\\ 0.25) do
               items |> Enum.map(&price(&1, rate)) |> Enum.sum()
             end

             # the tag a receipt carries
             def receipt(items), do: {Shop, Shop.count(items), total(items), band(Shop.count(items), 1)}

             defp price(%{kind: kind, price: p}, rate) when kind in @taxed, do: Tax.add(p, rate)
             defp price(%{price: p}, _rate), do: p
           end
           """

    assert %{
             created: "Split1.Shop.Pricing",
             moved: ["total/2", "receipt/1"],
             carried: ["price/2"],
             attributes: ["@taxed"],
             directives: ["import Bitwise, only: [band: 2]", "alias Split1.Shop", "alias Split1.Tax"],
             qualified: ["count/1", "__MODULE__"],
             delegated: ["total/2", "receipt/1"],
             left: [],
             to: %{version: "sha256:" <> _},
             from: %{version: "sha256:" <> _}
           } = reply

    # it compiles without a warning, and means what it meant
    assert compile([File.read!(dest), File.read!(file)]) == []
    items = [%{kind: :food, price: 4}, %{kind: :toy, price: 2}]
    # compiled by the test, so reached at run time: named, the call warns that it is not defined yet
    shop = Module.concat(["Split1.Shop"])
    assert shop.total(items) == 7.0
    assert shop.total(items, 0.5) == 8.0
    assert shop.receipt(items) == {Split1.Shop, 2, 7.0, 0}
    assert {:total, 1} in shop.__info__(:functions)
  end

  test "a private helper that functions staying behind also call is refused, and nothing is written",
       %{tmp_dir: dir} do
    file = Path.join(dir, "fmt.ex")

    src = """
    defmodule Split2 do
      def a(x), do: fmt(x)
      def b(x), do: fmt(x) <> "!"
      defp fmt(x), do: to_string(x)
    end
    """

    File.write!(file, src)
    dest = Path.join(dir, "fmt/out.ex")

    assert {:error, message} = Menard.Move.run(file, dest, ["a/1"], as: "Split2.Out", delegate: true)

    assert message ==
             "refused, nothing written: fmt/1 is private, and b/1 stays and calls it too. Move b/1 as well, " <>
               "or make fmt/1 public first (clause visibility FILE fmt/1 public): the moved code then calls Split2.fmt"

    assert File.read!(file) == src
    refute File.exists?(dest)
  end

  test "without delegate, the calls left pointing at nothing are named", %{tmp_dir: dir} do
    file = Path.join(dir, "calc.ex")

    File.write!(file, """
    defmodule Split3 do
      def a(x), do: x + 1

      def b(x), do: a(x) * 2
    end
    """)

    dest = Path.join(dir, "calc/inc.ex")
    assert {:ok, reply} = Menard.Move.run(file, dest, ["a/1"], as: "Split3.Inc", root: dir)

    assert File.read!(file) == "defmodule Split3 do\n  def b(x), do: a(x) * 2\nend\n"
    assert reply.delegated == []
    assert reply.left == ["calc.ex:2: a(x)"]
  end

  test "a module attribute still read in the source is copied, not moved", %{tmp_dir: dir} do
    file = Path.join(dir, "lim.ex")

    File.write!(file, """
    defmodule Split4 do
      @max 3

      def cap(n), do: min(n, @max)

      def room(n), do: @max - n
    end
    """)

    dest = Path.join(dir, "lim/cap.ex")
    assert {:ok, reply} = Menard.Move.run(file, dest, ["cap/1"], as: "Split4.Cap", delegate: true)
    assert reply.attributes == ["@max"]

    assert File.read!(file) == """
           defmodule Split4 do
             alias Split4.Cap

             @max 3

             defdelegate cap(n), to: Cap

             def room(n), do: @max - n
           end
           """

    assert File.read!(dest) == """
           defmodule Split4.Cap do
             @max 3

             def cap(n), do: min(n, @max)
           end
           """

    assert compile([File.read!(dest), File.read!(file)]) == []
    lim = Module.concat(["Split4"])
    assert lim.cap(9) == 3
  end

  test "a delegate's arguments are named from a clause that names them, a struct by its module",
       %{tmp_dir: dir} do
    file = Path.join(dir, "ev.ex")

    File.write!(file, """
    defmodule Split5 do
      def submit(user, attrs, tags \\\\ [])
      def submit(%{id: _} = user, attrs, tags), do: {user, attrs, tags}
      def submit(_, _, _), do: :error

      def occ(%{id: id}), do: occ(id)
      def occ(id) when is_integer(id), do: id

      def host(%URI{host: host}) when is_binary(host), do: host
      def host(_), do: nil

      def ping, do: :pong
    end
    """)

    dest = Path.join(dir, "ev/sub.ex")

    assert {:ok, _reply} =
             Menard.Move.run(file, dest, ["submit/3", "occ/1", "host/1", "ping/0"],
               as: "Split5.Sub",
               delegate: true
             )

    assert File.read!(file) == """
           defmodule Split5 do
             alias Split5.Sub

             defdelegate submit(user, attrs, tags \\\\ []), to: Sub

             defdelegate occ(id), to: Sub

             defdelegate host(uri), to: Sub

             defdelegate ping, to: Sub
           end
           """

    assert compile([File.read!(dest), File.read!(file)]) == []
    ev = Module.concat(["Split5"])
    assert ev.submit(%{id: 1}, :a) == {%{id: 1}, :a, []}
    assert ev.occ(%{id: 4}) == 4
    assert ev.host(URI.parse("https://x.org")) == "x.org"
    assert ev.ping() == :pong
  end

  test "a heredoc @doc keeps its lines where they were", %{tmp_dir: dir} do
    file = Path.join(dir, "doc.ex")

    File.write!(file, """
    defmodule Split7 do
      @doc \"\"\"
      Two lines
      of doc.
      \"\"\"
      def go, do: 1
    end
    """)

    dest = Path.join(dir, "doc/go.ex")
    assert {:ok, reply} = Menard.Move.run(file, dest, ["go/0"], as: "Split7.Go")

    # the patch, before any formatter: a dedent had pulled the text to column 1
    assert File.read!(dest) == """
           defmodule Split7.Go do
             @doc \"\"\"
             Two lines
             of doc.
             \"\"\"
             def go, do: 1
           end
           """

    assert [%{stage: :formatter, hunks: []} | _] = Enum.drop(reply.to.stages, 1)
  end

  test "a function that is not there is refused, naming it and what is there", %{tmp_dir: dir} do
    file = Path.join(dir, "n.ex")
    File.write!(file, "defmodule Split6 do\n  def go, do: 1\nend\n")

    assert {:error, "no nope/1 in Split6 — have: go/0"} =
             Menard.Move.run(file, Path.join(dir, "o.ex"), ["nope/1"], as: "O")
  end

  test "a moved @spec naming a type the source defines names the source's; a @typep is refused", %{
    tmp_dir: dir
  } do
    file = Path.join(dir, "cart.ex")

    File.write!(file, """
    defmodule Split8.Cart do
      @type t :: %{items: [item()]}
      @type item :: %{price: number()}

      @spec total(t()) :: number()
      def total(%{items: items}), do: items |> Enum.map(& &1.price) |> Enum.sum()

      @spec empty?(t()) :: boolean()
      def empty?(cart), do: cart.items == []
    end
    """)

    dest = Path.join(dir, "cart/sum.ex")
    assert {:ok, reply} = Menard.Move.run(file, dest, ["total/1"], as: "Split8.Cart.Sum", delegate: true)

    # a type is not a function: no delegate stands in for it, so the spec names it where it is
    assert File.read!(dest) == """
           defmodule Split8.Cart.Sum do
             alias Split8.Cart

             @spec total(Cart.t()) :: number()
             def total(%{items: items}), do: items |> Enum.map(& &1.price) |> Enum.sum()
           end
           """

    assert reply.qualified == ["@type t/0"]
    assert compile([File.read!(dest), File.read!(file)]) == []
    assert Module.concat(["Split8.Cart"]).total(%{items: [%{price: 2}, %{price: 3}]}) == 5

    # a private type cannot be named from another module: which way out is the caller's call
    priv = Path.join(dir, "priv.ex")

    src = """
    defmodule Split9 do
      @typep n :: integer()

      @spec double(n()) :: n()
      def double(x), do: x * 2

      @spec half(n()) :: n()
      def half(x), do: div(x, 2)
    end
    """

    File.write!(priv, src)
    out = Path.join(dir, "priv/double.ex")

    assert Menard.Move.run(priv, out, ["double/1"], as: "Split9.Double") ==
             {:error,
              "refused, nothing written: the moved @spec names n/0, a @typep of Split9, which no other " <>
                "module can name. Make it a @type first (stmt replace of the module's `@typep n`): " <>
                "the spec then names Split9.n()"}

    assert File.read!(priv) == src
    refute File.exists?(out)
  end

  test "a delegate's default that calls moved code is left to the destination: a delegate per arity", %{
    tmp_dir: dir
  } do
    file = Path.join(dir, "opts.ex")

    File.write!(file, """
    defmodule Split10 do
      def list(opts \\\\ defaults()), do: Keyword.merge(defaults(), opts)

      def fetch(id, opts \\\\ defaults(), retries \\\\ 3), do: {id, opts, retries}

      def page(n \\\\ 1), do: n

      defp defaults, do: [limit: 10]
    end
    """)

    dest = Path.join(dir, "opts/lists.ex")

    assert {:ok, _reply} =
             Menard.Move.run(file, dest, ["list/1", "fetch/3", "page/1"], as: "Split10.Lists", delegate: true)

    # `defaults()` evaluated in the source would call what is no longer there, and it is private
    # where it went: each arity delegates to the same arity, whose default is evaluated there. A
    # default that calls nothing moved stays as written.
    assert File.read!(file) == """
           defmodule Split10 do
             alias Split10.Lists

             defdelegate list, to: Lists

             defdelegate list(opts), to: Lists

             defdelegate fetch(id), to: Lists

             defdelegate fetch(id, opts), to: Lists

             defdelegate fetch(id, opts, retries), to: Lists

             defdelegate page(n \\\\ 1), to: Lists
           end
           """

    assert compile([File.read!(dest), File.read!(file)]) == []
    mod = Module.concat(["Split10"])
    assert mod.list() == [limit: 10]
    assert mod.list(limit: 2) == [limit: 2]
    assert mod.fetch(7) == {7, [limit: 10], 3}
    assert mod.fetch(7, [], 1) == {7, [], 1}
    assert mod.page() == 1
  end

  test "an import without only: goes along only when nothing else could answer the call it makes", %{
    tmp_dir: dir
  } do
    # alone, the bare import is what answers band/2: it goes, and the source, calling nothing of it
    # now, loses it
    file = Path.join(dir, "bits.ex")

    File.write!(file, """
    defmodule Split11 do
      import Bitwise

      def mask(x), do: band(x, 1)

      def id(x), do: x
    end
    """)

    assert {:ok, reply} =
             Menard.Move.run(file, Path.join(dir, "bits/mask.ex"), ["mask/1"], as: "Split11.Mask")

    assert reply.directives == ["import Bitwise"]
    assert reply.unresolved == []
    assert File.read!(file) == "defmodule Split11 do\n  def id(x), do: x\nend\n"

    # beside a `use`, which may import anything, what the AST shows cannot say which one answers
    # greet/1: neither is copied (a wrong guess is an unused import, which warns), and the reply
    # names the call and where it may come from
    file = Path.join(dir, "hi.ex")

    src = """
    defmodule Split12 do
      use Split1.Greeter

      import Bitwise

      def hello(x), do: greet(x)

      def mask(x), do: band(x, 1)
    end
    """

    File.write!(file, src)
    dest = Path.join(dir, "hi/hello.ex")
    assert {:ok, reply} = Menard.Move.run(file, dest, ["hello/1"], as: "Split12.Hello", delegate: true)

    assert File.read!(dest) == """
           defmodule Split12.Hello do
             def hello(x), do: greet(x)
           end
           """

    assert reply.directives == []
    assert reply.unresolved == ["greet/1 (one of: use Split1.Greeter; import Bitwise)"]

    # the source keeps both: band/2 still needs one of them
    assert File.read!(file) == """
           defmodule Split12 do
             use Split1.Greeter

             import Bitwise

             alias Split12.Hello

             defdelegate hello(x), to: Hello

             def mask(x), do: band(x, 1)
           end
           """

    # with the `use` the reply names, it compiles clean
    fixed = Menard.Directive.add(File.read!(dest), :use, "Split1.Greeter")
    assert compile([fixed, File.read!(file)]) == []
    assert Module.concat(["Split12"]).hello("x") == "hi x"
  end

  test "a multi-alias member only the moved code used leaves the source's line", %{tmp_dir: dir} do
    file = Path.join(dir, "multi.ex")

    File.write!(file, """
    defmodule Split13 do
      alias Split1.{Shop.Stock, Tax}

      def price(p), do: Tax.add(p, 0.5)

      def stock(n), do: Stock.take(n)
    end
    """)

    dest = Path.join(dir, "multi/price.ex")
    assert {:ok, _reply} = Menard.Move.run(file, dest, ["price/1"], as: "Split13.Price", delegate: true)

    # Tax, unused in the source now, would warn: it leaves the multi-alias, Stock stays
    assert File.read!(file) == """
           defmodule Split13 do
             alias Split1.Shop.Stock
             alias Split13.Price

             defdelegate price(p), to: Price

             def stock(n), do: Stock.take(n)
           end
           """

    assert compile([File.read!(dest), File.read!(file)]) == []
    assert Module.concat(["Split13"]).price(2) == 3.0
  end
end
