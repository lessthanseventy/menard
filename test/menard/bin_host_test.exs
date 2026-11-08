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
  test "a VM menard starts that crashes dumps in the temp dir, not the caller's project", %{tmp_dir: dir} do
    # a host VM menard starts that crashes on boot must not leave erl_crash.dump in the caller's cwd
    Host.mix_project(dir, :dumps)
    File.mkdir_p!(Path.join(dir, "test"))
    File.mkdir_p!(Path.join(dir, "tmp"))
    File.write!(Path.join(dir, "test/test_helper.exs"), "ExUnit.start()\n")

    File.write!(Path.join(dir, "test/dumps_test.exs"), """
    defmodule DumpsTest do
      use ExUnit.Case
      test "crashes", do: :erlang.halt(~c"boom")
    end
    """)

    {_out, _} =
      System.cmd(@bin, ["run", "test", "--in", dir],
        # the suite's own bin/menard set one: unset, it is this one's to choose
        env: [{"TMPDIR", Path.join(dir, "tmp")}, {"ERL_CRASH_DUMP", nil}],
        stderr_to_stdout: true
      )

    refute File.exists?(Path.join(dir, "erl_crash.dump"))
    assert File.read!(Path.join(dir, "tmp/menard-erl_crash.dump")) =~ "Slogan: boom"
  end

  @tag :tmp_dir
  test "the language server bin/lsp starts dumps in the temp dir too", %{tmp_dir: dir} do
    # Claude Code's lspServers start bin/lsp, not bin/menard, and its server is a VM in the project
    server = Path.join(dir, "server")
    File.write!(server, "#!/bin/sh\necho \"$ERL_CRASH_DUMP\"\n")
    File.chmod!(server, 0o755)

    {out, 0} =
      System.cmd(Path.join(@root, "bin/lsp"), [],
        env: [{"MENARD_LSP", server}, {"TMPDIR", dir}, {"ERL_CRASH_DUMP", nil}]
      )

    assert out == Path.join(dir, "menard-erl_crash.dump") <> "\n"
  end

  @tag :tmp_dir
  test "a stderr whose reader is gone gets the verb's exit, not SIGPIPE's", %{tmp_dir: dir} do
    # a refusal printed to a dead stderr pipe must not exit 141, the shell's own SIGPIPE on the
    # `cat` that passes the verb's stderr on, and lose the verb's 1
    File.write!(Path.join(dir, "a.ex"), "defmodule A do\nend\n")
    File.write!(Path.join(dir, "bad.edit"), "a.ex\n<<<<<<< SEARCH\nnope\n=======\nx\n>>>>>>> REPLACE\n")

    # the VM ignores SIGPIPE, and so would the bash it starts: a terminal's shell does not
    {_out, status} =
      System.cmd(
        "env",
        [
          "--default-signal=PIPE",
          "bash",
          "-c",
          ~S'"$0" edit - < bad.edit 2>&1 1>out.txt | true; exit ${PIPESTATUS[0]}',
          @bin
        ],
        cd: dir,
        env: [{"MENARD_CWD", dir}]
      )

    assert status == 1
  end

  @tag :tmp_dir
  test "edit --then at the CLI exits non-zero when the then is red, as `run` does", %{tmp_dir: dir} do
    # `menard edit --then check … && git commit` committed on a red gate: the reply said `ok: false`,
    # and the exit said 0
    Host.mix_project(dir, :thenred)
    File.mkdir_p!(Path.join(dir, "lib"))
    File.write!(Path.join(dir, "lib/t.ex"), "defmodule T do\n  def a, do: 1\nend\n")

    blocks = "lib/t.ex\n<<<<<<< SEARCH\n  def a, do: 1\n=======\n  def a, do: nope()\n>>>>>>> REPLACE\n"

    {out, status} =
      System.cmd(@bin, ["edit", "--then", "compile", blocks],
        cd: dir,
        env: [{"MENARD_CWD", nil}, {"MISE_ORIGINAL_CWD", nil}],
        stderr_to_stdout: true
      )

    assert out =~ ~s("ok":false)
    assert out =~ ~s("did":"edit t.ex: 1 replacement, then run compile")
    assert status == 1
  end

  @tag :tmp_dir
  test "edit --then at the CLI runs the then, as the MCP door does", %{tmp_dir: dir} do
    # `--then test` must not be dropped without a word at the CLI. Held at the door the agent types
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
    # `edit --then test test/x_test.exs -` must not be refused with the bare usage line
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
    # `write FILE --code "$(cat FILE)"` and `write FILE --file FILE` must not be refused with the
    # usage line that lists --file and --code among the flags
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
