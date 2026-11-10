defmodule Menard.DoorTest do
  # bin/menard hands a verb to the session's running hooks server (Menard.Door), so an edit boots
  # no VM: far faster than a VM per verb under load. The door here is this test VM's, under its own OS pid,
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
    # this VM was started by bin/menard under mise: its MENARD_CWD and MISE_ORIGINAL_CWD name
    # menard's own root, which the launcher would take for the caller's directory
    env = [{"TMPDIR", tmp}, {"MIX_ENV", "dev"}, {"MENARD_CWD", nil}, {"MISE_ORIGINAL_CWD", nil}, {"PWD", nil}]

    {:ok, dir: dir, tmp: tmp, env: env}
  end

  defp edit(dir, env) do
    System.cmd("sh", ["-c", ~s(printf '%s' "$1" | #{@bin} edit -), "sh", @blocks],
      cd: dir,
      env: env,
      stderr_to_stdout: true
    )
  end

  test "a session's door is under its harness's pid too: a session id changed since still finds it", ctx do
    door = start_supervised!({Menard.Door, key: ["a-session-id", System.pid()], dir: ctx.tmp})
    files = for key <- ["a-session-id", System.pid()], do: Path.join(ctx.tmp, "menard-door-#{key}")
    assert Enum.all?(files, &File.exists?/1)

    # as after /clear: the shell's id is one the server never had
    assert {_out, 0} = edit(ctx.dir, [{"CLAUDE_CODE_SESSION_ID", "another-id"} | ctx.env])
    assert Menard.Door.served() == 1

    GenServer.stop(door)
    refute Enum.any?(files, &File.exists?/1)
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
    File.write!(Path.join(ctx.tmp, "menard-door-#{System.pid()}"), "#{port}\n#{@root}\n")

    assert {out, 0} = edit(ctx.dir, ctx.env)
    assert out =~ ~r/^\{"did":"edit a.ex: 1 replacement"/
    assert File.read!(Path.join(ctx.dir, "lib/a.ex")) =~ "def one, do: 11"
  end

  # a request as the launcher frames it, sent by hand
  defp ask(port, fields, wait \\ 2_000) do
    {:ok, socket} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false])
    {:ok, "menard\n"} = :gen_tcp.recv(socket, 7, 2_000)
    :ok = :gen_tcp.send(socket, Enum.map(fields, &[&1, 0]))
    reply = :gen_tcp.recv(socket, 0, wait)
    :gen_tcp.close(socket)
    reply
  end

  defp door_file(ctx), do: Path.join(ctx.tmp, "menard-door-#{System.pid()}")

  test "the door is the session's alone: its file is the user's to read, and a request carries its token",
       ctx do
    start_supervised!({Menard.Door, key: System.pid(), dir: ctx.tmp})
    assert %{mode: mode} = File.stat!(door_file(ctx))
    assert Bitwise.band(mode, 0o077) == 0

    [port, _root, token] = door_file(ctx) |> File.read!() |> String.split("\n", trim: true)
    port = String.to_integer(port)
    assert byte_size(token) >= 32

    target = Path.join(ctx.dir, "evil.txt")
    write = [ctx.dir, "write", "2", target, "pwned", "0"]
    assert {:error, :closed} = ask(port, ["not-the-token" | write])
    assert {:error, :closed} = ask(port, ["" | write])
    refute File.exists?(target)
    assert Menard.Door.served() == 0

    assert {:ok, reply} = ask(port, [token | write], 30_000)
    assert reply =~ ~s("did":"write evil.txt")
    assert Menard.Door.served() == 1
  end

  test "the verbs the launcher keeps to itself are refused by the server too", ctx do
    start_supervised!({Menard.Door, key: System.pid(), dir: ctx.tmp})
    [port, _root, token] = door_file(ctx) |> File.read!() |> String.split("\n", trim: true)

    for verb <- ~w(run mcp hook guard) do
      assert {:error, :closed} = ask(String.to_integer(port), [token, ctx.dir, verb, "0", "0"])
    end

    assert Process.alive?(Process.whereis(Menard.Door))
  end

  test "a door that takes the connection and never answers is not waited on: the verb runs itself", ctx do
    {:ok, listen} = :gen_tcp.listen(0, ip: {127, 0, 0, 1})
    {:ok, port} = :inet.port(listen)
    File.write!(door_file(ctx), "#{port}\n#{@root}\ntoken\n")

    task = Task.async(fn -> edit(ctx.dir, ctx.env) end)
    assert {out, 0} = Task.await(task, 120_000)
    assert out =~ ~r/^\{"did":"edit a.ex: 1 replacement"/
    :gen_tcp.close(listen)
  end

  test "a door closing leaves the file of the server that took its place", ctx do
    door = start_supervised!({Menard.Door, key: System.pid(), dir: ctx.tmp})
    File.write!(door_file(ctx), "1\n#{@root}\nanother\n")
    GenServer.stop(door)
    assert File.read!(door_file(ctx)) =~ "another"
  end

  test "the session's door is found by its id, with no walk up the ancestors", ctx do
    start_supervised!({Menard.Door, key: "s-door-test", dir: ctx.tmp})
    env = List.keystore(ctx.env, "CLAUDE_CODE_SESSION_ID", 0, {"CLAUDE_CODE_SESSION_ID", "s-door-test"})

    assert {out, 0} = edit(ctx.dir, env)
    assert out =~ ~s("did":"edit a.ex: 1 replacement")
    assert Menard.Door.served() == 1
  end

  test "a door another build of menard opened is not used: the verb runs in this build's VM", ctx do
    start_supervised!({Menard.Door, key: System.pid(), dir: ctx.tmp})
    file = Path.join(ctx.tmp, "menard-door-#{System.pid()}")
    [port | _] = String.split(File.read!(file), "\n")
    File.write!(file, "#{port}\n/elsewhere/menard\n")

    assert {out, 0} = edit(ctx.dir, ctx.env)
    assert out =~ ~r/^\{"did":"edit a.ex: 1 replacement"/
    assert Menard.Door.served() == 0
  end

  test "`run` and a verb from inside menard's checkout keep their own VM", ctx do
    start_supervised!({Menard.Door, key: System.pid(), dir: ctx.tmp})

    {_, 0} = System.cmd(@bin, ["--frozen", "version"], env: ctx.env, stderr_to_stdout: true)
    {_, 0} = System.cmd(@bin, ["--frozen", "outline", "lib/menard/door.ex"], cd: @root, env: ctx.env)
    assert Menard.Door.served() == 0
  end
end
