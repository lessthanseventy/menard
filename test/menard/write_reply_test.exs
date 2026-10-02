defmodule Menard.WriteReplyTest do
  use ExUnit.Case, async: true

  alias Menard
  alias Mix.Tasks.Menard.Clause
  alias Mix.Tasks.Menard.Rename

  @moduletag :tmp_dir

  defp write_file(dir, name, content) do
    path = Path.join(dir, name)
    File.write!(path, content)
    path
  end

  test "a reply is written what-happened first and hash last: a reader of its first 60 characters saw only the hash" do
    json =
      Menard.encode(%{
        version: "sha256:abc",
        file: "/a/b.ex",
        stages: [%{stage: :patch, hunks: []}],
        did: "replace go/1"
      })

    assert json ==
             ~s({"did":"replace go/1","stages":[{"hunks":[],"stage":"patch"}],"file":"/a/b.ex","version":"sha256:abc"})

    assert JSON.decode!(Menard.encode(%{log: "l", failures: [], ok: false, tests: 3})) == %{
             "log" => "l",
             "failures" => [],
             "ok" => false,
             "tests" => 3
           }

    assert Menard.encode(%{log: "l", failures: [], ok: false, tests: 3}) =~
             ~r/^\{"ok":false,"tests":3,"failures"/
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
      # :formatter and :plugins follow only where they changed something
      assert [:patch] = Enum.map(reply.stages, & &1.stage)

      assert hd(reply.stages).hunks == [
               %{start: 2, removed: ["  def go, do: :a"], added: ["  def go, do: :b"]}
             ]
    end

    test "the version is the sha256 of the file on disk after the write", %{tmp_dir: dir} do
      file = write_file(dir, "b.ex", "defmodule B do\n  def go, do: :a\nend\n")
      patched = String.replace(File.read!(file), ":a", ":b")

      assert {:ok, reply} = Menard.write(file, patched)
      disk = File.read!(file)
      expected = "sha256:" <> binary_part(Base.encode16(:crypto.hash(:sha256, disk), case: :lower), 0, 12)
      assert reply.version == expected
    end

    test "the file on disk is the patched content (no formatter in a dir with no mix.exs)", %{tmp_dir: dir} do
      file = write_file(dir, "c.ex", "defmodule C do\n  def go, do: :a\nend\n")
      patched = String.replace(File.read!(file), ":a", ":b")

      assert {:ok, _reply} = Menard.write(file, patched)
      assert File.read!(file) == patched
    end

    test "the formatter stage is left out when nothing is reformatted", %{tmp_dir: dir} do
      file = write_file(dir, "d.ex", "defmodule D do\n  def go, do: :a\nend\n")
      patched = String.replace(File.read!(file), ":a", ":b")

      assert {:ok, reply} = Menard.write(file, patched)
      refute Enum.find(reply.stages, &(&1.stage == :formatter))
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

    test "says the file needs no read back: its stages are every change", %{tmp_dir: dir} do
      # an Edit gets "no need to Read it back" from Claude Code; a menard write got hunks alone, and in
      # bench1/bench2 B read files back after its last edit 2.6x as often as A
      file = write_file(dir, "a.ex", "defmodule A do\n  def go, do: :a\nend\n")
      assert {:ok, reply} = Menard.write(file, String.replace(File.read!(file), ":a", ":b"))
      assert reply.note =~ "no need to Read"
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

    test "a kept copy gone mid-prune does not fail the write that kept the next", %{tmp_dir: dir} do
      # another menard pruning the same directory removes a copy between the listing and its stat;
      # a link to nowhere is a copy that listed and will not stat
      kept = Path.join(Menard.cache_dir(), "versions")
      File.mkdir_p!(kept)
      gone = Path.join(kept, "gone-#{System.os_time()}")
      File.ln_s!(Path.join(dir, "nowhere"), gone)
      on_exit(fn -> File.rm(gone) end)

      assert "sha256:" <> _ = Menard.remember("defmodule Gone do\nend\n")
    end

    test "rename and move check every version before writing any file", %{tmp_dir: dir} do
      # rename and move write several files: every version is checked before any file is written
      a = write_file(dir, "ra.ex", "defmodule RA do\n  def old, do: 1\nend\n")
      b = write_file(dir, "rb.ex", "defmodule RB do\n  def go, do: RA.old()\nend\n")
      {:ok, %{version: va}} = Menard.write(a, File.read!(a))
      {:ok, %{version: vb}} = Menard.write(b, File.read!(b))
      assert Menard.check_versions([{a, va}, {b, vb}]) == :ok

      # another session edits b; a rename across both is refused, and neither file is touched
      File.write!(b, "defmodule RB do\n  def go, do: RA.old() + 1\nend\n")

      assert_raise Mix.Error, ~r/stale: .*rb\.ex/, fn ->
        ExUnit.CaptureIO.capture_io(fn ->
          Rename.run([
            "old",
            "new",
            a,
            b,
            "--version",
            "#{a}=#{va}",
            "--version",
            "#{b}=#{vb}"
          ])
        end)
      end

      assert File.read!(a) =~ "def old"
      assert File.read!(b) =~ "RA.old() + 1"

      # a move checks the file it takes the function from
      File.write!(a, "defmodule RA do\n  def old, do: 2\nend\n")
      dest = Path.join(dir, "rc.ex")

      assert_raise Mix.Error, ~r/stale/, fn ->
        ExUnit.CaptureIO.capture_io(fn ->
          Clause.run(["move", a, "old/0", "--to", dest, "--as", "RC", "--version", va])
        end)
      end

      refute File.exists?(dest)
    end

    test "a kept copy older than a week goes when the next is kept, and a newer one stays" do
      kept = Path.join(Menard.cache_dir(), "versions")
      File.mkdir_p!(kept)
      now = System.os_time(:second)
      old = Path.join(kept, "old-#{System.unique_integer([:positive])}")
      recent = Path.join(kept, "recent-#{System.unique_integer([:positive])}")
      File.write!(old, "")
      File.write!(recent, "")
      File.touch!(old, now - 8 * 24 * 3600)
      File.touch!(recent, now - 6 * 24 * 3600)
      on_exit(fn -> Enum.each([old, recent], &File.rm/1) end)

      # once a VM, not on every write
      assert :ok = Menard.prune_versions()
      refute File.exists?(old)
      assert File.exists?(recent)
    end
  end

  describe "clause insert_at at the CLI" do
    test "takes top and bottom", %{tmp_dir: dir} do
      a = write_file(dir, "ia.ex", "defmodule IA do\n  def one, do: 1\n\n  defp helper, do: :h\nend\n")

      ExUnit.CaptureIO.capture_io(fn -> Clause.run(["insert_at", a, "-", "top", "def zero, do: 0"]) end)
      ExUnit.CaptureIO.capture_io(fn -> Clause.run(["insert_at", a, "-", "bottom", "def last, do: 9"]) end)

      assert File.read!(a) =~ "def zero, do: 0\n\n  def one, do: 1"
      assert File.read!(a) =~ "defp helper, do: :h\n\n  def last, do: 9"
    end
  end

  describe "clause move at the CLI" do
    test "answers in JSON, both files' replies, like every other writing verb", %{tmp_dir: dir} do
      a = write_file(dir, "ma.ex", "defmodule MA do\n  def go, do: 1\n\n  def stay, do: 2\nend\n")
      dest = Path.join(dir, "mb.ex")

      out = ExUnit.CaptureIO.capture_io(fn -> Clause.run(["move", a, "go/0", "--to", dest, "--as", "MB"]) end)

      assert %{"created" => "MB", "to" => %{"file" => to, "version" => "sha256:" <> _}, "from" => from} =
               JSON.decode!(out)

      # named from where the CLI was called
      assert Path.expand(to) == dest
      assert Path.expand(from["file"]) == a
    end

    test "with no --to is refused by name, not a stack trace", %{tmp_dir: dir} do
      a = write_file(dir, "mc.ex", "defmodule MC do\n  def go, do: 1\nend\n")

      assert_raise Mix.Error, ~r/clause move needs to/, fn -> Clause.run(["move", a, "go/0"]) end
    end

    @tag :tmp_dir
    test "a long patch is where it went, not the caller's code again", %{tmp_dir: dir} do
      # the caller's own code is not news: a long patch says where it went, not what it was; a
      # formatter that only re-indented says so in a count (a block add of a test came back as 3 KB)
      file = write_file(dir, "w.ex", "defmodule W do\n  def go, do: :a\nend\n")
      body = Enum.map_join(1..8, "", &"    x#{&1} = #{&1}\n")

      patched =
        String.replace(File.read!(file), "  def go, do: :a\n", "  def go do\n" <> body <> "    :a\n  end\n")

      assert {:ok, reply} = Menard.write(file, patched)
      assert [%{start: 2, removed: 1, added: 11}] = hd(reply.stages).hunks
    end

    @tag :tmp_dir
    test "a write says once what it laid out", %{tmp_dir: dir} do
      file = write_file(dir, "m.ex", "defmodule M do\n  def a, do: 1\n\n  def b, do: 2\nend\n")
      patched = String.replace(File.read!(file), "  def b", "  defp h, do: 0\n\n  def b")

      assert {:ok, reply} = Menard.write(file, patched)
      assert reply.moved == ["h/0 to the module's end, below its public functions"]
    end
  end
end
