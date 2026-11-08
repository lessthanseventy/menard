defmodule Menard.DoorTest do
  # bin/menard hands a verb to the session's running hooks server (Menard.Door), so an edit boots
  # no VM: 24 s at the median under the seats' load against the MCP door's 1 s
  # (docs/review/2026-11-08-transcripts.md). The door here is this test VM's, under its own OS pid,
  # the parent of every process System.cmd starts; the project edited is outside menard's checkout,
  # as a host's is, since a verb from inside the checkout is never forwarded.
  use ExUnit.Case, async: false

  alias Menard.Test.Host
  alias Mix.Shell

  @root Path.expand("../..", __DIR__)
  @bin Path.join(@root, "bin/menard")
  @blocks "lib/a.ex\n<<<<<<< SEARCH\ndef one, do: 1\n=======\ndef one, do: 11\n>>>>>>> REPLACE\n"

  setup do
    # as the hooks server runs: a task's `info` and `error` are messages to the process that ran it
    shell = Mix.shell()
    Mix.shell(Shell.Process)
    on_exit(fn -> Mix.shell(shell) end)
    dir = Path.join(System.tmp_dir!(), "menard-door-#{System.pid()}-#{System.unique_integer([:positive])}")
    tmp = Path.join(dir, "tmp")
    File.mkdir_p!(Path.join(dir, "lib"))
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(dir) end)
    Host.mix_project(dir, :doored)
    File.write!(Path.join(dir, ".formatter.exs"), "[inputs: [\"lib/**/*.ex\"]]")
    File.write!(Path.join(dir, "lib/a.ex"), "defmodule A do\n  def one, do: 1\nend\n")
    # this VM was started by bin/menard under mise, in a Claude Code session: its MENARD_CWD and
    # MISE_ORIGINAL_CWD name menard's own root, which the launcher would take for the caller's
    # directory, and the session's id would name a door of the session's, not this test's
    env = [
      {"TMPDIR", tmp},
      {"MIX_ENV", "dev"},
      {"MENARD_CWD", nil},
      {"MISE_ORIGINAL_CWD", nil},
      {"PWD", nil},
      {"CLAUDE_CODE_SESSION_ID", nil}
    ]

    {:ok, dir: dir, tmp: tmp, env: env}
  end

  defp edit(dir, env) do
    System.cmd("sh", ["-c", ~s(printf '%s' "$1" | #{@bin} edit -), "sh", @blocks],
      cd: dir,
      env: env,
      stderr_to_stdout: true
    )
  end

  test "an edit through bin/menard is answered by the running server, no VM of its own", ctx do
    start_supervised!({Menard.Door, key: System.pid(), dir: ctx.tmp})

    assert {out, 0} = edit(ctx.dir, ctx.env)
    assert out =~ ~s("did":"edit a.ex: 1 replacement")
    assert File.read!(Path.join(ctx.dir, "lib/a.ex")) =~ "def one, do: 11"
    assert Menard.Door.served() == 1
  end

  test "a refusal comes back as the launcher's own would: one line on stderr, exit 1", ctx do
    start_supervised!({Menard.Door, key: System.pid(), dir: ctx.tmp})
    File.write!(Path.join(ctx.dir, "lib/a.ex"), "defmodule A do\n  def two, do: 2\nend\n")

    assert {out, 1} = edit(ctx.dir, ctx.env)
    assert out =~ "** (Mix) edit 1 of 1, lib/a.ex: this text is not there"
    refute out =~ "stacktrace"
    assert Menard.Door.served() == 1
  end

  test "a door nobody answers costs nothing but the try: the verb runs in its own VM", ctx do
    {:ok, listen} = :gen_tcp.listen(0, ip: {127, 0, 0, 1})
    {:ok, port} = :inet.port(listen)
    :gen_tcp.close(listen)
    File.write!(Path.join(ctx.tmp, "menard-door-#{System.pid()}"), "#{port}\n")

    assert {out, 0} = edit(ctx.dir, ctx.env)
    assert out =~ ~r/^\{"did":"edit a.ex: 1 replacement"/
    assert File.read!(Path.join(ctx.dir, "lib/a.ex")) =~ "def one, do: 11"
  end

  test "the session's door is found by its id, with no walk up the ancestors", ctx do
    start_supervised!({Menard.Door, key: "s-door-test", dir: ctx.tmp})
    env = List.keystore(ctx.env, "CLAUDE_CODE_SESSION_ID", 0, {"CLAUDE_CODE_SESSION_ID", "s-door-test"})

    assert {out, 0} = edit(ctx.dir, env)
    assert out =~ ~s("did":"edit a.ex: 1 replacement")
    assert Menard.Door.served() == 1
  end

  test "`run` and a verb from inside menard's checkout keep their own VM", ctx do
    start_supervised!({Menard.Door, key: System.pid(), dir: ctx.tmp})

    {_, 0} = System.cmd(@bin, ["--frozen", "version"], env: ctx.env, stderr_to_stdout: true)
    {_, 0} = System.cmd(@bin, ["--frozen", "outline", "lib/menard/door.ex"], cd: @root, env: ctx.env)
    assert Menard.Door.served() == 0
  end
end
