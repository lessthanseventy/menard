defmodule Menard.BinHostTest do
  # bin/menard, this checkout's own build, run on a host project in a tmp dir: nothing here
  # rebuilds or deletes a build of menard's, so these run beside every other async module. In
  # Menard.BinTest (not async, for the tests that do) their ~60 s ran one after another.
  use ExUnit.Case, async: true

  # a first verb after menard's source changed compiles it: past 60 s on a loaded box
  @moduletag timeout: 300_000

  alias Menard.Test.Host
  @root Path.expand("../..", __DIR__)

  @bin Path.join(@root, "bin/menard")

  @tag :tmp_dir
  test "--stdin passes the last argument on stdin, quotes and backslashes intact", %{tmp_dir: dir} do
    file = Path.join(dir, "a.ex")
    File.write!(file, "defmodule A do\n  def go, do: 1\nend\n")
    code = Path.join(dir, "code.txt")
    File.write!(code, ~S|"it's" <> "\\\\n"|)

    {_out, 0} =
      System.cmd("sh", ["-c", "#{@bin} clause replace #{file} go/0 \"\" --stdin < #{code}"],
        env: [{"MIX_ENV", "dev"}]
      )

    assert File.read!(file) =~ ~S|def go, do: "it's" <> "\\\\n"|
  end

  @tag :tmp_dir
  test "a reader that stops early (`| head`) gets its lines and no crash", %{tmp_dir: dir} do
    # the BEAM's writer crashes on a closed stdout (:epipe) and printed a stack trace for it
    File.mkdir_p!(Path.join(dir, "lib"))

    for n <- 1..400,
        do: File.write!(Path.join(dir, "lib/m#{n}.ex"), "defmodule M#{n} do\n  def f, do: 1\nend\n")

    {out, status} =
      System.cmd("bash", ["-c", ~s("$0" map | head -1), @bin],
        cd: dir,
        env: [{"MIX_ENV", "dev"}, {"MENARD_CWD", dir}],
        stderr_to_stdout: true
      )

    assert status == 0
    assert out =~ ~r/\AM\d+  lib\/m\d+\.ex  f\/0\n\z/
  end

  @tag :tmp_dir
  test "every VM menard starts has its schedulers' busy wait off, the caller's flags after", %{tmp_dir: dir} do
    # A VM's schedulers spin while they wait: a one-test `mix test` was 4 CPU-seconds in half a second,
    # every core busy, and the gate's hundreds of VMs 2,450 CPU-seconds. Every VM menard starts, and
    # every one those start, has them off; the caller's own ERL_FLAGS come after them, and win
    Host.mix_project(dir, :quiet)
    File.mkdir_p!(Path.join(dir, "test"))
    File.write!(Path.join(dir, "test/test_helper.exs"), "ExUnit.start()\n")

    File.write!(Path.join(dir, "test/quiet_test.exs"), """
    defmodule QuietTest do
      use ExUnit.Case
      test "busy wait is off", do: assert(System.get_env("ERL_FLAGS") =~ ~r/^\\+sbwt none .*\\+S 2$/)
    end
    """)

    {out, 0} =
      System.cmd(@bin, ["run", "test", "--in", dir], env: [{"ERL_FLAGS", "+S 2"}], stderr_to_stdout: true)

    assert out =~ ~s("ok":true)
  end

  @tag :tmp_dir
  test "edit --then at the CLI runs the then, as the MCP door does", %{tmp_dir: dir} do
    # 2026-10-01 19:15: `then` moved to Verbs.call, the edit task still called Verbs.Edit.run, and
    # `--then test` was dropped without a word at the CLI. Held at the door the agent types
    Host.mix_project(dir, :thencli)
    File.mkdir_p!(Path.join(dir, "lib"))
    File.write!(Path.join(dir, "lib/t.ex"), "defmodule T do\n  def go, do: 1\nend\n")
    blocks = "lib/t.ex\n<<<<<<< SEARCH\ndef go, do: 1\n=======\ndef go, do: 2\n>>>>>>> REPLACE\n"

    # Both unset: bin/menard falls back MENARD_CWD -> MISE_ORIGINAL_CWD -> $PWD, and a suite run
    # by `mise run check` (its own "test" task sets `dir =`, which makes mise export
    # MISE_ORIGINAL_CWD for the whole run) inherits the caller's worktree root instead of `cd:`'s
    {out, 0} =
      System.cmd(@bin, ["edit", "--then", "compile", blocks],
        cd: dir,
        env: [{"MENARD_CWD", nil}, {"MISE_ORIGINAL_CWD", nil}],
        stderr_to_stdout: true
      )

    assert out =~ ~s("did":"edit t.ex: 1 replacement, then run compile")
    assert out =~ ~s("run":{"ok":true)
  end

  @tag :tmp_dir
  test "edit --then test FILE… at the CLI runs those tests, as the MCP door's `then: \"test FILE…\"` does",
       %{tmp_dir: dir} do
    # Transcripts 2026-10-08 to 10-13: `edit --then test test/x_test.exs -` seven times, each
    # refused with the bare usage line, and the edit sent again without its `--then` at all
    Host.mix_project(dir, :thenfiles)
    File.mkdir_p!(Path.join(dir, "lib"))
    File.mkdir_p!(Path.join(dir, "test"))
    File.write!(Path.join(dir, "lib/t.ex"), "defmodule T do\n  def go, do: 1\nend\n")
    File.write!(Path.join(dir, "test/test_helper.exs"), "ExUnit.start()\n")

    File.write!(
      Path.join(dir, "test/other_test.exs"),
      "defmodule OtherTest do\n  use ExUnit.Case\n  test \"go\", do: assert(T.go() == 2)\nend\n"
    )

    blocks = "lib/t.ex\n<<<<<<< SEARCH\ndef go, do: 1\n=======\ndef go, do: 2\n>>>>>>> REPLACE\n"

    {out, 0} =
      System.cmd(@bin, ["edit", "--then", "test", "test/other_test.exs", blocks],
        cd: dir,
        env: [{"MENARD_CWD", nil}, {"MISE_ORIGINAL_CWD", nil}],
        stderr_to_stdout: true
      )

    assert out =~ ~s("did":"edit t.ex: 1 replacement, then run test")
    assert out =~ ~s("run":{"ok":true)
    assert out =~ ~s("tests":1)
  end

  @tag :tmp_dir
  test "a flag the usage lists fills the argument of that name: write FILE --code CODE", %{tmp_dir: dir} do
    # 2026-10-19: `write FILE --code "$(cat FILE)"` and `write FILE --file FILE`, each refused with
    # the usage line that lists --file and --code among the flags
    Host.mix_project(dir, :flagfill)
    File.mkdir_p!(Path.join(dir, "lib"))
    File.write!(Path.join(dir, "lib/t.ex"), "defmodule T do\n  def go, do: 1\nend\n")
    env = [{"MENARD_CWD", nil}, {"MISE_ORIGINAL_CWD", nil}]

    {out, 0} =
      System.cmd(@bin, ["write", "lib/t.ex", "--code", "defmodule T do\n  def go, do: 2\nend\n"],
        cd: dir,
        env: env,
        stderr_to_stdout: true
      )

    assert out =~ ~s("did":"write t.ex")
    assert File.read!(Path.join(dir, "lib/t.ex")) =~ "do: 2"

    {out, 0} =
      System.cmd(@bin, ["write", "--file", "lib/t.ex", "--code", "defmodule T do\n  def go, do: 3\nend\n"],
        cd: dir,
        env: env,
        stderr_to_stdout: true
      )

    assert out =~ ~s("did":"write t.ex")
    assert File.read!(Path.join(dir, "lib/t.ex")) =~ "do: 3"
  end
end
