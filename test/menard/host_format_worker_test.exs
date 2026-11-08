defmodule Menard.HostFormatWorkerTest do
  # the host's formatter as a process kept warm (Menard.Format.Worker): started, killed, died, out
  # of time. Apart from the other host_format tests so their host VMs boot beside each other.
  use ExUnit.Case, async: true

  import Menard.Test.HostFormat

  alias Menard.Format.Worker

  @moduletag :tmp_dir

  # every test here is its own project (tmp_dir), so a warm worker it started is never reused —
  # left running, it would idle out ten minutes later (Menard.Format.Worker's @idle), long past
  # the suite, as an orphaned host VM (systemd-reparented once mix test's own VM is gone).
  setup %{tmp_dir: dir} do
    on_exit(fn -> Worker.stop(Path.expand(dir)) end)
  end

  test "a write the format could not finish says so in its reply", %{tmp_dir: dir} do
    # a write the format could not finish said so on stderr only, and the reply looked clean
    host(dir, "[inputs: [\"lib/**/*.ex\"], plugins: [MenardNeverBuiltPlug]]")
    file = write(dir, "f.ex", "defmodule F do\nend\n")

    ExUnit.CaptureIO.capture_io(:stderr, fn ->
      send(self(), {:reply, Menard.write(file, "defmodule F do\n  def   f, do: 1\nend\n")})
    end)

    assert_received {:reply, {:ok, reply}}
    # why: the plugin that cannot be found, or, on a loaded machine, the clock run out
    assert reply.unformatted =~ ~r/MenardNeverBuiltPlug|did not finish/
    assert %{error: _} = Enum.find(reply.stages, &(&1.stage == :formatter))
    assert File.read!(file) =~ "def   f"
  end

  # up to three deadlines (31s) and their kills; ExUnit's 60s default is too close
  @tag timeout: 120_000
  test "a format out of time is killed, and nothing it spawned writes the file afterwards", %{tmp_dir: dir} do
    # the shell fallback's `mix format` ran on after menard gave up, and wrote the file after menard
    # had handed out its version: the agent's next edit was refused as stale. It sleeps past the
    # longest deadline below, so only a VM that survived its kill writes "late".
    plugin =
      plug(dir, "Slow", ~S"""
      File.write!(opts[:pid_file], System.pid())
      Process.sleep(60_000)
      File.write!(opts[:file], "# late\n")
      contents
      """)

    file = write(dir, "s.ex", "defmodule S do\nend\n")

    # the deadline must outlast the host VM's start, or it is stopped before the plugin says its pid,
    # and there is nothing to check: on a loaded host that start took past 1s. So a run stopped too
    # early is run again with more time, each with its own pid file.
    stopped = fn ms ->
      pid_file = Path.join(dir, "pid-#{ms}")

      host(
        dir,
        "[inputs: [\"lib/**/*.ex\"], plugins: [#{inspect(plugin)}], pid_file: #{inspect(pid_file)}, file: #{inspect(file)}]"
      )

      assert {:error, message} =
               Menard.format_staged(file, File.read!(file), cache: Path.join(dir, "cache"), timeout: ms)

      assert message =~ "did not finish in #{div(ms, 1000)}s"

      case File.read(pid_file) do
        {:ok, pid} -> pid
        {:error, :enoent} -> nil
      end
    end

    pid = Enum.find_value([1_000, 5_000, 25_000], stopped) || flunk("the host's VM never reached the plugin")
    # the host's VM was stopped with the deadline, not left to finish
    assert {_, status} = System.cmd("kill", ["-0", pid], stderr_to_stdout: true)
    assert status != 0, "the host's formatter (pid #{pid}) outlived its deadline"
    assert File.read!(file) == "defmodule S do\nend\n"
  end

  test "the formatter is kept warm: a second format is answered by the VM the first started", %{tmp_dir: dir} do
    # the host's VM takes 0.4s to start, which a session paid on every write
    plugin = plug(dir, "Pid", ~S|"# " <> System.pid() <> "\n" <> contents|)
    host(dir, "[inputs: [\"lib/**/*.ex\"], plugins: [#{inspect(plugin)}]]")
    file = write(dir, "a.ex", "defmodule A do\nend\n")

    vm = fn opts ->
      {:ok, "# " <> formatted, _split} =
        Menard.format_staged(file, File.read!(file), [cache: Path.join(dir, "cache")] ++ opts)

      formatted |> String.split("\n") |> hd()
    end

    first = vm.([])
    assert vm.([]) == first
    # asked for a process of its own, it is one
    assert vm.(warm: false) != first

    # the plugins are held as first loaded: a lock that changed since is a new VM
    File.write!(Path.join(dir, "mix.lock"), "%{}\n")
    assert vm.([]) != first
  end

  test "stopping a project's worker kills the host VM it started — nothing outlives the call", %{tmp_dir: dir} do
    plugin = plug(dir, "Pid", ~S|"# " <> System.pid() <> "\n" <> contents|)
    host(dir, "[inputs: [\"lib/**/*.ex\"], plugins: [#{inspect(plugin)}]]")
    file = write(dir, "a.ex", "defmodule A do\nend\n")

    {:ok, "# " <> rest, _split} = Menard.format_staged(file, File.read!(file), cache: Path.join(dir, "cache"))
    pid = rest |> String.split("\n") |> hd()
    assert {_, 0} = System.cmd("kill", ["-0", pid], stderr_to_stdout: true)

    Worker.stop(Path.expand(dir))

    assert {_, status} = System.cmd("kill", ["-0", pid], stderr_to_stdout: true)
    assert status != 0, "the host's VM (pid #{pid}) outlived stop/1"
  end

  # a loaded box pays for two BEAM boots serialized (this owner, then the host VM it spawns):
  # ~60 idle warm formatter VMs alone pushed one more boot past 9.5s in a probe on this machine,
  # and the suite keeps ~80 of these warm (format.exs's own comment) while doing real AST work,
  # not sitting idle, so 10s was never enough margin, not a hung watchdog.
  @tag timeout: 90_000
  test "the host VM does not outlive the process that started it — killed outright, not stopped",
       %{tmp_dir: dir} do
    # exercises priv/format.exs's own watchdog directly, not through Worker/DynamicSupervisor:
    # a stand-in "owner" OS process (not this test's BEAM) opens the warm VM exactly as
    # Menard.Format.Worker does, reports its pid, and gets SIGKILLed outright — no terminate/2,
    # no EOF the caller chose to send. The VM must notice its own ppid changed and exit anyway.
    host(dir, "[inputs: [\"lib/**/*.ex\"]]")
    script = Application.app_dir(:menard, "priv/format.exs")
    owner_exs = Path.join(dir, "owner.exs")

    File.write!(owner_exs, """
    port =
      Port.open({:spawn_executable, System.find_executable("sh")}, [
        :binary,
        :nouse_stdio,
        :exit_status,
        {:packet, 4},
        args: ["-c", ~s(exec "$@" </dev/null >/dev/null 2>&1), "sh", "elixir", #{inspect(script)}, "serve"],
        cd: #{inspect(dir)}
      ])

    receive do
      {^port, {:data, data}} ->
        case :erlang.binary_to_term(data) do
          {:pid, pid} -> IO.puts(pid)
        end
    end

    Process.sleep(:infinity)
    """)

    owner =
      Port.open({:spawn_executable, System.find_executable("elixir")}, [
        :binary,
        :exit_status,
        {:line, 1024},
        args: [owner_exs]
      ])

    vm_pid =
      receive do
        {^owner, {:data, {:eol, line}}} -> line
      after
        30_000 -> flunk("the stand-in owner never reported the host VM's pid")
      end

    on_exit(fn -> System.cmd("kill", ["-KILL", vm_pid], stderr_to_stdout: true) end)
    assert {_, 0} = System.cmd("kill", ["-0", vm_pid], stderr_to_stdout: true)

    {:os_pid, owner_pid} = Port.info(owner, :os_pid)
    # not stop/1, not a signal the VM is watching for: the owner is simply gone
    System.cmd("kill", ["-KILL", "#{owner_pid}"], stderr_to_stdout: true)

    dead =
      Enum.any?([250, 500, 1_000, 2_000, 2_000, 2_000], fn ms ->
        Process.sleep(ms)
        match?({_, 1}, System.cmd("kill", ["-0", vm_pid], stderr_to_stdout: true))
      end)

    assert dead, "the host VM (pid #{vm_pid}) outlived its killed owner"
  end

  test "a formatter whose VM died says why, and the next format starts another", %{tmp_dir: dir} do
    plugin = plug(dir, "Dies", ~S|if contents =~ "die", do: System.halt(3), else: contents|)
    host(dir, "[inputs: [\"lib/**/*.ex\"], plugins: [#{inspect(plugin)}]]")
    file = write(dir, "a.ex", "defmodule A do\nend\n")
    format = &Menard.format_staged(file, &1, cache: Path.join(dir, "cache"))

    assert {:error, "the host's formatter failed" <> _} = format.("# die\n")
    assert {:ok, "defmodule A do\nend\n", _split} = format.("defmodule A do\nend\n")
  end
end
