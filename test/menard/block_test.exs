defmodule Menard.BlockTest do
  # A macro's do-block: schema do, describe "…" do, test "…" do.
  use ExUnit.Case, async: true

  alias Menard.Block

  @src """
  defmodule A do
    schema do
      field(:x, :string)
      field(:y, :integer)
    end

    describe "one" do
      test "a" do
        assert 1 == 1
      end
    end

    describe "two" do
      test "b" do
        assert 2 == 2
      end
    end
  end
  """

  test "replace swaps a block's body, keeping the header line and the end" do
    out = Block.replace(@src, "schema", "field(:only, :string)")

    assert out =~ "schema do\n    field(:only, :string)\n  end"
    refute out =~ "field(:y, :integer)"
    assert out =~ ~s(describe "one" do)
  end

  test "get reads a block's body as written" do
    assert Block.get(@src, "schema") =~ "field(:x, :string)"
  end

  test "a block name the source never mentions makes no atom: the VM never collects one" do
    name = "never_block_#{System.unique_integer([:positive])}"
    assert {:error, _} = Block.get(@src, name)
    assert Block.get_all(@src, name) == []
    assert_raise ArgumentError, fn -> String.to_existing_atom(name) end
    # adding one writes the name into the source, and the write parse-checks it: that makes the atom
    assert Block.add(@src, name, "x", "assert true") =~ ~s(#{name} "x" do)
  end

  test "a label addresses one of several blocks sharing a name" do
    out = Block.replace(@src, "describe", "test \"c\" do\n  assert 3 == 3\nend", label: "two")

    assert out =~ ~s(describe "two" do\n    test "c" do)
    assert out =~ ~s(test "a" do)
  end

  test "several blocks of one name with no label is refused, listing them" do
    assert {:error, message} = Block.replace(@src, "describe", "x")
    assert message =~ "2 `describe` blocks"
    assert message =~ ~s("one")
    assert message =~ ~s("two")
  end

  test "a block that isn't there is an error, not a silent no-op" do
    assert {:error, message} = Block.get(@src, "nope")
    assert message =~ "no `nope do` block"
  end

  test "list finds nested blocks too — a test lives inside a describe" do
    found = Block.list(@src)

    assert {:schema, nil, _line} = Enum.find(found, &(elem(&1, 0) == :schema))
    assert Enum.any?(found, &match?({:test, "a", _}, &1))
  end

  test "def and defmodule are not blocks — they have their own verbs" do
    names = @src |> Block.list() |> Enum.map(&elem(&1, 0))
    refute :defmodule in names
    refute :def in names
  end

  test "add writes a new block after the last sibling of its name" do
    out = Block.add(@src, "describe", "three", "test \"c\" do\n  assert 3 == 3\nend")

    assert out =~ ~s(describe "three" do)
    assert out =~ ~s(describe "two" do)
    # the new one lands AFTER the last sibling, not before the first
    assert String.slice(out, 0, :binary.match(out, "describe \"three\"") |> elem(0)) =~ "describe \"two\""
  end

  test "add --in appends inside the named parent block" do
    out = Block.add(@src, "test", "c", "assert 3 == 3", in: "two")

    # inside the named describe, at its end — where a new test goes
    assert out =~ ~s(test "b" do\n      assert 2 == 2\n    end\n\n    test "c" do)
    # and not inside the other one
    refute out =~ ~s(test "a" do\n      assert 1 == 1\n    end\n\n    test "c")
  end

  test "a label-less macro (setup do) is added without one" do
    out = Block.add(@src, "setup", nil, ":ok")

    assert out =~ "setup do\n    :ok\n  end"
  end

  test "an --in parent that isn't there is refused, not guessed at" do
    assert {:error, message} = Block.add(@src, "test", "x", "assert true", in: "nope")
    assert message =~ "no block or module"
  end

  test "replace on a do: block keeps the call line" do
    src = """
    defmodule ATest do
      use ExUnit.Case
      test "one", do: assert(1 == 1)
    end
    """

    assert Block.replace(src, "test", "assert 2 == 2", label: "one") =~ ~s(test "one", do: assert 2 == 2)

    assert Block.replace(src, "test", "x = 2\nassert x == 2", label: "one") == """
           defmodule ATest do
             use ExUnit.Case
             test "one" do
               x = 2
               assert x == 2
             end
           end
           """
  end

  test "replace of a body that ends in a heredoc keeps the end" do
    src = """
    defmodule ATest do
      use ExUnit.Case

      test "t" do
        assert x() == \"\"\"
        a
        \"\"\"
      end
    end
    """

    assert Block.replace(src, "test", "assert true", label: "t") =~ "test \"t\" do\n    assert true\n  end\n"
  end

  test "get returns the body alone, dedented — for do: and do…end alike" do
    src = """
    defmodule ATest do
      use ExUnit.Case
      test "one", do: assert(1 == 1)

      test "two" do
        x = 2
        assert x == 2
      end
    end
    """

    assert Block.get(src, "test", label: "one") == "assert(1 == 1)"
    assert Block.get(src, "test", label: "two") == "x = 2\nassert x == 2"
  end

  test "control flow inside a function is not a block — that is stmt's" do
    src = """
    defmodule A do
      schema "t" do
        field :a
      end

      def go(x) do
        if x do
          :y
        end
      end
    end
    """

    assert Block.list(src) == [{:schema, "t", 2}]
  end

  test "delete removes one block, its glued comment, and the blank line it leaves" do
    src = """
    defmodule ATest do
      use ExUnit.Case

      # about one
      test "one" do
        assert 1
      end

      test "two" do
        assert 2
      end
    end
    """

    assert Block.delete(src, "test", label: "one") == """
           defmodule ATest do
             use ExUnit.Case

             test "two" do
               assert 2
             end
           end
           """

    assert {:error, _} = Block.delete(src, "test", label: "nope")
  end

  test "add writes a test that takes the context" do
    src = """
    defmodule ATest do
      use ExUnit.Case

      test "one" do
        assert 1
      end
    end
    """

    out = Block.add(src, "test", "with ctx", "assert ws", args: "%{workspace: ws}")
    assert out =~ ~s(test "with ctx", %{workspace: ws} do\n    assert ws\n  end)
  end

  test "replace handed the whole block it names takes that block's body" do
    # a whole `describe "two" do … end` where its body was asked for: the body is taken, not nested
    code = "describe \"two\" do\n  test \"c\" do\n    assert 3 == 3\n  end\nend"
    out = Block.replace(@src, "describe", code, label: "two")
    assert out =~ "describe \"two\" do\n    test \"c\" do\n      assert 3 == 3\n    end\n  end"
    refute out =~ "describe \"two\" do\n    describe"
    # one labelled otherwise is a mistake, not a shorthand; the refusal says which, and the way to
    # rename (an agent read "pass what goes inside it" and lost turns: the label was the difference)
    other = "describe \"three\" do\n  test \"c\" do\n    assert 3 == 3\n  end\nend"
    assert {:error, message} = Block.replace(@src, "describe", other, label: "two")
    assert message =~ ~s(`describe "three"`)
    assert message =~ ~s(`describe "two"`)
    assert message =~ "relabel"
  end

  test "replace with a body that repeats its leading comment writes it once" do
    # a new body that opens with the comment the old one opened with: once, not twice
    src = """
    defmodule A do
      describe "one" do
        # the setup these share
        test "a" do
          assert 1 == 1
        end
      end
    end
    """

    body = "# the setup these share\ntest \"b\" do\n  assert 2 == 2\nend"
    once = Block.replace(src, "describe", body, label: "one")
    assert length(String.split(once, "# the setup these share")) == 2

    # a duplicate already there is cleared by the next replace, and a body with no comment keeps it
    doubled = String.replace(src, "    # the setup", "    # the setup these share\n    # the setup")

    assert length(
             String.split(Block.replace(doubled, "describe", body, label: "one"), "# the setup these share")
           ) == 2

    assert Block.replace(src, "describe", "test \"c\", do: :ok", label: "one") =~ "# the setup these share"
  end

  test "add writes the @tags above the test it adds" do
    # a test that takes a tmp_dir needs its @tag right above it; with no way to write one it took a
    # @moduletag, or a hand edit
    out =
      Block.add(@src, "test", "c", "assert File.dir?(dir)",
        in: "two",
        args: "%{tmp_dir: dir}",
        tag: [":tmp_dir", "timeout: 5_000"]
      )

    assert out =~ ~s(    @tag :tmp_dir\n    @tag timeout: 5_000\n    test "c", %{tmp_dir: dir} do)

    # a bare name is the tag, as `--tag tmp_dir` means it: written as it was, `@tag tmp_dir` is a
    # variable, and the test file did not compile
    out = Block.add(@src, "test", "c", "assert dir", in: "two", args: "%{tmp_dir: dir}", tag: ["tmp_dir"])
    assert out =~ ~s(    @tag :tmp_dir\n    test "c")
  end

  test "add with no macro name is refused, naming the fix, not written as unparseable code" do
    for name <- ["", nil] do
      assert {:error, message} = Block.add(@src, name, "x", "assert true")
      assert message =~ "test"
    end
  end

  test "replace fills an empty body, where there is no body to take a range from" do
    src = "defmodule ATest do\n  use ExUnit.Case\n\n  test \"e\" do\n  end\nend\n"

    assert Block.replace(src, "test", "assert 1 == 1", label: "e") ==
             "defmodule ATest do\n  use ExUnit.Case\n\n  test \"e\" do\n    assert 1 == 1\n  end\nend\n"
  end

  test "add handed a whole block of its macro writes that block, not one nested in another" do
    # as the eval's agent wrote it: name and label given, and the whole describe as the code
    code =
      "describe \"three\" do\n  @tag :tmp_dir\n  test \"c\", %{tmp_dir: dir} do\n    assert dir\n  end\nend"

    # a label that differs is the agent paraphrasing the block it wrote (long1 cart-refactor.B.sonnet),
    # never a block to nest it in: a describe does not nest, nor a test in a test
    for label <- ["three", nil, "four"] do
      out = Block.add(@src, "describe", label, code)
      assert out =~ "describe \"three\" do\n    @tag :tmp_dir\n    test \"c\""
      refute out =~ "describe \"three\" do\n    describe"
      refute out =~ "four"
    end
  end

  test "add handed a whole test keeps its context and every comment in its body" do
    # the CLI passes `args: nil` when --args is not given, and that dropped the context; the body was
    # sliced from its first expression, and that dropped a comment above it
    code = "test \"c\", %{tmp_dir: dir} do\n  # why\n  assert dir\n  # after\nend"

    for opts <- [[], [args: nil]] do
      out = Block.add(@src, "test", nil, code, opts)
      assert out =~ ~r/test "c", %\{tmp_dir: dir\} do\n\s+# why\n\s+assert dir\n\s+# after\n\s+end/
    end
  end

  test "add handed several whole tests adds each, and a block that does not parse says so" do
    # bench1 new-component.B.haiku gave two whole tests in one add and was told to pass a body;
    # and a whole test with a stray paren was told the same, not that it did not parse
    code = "test \"x\", %{a: a} do\n  assert a\nend\n\ntest \"y\" do\n  assert 2\nend"

    for label <- ["x", nil] do
      out = Block.add(@src, "test", label, code)
      assert out =~ ~r/test "x", %\{a: a\} do\n\s+assert a\n\s+end/
      assert out =~ ~r/test "y" do\n\s+assert 2\n\s+end/
    end

    assert {:error, message} = Block.add(@src, "test", nil, "test \"z\" do\n  assert f(1))\nend")
    assert message =~ "does not parse"
  end

  test "get_all: every block of the name, each with its label, line and body" do
    # bench3 new-component.B.haiku asked block for the tests with no label and was told to pick one
    src =
      "defmodule ATest do\n  use ExUnit.Case\n\n  test \"a\" do\n    assert 1\n  end\n\n  test \"b\" do\n    assert 2\n  end\nend\n"

    assert [%{label: "a", line: 4, code: "assert 1"}, %{label: "b", line: 8, code: "assert 2"}] =
             Block.get_all(src, "test")
  end

  test "a label with no name finds its block, whatever the macro" do
    # bench3 new-component.B.sonnet: replace {label: "…"} with no name was told there was no such block
    out = Block.replace(@src, nil, "assert 9 == 9", label: "b")
    assert out =~ ~s(test "b" do\n      assert 9 == 9)
  end

  test "add handed a whole block names it by the block's own label, whatever label came with it" do
    # long1 cart-refactor.B.sonnet: label "…and no placeholders", the test "…and leaves no placeholders";
    # a block being added has nothing to be told apart from
    code = "test \"c, as written\" do\n  assert 3 == 3\nend"
    out = Block.add(@src, "test", "c, as asked", code)
    assert out =~ ~s(test "c, as written" do)
    refute out =~ "as asked"
  end

  test "no name, a whole block as the code: the block names its macro" do
    # long2 cart-refactor.B.haiku: block with no name and a whole `test "…" do … end`, refused as
    # "a whole `` block"
    code = "test \"c\" do\n  assert 3 == 3\nend"
    assert Block.add(@src, nil, nil, code) =~ ~s(test "c" do\n)
    out = Block.replace(@src, "", "test \"b\" do\n  assert 9 == 9\nend", label: "b")
    assert out =~ ~s(test "b" do\n      assert 9 == 9)
  end

  test "a whole test with its @tag above is added whole, the tag above it" do
    # an agent writes a tmp_dir test as it reads in a file, @tag and all: that was taken for a body
    # and wrapped in a bare `test do`, which parses and does not compile
    code = ~s|@tag :tmp_dir\ntest "d", %{tmp_dir: dir} do\n  assert File.dir?(dir)\nend|
    out = Block.add(@src, "test", nil, code, in: "two")

    assert out =~ ~s|    @tag :tmp_dir\n    test "d", %{tmp_dir: dir} do\n      assert File.dir?(dir)|
    refute out =~ "test do"
  end

  # Work counted, not timed: the calling process's reductions for listing a module's blocks, the
  # parse already cached, at n and 4n tests. Linear measured 4.1x; collecting with `acc ++ [node]`
  # copied the list at every block found, 10-12x. `++` bumps reductions per chunk it copies, not per
  # cell, so below ~8k blocks the traversal hides it: these sizes are where it shows.
  test "collecting a module's blocks is linear in how many it has" do
    work = fn n ->
      src = "defmodule Big do\n" <> Enum.map_join(1..n, &"  test \"t#{&1}\" do\n    :ok\n  end\n") <> "end\n"
      ^n = length(Block.list(src))
      {:reductions, before} = Process.info(self(), :reductions)
      Block.list(src)
      {:reductions, later} = Process.info(self(), :reductions)
      later - before
    end

    ratio = work.(32_000) / work.(8_000)
    assert ratio < 7, "4x the blocks cost #{Float.round(ratio, 1)}x the work"
  end

  test "replace handed a whole test with other args takes its args with its body" do
    # the whole test given with a context the file's test lacked: only the body was taken, and the
    # `dir` in it was an undefined variable
    src =
      "defmodule T do\n  test \"a\" do\n    assert 1\n  end\n\n  test \"b\", %{x: x} do\n    assert x\n  end\nend\n"

    assert Block.replace(src, "test", "test \"a\", %{tmp_dir: dir} do\n  assert dir\nend", label: "a") ==
             String.replace(
               src,
               "test \"a\" do\n    assert 1",
               "test \"a\", %{tmp_dir: dir} do\n    assert dir"
             )

    assert Block.replace(src, "test", "test \"b\", %{y: y} do\n  assert y\nend", label: "b") ==
             String.replace(src, "%{x: x} do\n    assert x", "%{y: y} do\n    assert y")

    # the same args, or a bare body: the head stays as written
    assert Block.replace(src, "test", "test \"b\", %{x: x} do\n  assert !x\nend", label: "b") ==
             String.replace(src, "assert x", "assert !x")

    assert Block.replace(src, "test", "assert 2", label: "a") == String.replace(src, "assert 1", "assert 2")
  end

  test "add keeps a blank line in the body blank, no trailing spaces" do
    out = Block.add(@src, "test", "c", "x = 3\n\nassert x == 3", in: "two")

    assert out ==
             String.replace(
               @src,
               "      assert 2 == 2\n    end\n",
               "      assert 2 == 2\n    end\n\n    test \"c\" do\n      x = 3\n\n      assert x == 3\n    end\n"
             )
  end

  test "add keeps a multi-line string in the body at its value" do
    # the string's second line is part of its value: indenting it would change what it says
    out = Block.add(@src, "test", "c", "assert \"one\ntwo\" =~ \"t\"", in: "two")

    assert out ==
             String.replace(
               @src,
               "      assert 2 == 2\n    end\n",
               "      assert 2 == 2\n    end\n\n    test \"c\" do\n      assert \"one\ntwo\" =~ \"t\"\n    end\n"
             )
  end

  test "replace handed a whole test with @tag lines above it takes them as the test's tags" do
    # Found 2026-09-26: a whole test with an `@tag` above it was taken for a body, and came out as a
    # test nested in the old one. Its tags are the test's own: they replace the ones above it.
    src = """
    defmodule T do
      use ExUnit.Case

      @tag :tmp_dir
      test "one", %{tmp_dir: dir} do
        assert dir
      end

      test "two" do
        assert 2
      end
    end
    """

    tagged = "@tag skip: \"no toolchain\"\ntest \"one\" do\n  assert 1\nend"

    assert Block.replace(src, "test", tagged, label: "one") == """
           defmodule T do
             use ExUnit.Case

             @tag skip: "no toolchain"
             test "one", %{tmp_dir: dir} do
               assert 1
             end

             test "two" do
               assert 2
             end
           end
           """

    # a tag put above a test that had none
    assert Block.replace(src, "test", "@tag :slow\ntest \"two\" do\n  assert 2\nend", label: "two") =~
             ~s(  end\n\n  @tag :slow\n  test "two" do\n)

    # a whole test with no tags keeps the ones it has
    assert Block.replace(src, "test", "test \"one\", %{tmp_dir: dir} do\n  assert dir != nil\nend",
             label: "one"
           ) =~
             ~s(  @tag :tmp_dir\n  test "one", %{tmp_dir: dir} do\n    assert dir != nil\n)

    # tags above a body are not the test's: there is nothing to put them over
    assert {:error, "an @tag" <> _} = Block.replace(src, "test", "@tag :slow\nassert 2", label: "two")
  end

  test "a label finds its block in whichever module of the file holds it" do
    # mcp_test.exs holds three modules: `block get … --label` was refused, "name one", though the label
    # named one test of all of them
    src =
      "defmodule ATest do\n  use ExUnit.Case\n  test \"a\" do\n    assert 1\n  end\nend\n\ndefmodule BTest do\n  use ExUnit.Case\n  test \"b\" do\n    assert 2\n  end\nend\n"

    assert Block.get(src, "test", label: "b") == "assert 2"
    assert {:error, why} = Block.get(src, "test", [])
    assert why =~ "several modules"
  end
end
