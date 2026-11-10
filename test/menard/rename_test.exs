defmodule Menard.RenameTest do
  # AST-aware renames (Sourceror): the identifier changes wherever it is an identifier — def/defp
  # heads, calls, captures, variables — and, on request, the atom and keyword key too; a string or
  # a comment mentioning the name is left alone. Comments and layout survive.
  use ExUnit.Case, async: true

  alias Menard.Rename

  @src """
  defmodule Demo do
    # the author_workspaces list — a comment stays
    @doc "author_workspaces in a string stays"
    def author_workspaces(state), do: Map.get(state, :author_workspaces, [])

    defp count(state), do: length(author_workspaces(state))

    def ring(state), do: Enum.map(author_workspaces(state), & &1.id) |> Kernel.++([&author_workspaces/1])

    def keys, do: %{author_workspaces: 1, other: "author_workspaces"}
  end
  """

  test "old as Mod.fun renames that module's function alone: its heads, and the calls that resolve to it" do
    # `rename total grand_total lib/**` by name alone would rename every module's `total`
    src = """
    defmodule Shop.Cart do
      def total(c), do: sum(c)
      def total(c, r), do: total(c) * r
      def go, do: __MODULE__.total([]) + &total/1

      defmodule Inner do
        def total(x), do: x
      end
    end

    defmodule Shop.Report do
      alias Shop.Cart
      import Shop.Cart, only: [total: 1]
      def a(c), do: Cart.total(c) + Shop.Cart.total(c, 1) + total(c)
      def b, do: Enum.map([], &Cart.total/1)
      def c, do: Shop.Cart.Inner.total(1)
    end

    defmodule Other do
      def total(z), do: z
      def d, do: total(1)
    end
    """

    out = Rename.run(src, "Shop.Cart.total", "grand_total")
    assert out =~ "def grand_total(c), do: sum(c)"
    assert out =~ "def grand_total(c, r), do: grand_total(c) * r"
    assert out =~ "def go, do: __MODULE__.grand_total([]) + &grand_total/1"
    assert out =~ "defmodule Inner do\n    def total(x), do: x"
    assert out =~ "def a(c), do: Cart.grand_total(c) + Shop.Cart.grand_total(c, 1) + grand_total(c)"
    assert out =~ "&Cart.grand_total/1"
    assert out =~ "Shop.Cart.Inner.total(1)"
    assert out =~ "def total(z), do: z\n  def d, do: total(1)"
  end

  test "a new name that is no name, or an arity on the old one, is refused before anything is read" do
    for {old, new} <- [
          {"go", "bad name"},
          {"go", "x;y"},
          {"go", "Go"},
          {"go", "end"},
          {"A.go", "B.run"},
          {"Shop.Cart", "basket"},
          {"Shop.Cart", "Shop.basket"},
          {"A.go/3", "run"},
          {"go/1", "run"}
        ] do
      assert {:error, why} = Rename.run("defmodule A do\n  def go, do: 1\nend\n", old, new)
      assert why =~ "rename", "#{old} → #{new}: #{why}"
    end

    assert Rename.run("defmodule A do\n  def go?, do: 1\nend\n", "go?", "run!") =~ "def run!, do: 1"
  end

  test "a module spelled from Elixir, `Elixir.Shop.Cart`, is renamed and keeps the spelling" do
    src = "defmodule U do\n  def go, do: Elixir.Shop.Cart.total(1) + Elixir.Shop.Cart.Item.n()\nend\n"
    out = Rename.run(src, "Shop.Cart", "Shop.Basket")
    assert out =~ "Elixir.Shop.Basket.total(1) + Elixir.Shop.Basket.Item.n()"
  end

  test "a rename onto a function the module already has is refused: two functions would be one" do
    src = """
    defmodule A do
      def go(x), do: x
      def run(x), do: x + 1
      def run(x, y), do: x + y
    end
    """

    assert {:error, why} = Rename.run(src, "go", "run")
    assert why =~ "A already has run/1"
    assert {:error, _} = Rename.run(src, "A.go", "run")
    assert Rename.run(src, "x", "y", only: :variables) =~ "def go(y), do: y"

    assert Rename.run(
             "defmodule B do\n  def go(x, y, z), do: x\n  def run(x), do: go(x, 1, 2)\nend\n",
             "go",
             "run"
           ) =~
             "def run(x, y, z)"
  end

  test "Mod.fun renames the function in an import's only: and except: of that module" do
    src = """
    defmodule U do
      import Shop.Cart, only: [total: 1, other: 1]
      import Else, only: [total: 1]
      def go, do: total(1)
    end
    """

    out = Rename.run(src, "Shop.Cart.total", "sum")
    assert out =~ "import Shop.Cart, only: [sum: 1, other: 1]"
    assert out =~ "import Else, only: [total: 1]"
    assert out =~ "def go, do: sum(1)"
  end

  test "a name in defoverridable and in @compile's inline follows its function" do
    src = """
    defmodule A do
      @compile {:inline, go: 1}
      def go(x), do: x
      defoverridable go: 1, stay: 0
    end
    """

    out = Rename.run(src, "go", "run")
    assert out =~ "@compile {:inline, run: 1}"
    assert out =~ "defoverridable run: 1, stay: 0"
  end

  test "a module defined inside another is renamed where it is defined, and where its parent names it bare" do
    src = """
    defmodule Shop do
      defmodule Cart do
        def add(c), do: c
      end

      def x, do: Cart.add(1)
    end
    """

    out = Rename.run(src, "Shop.Cart", "Shop.Basket")
    assert out =~ "  defmodule Basket do"
    assert out =~ "def x, do: Basket.add(1)"

    assert {:error, why} = Rename.run(src, "Shop.Cart", "Store.Basket")
    assert why =~ "defined inside Shop"
  end

  test "renames def heads, calls and captures; leaves strings and comments" do
    out = Rename.run(@src, "author_workspaces", "live_workspaces")
    assert out =~ "def live_workspaces(state), do: Map.get(state, :author_workspaces, [])"
    assert out =~ "length(live_workspaces(state))"
    assert out =~ "&live_workspaces/1"
    assert out =~ "# the author_workspaces list — a comment stays"
    assert out =~ ~s(@doc "author_workspaces in a string stays")
    assert out =~ ~s("author_workspaces"})
    # the atom and the keyword key are untouched without the flag
    assert out =~ ":author_workspaces, []"
    assert out =~ "%{author_workspaces: 1"
  end

  test "with atoms: true the atom and the keyword key follow" do
    out = Rename.run(@src, "author_workspaces", "live_workspaces", atoms: true)
    assert out =~ "Map.get(state, :live_workspaces, [])"
    assert out =~ "%{live_workspaces: 1"
    assert out =~ ~s(other: "author_workspaces")
  end

  test "a source with nothing to rename comes back byte-identical" do
    assert Rename.run(@src, "nothing_here", "x") == @src
  end

  test "a name the source never mentions makes no atom: the VM never collects one" do
    name = "never_named_#{System.unique_integer([:positive])}"
    assert Rename.run(@src, name, "x", atoms: true, comments: true) == @src
    assert_raise ArgumentError, fn -> String.to_existing_atom(name) end
  end

  test "an unparseable source is an error, never a partial write" do
    assert {:error, _} = Rename.run("def (", "a", "b")
  end

  # The patch discipline: only the renamed bytes move. Odd layout, comments, blank runs — all kept.
  test "everything but the identifier is byte-for-byte the same" do
    src =
      "defmodule Odd do\n\n\n  def   author_workspaces( s ),   do:   s   # keep\n\n  def two, do: author_workspaces(1)\nend\n"

    out = Rename.run(src, "author_workspaces", "live_workspaces")

    assert out ==
             "defmodule Odd do\n\n\n  def   live_workspaces( s ),   do:   s   # keep\n\n  def two, do: live_workspaces(1)\nend\n"
  end

  test "comments: true renames whole-word mentions in comments, not substrings or strings" do
    src =
      "# author_workspaces feeds the ring; author_workspaces_extra is another thing\n" <>
        "def author_workspaces, do: \"author_workspaces\"\n"

    out = Rename.run(src, "author_workspaces", "live_workspaces", comments: true)

    assert out ==
             "# live_workspaces feeds the ring; author_workspaces_extra is another thing\n" <>
               "def live_workspaces, do: \"author_workspaces\"\n"
  end

  test "comments: true reaches only real comments, not a `#` line of a heredoc or of ~H markup" do
    src = ~S'''
    defmodule A do
      @moduledoc """
      # old
      """
      # old is the one
      def old, do: 1

      def render(assigns) do
        ~H"""
        <p>#old</p>
        """
      end
    end
    '''

    assert Rename.run(src, "old", "fresh", comments: true) ==
             src
             |> String.replace("# old is", "# fresh is")
             |> String.replace("def old", "def fresh")
  end

  test "old as a module renames its defmodule, its alias and the calls that spell it, code only" do
    src = """
    defmodule Shop.Cart do
      @moduledoc "Shop.Cart.Item in a string stays"
      alias Shop.Cart.Item
      def total(c), do: Shop.Cart.Item.sum(c) + Item.sum(c) + Enum.sum(c)
    end

    defmodule Shop.Cart.Item do
      def sum(_), do: 1
    end
    """

    out = Rename.run(src, "Shop.Cart.Item", "Shop.Line")
    assert out =~ "defmodule Shop.Cart do"
    assert out =~ "alias Shop.Line\n"
    assert out =~ "Shop.Line.sum(c) + Line.sum(c) + Enum.sum(c)"
    assert out =~ "defmodule Shop.Line do"
    assert out =~ ~s(@moduledoc "Shop.Cart.Item in a string stays")
  end

  test "old as a module renames the names under it and a multi-alias's entry, not a name it only begins" do
    nested = """
    defmodule Acme.Billing do
      defmodule Error do
        defexception [:message]
      end
    end

    defmodule Acme.Other do
      alias Acme.Billing
      def fail, do: raise(Billing.Error)
      def again, do: raise(Acme.Billing.Error)
    end
    """

    out = Rename.run(nested, "Acme.Billing", "Acme.Invoicing")
    assert out =~ "defmodule Acme.Invoicing do\n  defmodule Error do"
    assert out =~ "raise(Invoicing.Error)"
    assert out =~ "raise(Acme.Invoicing.Error)"

    multi = """
    defmodule Acme.Caller do
      alias Acme.{Billing, BillingAddress}
      def go, do: {Billing.charge(), BillingAddress.new(), Acme.BillingAddress}
    end
    """

    assert Rename.run(multi, "Acme.Billing", "Acme.Invoicing") == """
           defmodule Acme.Caller do
             alias Acme.{Invoicing, BillingAddress}
             def go, do: {Invoicing.charge(), BillingAddress.new(), Acme.BillingAddress}
           end
           """

    as = """
    defmodule Acme.Report do
      alias Acme.Billing, as: Pay
      alias Acme.Reports.Billing
      def go, do: {Pay.charge(), Billing.title()}
    end
    """

    assert Rename.run(as, "Acme.Billing", "Acme.Invoicing") == """
           defmodule Acme.Report do
             alias Acme.Invoicing, as: Pay
             alias Acme.Reports.Billing
             def go, do: {Pay.charge(), Billing.title()}
           end
           """
  end

  test "a multi-alias entry moves out of the braces when the new name has another base" do
    src = """
    defmodule Acme.Caller do
      alias Acme.{Billing, X}
      def go, do: {Billing.charge(), X.new()}
    end
    """

    assert Rename.run(src, "Acme.Billing", "Shop.Invoicing") == """
           defmodule Acme.Caller do
             alias Acme.X
             alias Shop.Invoicing
             def go, do: {Invoicing.charge(), X.new()}
           end
           """

    three = String.replace(src, "{Billing, X}", "{Billing, X, Y}")

    assert Rename.run(three, "Acme.Billing", "Shop.Invoicing") =~
             "  alias Acme.{X, Y}\n  alias Shop.Invoicing\n"

    alone = String.replace(src, "{Billing, X}", "{Billing}")
    assert Rename.run(alone, "Acme.Billing", "Shop.Invoicing") =~ "  alias Shop.Invoicing\n  def go"
  end

  test "an alias binds the bare last segment in its own module, and in the modules nested in it" do
    src = """
    defmodule A do
      alias Acme.Billing
      def go, do: Billing.x()

      defmodule Inner do
        def go, do: Billing.y()
      end
    end

    defmodule B do
      alias Acme.Reports.Billing
      def go, do: Billing.x()
    end
    """

    assert Rename.run(src, "Acme.Billing", "Acme.Invoicing") == """
           defmodule A do
             alias Acme.Invoicing
             def go, do: Invoicing.x()

             defmodule Inner do
               def go, do: Invoicing.y()
             end
           end

           defmodule B do
             alias Acme.Reports.Billing
             def go, do: Billing.x()
           end
           """
  end

  test "renames a remote call and a remote capture, not a field access" do
    src = """
    defmodule A do
      def go, do: B.old(1)
      def f, do: &B.old/1
      def g, do: __MODULE__.old()
      def h(map), do: map.old
    end
    """

    assert Rename.run(src, "old", "new") == """
           defmodule A do
             def go, do: B.new(1)
             def f, do: &B.new/1
             def g, do: __MODULE__.new()
             def h(map), do: map.old
           end
           """
  end

  test "only: narrows a rename to functions or to variables" do
    src = """
    defmodule A do
      def old(x), do: x
      def zero, do: &old/1
      def go(old), do: old + old(1)
    end
    """

    assert Rename.run(src, "old", "new", only: :functions) == """
           defmodule A do
             def new(x), do: x
             def zero, do: &new/1
             def go(old), do: old + new(1)
           end
           """

    assert Rename.run(src, "old", "new", only: :variables) == """
           defmodule A do
             def old(x), do: x
             def zero, do: &old/1
             def go(new), do: new + old(1)
           end
           """
  end

  test "only: leaves a module attribute alone, and :functions renames the import that names the function" do
    src = """
    defmodule A do
      import B, only: [old: 1]
      @old 1
      def go(old), do: old(@old) + old
    end
    """

    assert Rename.run(src, "old", "new", only: :functions) == """
           defmodule A do
             import B, only: [new: 1]
             @old 1
             def go(old), do: new(@old) + old
           end
           """

    assert Rename.run(src, "old", "new", only: :variables) == """
           defmodule A do
             import B, only: [old: 1]
             @old 1
             def go(new), do: old(@old) + new
           end
           """
  end

  test "a call inside ~H is renamed with the rest" do
    # a call inside ~H is a string to the AST: `rename` left it, said the file was done, and the
    # project stopped compiling (hhaa: `:if={… is_editable?(@background_check)}`)
    src = """
    defmodule L do
      def is_editable?(x), do: x

      def render(assigns) do
        ~H\"\"\"
        <div :if={is_editable?(@x)}><%= L.is_editable?(@y) %> @is_editable? is_editable_x</div>
        \"\"\"
      end
    end
    """

    out = Rename.run(src, "is_editable?", "editable?", only: :functions)
    assert out =~ "def editable?(x)"
    assert out =~ ":if={editable?(@x)}"
    assert out =~ "<%= L.editable?(@y) %>"
    # an assign and a longer name are not the call
    assert out =~ "@is_editable? is_editable_x"

    # renaming variables leaves ~H alone
    assert Rename.run(src, "is_editable?", "editable?", only: :variables) =~ ":if={is_editable?(@x)}"
  end

  test "a rename reaches the docs: a mention and a doctest in @moduledoc and @doc, not other strings" do
    # a doctest left behind would call a function that is no longer there
    src = ~S"""
    defmodule A do
      @moduledoc "Prices go through `old/1`."

      @doc \"""
      The old way.

          iex> A.old(1)
          1
      \"""
      def old(x), do: x

      def label, do: "old"
    end
    """

    out = Menard.Rename.run(src, "old", "fresh")
    assert out =~ "Prices go through `fresh/1`."
    assert out =~ "iex> A.fresh(1)"
    assert out =~ "The old way."
    assert out =~ ~s(def label, do: "old")
    assert out =~ "def fresh(x)"
    refute Menard.Rename.run(src, "old", "fresh", docs: false) =~ "`fresh/1`"
  end
end
