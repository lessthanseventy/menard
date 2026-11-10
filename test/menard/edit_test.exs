defmodule Menard.EditTest do
  # `edit`: several replacements, across files, in ONE call. What agents write a Python heredoc
  # for (`s = s.replace(old, new)`, file after file, then the tests): one whose replace says
  # nothing when the text it looks for is not there.
  use ExUnit.Case, async: true

  import Menard.Test.Edits

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

  # the Nix that crashed it: `'';` is Elixir's empty charlist, and a comment after it what Sourceror
  # raises on; the text of a file that is no Elixir should not reach a parser of Elixir at all
  test "the text of a file that is not Elixir is not parsed as Elixir", %{tmp_dir: dir} do
    new = "uno\n'';\n\n# the shell's rc"

    assert {:ok, _} = edit(dir, [%{file: "notes.md", old: "one", new: new}])
    assert read(dir, "notes.md") == new <> "\n"
  end

  test "a file with no newline at its end keeps none", %{tmp_dir: dir} do
    File.write!(Path.join(dir, "VERSION"), "v1.2")
    assert {:ok, _} = edit(dir, [%{file: "VERSION", old: "1.2", new: "1.3"}])
    assert read(dir, "VERSION") == "v1.3"
  end

  test "a file of CRLF lines is found by text written with LF, and keeps its line ends", %{tmp_dir: dir} do
    File.write!(Path.join(dir, "run.bat"), "one\r\ntwo\r\nthree\r\n")
    assert {:ok, _} = edit(dir, [%{file: "run.bat", old: "one\ntwo", new: "uno\ndos\nmas"}])
    assert read(dir, "run.bat") == "uno\r\ndos\r\nmas\r\nthree\r\n"
  end

  test "one file named two ways takes both edits", %{tmp_dir: dir} do
    File.write!(Path.join(dir, "real.txt"), "one\ntwo\n")
    File.ln_s!(Path.join(dir, "real.txt"), Path.join(dir, "link.txt"))

    assert {:ok, %{changed: [_one]}} =
             edit(dir, [
               %{file: "real.txt", old: "one", new: "ONE"},
               %{file: "link.txt", old: "two", new: "TWO"}
             ])

    assert read(dir, "real.txt") == "ONE\nTWO\n"
  end

  test "an Elixir file that is a literal and a comment after it is edited", %{tmp_dir: dir} do
    File.write!(Path.join(dir, "settings.exs"), "[a: 1]\n# the last word\n")

    assert {:ok, _} = edit(dir, [%{file: "settings.exs", old: "a: 1", new: "a: 2"}])
    assert read(dir, "settings.exs") == "[a: 2]\n# the last word\n"
  end

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

  # through MCP a relative path is from the directory the session started in, not the shell's: a
  # session started a level up looked in the wrong place and was told only that nothing was there
  test "a file that is not there is named by where it was looked for", %{tmp_dir: dir} do
    assert {:error, why} = edit(dir, [%{file: "lib/c.ex", old: "x", new: "y"}])
    assert why =~ Path.join(dir, "lib/c.ex")
  end

  test "a text that is there twice is refused with its lines, unless all of them are asked for", %{
    tmp_dir: dir
  } do
    assert {:error, why} = edit(dir, [%{file: "lib/a.ex", old: "do:", new: "do: 0 +"}])
    assert why =~ "2 times"
    assert why =~ "lines 2, 3"

    assert {:ok, %{replacements: 2}} = edit(dir, [%{file: "lib/a.ex", old: "do:", new: "do: 0 +", all: true}])
    assert read(dir, "lib/a.ex") =~ "def one, do: 0 + 1\n  def two, do: 0 + 2"
  end

  test "a batch refused at its write leaves no directory it made for a file before", %{tmp_dir: dir} do
    File.write!(Path.join(dir, "lib/b.ex"), "defmodule B do\n  def go, do: A.one()\nend\n")
    File.chmod!(Path.join(dir, "lib/b.ex"), 0o444)
    File.chmod!(Path.join(dir, "lib"), 0o555)
    on_exit(fn -> File.chmod(Path.join(dir, "lib"), 0o755) end)

    assert {:error, _} =
             edit(dir, [
               %{file: "new/deep/c.txt", old: "", new: "c\n"},
               %{file: "lib/b.ex", old: "A.one()", new: "A.two()"}
             ])

    refute File.exists?(Path.join(dir, "new"))
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

  test "a crash writing one file puts back the files written before it", %{tmp_dir: dir} do
    ro = Path.join(dir, "ro")
    File.mkdir_p!(ro)
    File.chmod!(ro, 0o500)
    on_exit(fn -> File.chmod!(ro, 0o700) end)

    assert_raise File.Error, fn ->
      edit(dir, [
        %{file: "lib/a.ex", old: "def one, do: 1", new: "def one, do: 11"},
        %{file: "ro/sub/new.ex", old: "", new: "defmodule New do\nend\n"}
      ])
    end

    assert read(dir, "lib/a.ex") =~ "def one, do: 1\n"
  end

  test "a file that cannot be written is refused in a sentence, nothing else touched", %{tmp_dir: dir} do
    # a sandboxed seat with its scratch dir read-only must not answer a stack trace from File.write!/3
    a = Path.join(dir, "lib/a.ex")
    b = Path.join(dir, "lib/b.ex")
    File.chmod!(b, 0o444)

    assert {:error, why} =
             edit(dir, [
               %{file: "lib/a.ex", old: "def one, do: 1", new: "def one, do: 11"},
               %{file: "lib/b.ex", old: "A.one()", new: "A.one() + 1"}
             ])

    assert why =~ "lib/b.ex"
    assert why =~ "cannot be written"
    assert why =~ "permission denied"
    assert read(dir, "lib/a.ex") =~ "def one, do: 1\n"
    File.chmod!(b, 0o644)
    File.chmod!(a, 0o644)
  end

  test "a path outside the root, in no checkout under the home, is refused", %{tmp_dir: dir} do
    assert {:error, "refused: /nonexistent-menard/x.ex is outside" <> _} =
             edit(dir, [%{file: "/nonexistent-menard/x.ex", old: "a", new: "b"}])
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

    # a stray separator must not go into the file as text
    stray = "lib/a.ex\n<<<<<<< SEARCH\nx\n=======\ny\n\n=======\n>>>>>>> REPLACE\n"
    assert {:error, why} = Menard.Edit.blocks(stray)
    assert why =~ "a second `=======`"
  end

  @tag :tmp_dir
  test "a refused batch is kept, and --retry N takes that edit again with the rest as they were", %{
    tmp_dir: dir
  } do
    File.mkdir_p!(Path.join(dir, "lib"))
    File.write!(Path.join(dir, "lib/a.ex"), "defmodule A do\n  def one, do: 1\n  def two, do: 2\nend\n")
    System.put_env("MENARD_CWD", dir)
    on_exit(fn -> System.delete_env("MENARD_CWD") end)

    batch = """
    lib/a.ex
    <<<<<<< SEARCH
      def one, do: 1
    =======
      def uno, do: 1
    >>>>>>> REPLACE
    <<<<<<< SEARCH
      def two, do: 22
    =======
      def dos, do: 2
    >>>>>>> REPLACE
    """

    error = assert_raise(Mix.Error, fn -> Mix.Tasks.Menard.Edit.run([batch]) end)
    assert error.message =~ "edit 2 of 2, lib/a.ex: this text is not there"
    assert error.message =~ "The other 1 are kept: send edit 2 corrected, alone"
    assert error.message =~ "--retry 2 -"
    assert File.read!(Path.join(dir, "lib/a.ex")) =~ "def one, do: 1"

    retry = "lib/a.ex\n<<<<<<< SEARCH\n  def two, do: 2\n=======\n  def dos, do: 2\n>>>>>>> REPLACE\n"
    out = ExUnit.CaptureIO.capture_io(fn -> Mix.Tasks.Menard.Edit.run(["--retry", "2", retry]) end)
    assert out =~ ~s("replacements":2)

    assert File.read!(Path.join(dir, "lib/a.ex")) ==
             "defmodule A do\n  def uno, do: 1\n  def dos, do: 2\nend\n"

    error = assert_raise(Mix.Error, fn -> Mix.Tasks.Menard.Edit.run(["--retry", "5", retry]) end)
    assert error.message =~ "nothing kept to retry as edit 5"
  end

  @tag :tmp_dir
  test "a refused batch is kept for a project however deep its path", %{tmp_dir: dir} do
    # a kept file named by the whole path, encoded, would pass 255 bytes and the refusal would be
    # File.Error's "file name too long"
    deep = Path.join(dir, String.duplicate("d", 200))
    File.mkdir_p!(Path.join(deep, "lib"))
    File.write!(Path.join(deep, "lib/a.ex"), "defmodule A do\n  def one, do: 1\nend\n")
    System.put_env("MENARD_CWD", deep)
    on_exit(fn -> System.delete_env("MENARD_CWD") end)

    batch = """
    lib/a.ex
    <<<<<<< SEARCH
      def one, do: 1
    =======
      def uno, do: 1
    >>>>>>> REPLACE
    <<<<<<< SEARCH
      def two, do: 2
    =======
      def dos, do: 2
    >>>>>>> REPLACE
    """

    error = assert_raise(Mix.Error, fn -> Mix.Tasks.Menard.Edit.run([batch]) end)
    assert error.message =~ "The other 1 are kept"
  end

  test "a block with no path line is the file of the block before it" do
    # a second block for the same file written without its path again, not refused with "expected a
    # file's path … got: <<<<<<< SEARCH"
    blocks = """
    lib/a.ex
    <<<<<<< SEARCH
    one
    =======
    uno
    >>>>>>> REPLACE
    <<<<<<< SEARCH
    two
    =======
    dos
    >>>>>>> REPLACE

    <<<<<<< SEARCH
    three
    =======
    tres
    >>>>>>> REPLACE
    lib/b.ex
    <<<<<<< SEARCH
    four
    =======
    cuatro
    >>>>>>> REPLACE
    """

    assert {:ok, edits} = Menard.Edit.blocks(blocks)

    assert Enum.map(edits, &{&1.file, &1.old}) == [
             {"lib/a.ex", "one"},
             {"lib/a.ex", "two"},
             {"lib/a.ex", "three"},
             {"lib/b.ex", "four"}
           ]

    # a `=======` closing a block, with a bare block after it
    short =
      "lib/a.ex\n<<<<<<< SEARCH\none\n=======\nuno\n=======\n<<<<<<< SEARCH\ntwo\n=======\ndos\n>>>>>>> REPLACE\n"

    assert {:ok, [%{old: "one", new: "uno"}, %{file: "lib/a.ex", old: "two", new: "dos"}]} =
             Menard.Edit.blocks(short)

    # the first block has no file to inherit: still what was expected, and what came
    assert {:error, why} = Menard.Edit.blocks("<<<<<<< SEARCH\none\n=======\nuno\n>>>>>>> REPLACE\n")
    assert why =~ "expected a file's path"
  end

  test "an edit that would put a function between the clauses of another is refused: it parses, and does not build",
       %{tmp_dir: dir} do
    # a helper written under the clause that calls it, above that function's next clause: the
    # compiler warns that the clauses are not grouped, and a build with warnings as errors fails.
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

    # the clause changed and a new function under it: the clause stays, the function goes after
    # tool's last clause
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
    # a block whose text and replacement are the same changes nothing, found or not, so a miss would
    # send its writer to look for text it never meant to change
    assert {:error, why} = edit(dir, [%{file: "lib/a.ex", old: "def one, do: 1", new: "def one, do: 1"}])
    assert why =~ "the same"
    assert why =~ "nothing was written"
  end

  @tag :tmp_dir
  test "a reply names a file under the root from the root", %{tmp_dir: dir} do
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
    # the two markers on one line, and a block ended at its second `=======`
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
