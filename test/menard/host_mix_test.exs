defmodule Menard.HostMixTest do
  # The host's mix, on the host's toolchain — unless the host pins one that is not installed. Then
  # mise would build it (Erlang from source, through kerl: minutes, and a failure on a machine
  # without its build deps) before `run` answered ok:false with no reason.
  use ExUnit.Case, async: true

  alias Menard.Test.Host

  @moduletag :tmp_dir

  @tag skip: !System.find_executable("mise") && "needs mise"
  test "a pinned toolchain that is not installed is never built: the mix on PATH runs, and says so",
       %{tmp_dir: dir} do
    File.write!(Path.join(dir, ".tool-versions"), "erlang 26.2.3\nelixir 1.16.2-otp-26\n")

    {out, status} = Menard.host_mix(dir, ["--version"])

    assert status == 0
    assert out =~ "Mix"
    assert out =~ "erlang 26.2.3"
    # the note is the PATH branch's, where `mise exec` (the one that builds) never runs: no clock
    # needed to tell a build from none
    assert out =~ "not installed"
  end

  test "the host's mix reads no stdin: a prompt gets end of input, not a wait", %{tmp_dir: dir} do
    # `mix deps.get` asking "Shall I install Hex? [Yn]" waited forever on the CLI door: the port's
    # stdin stays open and never says anything
    Host.mix_project(dir, :asks)

    {out, status} = Menard.host_mix(dir, ["run", "-e", ~s|IO.inspect(IO.gets("go? "))|], timeout: 20_000)
    assert status == 0, out
    assert out =~ ":eof"
  end

  test "a deadline a millisecond short of a second is that second, not one less", %{tmp_dir: dir} do
    # a verb's deadline is what is left of it when each mix starts: 10_000ms given, 9_999 left a
    # millisecond later, and the kill came at 9s
    Host.mix_project(dir, :waits)

    {out, _status} = Menard.host_mix(dir, ["run", "-e", "Process.sleep(:infinity)"], timeout: 1_999)
    assert out =~ "did not finish in 2s"
  end

  test "an orphan that holds the output pipe does not hold the command: it returns with its output", %{
    tmp_dir: dir
  } do
    # a port's exit_status comes only at end of file on the pipe, so a grandchild that outlived the
    # command kept `run test` waiting for as long as it lived
    task =
      Task.async(fn ->
        Menard.host_cmd(dir, ["sh", "-c", "sleep 300 & echo $!; echo hi"], timeout: 20_000)
      end)

    result = Task.yield(task, 10_000) || Task.shutdown(task, :brutal_kill)

    assert {:ok, {out, 0}} = result
    [pid, "hi"] = out |> String.split("\n", trim: true) |> Enum.take(-2)
    System.cmd("kill", [pid])
  end
end
