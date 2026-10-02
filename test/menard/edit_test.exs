defmodule Menard.EditTest do
  # `edit`: several replacements, across files, in ONE call. What agents write a Python heredoc
  # for (`s = s.replace(old, new)`, file after file, then the tests): in the eval's traces the most
  # common way a capable model edits Elixir, and one whose replace says nothing when the text it
  # looks for is not there.
  use ExUnit.Case, async: true

  alias Menard.Test.Host
  alias Menard.Verbs

  @moduletag :tmp_dir

  setup %{tmp_dir: dir} do
    Host.mix_project(dir, :edits)
    File.mkdir_p!(Path.join(dir, "lib"))
    File.write!(Path.join(dir, ".formatter.exs"), "[inputs: [\"lib/**/*.ex\"]]")
    File.write!(Path.join(dir, "lib/a.ex"), "defmodule A do\n  def one, do: 1\n  def two, do: 2\nend\n")
    File.write!(Path.join(dir, "lib/b.ex"), "defmodule B do\n  def go, do: A.one()\nend\n")
    File.write!(Path.join(dir, "notes.md"), "one\n")
    :ok
  end

  # as both doors call it: `then` runs in `Menard.Verbs.call/2`
  defp edit(dir, edits, more \\ %{}), do: Verbs.call(Verbs.Edit, Map.merge(%{root: dir, edits: edits}, more))
  defp read(dir, file), do: File.read!(Path.join(dir, file))

  test "every replacement is made, in every file, and each file answers with what changed", %{
    tmp_dir: dir
  } do
    assert {:ok, reply} =
             edit(dir, [
               %{file: "lib/a.ex", old: "def one, do: 1", new: "def uno, do:   1"},
               %{file: "lib/a.ex", old: "def two, do: 2", new: "def two, do: 22"},
               %{file: "lib/b.ex", old: "A.one()", new: "A.uno()"}
             ])

    assert reply.did == "edit a.ex, b.ex: 3 replacements"
    # written through the one pipeline: parse-checked, and formatted by the project's formatter
    assert read(dir, "lib/a.ex") == "defmodule A do\n  def uno, do: 1\n  def two, do: 22\nend\n"
    assert read(dir, "lib/b.ex") =~ "A.uno()"
    assert [%{file: a, version: "sha256:" <> _} = first, %{file: b} = second] = reply.changed
    assert {Path.basename(a), Path.basename(b)} == {"a.ex", "b.ex"}
    # what the caller wrote is not said back: what the formatter made of it is, where it made anything
    assert [%{stage: :formatter, hunks: [%{added: ["  def uno, do: 1"]}]}] = first.stages
    refute is_map_key(second, :stages)
  end

  test "a text that is not there refuses the whole call, and says which", %{tmp_dir: dir} do
    before = {read(dir, "lib/a.ex"), read(dir, "lib/b.ex")}

    assert {:error, why} =
             edit(dir, [
               %{file: "lib/a.ex", old: "def one, do: 1", new: "def uno, do: 1"},
               %{file: "lib/b.ex", old: "A.once()", new: "A.uno()"}
             ])

    assert why =~ "nothing was written"
    assert why =~ "lib/b.ex"
    assert why =~ "A.once()"
    assert why =~ "not there"
    assert {read(dir, "lib/a.ex"), read(dir, "lib/b.ex")} == before
  end

  test "a text that is there twice is refused with its lines, unless all of them are asked for", %{
    tmp_dir: dir
  } do
    assert {:error, why} = edit(dir, [%{file: "lib/a.ex", old: "do:", new: "do: 0 +"}])
    assert why =~ "2 times"
    assert why =~ "lines 2, 3"

    assert {:ok, _} = edit(dir, [%{file: "lib/a.ex", old: "do:", new: "do: 0 +", all: true}])
    assert read(dir, "lib/a.ex") =~ "def one, do: 0 + 1\n  def two, do: 0 + 2"
  end

  test "a later replacement sees what an earlier one of the call made", %{tmp_dir: dir} do
    assert {:ok, _} =
             edit(dir, [
               %{file: "lib/a.ex", old: "def one, do: 1", new: "def first, do: 1"},
               %{file: "lib/a.ex", old: "def first", new: "def primero"}
             ])

    assert read(dir, "lib/a.ex") =~ "def primero, do: 1"
  end

  test "Elixir that would not parse is refused before any file is written", %{tmp_dir: dir} do
    before = {read(dir, "lib/a.ex"), read(dir, "lib/b.ex")}

    assert {:error, why} =
             edit(dir, [
               %{file: "lib/b.ex", old: "A.one()", new: "A.uno()"},
               %{file: "lib/a.ex", old: "def two, do: 2", new: "def two(, do: 2"}
             ])

    assert why =~ "lib/a.ex"
    assert why =~ "nothing was written"
    assert {read(dir, "lib/a.ex"), read(dir, "lib/b.ex")} == before
  end

  test "a file that is not Elixir is edited as text, and a new file is made of an empty old", %{
    tmp_dir: dir
  } do
    assert {:ok, reply} =
             edit(dir, [
               %{file: "notes.md", old: "one", new: "uno"},
               %{file: "lib/c.ex", old: "", new: "defmodule C do\n  def   c, do: 3\nend\n"}
             ])

    assert read(dir, "notes.md") == "uno\n"
    assert read(dir, "lib/c.ex") == "defmodule C do\n  def c, do: 3\nend\n"
    assert length(reply.changed) == 2

    # an empty old on a file that is there is no address
    assert {:error, why} = edit(dir, [%{file: "lib/c.ex", old: "", new: "x"}])
    assert why =~ "exists"
  end

  test "a path outside the root is refused", %{tmp_dir: dir} do
    assert {:error, "refused: ../x.ex is outside" <> _} =
             edit(dir, [%{file: "../x.ex", old: "a", new: "b"}])
  end

  test "then: a run verb after the edits, its answer in the reply", %{tmp_dir: dir} do
    assert {:ok, %{run: %{ok: true}} = reply} =
             edit(dir, [%{file: "lib/a.ex", old: "def two, do: 2", new: "def two, do: 22"}], %{
               then: "compile"
             })

    assert reply.did == "edit a.ex: 1 replacement, then run compile"

    # red is an answer: the edits stand, and the reply says what the compiler said of them
    assert {:ok, %{run: %{ok: false, failures: [%{message: message} | _]}}} =
             edit(dir, [%{file: "lib/b.ex", old: "A.one()", new: "A.nope()"}], %{then: "compile"})

    assert message =~ "A.nope/0"
    assert read(dir, "lib/b.ex") =~ "A.nope()"
  end

  test "then: test runs the tests of what the edit changed, not the whole suite", %{tmp_dir: dir} do
    # 2026-09-30: a one-line edit's `then: test` ran menard's 1,034 tests, and timed out at 620 s
    File.mkdir_p!(Path.join(dir, "test"))
    File.write!(Path.join(dir, "test/test_helper.exs"), "ExUnit.start()\n")

    File.write!(
      Path.join(dir, "test/a_test.exs"),
      "defmodule ATest do\n  use ExUnit.Case\n  test \"two\", do: assert(A.two() == 22)\nend\n"
    )

    File.write!(
      Path.join(dir, "test/b_test.exs"),
      "defmodule BTest do\n  use ExUnit.Case\n  test \"elsewhere\", do: assert(false)\nend\n"
    )

    assert {:ok, %{run: %{ok: true, tests: 1}}} =
             edit(dir, [%{file: "lib/a.ex", old: "def two, do: 2", new: "def two, do: 22"}], %{
               then: "test"
             })

    # an edited test file is its own test
    assert {:ok, %{run: %{ok: false, tests: 1}}} =
             edit(dir, [%{file: "test/b_test.exs", old: "elsewhere", new: "still elsewhere"}], %{
               then: "test"
             })
  end

  test "the CLI's edits are search/replace blocks", %{tmp_dir: dir} do
    blocks = """
    lib/a.ex
    <<<<<<< SEARCH
      def one, do: 1
    =======
      def uno, do: 1
    >>>>>>> REPLACE

    lib/a.ex
    <<<<<<< SEARCH
      def two, do: 2
    =======
      def dos do
        2
      end
    >>>>>>> REPLACE
    lib/b.ex
    <<<<<<< SEARCH
    A.one()
    =======
    A.uno()
    >>>>>>> REPLACE
    """

    assert {:ok, edits} = Menard.Edit.blocks(blocks)
    assert [%{file: "lib/a.ex", old: "  def one, do: 1", new: "  def uno, do: 1"}, second, third] = edits
    assert second.new == "  def dos do\n    2\n  end"
    assert third == %{file: "lib/b.ex", old: "A.one()", new: "A.uno()"}

    assert {:ok, %{changed: [_, _]}} = edit(dir, edits)
    assert read(dir, "lib/a.ex") =~ "def dos do\n    2\n  end"

    assert {:error, why} = Menard.Edit.blocks("lib/a.ex\n<<<<<<< SEARCH\nx\n")
    assert why =~ "======="

    # Found 2026-09-29, by the one who wrote it: a stray separator went into the file as text
    stray = "lib/a.ex\n<<<<<<< SEARCH\nx\n=======\ny\n\n=======\n>>>>>>> REPLACE\n"
    assert {:error, why} = Menard.Edit.blocks(stray)
    assert why =~ "a second `=======`"
  end

  test "an edit that would put a function between the clauses of another is refused: it parses, and does not build",
       %{tmp_dir: dir} do
    # Found 2026-09-29, twice in an hour, by the one who wrote edit: a helper written under the clause
    # that calls it, above that function's next clause. The compiler warns that the clauses are not
    # grouped, and a build with warnings as errors fails.
    File.write!(Path.join(dir, "lib/t.ex"), """
    defmodule T do
      def tool(:a), do: a()
      def tool(:b), do: :b

      defp a, do: :a
    end
    """)

    before = read(dir, "lib/t.ex")

    # a clause of tool/1 itself in what would move: moved, it would reorder tool's matches
    assert {:error, why} =
             edit(dir, [
               %{
                 file: "lib/t.ex",
                 old: "  def tool(:a), do: a()\n",
                 new: "  def tool(:a), do: a()\n  def tool(:c), do: :c\n\n  defp helped(x), do: x\n\n"
               }
             ])

    assert why =~ "lib/t.ex"
    assert why =~ "helped/1"
    assert why =~ "between the clauses of tool/1"
    assert why =~ "nothing was written"
    assert read(dir, "lib/t.ex") == before

    # the clause changed and a new function under it (Oban 04: refused, and a 5k batch sent again):
    # the clause stays, the function goes after tool's last clause
    assert {:ok, reply} =
             edit(dir, [
               %{
                 file: "lib/t.ex",
                 old: "  def tool(:a), do: a()\n",
                 new: "  def tool(:a), do: helped(a())\n\n  defp helped(x), do: x\n\n"
               }
             ])

    assert read(dir, "lib/t.ex") ==
             "defmodule T do\n  def tool(:a), do: helped(a())\n  def tool(:b), do: :b\n\n  defp helped(x), do: x\n\n  defp a, do: :a\nend\n"

    assert reply.moved == ["lib/t.ex: helped/1 after the last clause of tool/1, not between its clauses"]
    File.write!(Path.join(dir, "lib/t.ex"), before)

    # a new function added under a clause, the clause left as it was, has one place it can go:
    # after the function's last clause, and there it is written, the reply saying so
    assert {:ok, reply} =
             edit(dir, [
               %{
                 file: "lib/t.ex",
                 old: "  def tool(:a), do: a()\n",
                 new: "  def tool(:a), do: a()\n\n  defp helped(x), do: x\n"
               }
             ])

    assert read(dir, "lib/t.ex") ==
             "defmodule T do\n  def tool(:a), do: a()\n  def tool(:b), do: :b\n\n  defp helped(x), do: x\n\n  defp a, do: :a\nend\n"

    assert reply.moved == ["lib/t.ex: helped/1 after the last clause of tool/1, not between its clauses"]

    # a file that had its clauses apart already is not refused for it: that is not this edit's doing
    apart = "defmodule U do\n  def f(1), do: 1\n  def g, do: 0\n  def f(2), do: 2\nend\n"
    File.write!(Path.join(dir, "lib/u.ex"), apart)
    assert {:ok, _} = edit(dir, [%{file: "lib/u.ex", old: "def g, do: 0", new: "def g, do: :zero"}])
  end

  @tag :tmp_dir
  test "an old text as clause get gives it, at column 0, is found where it sits deeper, and new goes in at that depth",
       %{tmp_dir: dir} do
    # clause get and block get give code at column 0; pasted into edit's `old`, it missed a doc that
    # sat six spaces deep, and the edit was made again with the file's indentation
    File.write!(Path.join(dir, "lib/d.ex"), """
    defmodule D do
      def noun do
        %{
          doc: \"\"\"
          first line
          second line
          \"\"\"
        }
      end
    end
    """)

    assert {:ok, reply} =
             edit(dir, [
               %{
                 file: "lib/d.ex",
                 old: "first line\nsecond line",
                 new: "first line\nsecond line\n\nthird line"
               }
             ])

    assert read(dir, "lib/d.ex") =~ "      second line\n\n      third line\n      \"\"\""
    assert reply.indented == ["lib/d.ex: found 6 spaces deeper than given, and written there"]

    # found at two depths, it is refused as text found twice is
    File.write!(Path.join(dir, "lib/e.ex"), "defmodule E do\n  x = 1\n    x = 1\nend\n")
    assert {:error, _} = edit(dir, [%{file: "lib/e.ex", old: "x = 1\n", new: "x = 2\n"}])
  end

  test "a miss answers with the file's own lines from where the text parts from them", %{tmp_dir: dir} do
    # the formatter wrapped what the agent last wrote: the miss shows the lines as they are now, so the
    # next try needs no read
    File.write!(Path.join(dir, "lib/c.ex"), """
    defmodule C do
      def go(x) do
        case x do
          nil ->
            :none

          _ ->
            :some
        end
      end
    end
    """)

    old = "  def go(x) do\n    case x do\n      nil -> :none\n      _ -> :some\n    end"
    assert {:error, why} = edit(dir, [%{file: "lib/c.ex", old: old, new: "  def go(x) do\n    x"}])

    assert why =~ "the first 2 lines are there, at line 2"
    assert why =~ "      nil ->\n        :none\n\n      _ ->\n        :some"
    refute why =~ "nil -> :none"
  end

  test "an old text at column 0 with a new function under its changed clause is found deeper, and the function goes after the run",
       %{tmp_dir: dir} do
    # `old` as clause get gives it, at column 0, and a new function under the changed clause
    File.write!(Path.join(dir, "lib/t.ex"), """
    defmodule T do
      def tool(:a) do
        a()
      end

      def tool(:b), do: :b

      defp a, do: :a
    end
    """)

    assert {:ok, reply} =
             edit(dir, [
               %{
                 file: "lib/t.ex",
                 old: "def tool(:a) do\n  a()\nend\n",
                 new: "def tool(:a) do\n  helped(a())\nend\n\ndefp helped(x), do: x\n"
               }
             ])

    assert read(dir, "lib/t.ex") ==
             "defmodule T do\n  def tool(:a) do\n    helped(a())\n  end\n\n  def tool(:b), do: :b\n\n  defp helped(x), do: x\n\n  defp a, do: :a\nend\n"

    assert reply.moved == ["lib/t.ex: helped/1 after the last clause of tool/1, not between its clauses"]
    assert reply.indented == ["lib/t.ex: found 2 spaces deeper than given, and written there"]
  end

  @tag :tmp_dir
  test "a miss on its first line shows the line that starts most like it", %{tmp_dir: dir} do
    # the first line itself was wrapped by the formatter: the line that starts most like it, and on
    File.write!(Path.join(dir, "lib/n.ex"), """
    defmodule N do
      def go(
            first_long_argument_name,
            second_long_argument_name
          ) do
        first_long_argument_name
      end
    end
    """)

    old = "  def go(first_long_argument_name, second_long_argument_name) do\n    first_long_argument_name"
    assert {:error, why} = edit(dir, [%{file: "lib/n.ex", old: old, new: "  def go(a, b) do\n    a"}])
    assert why =~ "nearest, at line 2:\n  def go(\n        first_long_argument_name,"
  end

  @tag :tmp_dir
  test "a replacement the same as its text is refused, found or not", %{tmp_dir: dir} do
    # a block whose text and replacement are the same changes nothing, found or not: written as one
    # (2026-10-01), it missed, and the miss sent its writer to look for text it never meant to change
    assert {:error, why} = edit(dir, [%{file: "lib/a.ex", old: "def one, do: 1", new: "def one, do: 1"}])
    assert why =~ "the same"
    assert why =~ "nothing was written"
  end

  @tag :tmp_dir
  test "every writing verb takes then, as edit does", %{tmp_dir: dir} do
    # every writing verb takes `then`, as edit does: a test added with block add was run by a second call
    File.mkdir_p!(Path.join(dir, "test"))
    File.write!(Path.join(dir, "test/test_helper.exs"), "ExUnit.start()\n")

    File.write!(
      Path.join(dir, "test/a_test.exs"),
      "defmodule ATest do\n  use ExUnit.Case\n\n  test \"one\", do: assert(A.one() == 1)\nend\n"
    )

    assert {:ok, %{run: run} = reply} =
             Verbs.call(Verbs.Block, %{
               root: dir,
               verb: "add",
               file: Path.join(dir, "test/a_test.exs"),
               name: "test",
               label: "two",
               code: "assert A.two() == 2",
               then: "test"
             })

    assert reply.did =~ "then run test"
    assert %{ok: true, tests: 2} = run

    assert {:error, why} =
             Verbs.call(Verbs.Block, %{verb: "list", file: Path.join(dir, "test/a_test.exs"), then: "lint"})

    assert why =~ "no then"
  end

  @tag :tmp_dir
  test "then runs in the mix project of the files it wrote, nested under the root or not", %{tmp_dir: dir} do
    # Fable 2026-10-01: `then` ran in the root and mapped lib/ to test/ from it, so in a repo whose mix
    # project is server/ (tlon's) no test was found and --stale ran where there was no mix.exs
    server = Path.join(dir, "server")
    File.mkdir_p!(server)
    Host.mix_project(server, :nested)
    File.mkdir_p!(Path.join(server, "lib"))
    File.mkdir_p!(Path.join(server, "test"))
    File.write!(Path.join(server, "lib/n.ex"), "defmodule N do\n  def go, do: 1\nend\n")
    File.write!(Path.join(server, "test/test_helper.exs"), "ExUnit.start()\n")

    File.write!(
      Path.join(server, "test/n_test.exs"),
      "defmodule NTest do\n  use ExUnit.Case\n  test \"go\", do: assert(N.go() == 2)\nend\n"
    )

    assert {:ok, %{run: run}} =
             edit(dir, [%{file: "server/lib/n.ex", old: "def go, do: 1", new: "def go, do: 2"}], %{
               then: "test"
             })

    assert %{ok: true, tests: 1, dir: "server"} = run
  end

  @tag :tmp_dir
  test "then takes the test files to run, where the change's are not its files' mirror", %{tmp_dir: dir} do
    # a change whose tests are not the mirror of its files (a formatter in priv/, its tests in
    # run_test.exs) named them, and ran them by a second call: `then` takes the files
    File.mkdir_p!(Path.join(dir, "test"))
    File.write!(Path.join(dir, "test/test_helper.exs"), "ExUnit.start()\n")

    File.write!(
      Path.join(dir, "test/a_test.exs"),
      "defmodule ATest do\n  use ExUnit.Case\n  test \"a\", do: :ok\nend\n"
    )

    File.write!(
      Path.join(dir, "test/b_test.exs"),
      "defmodule BTest do\n  use ExUnit.Case\n  test \"b\", do: assert(A.two() == 22)\nend\n"
    )

    assert {:ok, %{run: %{ok: true, tests: 1}}} =
             edit(dir, [%{file: "lib/a.ex", old: "def two, do: 2", new: "def two, do: 22"}], %{
               then: "test test/b_test.exs"
             })

    assert {:error, why} =
             edit(dir, [%{file: "lib/a.ex", old: "def two, do: 22", new: "def two, do: 2"}], %{
               then: "check lib"
             })

    assert why =~ "only test takes files"

    assert {:error, _} =
             edit(dir, [%{file: "lib/a.ex", old: "def two, do: 22", new: "def two, do: 2"}], %{then: "lint"})
  end

  @tag :tmp_dir
  test "a reply names a file under the root from the root", %{tmp_dir: dir} do
    # Fable 2026-10-01: an absolute path in every file of every reply, 44% of a CLI find's characters.
    # Under the root, a file is named from it
    File.mkdir_p!(Path.join(dir, "lib"))
    File.write!(Path.join(dir, "lib/r.ex"), "defmodule R do\n  def go, do: 1\nend\n")

    assert {:ok, reply} =
             Verbs.call(Verbs.Edit, %{
               root: dir,
               edits: [%{file: "lib/r.ex", old: "def go, do: 1", new: "def go, do: 2"}]
             })

    assert [%{file: "lib/r.ex"}] = reply.changed

    assert {:ok, %{hits: [%{file: "lib/b.ex"}, %{file: "lib/r.ex"}]}} =
             Verbs.call(Verbs.Find, %{root: dir, kind: "defs", target: "go", files: [Path.join(dir, "lib")]})
  end

  @tag :tmp_dir
  test "edit blocks take the markers' first slips, and a text there twice is shown where", %{tmp_dir: dir} do
    # Fable 2026-10-01: first guesses refused, the batch sent again (3 of 37 CLI edits in one session,
    # 7.4k characters): the two markers on one line, and a block ended at its second `=======`
    one_line = "lib/a.ex\n<<<<<<< SEARCH\nold\n=======>>>>>>> REPLACE\n"
    assert {:ok, [%{file: "lib/a.ex", old: "old", new: ""}]} = Menard.Edit.blocks(one_line)

    ended =
      "lib/a.ex\n<<<<<<< SEARCH\nold\n=======\nnew\n=======\nlib/b.ex\n<<<<<<< SEARCH\nx\n=======\ny\n>>>>>>> REPLACE\n"

    assert {:ok, [%{file: "lib/a.ex", old: "old", new: "new"}, %{file: "lib/b.ex", old: "x", new: "y"}]} =
             Menard.Edit.blocks(ended)

    # there N times: each match with the lines around it, not the text said back
    File.write!(Path.join(dir, "lib/n.ex"), "defmodule N do\n  def a, do: go()\n  def b, do: go()\nend\n")
    assert {:error, why} = edit(dir, [%{file: "lib/n.ex", old: "go()", new: "run()"}])
    assert why =~ "line 2:"
    assert why =~ "  def a, do: go()"
    assert why =~ "line 3:"
  end

  @tag :tmp_dir
end
