defmodule Menard.StmtTest do
  # One statement inside a body. Case arms come with it: an arm is a statement of its `case`.
  use ExUnit.Case, async: true

  alias Menard.Stmt

  @src """
  defmodule St do
    def init(_opts) do
      subscribe_a()
      subscribe_b()

      case start() do
        0 -> {:ok, :up}
        n -> {:error, n}
      end
    end

    def solo(x) do
      only_one(x)
    end
  end
  """

  test "list names the body's statements, the case arms and their bodies — not `do` or the head" do
    assert Stmt.list(@src, "init/1", "_opts") == [
             "subscribe_a()",
             "subscribe_b()",
             "case start() do\n      0 -> {:ok, :up}\n      n -> {:error, n}\n    end",
             "0 -> {:ok, :up}",
             "{:ok, :up}",
             "n -> {:error, n}",
             "{:error, n}"
           ]
  end

  test "a single-statement body still lists its one statement" do
    assert Stmt.list(@src, "solo/1", "x") == ["only_one(x)"]
  end

  test "insert_after puts a new statement below the one named, at its indent" do
    out = Stmt.insert_after(@src, "init/1", "_opts", "subscribe_b()", "Import.run()")

    assert out =~ "    subscribe_b()\n\n    Import.run()\n"
    assert out =~ "case start() do"
  end

  test "insert_before puts one above" do
    out = Stmt.insert_before(@src, "init/1", "_opts", "subscribe_a()", "before_all()")

    assert out =~ "    before_all()\n\n    subscribe_a()"
  end

  test "replace swaps a CASE ARM without touching its neighbour" do
    out = Stmt.replace(@src, "init/1", "_opts", "0 -> {:ok, :up}", "0 -> {:ok, :running}")

    assert out =~ "0 -> {:ok, :running}"
    assert out =~ "n -> {:error, n}"
    refute out =~ "{:ok, :up}"
  end

  test "replace swaps a plain statement" do
    out = Stmt.replace(@src, "init/1", "_opts", "subscribe_a()", "subscribe_everything()")

    assert out =~ "subscribe_everything()"
    refute out =~ "subscribe_a()"
  end

  test "delete removes the statement and the blank line it left" do
    out = Stmt.delete(@src, "init/1", "_opts", "subscribe_b()")

    refute out =~ "subscribe_b()"
    assert out =~ "subscribe_a()"
    assert out =~ "case start() do"
  end

  test "a statement that isn't there is refused, and the message lists what is" do
    assert {:error, message} = Stmt.replace(@src, "init/1", "_opts", "nope()", "x()")
    assert message =~ "no statement `nope()`"
    assert message =~ "subscribe_a()"
  end

  test "whitespace in the match doesn't matter — it is addressed as written, squashed" do
    out = Stmt.replace(@src, "init/1", "_opts", "0->{:ok,:up}", "0 -> :fine")
    assert out =~ "0 -> :fine"
  end

  test "an ambiguous match is refused with line numbers, and --nth picks one" do
    src = """
    defmodule D do
      def go(x) do
        tick()
        other(x)
        tick()
      end
    end
    """

    assert {:error, message} = Stmt.delete(src, "go/1", "x", "tick()")
    assert message =~ "2 statements match"
    assert message =~ "--nth 1..2"

    out = Stmt.replace(src, "go/1", "x", "tick()", "tock()", nth: 2)
    assert out =~ "other(x)\n    tock()"
  end

  test "reaches inside an anonymous fn — a call in Enum.each(fn -> end) had no verb" do
    src = """
    defmodule Fnx do
      def go(entries, id) do
        Enum.each(entries, fn %{name: name} ->
          spawn_window(id, instantiate(name))
        end)
      end
    end
    """

    assert "spawn_window(id, instantiate(name))" in Stmt.list(src, "go/2", "entries, id")

    out =
      Stmt.replace(
        src,
        "go/2",
        "entries, id",
        "spawn_window(id, instantiate(name))",
        "spawn_window(id, instantiate(name, id))"
      )

    assert out =~ "spawn_window(id, instantiate(name, id))"
    assert out =~ "Enum.each(entries, fn %{name: name} ->"
  end

  test "a multi-statement fn body lists each of its statements" do
    src = """
    defmodule Fnx do
      def go(list) do
        Enum.map(list, fn x ->
          first(x)
          second(x)
        end)
      end
    end
    """

    statements = Stmt.list(src, "go/1", "list")

    assert "first(x)" in statements
    assert "second(x)" in statements
  end

  test "an unknown clause is refused before any statement is looked for" do
    assert {:error, message} = Stmt.list(@src, "nope/9", "x")
    assert message =~ "no clause nope/9"
  end

  test "a literal body — a 2-tuple, an atom — is a statement too" do
    src = """
    defmodule A do
      def go(x) do
        case x do
          :a -> {:ok, x}
          _ -> :error
        end
      end
    end
    """

    out = Stmt.replace(src, "go/1", "x", "{:ok, x}", "{:ok, x, :tagged}")
    assert out =~ ":a -> {:ok, x, :tagged}"
    assert Stmt.replace(src, "go/1", "x", ":error", ":nope") =~ "_ -> :nope"
  end

  test "insert_after a heredoc keeps the heredoc closed" do
    src = """
    defmodule A do
      def go do
        text = \"\"\"
        hi
        \"\"\"
        text
      end
    end
    """

    out = Stmt.insert_after(src, "go/0", "", "text = \"\"\"\nhi\n\"\"\"", "IO.puts(text)")
    assert out =~ "  \"\"\"\n\n    IO.puts(text)\n    text\n"
  end

  test "replacing an arm that ends in a literal keeps the line break after it" do
    src = """
    defmodule A do
      def y(a) do
        case a do
          nil -> false
        end
      end
    end
    """

    assert Stmt.replace(src, "y/1", "a", "nil -> false", "nil -> true") =~ "nil -> true\n    end"
  end

  test "comment sets, replaces and removes the # comment above one statement" do
    src = """
    defmodule A do
      def go(x) do
        # old why
        step(x)
      end
    end
    """

    replaced = Stmt.comment(src, "go/1", "x", "step(x)", "the new why")
    assert replaced =~ "    # the new why\n    step(x)"
    refute replaced =~ "old why"
    assert Stmt.comment(src, "go/1", "x", "step(x)", nil) =~ "def go(x) do\n    step(x)"
  end

  test "a with's steps and its else arms are statements" do
    # a `with`'s steps are statements, and so is each arm of its `else` — with an `else` or without
    src = """
    defmodule W do
      def go(x) do
        with {:ok, a} <- fetch(x),
             {:ok, b} <- parse(a) do
          b
        else
          {:error, e} -> e
        end
      end
    end
    """

    listed = Stmt.list(src, "go/1", "x")
    assert "{:ok, a} <- fetch(x)" in listed
    assert "{:ok, b} <- parse(a)" in listed
    assert "{:error, e} -> e" in listed

    out = Stmt.replace(src, "go/1", "x", "{:ok, b} <- parse(a)", "{:ok, b} <- parse(a, strict: true)")
    assert out =~ "{:ok, b} <- parse(a, strict: true) do"
    assert out =~ "{:error, e} -> e"
  end

  test "a leading fragment addresses the one statement that starts with it" do
    # a statement is addressed by what is written, and its start is enough when only one starts so
    src = """
    defmodule P do
      def go(dir) do
        elixir_files =
          dir
          |> Path.join("**/*.ex")
          |> Path.wildcard()

        elixir_tests = Path.wildcard(Path.join(dir, "**/*_test.exs"))
        {elixir_files, elixir_tests}
      end
    end
    """

    out =
      Stmt.replace(
        src,
        "go/1",
        "dir",
        "elixir_files =",
        "elixir_files = Path.wildcard(Path.join(dir, \"**/*.ex\"))"
      )

    assert out =~ ~s[elixir_files = Path.wildcard(Path.join(dir, "**/*.ex"))\n]
    assert out =~ "elixir_tests = Path.wildcard"

    # two start that way: refused, and both named
    assert {:error, message} = Stmt.delete(src, "go/1", "dir", "elixir_")
    assert message =~ "elixir_files ="
    assert message =~ "elixir_tests ="
  end

  test "a __MODULE__ call and a literal before end are patched at their own bytes" do
    # Sourceror starts `__MODULE__.go()` after the `__MODULE__`, and ends a literal before `end` one
    # past it: a patch over either left `__MODULE__` behind, or ate the space before `end`
    src = """
    defmodule A do
      def go do
        __MODULE__.Docs.helper(1)
      end

      def cb, do: Enum.map([1], fn _ -> nil end)
    end
    """

    assert Stmt.replace(src, "go/0", "", "__MODULE__.Docs.helper(1)", "__MODULE__.Docs.helper(2)") =~
             "\n    __MODULE__.Docs.helper(2)\n"

    assert Menard.Clause.replace_body(src, "go/0", "", "__MODULE__.Docs.other()") =~
             "\n    __MODULE__.Docs.other()\n  end"

    assert Stmt.replace(src, "cb/0", "", "nil", "nil") == src
  end

  test "a miss on text inside a template says Edit reaches it" do
    src = ~S'''
    defmodule L do
      def render(assigns) do
        ~H"""
        <p>{Cart.total(@cart)}</p>
        """
      end
    end
    '''

    # replace reaches template text now; the other verbs still send it to Edit
    assert {:error, message} =
             Stmt.insert_after(src, "render/1", "assigns", "<p>{Cart.total(@cart)}</p>", "x")

    assert message =~ "inside a string"
    assert message =~ "Edit"
  end

  test "replace reaches an expression in a ~H template; the other verbs still send it to Edit" do
    # bench1 and bench2 add-alias.B.haiku, new-component.B.haiku: each first tried stmt replace on
    # a `{…}` in the template, and was refused
    src = ~S'''
    defmodule L do
      def render(assigns) do
        ~H"""
        <p :if={
          Catalog.price_with_tax(%Shop.Product{sku: ""}) > 0
        }>x</p>
        <p>{Catalog.name(@p)}</p>
        """
      end
    end
    '''

    out =
      Stmt.replace(
        src,
        "render/1",
        "assigns",
        ~S|Catalog.price_with_tax(%Shop.Product{sku: ""}) > 0|,
        ~S|Catalog.price_with_tax(%Product{sku: ""}) > 0|
      )

    assert out =~ ~s|<p :if={\n      Catalog.price_with_tax(%Product{sku: ""}) > 0\n    }>x</p>|

    out = Stmt.replace(src, "render/1", "assigns", "Catalog.name(@p)", "Catalog.title(@p)")
    assert out =~ "<p>{Catalog.title(@p)}</p>"

    assert {:error, message} = Stmt.insert_after(src, "render/1", "assigns", "Catalog.name(@p)", "x")
    assert message =~ "Edit"
  end

  test "replace reaches any text of a ~H template, a whole line of markup too" do
    # bench2 change-signature.B.haiku matched a whole `<p :for=…>{…}</p>` line, two expressions and
    # the markup around them
    src = ~S'''
    defmodule L do
      def render(assigns) do
        ~H"""
        <p :for={line <- Cart.lines(@cart)}>{Cart.format_line(line)}</p>
        """
      end
    end
    '''

    out =
      Stmt.replace(
        src,
        "render/1",
        "assigns",
        "<p :for={line <- Cart.lines(@cart)}>{Cart.format_line(line)}</p>",
        "<p :for={line <- Cart.lines(@cart, 0.1)}>{Money.format_line(line)}</p>"
      )

    assert out =~ "    <p :for={line <- Cart.lines(@cart, 0.1)}>{Money.format_line(line)}</p>\n"
  end

  test "a miss lists each line a statement starts on once, not every nested node in full" do
    # a miss in a long case printed each arm, and each call inside each arm, in full: the reply ran
    # to the whole clause many times over
    arms = Enum.map_join(1..40, "\n", &"      #{&1} -> {:ok, Enum.map([#{&1}], fn x -> x * #{&1} end)}")
    src = "defmodule A do\n  def f(x) do\n    case x do\n#{arms}\n    end\n  end\nend\n"

    assert {:error, message} = Stmt.replace(src, "f/1", "x", "nope()", "1")
    assert String.length(message) < 2_000
    assert message =~ "more"
  end

  test "a statement in a test, the test named by its label where the head goes" do
    # bench2 move-function.B.haiku: stmt {name_arity: "-", head: "formats a line", match: …}
    src = """
    defmodule ATest do
      use ExUnit.Case

      test "formats a line" do
        [line] = lines()
        assert Cart.format_line(line) == "1 x Mug"
      end
    end
    """

    out =
      Stmt.replace(
        src,
        "-",
        "formats a line",
        ~s|assert Cart.format_line(line) == "1 x Mug"|,
        ~s|assert Money.format_line(line) == "1 x Mug"|
      )

    assert out =~ ~s|    [line] = lines()\n    assert Money.format_line(line) == "1 x Mug"\n|
    assert {:error, _} = Stmt.replace(src, "-", "no such test", "x", "y")
  end

  test "a statement in a test, the label given as the name_arity" do
    # bench3 move-function.B.haiku: stmt {name_arity: "formats a line/0", head: ""}
    src =
      "defmodule ATest do\n  use ExUnit.Case\n\n  test \"formats a line\" do\n    assert f(1) == 1\n  end\nend\n"

    out = Stmt.replace(src, "formats a line/0", "", "assert f(1) == 1", "assert g(1) == 1")
    assert out =~ "    assert g(1) == 1\n"
  end

  test "a replace matched by its start that leaves code which does not parse says what it matched" do
    # replacing `case x do` with one line took the whole case, and the refusal said only
    # "missing terminator: end" (found fixing bench3's bugs, twice)
    src =
      "defmodule A do\n  def f(x) do\n    case x do\n      1 -> :one\n      _ -> :other\n    end\n  end\nend\n"

    assert {:error, message} = Stmt.replace(src, "f/1", "x", "case x do", "y = x\ncase y do")
    assert message =~ "whole statement"
    assert message =~ "lines 3-6"
  end

  test "a statement of the module itself, when no clause or test is named: defstruct, @type" do
    # bench3 not-compiling.B.haiku: nothing reached `defstruct […]` or `@type t :: …`; it tried
    # clause t/0, stmt t/0, two Edits, then replaced the whole module
    src = "defmodule P do\n  defstruct [:sku, stock: 0]\n\n  @type t :: %__MODULE__{sku: String.t()}\nend\n"
    out = Stmt.replace(src, "-", "", "defstruct [:sku, stock: 0]", "defstruct [:sku, stock: 0, weight: 0]")
    assert out =~ "  defstruct [:sku, stock: 0, weight: 0]\n"

    out =
      Stmt.replace(src, "t/0", "", "@type t ::", "@type t :: %__MODULE__{sku: String.t(), weight: integer()}")

    assert out =~ "  @type t :: %__MODULE__{sku: String.t(), weight: integer()}\n"
  end

  test "the module fallback reaches the module's own statements, never one inside a function or test" do
    # bench4 bug-receipt-total.B.haiku named subject/1, the function under test, in the TEST file: the
    # fallback found the assert inside a test and put a new test inside that test
    src =
      "defmodule MTest do\n  use ExUnit.Case\n\n  test \"subject quotes the id\" do\n    assert M.subject(1) == 1\n  end\nend\n"

    assert {:error, message} =
             Stmt.insert_after(src, "subject/1", "order_id", "assert M.subject(1) == 1", "test \"x\" do\nend")

    assert message =~ "subject/1"
    # the module's own statements are still reached
    assert Stmt.replace(src, "-", "", "use ExUnit.Case", "use ExUnit.Case, async: true") =~
             "use ExUnit.Case, async: true"
  end

  test "naming nothing searches the whole file for the one statement written" do
    # bench5 move-function.B.haiku: name_arity "" and head "" for a line inside a test
    src = "defmodule CTest do\n  use ExUnit.Case\n\n  test \"formats\" do\n    assert f(1) == 1\n  end\nend\n"
    assert Stmt.replace(src, "", "", "assert f(1) == 1", "assert g(1) == 1") =~ "    assert g(1) == 1\n"
    # naming a function that is not there still reaches only the module's own statements
    assert {:error, _} = Stmt.replace(src, "subject/1", "x", "assert f(1) == 1", "assert g(1) == 1")
  end

  test "comments inside the statement don't count: it matches as written without them" do
    src = """
    defmodule Sb do
      def sidebar do
        %{
          # what the board shows first
          open: 1,
          # "#" in a string is not a comment
          tag: "#top"
        }
      end
    end
    """

    out = Stmt.replace(src, "sidebar/0", "", ~s|%{open: 1, tag: "#top"}|, "%{open: 2}")
    assert out =~ "%{open: 2}"
    refute out =~ "open: 1"
  end
end
