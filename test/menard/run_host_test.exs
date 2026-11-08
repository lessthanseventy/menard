defmodule Menard.RunHostTest do
  # the host's mix as a process: its toolchain, its log, its deadline, its mix.lock. Apart from the
  # other run tests: each runs a host's mix, and they run beside each other here.
  use ExUnit.Case, async: true

  alias Menard.Run
  alias Menard.Test.Host

  # real mix runs in a tmp project, stretched by the box's load (see Menard.RunTest)
  @moduletag timeout: 150_000
  @moduletag :tmp_dir

  test "compile reports a warning left by an earlier compile", %{tmp_dir: dir} do
    Host.mix_project(dir, :warm)

    File.mkdir_p!(Path.join(dir, "lib"))
    File.write!(Path.join(dir, "lib/warm.ex"), "defmodule Warm do\n  def go(x), do: 1\nend\n")
    System.cmd("mix", ["compile"], cd: dir, stderr_to_stdout: true, env: [{"MIX_ENV", nil}])

    result = Menard.Run.result(dir, "compile", [])
    refute result.ok
    assert [%{kind: "warning", at: "lib/warm.ex:2", message: message}] = result.failures
    assert message =~ "x"
  end

  @pinned "1.19.4-otp-27"

  test "the host's mix runs on the host's toolchain, not menard's", %{tmp_dir: dir} do
    File.write!(Path.join(dir, "mise.toml"), "[tools]\nelixir = \"#{@pinned}\"\nerlang = \"27\"\n")

    File.write!(Path.join(dir, "mix.exs"), """
    defmodule Pin.MixProject do
      use Mix.Project
      def project, do: [app: :pin, version: "0.1.0", aliases: [precommit: ["run --no-start -e \\"IO.puts(System.version())\\""]]]
    end
    """)

    System.cmd("mise", ["trust", Path.join(dir, "mise.toml")], stderr_to_stdout: true)
    assert Menard.Run.result(dir, "check", []).tail =~ "1.19.4"
  end

  test "a run behind its mix.lock fetches, runs again, and says what it fetched", %{tmp_dir: dir} do
    # a pull that moved mix.lock leaves deps/ behind it: `run` fetches, runs again, and says so
    dep = Path.join(dir, "dep")
    File.mkdir_p!(Path.join(dep, "lib"))

    File.write!(
      Path.join(dep, "mix.exs"),
      "defmodule Dep.MixProject do\n  use Mix.Project\n  def project, do: [app: :dep, version: \"0.1.0\"]\nend\n"
    )

    File.write!(Path.join(dep, "lib/dep.ex"), "defmodule Dep do\n  def one, do: 1\nend\n")
    git = &System.cmd("git", &1, cd: dep, stderr_to_stdout: true)
    git.(["init", "-q"])
    git.(["add", "."])
    git.(["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "dep"])

    host = Path.join(dir, "host")
    File.mkdir_p!(Path.join(host, "lib"))

    File.write!(Path.join(host, "mix.exs"), """
    defmodule Host.MixProject do
      use Mix.Project
      def project, do: [app: :host, version: "0.1.0", deps: [{:dep, git: #{inspect(dep)}}]]
    end
    """)

    File.write!(Path.join(host, "lib/host.ex"), "defmodule Host do\n  def two, do: Dep.one() + 1\nend\n")
    System.cmd("mix", ["deps.get"], cd: host, stderr_to_stdout: true, env: [{"MIX_ENV", nil}])
    # the checkout falls behind its lock
    File.rm_rf!(Path.join(host, "deps"))

    result = Menard.Run.result(host, "compile", [])
    assert result.ok, result.tail
    assert result.fetched == ["dep"]
  end

  test "a red run keeps its whole output in a log and names it; a green one names none", %{tmp_dir: dir} do
    # cap.sh's rule, Tlön's: run once, read the log; never run again with another grep to see more
    Host.mix_project(dir, :logged)

    File.mkdir_p!(Path.join(dir, "test"))
    File.write!(Path.join(dir, "test/test_helper.exs"), "ExUnit.start()\n")
    test = Path.join(dir, "test/logged_test.exs")
    File.write!(test, "defmodule LoggedTest do\n  use ExUnit.Case\n  test \"one\", do: assert(1 == 2)\nend\n")

    red = Menard.Run.lean(Menard.Run.result(dir, "test", [], []))
    refute red.ok
    assert File.read!(red.log) =~ "Assertion with == failed"

    File.write!(test, "defmodule LoggedTest do\n  use ExUnit.Case\n  test \"one\", do: assert(1 == 1)\nend\n")
    green = Menard.Run.lean(Menard.Run.result(dir, "test", [], []))
    assert green.ok
    refute Map.has_key?(green, :log)
  end

  test "a run past its deadline kills the host's mix and says what it was doing", %{tmp_dir: dir} do
    # an MCP client gave up on `run` while its mix kept compiling, and the agent's own `mix test` then
    # raced it in the same _build: "corrupt atom table"
    Host.mix_project(dir, :slow)

    File.mkdir_p!(Path.join(dir, "test"))
    File.write!(Path.join(dir, "test/test_helper.exs"), "ExUnit.start()\n")
    pidfile = Path.join(dir, "mix.pid")

    # the test starts once the project compiles (a few seconds), names its VM and says so, then hangs:
    # only the deadline ends it
    File.write!(Path.join(dir, "test/slow_test.exs"), """
    defmodule SlowTest do
      use ExUnit.Case
      test "fails first", do: assert(1 == 2)

      test "slow" do
        File.write!(#{inspect(pidfile)}, System.pid())
        IO.puts("halfway there")
        Process.sleep(:infinity)
      end
    end
    """)

    # compiled before the clock starts: on a loaded box the compile alone passed the deadline, and
    # the run then had no running test to name
    assert %{exit: 0, tests: 0} = Menard.Run.result(dir, "test", ["--exclude", "test"], [])

    # the bound is loose on purpose: the test itself never ends, so any answer is the kill, and the
    # room past 10s is a loaded host's teardown, not slack in the deadline
    started = System.monotonic_time(:millisecond)
    result = Menard.Run.result(dir, "test", ["--seed", "0"], timeout: 10_000)
    assert System.monotonic_time(:millisecond) - started < 40_000

    refute result.ok
    assert result.tail =~ "did not finish in 10s"
    # a run stopped at its deadline answers what it had: the failures so far, and the test that was
    # still running
    assert %{name: "fails first"} = Enum.find(result.failures, &(&1.kind == "test"))
    assert %{name: "slow", at: "test/slow_test.exs:5"} = Enum.find(result.failures, &(&1.kind == "timeout"))

    # `timeout` returns once its child is gone, so the VM is dead by now, not dying
    assert {_, status} = System.cmd("kill", ["-0", File.read!(pidfile)], stderr_to_stdout: true)
    assert status != 0
  end

  @tag :tmp_dir
  test "a raised error says where it was raised: the frames in the project", %{tmp_dir: dir} do
    # a KeyError raised in lib/shop/cart.ex:25: the frames in the project say where
    Host.mix_project(dir, :raises)
    File.mkdir_p!(Path.join(dir, "lib"))
    File.mkdir_p!(Path.join(dir, "test"))

    File.write!(
      Path.join(dir, "lib/cart.ex"),
      "defmodule Cart do\n  def total(cart) do\n    Map.fetch!(cart, :items)\n  end\nend\n"
    )

    File.write!(Path.join(dir, "test/test_helper.exs"), "ExUnit.start()\n")

    File.write!(
      Path.join(dir, "test/cart_test.exs"),
      # a cart from config, not `%{}`: 1.20's type checker warns of that one at compile time
      "defmodule CartTest do\n  use ExUnit.Case\n  test \"total\", do: Cart.total(Application.get_env(:raises, :cart, %{}))\nend\n"
    )

    assert %{failures: [%{message: message, stack: stack}]} = Run.lean(Run.result(dir, "test", []))
    assert message =~ "KeyError"
    assert Enum.any?(stack, &(&1 =~ "lib/cart.ex:3"))
    assert length(stack) <= 3
  end
end
