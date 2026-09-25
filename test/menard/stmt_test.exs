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
end
