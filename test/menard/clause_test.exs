defmodule Menard.ClauseTest do
  # The clause verbs — what replaces the grep/sed dance: address a clause by `name/arity` and a
  # head pattern (its args, as written), then replace its body, delete it, or insert a new clause
  # after it. Patches, not reprints: everything else in the file is byte-identical.
  use ExUnit.Case, async: true

  alias Menard.Clause

  @src """
  defmodule Demo do
    # first
    def go(:a), do: 1

    # second
    def go(:b) do
      2
    end

    def go(other), do: other
  end
  """

  test "replace_body swaps one clause's body and keeps its form — do…end or do:" do
    out = Clause.replace_body(@src, "go/1", ":b", "20")
    assert out == String.replace(@src, "    2\n", "    20\n")

    assert Clause.replace_body(@src, "go/1", ":a", "10") == String.replace(@src, "do: 1", "do: 10")
  end

  test "delete removes the clause (and the comment glued above it), nothing else" do
    out = Clause.delete(@src, "go/1", ":a")
    assert out == String.replace(@src, "  # first\n  def go(:a), do: 1\n\n", "")
  end

  test "insert_after adds a clause right after the addressed one" do
    out = Clause.insert_after(@src, "go/1", ":a", "def go(:c), do: 3")
    assert out == String.replace(@src, "def go(:a), do: 1\n", "def go(:a), do: 1\n  def go(:c), do: 3\n")
  end

  test "insert_after and insert_before take code already at the clause's indent as it is, trailing newline and all" do
    code = "  def go(:c) do\n    3\n  end\n"

    assert Clause.insert_after(@src, "go/1", ":a", code) ==
             String.replace(@src, "def go(:a), do: 1\n", "def go(:a), do: 1\n" <> code)

    assert Clause.insert_before(@src, "go/1", ":a", code) ==
             String.replace(@src, "  # first\n", code <> "  # first\n")
  end

  test "insert_before goes above the clause's comment and docs, not between them and its def" do
    out = Clause.insert_before(@src, "go/1", ":a", "def go(nil), do: 0")

    # ABOVE the comment, not between it and the clause it describes: `# first` labels go(:a), and a
    # @doc in that position would not merely be mislabelled — it would ATTACH to the new clause.
    assert out == String.replace(@src, "  # first\n", "  def go(nil), do: 0\n  # first\n")
  end

  test "an unknown clause is an error naming the candidates" do
    assert {:error, msg} = Clause.replace_body(@src, "go/1", ":zzz", "1")
    assert msg =~ "go/1"
    assert msg =~ ":a"
    assert {:error, _} = Clause.delete(@src, "nope/0", "", [])
  end

  test "find locates a clause with no opts, as the verbs address it" do
    assert {:ok, %{kind: :def, name: "go", args: ":b", guard: nil, head_text: ":b", indent: "  "}} =
             Clause.find(@src, "go/1", ":b")
  end

  test "a name/arity is matched as text, never made an atom: atoms are never collected" do
    name = "never_an_atom_#{System.unique_integer([:positive])}"

    assert Clause.delete(@src, "#{name}/1", "x") ==
             {:error, "no clause #{name}/1 with head `x` — have: none"}

    assert_raise ArgumentError, fn -> String.to_existing_atom(name) end
  end

  test "a file with several modules: Mod.name/arity scopes the edit; a bare name they share is refused" do
    src = "defmodule A do\n  def run(x), do: x\nend\n\ndefmodule B do\n  def run(x), do: x\nend\n"

    assert Clause.replace_body(src, "B.run/1", "x", "x + 1") ==
             "defmodule A do\n  def run(x), do: x\nend\n\ndefmodule B do\n  def run(x), do: x + 1\nend\n"

    assert {:error, msg} = Clause.replace_body(src, "run/1", "x", "x + 1")
    assert msg =~ "A, B"
    assert msg =~ "Mod.run/1"
    assert {:error, msg} = Clause.replace_body(src, "C.run/1", "x", "x + 1")
    assert msg =~ "no module C"
  end

  test "a guard is part of the head" do
    src = "defmodule G do\n  def f(x) when is_integer(x), do: x\n  def f(x), do: 0\nend\n"

    assert Clause.replace_body(src, "f/1", "x when is_integer(x)", "x * 2") ==
             "defmodule G do\n  def f(x) when is_integer(x), do: x * 2\n  def f(x), do: 0\nend\n"

    assert Clause.delete(src, "f/1", "x") == "defmodule G do\n  def f(x) when is_integer(x), do: x\nend\n"
  end

  describe "rewrite — the whole clause, head included" do
    test "changes the head, which replace_body structurally cannot" do
      out = Clause.rewrite(@src, "go/1", ":a", "def go(:a = atom), do: atom")
      assert out == String.replace(@src, "def go(:a), do: 1", "def go(:a = atom), do: atom")
    end

    test "adds a guard, keeping the rest of the file" do
      out = Clause.rewrite(@src, "go/1", "other", "def go(other) when is_integer(other), do: other")

      assert out ==
               String.replace(
                 @src,
                 "def go(other), do: other",
                 "def go(other) when is_integer(other), do: other"
               )
    end

    test "a multi-line clause is shifted out to the clause's own column" do
      out = Clause.rewrite(@src, "go/1", ":a", "def go(:a) do\n  1 + 1\nend")
      assert out == String.replace(@src, "  def go(:a), do: 1", "  def go(:a) do\n    1 + 1\n  end")
    end

    test "refuses one clause of several turned into another kind, name or arity — the module stops compiling" do
      assert Clause.rewrite(@src, "go/1", ":a", "defp go(:a), do: 1") ==
               {:error,
                "go/1 has other clauses, so this one stays `def go/1`, and CODE is `defp go/1` — " <>
                  "`visibility` flips every clause; a new function goes in with `insert_at`"}

      assert Clause.rewrite(@src, "go/1", ":b", "def go(:b, x), do: x") ==
               {:error,
                "go/1 has other clauses, so this one stays `def go/1`, and CODE is `def go/2` — " <>
                  "`visibility` flips every clause; a new function goes in with `insert_at`"}
    end

    test "the only clause is the whole function, and may change its kind, name or arity" do
      src = "defmodule O do\n  def go(x), do: x\nend\n"

      assert Clause.rewrite(src, "go/1", "x", "defp go(x, y), do: x + y") ==
               "defmodule O do\n  defp go(x, y), do: x + y\nend\n"
    end

    test "refuses a bare expression — that would leave a def replaced by an expression" do
      assert {:error, message} = Clause.rewrite(@src, "go/1", ":a", "1 + 1")
      assert message =~ "needs a whole clause"
    end

    test "refuses code that does not parse" do
      assert {:error, message} = Clause.rewrite(@src, "go/1", ":a", "def go(:a) do")
      assert message =~ "not parseable"
    end
  end

  describe "head matching tolerates the parens people copy off the def line" do
    test "`(:b)` finds the clause whose head is `:b`" do
      assert Clause.replace_body(@src, "go/1", "(:b)", "20") == String.replace(@src, "    2\n", "    20\n")
    end

    test "the parens may wrap the args of a GUARDED head, with the guard left outside" do
      src = "defmodule D do\n  def only(x) when is_integer(x), do: x\nend\n"
      out = Clause.replace_body(src, "only/1", "(x) when is_integer(x)", ":int")
      assert out == "defmodule D do\n  def only(x) when is_integer(x), do: :int\nend\n"
    end

    test "parens that are not a wrapper stay put — and the miss names the real head" do
      src = "defmodule D do\n  def pair(a, b), do: {a, b}\n  def pair(nil, b), do: b\nend\n"
      assert {:error, message} = Clause.replace_body(src, "pair/2", "(a), (b)", ":ok")
      assert message =~ "have: `a, b`"
    end

    test "the whole def line, or the call, finds the clause too" do
      assert Clause.replace_body(@src, "go/1", "def go(:b)", "20") ==
               String.replace(@src, "    2\n", "    20\n")

      assert Clause.replace_body(@src, "go/1", "go(:b)", "20") == String.replace(@src, "    2\n", "    20\n")

      src = "defmodule D do\n  defp only(x) when is_integer(x), do: x\nend\n"

      assert Clause.replace_body(src, "only/1", "defp only(x) when is_integer(x)", ":int") ==
               "defmodule D do\n  defp only(x) when is_integer(x), do: :int\nend\n"
    end

    test "an empty head is the function's only clause, and refused among several" do
      # with only one clause there is nothing to tell apart: an empty head means that one
      one = "defmodule D do\n  def pct(done, total), do: done / total\nend\n"

      assert Clause.replace_body(one, "pct/2", "", "done * 100 / total") ==
               "defmodule D do\n  def pct(done, total), do: done * 100 / total\nend\n"

      # with two, it still names the heads to choose from
      two = "defmodule D do\n  def pct(0, _), do: 0\n  def pct(done, total), do: done / total\nend\n"
      assert {:error, message} = Clause.replace_body(two, "pct/2", "", "1")
      assert message =~ "`0, _`"
      assert message =~ "`done, total`"
    end

    test "the def line copied with its do finds the clause" do
      assert Clause.replace_body(@src, "go/1", "def go(:b) do", "20") ==
               String.replace(@src, "    2\n", "    20\n")

      assert Clause.replace_body(@src, "go/1", "def go(:a), do:", "10") ==
               String.replace(@src, "do: 1", "do: 10")
    end

    test "the guard may be left off when it is not what tells the clauses apart" do
      src = "defmodule D do\n  def only(x) when is_integer(x), do: x\n  def only(y), do: y\nend\n"

      assert Clause.replace_body(src, "only/1", "x", ":int") ==
               String.replace(src, "is_integer(x), do: x", "is_integer(x), do: :int")

      # the guard is what tells these two apart: left off, the exact head wins, and a tie is refused
      tie = "defmodule D do\n  def f(x) when is_integer(x), do: x\n  def f(x) when is_atom(x), do: x\nend\n"
      assert {:error, message} = Clause.replace_body(tie, "f/1", "x", ":no")
      assert message =~ "is_integer"
      assert message =~ "is_atom"
    end

    test "a function with one clause answers to any head" do
      # one clause has nothing to tell apart, so a head that misses (the NEW one, on a rewrite) still means it
      one = "defmodule D do\n  def total(%{} = cart), do: cart\nend\n"

      assert Clause.rewrite(one, "total/1", "cart, rate", "def total(cart, rate), do: {cart, rate}") ==
               "defmodule D do\n  def total(cart, rate), do: {cart, rate}\nend\n"

      assert Clause.replace_body(one, "total/1", "whatever", ":ok") ==
               "defmodule D do\n  def total(%{} = cart), do: :ok\nend\n"
    end

    test "a test named as a function is refused with the block call that reaches it" do
      src =
        ~s|defmodule CartTest do\n  use ExUnit.Case\n\n  test "total includes tax" do\n    assert 1\n  end\nend\n|

      # as the eval's agents guessed it: the label as the name, or as the head
      for {name_arity, head} <- [{"total includes tax/0", ""}, {"total/0", ~s|"total includes tax"|}] do
        assert {:error, message} = Clause.replace_body(src, name_arity, head, ":ok")
        assert message =~ ~s|block replace FILE test --label "total includes tax"|
      end
    end
  end

  describe "insert_at — a new function, with no sibling clause to anchor to" do
    @mixed """
    defmodule M do
      def one, do: 1

      def two, do: 2

      defp helper, do: :h
    end
    """

    test "a defp lands after the last private function" do
      out = Clause.insert_at(@mixed, nil, nil, "defp fresh, do: :f")

      assert out ==
               String.replace(
                 @mixed,
                 "defp helper, do: :h\n",
                 "defp helper, do: :h\n\n  defp fresh, do: :f\n"
               )
    end

    test "a def lands after the last PUBLIC function, above the privates" do
      out = Clause.insert_at(@mixed, nil, nil, "def three, do: 3")
      assert out == String.replace(@mixed, "def two, do: 2\n", "def two, do: 2\n\n  def three, do: 3\n")
    end

    test ":top puts it before the module's first definition" do
      out = Clause.insert_at(@mixed, nil, :top, "def zero, do: 0")
      assert out == String.replace(@mixed, "  def one", "  def zero, do: 0\n\n  def one")
    end

    test ":bottom puts it after the module's last definition" do
      out = Clause.insert_at(@mixed, nil, :bottom, "def last, do: :l")

      assert out ==
               String.replace(@mixed, "defp helper, do: :h\n", "defp helper, do: :h\n\n  def last, do: :l\n")
    end

    test "an empty module takes the code just inside it" do
      out = Clause.insert_at("defmodule E do\nend\n", nil, nil, "def only, do: 1")
      assert out == "defmodule E do\n  def only, do: 1\nend\n"
    end

    test "a @doc above the code doesn't get mistaken for the thing being inserted" do
      out = Clause.insert_at(@mixed, nil, nil, "@doc \"h\"\ndefp documented, do: :d")

      assert out ==
               String.replace(
                 @mixed,
                 "defp helper, do: :h\n",
                 "defp helper, do: :h\n\n  @doc \"h\"\n  defp documented, do: :d\n"
               )
    end

    test "names the module in a file that has several" do
      src = "defmodule A do\n  def a, do: 1\nend\n\ndefmodule B do\n  def b, do: 2\nend\n"
      out = Clause.insert_at(src, "B", nil, "def added, do: 3")
      assert out == String.replace(src, "def b, do: 2\n", "def b, do: 2\n\n  def added, do: 3\n")
    end

    test "refuses an unnamed module when the file has several" do
      src = "defmodule A do\n  def a, do: 1\nend\n\ndefmodule B do\n  def b, do: 2\nend\n"
      assert {:error, message} = Clause.insert_at(src, nil, nil, "def added, do: 3")
      assert message =~ "several modules"
    end

    test "names the modules that exist when the one asked for does not" do
      assert {:error, message} = Clause.insert_at(@mixed, "Nope", nil, "def x, do: 1")
      assert message =~ "no module Nope"
      assert message =~ "M"
    end

    test "a blank line inside the new function stays blank, no trailing spaces" do
      code = "def spaced do\n  x = 1\n\n  x\nend"
      out = Clause.insert_at("defmodule E do\nend\n", nil, nil, code)
      assert out == "defmodule E do\n  def spaced do\n    x = 1\n\n    x\n  end\nend\n"
    end

    test "a multi-line string inside the new function keeps its value" do
      # the string's second line is part of its value: indenting it would change what it says
      code = "def two_lines do\n  \"one\ntwo\"\nend"
      out = Clause.insert_at(@mixed, nil, :bottom, code)

      assert out ==
               String.replace(
                 @mixed,
                 "defp helper, do: :h\n",
                 "defp helper, do: :h\n\n  def two_lines do\n    \"one\ntwo\"\n  end\n"
               )
    end
  end

  describe "delete takes the attributes attached to the clause" do
    @attrs """
    defmodule A do
      @impl Panel
      def go(:a), do: 1

      @impl Panel
      def go(:b), do: 2

      @impl Panel
      def go(:c), do: 3
    end
    """

    test "an @impl above a MIDDLE clause goes with it, or it re-attaches to the next one" do
      out = Clause.delete(@attrs, "go/1", ":b")

      # an @impl per surviving clause — a third would be the redefining warning
      assert out == String.replace(@attrs, "  @impl Panel\n  def go(:b), do: 2\n\n", "")
    end

    test "a @doc and @spec above the clause go with it" do
      src = """
      defmodule A do
        @doc "the one"
        @spec go(atom()) :: integer()
        def go(:a), do: 1

        def other, do: 2
      end
      """

      out = Clause.delete(src, "go/1", ":a")

      assert out == "defmodule A do\n  def other, do: 2\nend\n"
    end

    test "a comment written ABOVE the attribute goes too — the whole block is the clause" do
      src = """
      defmodule A do
        # why this exists
        @impl true
        def go(:a), do: 1

        def other, do: 2
      end
      """

      out = Clause.delete(src, "go/1", ":a")

      assert out == "defmodule A do\n  def other, do: 2\nend\n"
    end

    test "only CONTIGUOUS attributes count — a @doc on the FIRST clause survives deleting a later one" do
      src = """
      defmodule A do
        @doc "documents go/1"
        def go(:a), do: 1
        def go(:b), do: 2
      end
      """

      out = Clause.delete(src, "go/1", ":b")

      assert out == String.replace(src, "  def go(:b), do: 2\n", "")
    end

    test "deleting ONE clause of several keeps the function's @doc and @spec for the clauses left" do
      src = """
      defmodule A do
        @doc "documents go/1"
        @spec go(atom()) :: integer()
        # why :a
        @impl true
        def go(:a), do: 1

        def go(:b), do: 2
      end
      """

      assert Clause.delete(src, "go/1", ":a") == """
             defmodule A do
               @doc "documents go/1"
               @spec go(atom()) :: integer()
               def go(:b), do: 2
             end
             """
    end

    test "an attribute that is NOT clause-attached is left where it is" do
      src = """
      defmodule A do
        @timeout 5_000
        def go(:a), do: 1

        def other, do: @timeout
      end
      """

      out = Clause.delete(src, "go/1", ":a")

      assert out == String.replace(src, "  def go(:a), do: 1\n", "")
    end
  end

  describe "visibility — every clause at once" do
    @multi """
    defmodule A do
      @doc "what it does"
      @spec go(atom()) :: integer()
      def go(:a), do: 1
      def go(:b), do: 2
      def go(_other), do: 0

      def other, do: :ok
    end
    """

    test "privatize flips EVERY clause — a half-flipped function does not compile" do
      out = Clause.visibility(@multi, "go/1", :private)

      # the untouched neighbour keeps its visibility
      assert out ==
               @multi
               |> String.replace("  @doc \"what it does\"\n", "")
               |> String.replace("def go(", "defp go(")
    end

    test "privatize drops the @doc, which Elixir would discard with a warning" do
      out = Clause.visibility(@multi, "go/1", :private)

      # @spec is legal on a defp and stays
      assert out ==
               @multi
               |> String.replace("  @doc \"what it does\"\n", "")
               |> String.replace("def go(", "defp go(")
    end

    test "publicize flips them back" do
      private = Clause.visibility(@multi, "go/1", :private)
      out = Clause.visibility(private, "go/1", :public)

      assert out == String.replace(@multi, "  @doc \"what it does\"\n", "")
    end

    test "keeps the family — a defmacrop becomes a defmacro, not a def" do
      src = "defmodule A do\n  defmacrop m(x), do: x\nend\n"
      assert Clause.visibility(src, "m/1", :public) == "defmodule A do\n  defmacro m(x), do: x\nend\n"
    end

    test "already at the wanted visibility is a no-op, byte for byte" do
      assert Clause.visibility(@multi, "go/1", :public) == @multi
    end

    test "a function that isn't there is an error, not a silent no-op" do
      assert {:error, message} = Clause.visibility(@multi, "nope/9", :private)
      assert message =~ "nope/9"
    end

    test "only the named function moves" do
      out = Clause.visibility(@multi, "other/0", :private)

      assert out == String.replace(@multi, "def other", "defp other")
    end

    test "a zero-arity clause answers to its own name as a head" do
      src = """
      defmodule A do
        def bg, do: 0
      end
      """

      # a zero-arity clause has no head at all, so the name is the head a caller would write
      # and it stays paren-free: rewriting `def bg` as `def bg()` is a diff nobody asked for
      for head <- ["", "bg", "bg()", "def bg"] do
        assert Clause.replace_body(src, "bg/0", head, "1") == String.replace(src, "do: 0", "do: 1")
      end
    end

    test "replace_body never nests a def inside itself" do
      src = """
      defmodule A do
        def bg, do: 0
      end
      """

      # `def bg, do: def(bg, do: 1)` is VALID Elixir, so the parse-check passes and only the compiler
      # objects. A whole clause is refused toward `rewrite`, never nested
      assert {:error, message} = Clause.replace_body(src, "bg/0", "", "def bg, do: 1")
      assert message =~ "rewrite"
    end
  end

  test "move takes EVERY clause, with the doc, spec and comment above them" do
    src = """
    defmodule A do
      def stays, do: :here

      # why this one is special
      @doc "entry"
      @spec go(integer()) :: integer()
      def go(0), do: :zero
      def go(n), do: n + 1
    end
    """

    dest = """
    defmodule B do
      def existing, do: 1
    end
    """

    moved = """
      # why this one is special
      @doc "entry"
      @spec go(integer()) :: integer()
      def go(0), do: :zero
      def go(n), do: n + 1
    """

    {:ok, out_src, out_dest} = Clause.move(src, dest, "go/1")

    # a @doc or @spec left behind re-attaches to whatever definition follows it
    assert out_src == "defmodule A do\n  def stays, do: :here\nend\n"

    assert out_dest ==
             String.replace(dest, "  def existing, do: 1\n", "  def existing, do: 1\n\n" <> moved)
  end

  test "move closes the gap it leaves, and lands at the destination's own indent" do
    src = """
    defmodule A do
      def one, do: 1

      def go, do: :moved

      def two, do: 2
    end
    """

    {:ok, out_src, out_dest} = Clause.move(src, "defmodule B do\nend\n", "go/0")

    assert out_src == String.replace(src, "  def go, do: :moved\n\n", "")
    assert out_dest == "defmodule B do\n  def go, do: :moved\nend\n"
  end

  test "move refuses a function that is not there, naming it" do
    assert {:error, message} = Clause.move("defmodule A do\nend\n", "defmodule B do\nend\n", "nope/1")
    assert message =~ "nope/1"
  end

  test "replace keeps the clause's rescue, and only the body moves" do
    src = """
    defmodule A do
      def go(x) do
        risky(x)
      rescue
        _ -> :error
      end
    end
    """

    assert Clause.replace_body(src, "go/1", "x", "safer(x)\nlog(x)") == """
           defmodule A do
             def go(x) do
               safer(x)
               log(x)
             rescue
               _ -> :error
             end
           end
           """
  end

  test "a module name scopes to that module, not the modules nested in it" do
    src = """
    defmodule Outer do
      def foo(x), do: x

      defmodule Inner do
        def foo(x), do: x + 1
      end
    end
    """

    assert Clause.replace_body(src, "Outer.foo/1", "x", ":outer") ==
             String.replace(src, "def foo(x), do: x\n", "def foo(x), do: :outer\n")

    assert Clause.replace_body(src, "Outer.Inner.foo/1", "x", ":inner") ==
             String.replace(src, "do: x + 1", "do: :inner")

    assert {:error, message} = Clause.replace_body(src, "foo/1", "x", ":any")
    assert message =~ "Outer, Outer.Inner"
  end

  test "a body with keywords of its own is not handed to a do: clause's def" do
    src = """
    defmodule A do
      def f(x), do: x
    end
    """

    assert Clause.replace_body(src, "f/1", "x", "if x, do: 1, else: 2") == """
           defmodule A do
             def f(x) do
               if x, do: 1, else: 2
             end
           end
           """
  end

  test "a body Elixir reads back only with a warning, inline, goes in a do block" do
    src = "defmodule A do\n  def f(x), do: x\nend\n"

    for code <- ["foo 1, a: 2", "x |> foo 1"] do
      assert Clause.replace_body(src, "f/1", "x", code) ==
               "defmodule A do\n  def f(x) do\n    #{code}\n  end\nend\n"
    end
  end

  test "replacing a do: body that is a literal keeps the blank line after it" do
    src = """
    defmodule A do
      defp x?(_node), do: false

      defp y, do: 1
    end
    """

    assert Clause.replace_body(src, "x?/1", "_node", "true") == String.replace(src, "do: false", "do: true")
  end

  test "a body carrying its own rescue into a clause that has one is refused, not doubled" do
    src = """
    defmodule A do
      def go(x) do
        risky(x)
      rescue
        _ -> :error
      end
    end
    """

    assert {:error, message} = Clause.replace_body(src, "go/1", "x", "safer(x)\nrescue\n  _ -> :other")
    assert message =~ "rewrite"
  end

  test "a DIFFERENT function inserted beside one clause goes around the whole function, never inside it" do
    src = """
    defmodule A do
      def a(1), do: 1
      def a(2), do: 2

      def z, do: :z
    end
    """

    after_out = Clause.insert_after(src, "a/1", "1", "defp helper, do: :h")
    assert after_out == String.replace(src, "def a(2), do: 2\n", "def a(2), do: 2\n\n  defp helper, do: :h\n")

    before_out = Clause.insert_before(src, "a/1", "2", "defp helper, do: :h")
    assert before_out == String.replace(src, "  def a(1)", "  defp helper, do: :h\n\n  def a(1)")
  end

  test "a head with defaults answers without them too" do
    src = """
    defmodule A do
      def go(a, opts \\\\ []), do: {a, opts}
    end
    """

    assert Clause.replace_body(src, "go/2", "a, opts", ":bare") ==
             String.replace(src, "do: {a, opts}", "do: :bare")

    assert Clause.replace_body(src, "go/2", "a, opts \\\\ []", ":full") ==
             String.replace(src, "do: {a, opts}", "do: :full")
  end

  test "a body starting with x not in y is replaced from its first byte" do
    # Sourceror starts `name not in [...]` at `not`; the patch left `name ` in front of the new body
    src = "defmodule B do\n  defp keep?(name) do\n    name not in [:def] and\n      ok?(name)\n  end\nend\n"

    assert Clause.replace_body(src, "keep?/1", "name", "name in [:x]") ==
             String.replace(src, "name not in [:def] and\n      ok?(name)", "name in [:x]")
  end

  test "a module defined twice is refused by name, not edited in the first" do
    # a module defined twice (`if Code.ensure_loaded?(Decimal) do … else … end`): an edit landed in the
    # first whatever was meant, and one set from the second's value swapped them
    src = """
    if Code.ensure_loaded?(Decimal) do
      defmodule Money do
        @moduledoc "with Decimal"
        def go, do: 1
      end
    else
      defmodule Money do
        @moduledoc false
        def go, do: 2
      end
    end
    """

    assert {:error, message} = Menard.Attr.set(src, "moduledoc", "false", module: "Money")
    assert message =~ "Money is defined 2 times"
    assert {:error, _} = Clause.replace_body(src, "Money.go/0", "", "3")
  end

  test "rewrite's leading comment lands above the clause's @impl, where clause comment puts one" do
    src = "defmodule T do\n  @impl true\n  def run(argv), do: argv\nend\n"
    out = Clause.rewrite(src, "run/1", "argv", "# why\ndef run(args), do: args")
    assert out == "defmodule T do\n  # why\n  @impl true\n  def run(args), do: args\nend\n"
  end

  test "replace handed a whole clause is refused toward rewrite, the function's own or another's" do
    src = "defmodule T do\n  def total(cart), do: cart\nend\n"
    # as the eval's agents wrote it: the def line and all. One name per edit: `rewrite` is that one
    assert {:error, message} =
             Clause.replace_body(src, "total/1", "cart", "def total(cart) do\n  cart * 2\nend")

    assert message =~ "rewrite"
    assert {:error, message} = Clause.replace_body(src, "total/1", "cart", "def other(x), do: x")
    assert message =~ "rewrite"
    # a comment above the def hid that it was a whole clause, and it was nested in the old one:
    # it parsed, and did not compile (found fixing bench1's bugs)
    assert {:error, message} =
             Clause.replace_body(src, "total/1", "cart", "# why\ndef total(cart) do\n  cart * 2\nend")

    assert message =~ "rewrite"
  end

  test "delete_function takes every clause, with the @doc, @spec and comments above them" do
    src = """
    defmodule A do
      def keep, do: 1

      # why two
      @doc "Two."
      @spec two(integer()) :: integer()
      def two(1), do: 1
      def two(n), do: n * 2

      def after_it, do: 3
    end
    """

    assert Clause.delete_function(src, "two/1") ==
             "defmodule A do\n  def keep, do: 1\n\n  def after_it, do: 3\nend\n"

    assert {:error, _} = Clause.delete_function(src, "nope/1")
  end

  test "get: one clause by its head, or with no head the whole function, as written" do
    # bench2 bug-receipt-total.B.haiku asked clause for "get": reading one function, not the file
    src = """
    defmodule A do
      def keep, do: 1

      # why two
      @doc "Two."
      def two(1), do: 1
      def two(n), do: n * 2
    end
    """

    assert {:ok, %{code: "# why two\n@doc \"Two.\"\ndef two(1), do: 1\ndef two(n), do: n * 2", lines: [4, 7]}} =
             Clause.get(src, "two/1", nil)

    assert {:ok, %{code: "def two(n), do: n * 2", lines: [7, 7]}} = Clause.get(src, "two/1", "n")
    assert {:error, _} = Clause.get(src, "nope/0", nil)
  end

  test "naming a test macro as the function points at block, which reaches the tests" do
    # bench3 move-function.B.sonnet: stmt list with name_arity "test/2", told only "have: none"
    src = "defmodule ATest do\n  use ExUnit.Case\n\n  test \"a\" do\n    assert 1\n  end\nend\n"
    assert {:error, message} = Clause.replace_body(src, "test/2", "", "x")
    assert message =~ "block"
    assert message =~ ~s(name: "test")
  end

  test "a whole clause under its @doc is the rewrite, and takes the old @doc's place" do
    # long1 cart-refactor.B.haiku: clause replace with `@doc """…"""` + def nested the @doc in the
    # old body, "cannot set attribute @doc inside function/macro", and the step ended not compiling
    src = "defmodule A do\n  @doc \"Old.\"\n  def f(x), do: x\n\n  def g, do: 1\nend\n"
    code = "@doc \"New.\"\n@spec f(integer()) :: integer()\ndef f(x) do\n  x + 1\nend"

    out = Clause.rewrite(src, "f/1", "x", code)

    assert out ==
             "defmodule A do\n  @doc \"New.\"\n  @spec f(integer()) :: integer()\n  def f(x) do\n    x + 1\n  end\n\n  def g, do: 1\nend\n"
  end

  test "rewrite takes the clause and whatever the code adds after it: a new function beside it" do
    # long1 cart-refactor.B.sonnet rewrote product_card/1 and added availability/1 in one call, and
    # was told it needed a whole clause
    src = "defmodule A do\n  def card(x), do: x\nend\n"
    code = "def card(x), do: badge(x)\n\n@doc \"The badge.\"\ndef badge(x), do: x"
    out = Clause.rewrite(src, "card/1", "x", code)

    assert out ==
             "defmodule A do\n  def card(x), do: badge(x)\n\n  @doc \"The badge.\"\n  def badge(x), do: x\nend\n"
  end

  test "a component's attr and slot lines belong to its def: insert_before goes above them, delete takes them" do
    # bench4 new-component.B.haiku inserted a new component before product_card/1 and it landed
    # between product_card's `attr :product` and its def: a duplicate attr, a compile error
    src =
      "defmodule C do\n  use Phoenix.Component\n\n  attr :product, :map, required: true\n  slot :inner_block\n\n  def card(assigns) do\n    ~H\"x\"\n  end\nend\n"

    out =
      Clause.insert_before(
        src,
        "card/1",
        "assigns",
        "attr :product, :map\n\ndef badge(assigns) do\n  ~H\"y\"\nend"
      )

    assert out ==
             String.replace(
               src,
               "  attr :product, :map, required: true\n",
               "  attr :product, :map\n\n  def badge(assigns) do\n    ~H\"y\"\n  end\n\n  attr :product, :map, required: true\n"
             )

    assert Clause.delete(src, "card/1", "assigns") == "defmodule C do\n  use Phoenix.Component\nend\n"
  end

  test "a head that is part of exactly one clause's head names that clause" do
    # bench4 new-module.B.haiku addressed apply_code/2 by "TENOFF", the argument that tells its
    # clauses apart, and was refused with the three heads
    src =
      "defmodule D do\n  def apply_code(cents, \"TENOFF\"), do: div(cents * 9, 10)\n  def apply_code(cents, \"FIVE\"), do: max(cents - 500, 0)\n  def apply_code(_cents, _code), do: :error\nend\n"

    assert Clause.replace_body(src, "apply_code/2", ~s|"TENOFF"|, "cents") ==
             String.replace(src, "do: div(cents * 9, 10)", "do: cents")

    # a part that fits several is still refused
    assert {:error, _} = Clause.replace_body(src, "apply_code/2", "cents", "0")
  end

  test "naming a type where a function goes says it is a type, and what reaches it" do
    # bench3 and bench4 not-compiling.B.haiku: clause t/0 for `@type t ::`, told "have: none"
    src = "defmodule P do\n  defstruct [:a]\n  @type t :: %__MODULE__{a: integer()}\nend\n"
    assert {:error, message} = Clause.replace_body(src, "t/0", "", "x")
    assert message =~ "@type t"
    assert message =~ "stmt"
  end

  test "a whole component, its attr lines and @doc above the def, is a rewrite; replace refuses it" do
    # long2 cart-refactor.B.haiku replaced cart_summary/1 with `attr …` `attr …` `@doc …` then the def:
    # not seen as a whole clause, nested in the old body, and step 02 ended not compiling again
    src =
      "defmodule C do\n  use Phoenix.Component\n\n  attr :cart, :map, required: true\n\n  @doc \"Old.\"\n  def summary(assigns) do\n    ~H\"old\"\n  end\nend\n"

    code =
      "attr :cart, :map, required: true\nattr :region, :atom, default: :home\n\n@doc \"New.\"\ndef summary(assigns) do\n  ~H\"new\"\nend"

    assert {:error, message} = Clause.replace_body(src, "summary/1", "assigns", code)
    assert message =~ "rewrite"

    out = Clause.rewrite(src, "summary/1", "assigns", code)

    assert out ==
             "defmodule C do\n  use Phoenix.Component\n\n" <>
               "  attr :cart, :map, required: true\n  attr :region, :atom, default: :home\n\n" <>
               "  @doc \"New.\"\n  def summary(assigns) do\n    ~H\"new\"\n  end\nend\n"
  end

  test "a defguard or a defdelegate has no body: replace_body is refused toward rewrite, never written as `do … end`" do
    # written as a clause with a body, `defguard is_x(x) when … do` parses and does not compile
    src =
      "defmodule G do\n  defguard is_x(x) when is_integer(x)\n  defdelegate d(x), to: Enum, as: :count\nend\n"

    assert {:error, message} = Clause.replace_body(src, "is_x/1", "x", "is_atom(x)")
    assert message =~ "defguard"
    assert message =~ "rewrite"

    assert {:error, message} = Clause.replace_body(src, "d/1", "x", "x")
    assert message =~ "defdelegate"

    assert Clause.rewrite(src, "is_x/1", "x", "defguard is_x(x) when is_atom(x)") ==
             String.replace(src, "when is_integer(x)", "when is_atom(x)")
  end
end
