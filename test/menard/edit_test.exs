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

  defp edit(dir, edits, more \\ %{}), do: Verbs.Edit.run(Map.merge(%{root: dir, edits: edits}, more))
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
    assert [%{file: a, version: "sha256:" <> _, stages: [_ | _]}, %{file: b}] = reply.changed
    assert {Path.basename(a), Path.basename(b)} == {"a.ex", "b.ex"}
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
end
