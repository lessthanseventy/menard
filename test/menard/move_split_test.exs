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
end
