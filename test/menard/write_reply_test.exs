defmodule Menard.WriteReplyTest do
  use ExUnit.Case, async: true

  alias Menard

  @moduletag :tmp_dir

  defp write_file(dir, name, content) do
    path = Path.join(dir, name)
    File.write!(path, content)
    path
  end

  describe "Menard.write/3 — the staged reply" do
    test "returns the reply shape: did, file, version, stages", %{tmp_dir: dir} do
      file = write_file(dir, "a.ex", "defmodule A do\n  def go, do: :a\nend\n")
      original = File.read!(file)

      patched = String.replace(original, ":a", ":b")

      assert {:ok, reply} = Menard.write(file, patched, did: "replace go/1 `:a` in a.ex")
      assert reply.did == "replace go/1 `:a` in a.ex"
      assert reply.file == file
      assert String.starts_with?(reply.version, "sha256:")
      # a third, :plugins, when the file's formatter has plugins, as menard's own does
      assert [:patch, :formatter | _] = Enum.map(reply.stages, & &1.stage)
      assert hd(reply.stages).stage == :patch

      assert hd(reply.stages).hunks == [
               %{start: 2, removed: ["  def go, do: :a"], added: ["  def go, do: :b"]}
             ]
    end

    test "the version is the sha256 of the file on disk after the write", %{tmp_dir: dir} do
      file = write_file(dir, "b.ex", "defmodule B do\n  def go, do: :a\nend\n")
      patched = String.replace(File.read!(file), ":a", ":b")

      assert {:ok, reply} = Menard.write(file, patched)
      disk = File.read!(file)
      expected = "sha256:" <> Base.encode16(:crypto.hash(:sha256, disk), case: :lower)
      assert reply.version == expected
    end

    test "the file on disk is the patched content (no formatter in a dir with no mix.exs)", %{tmp_dir: dir} do
      file = write_file(dir, "c.ex", "defmodule C do\n  def go, do: :a\nend\n")
      patched = String.replace(File.read!(file), ":a", ":b")

      assert {:ok, _reply} = Menard.write(file, patched)
      assert File.read!(file) == patched
    end

    test "the formatter stage is empty when nothing is reformatted", %{tmp_dir: dir} do
      file = write_file(dir, "d.ex", "defmodule D do\n  def go, do: :a\nend\n")
      patched = String.replace(File.read!(file), ":a", ":b")

      assert {:ok, reply} = Menard.write(file, patched)
      formatter_stage = Enum.find(reply.stages, &(&1.stage == :formatter))
      assert formatter_stage.hunks == []
    end

    test "a parse error is refused and the file is untouched", %{tmp_dir: dir} do
      file = write_file(dir, "e.ex", "defmodule E do\n  def go, do: :a\nend\n")
      before = File.read!(file)

      assert {:error, reason} = Menard.write(file, "defmodule E do\n  def go, do:\nend\n")
      assert reason =~ "refusing to write"
      assert File.read!(file) == before
    end

    test "a new file: the patch stage shows all lines as added", %{tmp_dir: dir} do
      file = Path.join(dir, "new.ex")
      content = "defmodule New do\n  def go, do: :ok\nend\n"

      assert {:ok, reply} = Menard.write(file, content, did: "write new.ex")
      assert hd(reply.stages).hunks == [%{start: 1, removed: [], added: String.split(content, "\n")}]
      assert File.read!(file) == content
    end

    test "checked_write/2 still works (the thin wrapper)", %{tmp_dir: dir} do
      file = write_file(dir, "f.ex", "defmodule F do\n  def go, do: :a\nend\n")
      patched = String.replace(File.read!(file), ":a", ":b")

      assert :ok = Menard.checked_write(file, patched)
      assert File.read!(file) == patched
    end
  end

  describe "Menard.write/3 — a version given is a version checked" do
    test "the version from the last reply lets the next edit through", %{tmp_dir: dir} do
      file = write_file(dir, "v1.ex", "defmodule V do\n  def go, do: :a\nend\n")
      {:ok, first} = Menard.write(file, "defmodule V do\n  def go, do: :b\nend\n")

      assert {:ok, _} = Menard.write(file, "defmodule V do\n  def go, do: :c\nend\n", version: first.version)
      assert File.read!(file) =~ ":c"
    end

    test "an edit against a version the file no longer has is refused, with what changed since", %{
      tmp_dir: dir
    } do
      file = write_file(dir, "v2.ex", "defmodule V do\n  def go, do: :a\n  def other, do: 1\nend\n")
      {:ok, mine} = Menard.write(file, "defmodule V do\n  def go, do: :b\n  def other, do: 1\nend\n")

      # another session edits the file after my last reply
      theirs = "defmodule V do\n  def go, do: :b\n  def other, do: 2\nend\n"
      File.write!(file, theirs)

      assert {:error, message} =
               Menard.write(file, "defmodule V do\n  def go, do: :c\n  def other, do: 1\nend\n",
                 version: mine.version
               )

      assert message =~ "stale"
      assert message =~ "def other, do: 2"
      assert File.read!(file) == theirs
    end

    test "force writes over a stale version", %{tmp_dir: dir} do
      file = write_file(dir, "v3.ex", "defmodule V do\n  def go, do: :a\nend\n")
      File.write!(file, "defmodule V do\n  def go, do: :z\nend\n")

      assert {:ok, _} =
               Menard.write(file, "defmodule V do\n  def go, do: :c\nend\n",
                 version: "sha256:0000",
                 force: true
               )

      assert File.read!(file) =~ ":c"
    end

    test "a version menard never handed out is still refused, and says to re-read", %{tmp_dir: dir} do
      file = write_file(dir, "v4.ex", "defmodule V do\n  def go, do: :a\nend\n")

      assert {:error, message} =
               Menard.write(file, "defmodule V do\n  def go, do: :c\nend\n", version: "sha256:0000")

      assert message =~ "re-read"
      assert File.read!(file) =~ ":a"
    end
  end
end
