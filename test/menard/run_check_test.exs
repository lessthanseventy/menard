defmodule Menard.RunCheckTest do
  # `run check`: the precommit alias or its three steps, one at a time per project. Apart from the
  # other run tests: each is a whole gate of a host's mix, and they run beside each other here.
  use ExUnit.Case, async: true

  alias Menard.Run
  alias Menard.Test.Host

  # real mix runs in a tmp project, stretched by the box's load (see Menard.RunTest)
  @moduletag timeout: 150_000
  @moduletag :tmp_dir

  test "check with no precommit alias runs format, warnings-as-errors and tests itself", %{tmp_dir: dir} do
    # `run check` is format + warnings-as-errors + tests; a host with no precommit alias still gets them
    Host.mix_project(dir, :plain)

    File.write!(
      Path.join(dir, ".formatter.exs"),
      "[inputs: [\"{mix,.formatter}.exs\", \"{lib,test}/**/*.{ex,exs}\"]]\n"
    )

    File.mkdir_p!(Path.join(dir, "lib"))
    File.mkdir_p!(Path.join(dir, "test"))
    File.write!(Path.join(dir, "lib/plain.ex"), "defmodule Plain do\n  def go, do: 1\nend\n")
    File.write!(Path.join(dir, "test/test_helper.exs"), "ExUnit.start()\n")

    File.write!(
      Path.join(dir, "test/plain_test.exs"),
      "defmodule PlainTest do\n  use ExUnit.Case\n  test \"go\", do: assert(Plain.go() == 1)\nend\n"
    )

    result = Menard.Run.result(dir, "check", [])
    assert result.ok, result.tail
    assert result.ran =~ "no precommit alias"
    assert result.tail =~ "Result: 1 passed"

    # its test step's failures are the formatter's, as `run test`'s are: from the prose, a `left:`
    # past one line is not cut to its first line
    File.write!(
      Path.join(dir, "test/plain_test.exs"),
      "defmodule PlainTest do\n  use ExUnit.Case\n  test \"go\", do: assert(Enum.to_list(1..60) == [])\nend\n"
    )

    assert %{ok: false, failures: [failure]} = Menard.Run.result(dir, "check", [])
    assert failure.left =~ "22,\n 23, 24"
  end

  test "check names the precommit step that failed when nothing in its output parses", %{tmp_dir: dir} do
    File.write!(Path.join(dir, "mix.exs"), """
    defmodule Stepped.MixProject do
      use Mix.Project

      def project,
        do: [
          app: :stepped,
          version: "0.1.0",
          aliases: [precommit: ["compile", ~s(cmd sh -c "echo linting ${MIX_DEBUG:-quiet}; echo 'x.sh:3: bad thing'; exit 1"), "test"]]
        ]
    end
    """)

    result = Menard.Run.result(dir, "check", [])
    refute result.ok

    assert [%{kind: "step", at: "mix.exs", step: "cmd sh -c" <> _, message: message}] = result.failures
    assert message =~ "x.sh:3: bad thing"
    # the task trace that names the step stays in precommit's VM: a host's tests running mix read it
    assert message =~ "linting quiet"
    refute message =~ "Mix.Tasks.Cmd.run"
  end

  test "check answers with its failures in the one shape: a file not formatted, a failing test", %{
    tmp_dir: dir
  } do
    Host.mix_project(dir, :plain)

    File.write!(Path.join(dir, ".formatter.exs"), "[inputs: [\"{lib,test}/**/*.{ex,exs}\"]]\n")
    File.mkdir_p!(Path.join(dir, "lib"))
    File.mkdir_p!(Path.join(dir, "test"))
    File.write!(Path.join(dir, "lib/plain.ex"), "defmodule Plain do\n  def   go, do: 1\nend\n")
    File.write!(Path.join(dir, "test/test_helper.exs"), "ExUnit.start()\n")

    File.write!(
      Path.join(dir, "test/plain_test.exs"),
      "defmodule PlainTest do\n  use ExUnit.Case\n\n  test \"go\" do\n    assert Plain.go() == 2\n  end\nend\n"
    )

    # the file a formatter fixes is formatted first, and named; the failing test is the answer
    result = Menard.Run.result(dir, "check", [])
    assert result.formatted == ["lib/plain.ex"]
    refute result.ok

    assert [%{kind: "test", at: "test/plain_test.exs:4", message: "Assertion with == failed", source: source}] =
             result.failures

    assert source =~ "assert Plain.go() == 2"
  end

  test "run check says how many tests were skipped, as run test does", %{tmp_dir: dir} do
    # check reads ExUnit's prose, not menard's formatter: `2 tests, 0 failures, 1 skipped` came back
    # as `tests: 2` and no word of the skip
    File.write!(Path.join(dir, "mix.exs"), """
    defmodule CheckSkips.MixProject do
      use Mix.Project
      def project, do: [app: :check_skips, version: "0.1.0", aliases: [precommit: ["test"]]]
      def cli, do: [preferred_envs: [precommit: :test]]
    end
    """)

    File.mkdir_p!(Path.join(dir, "test"))
    File.write!(Path.join(dir, "test/test_helper.exs"), "ExUnit.start()\n")

    File.write!(Path.join(dir, "test/check_skips_test.exs"), """
    defmodule CheckSkipsTest do
      use ExUnit.Case

      test "runs", do: :ok

      @tag skip: "no toolchain"
      test "skips", do: :ok
    end
    """)

    assert Run.lean(Menard.Run.result(dir, "check", [])) == %{
             ok: true,
             failures: [],
             tests: 1,
             failed: 0,
             skipped: 1
           }
  end

  @tag :tmp_dir
  test "check formats the project first, and names what it formatted", %{tmp_dir: dir} do
    # Formatting is mechanical: check formats the project first, and names what it did
    File.write!(Path.join(dir, "mix.exs"), """
    defmodule Before.MixProject do
      use Mix.Project
      def project, do: [app: :before, version: "0.1.0", aliases: [precommit: ["format --check-formatted"]]]
    end
    """)

    File.write!(Path.join(dir, ".formatter.exs"), ~s([inputs: ["lib/**/*.ex"]]\n))
    File.mkdir_p!(Path.join(dir, "lib"))
    File.write!(Path.join(dir, "lib/old.ex"), "defmodule Old do\n  def a,   do: 1\nend\n")

    assert %{ok: true, formatted: ["lib/old.ex"]} = Run.lean(Run.result(dir, "check", []))
    assert File.read!(Path.join(dir, "lib/old.ex")) == "defmodule Old do\n  def a, do: 1\nend\n"
  end

  @tag :tmp_dir
  test "one check at a time in a project: the next waits, and says how long", %{tmp_dir: dir} do
    # two sessions' gates in one checkout race in its _build and tmp/: a check waits for the one
    # already running, and says so; a lock its holder left behind dead is no wait
    Host.mix_project(dir, :locked)
    lock = Path.join(dir, "_build/.menard-check.lock")
    File.mkdir_p!(Path.dirname(lock))

    holder = Port.open({:spawn, "sleep 3"}, [])
    {:os_pid, pid} = Port.info(holder, :os_pid)
    File.write!(lock, to_string(pid))
    assert %{waited: waited} = Run.result(dir, "check", [])
    assert waited >= 2
    refute File.exists?(lock)

    File.write!(lock, "999999999")
    refute Map.has_key?(Run.result(dir, "check", []), :waited)

    # this VM's own, its check gone (killed at a deadline, its `after` never run): no wait
    File.write!(lock, System.pid())
    refute Map.has_key?(Run.result(dir, "check", []), :waited)
    # a dead holder's lock is moved aside to be taken (a rename only one waiter wins), then gone
    assert Path.wildcard(lock <> ".*") == []
  end

  @tag :tmp_dir
  test "a test run waits for a run already in the project, as a check does", %{tmp_dir: dir} do
    # ExUnit gives a test the same tmp/ directory in every run of a checkout, and clears it as the
    # test starts: a second run beside the first deleted the files its tests were reading
    Host.mix_project(dir, :locked_test)
    File.mkdir_p!(Path.join(dir, "test"))
    File.write!(Path.join(dir, "test/test_helper.exs"), "ExUnit.start()\n")

    File.write!(
      Path.join(dir, "test/a_test.exs"),
      "defmodule ATest do\n  use ExUnit.Case\n  test \"a\", do: :ok\nend\n"
    )

    lock = Path.join(dir, "_build/.menard-check.lock")
    File.mkdir_p!(Path.dirname(lock))

    holder = Port.open({:spawn, "sleep 3"}, [])
    {:os_pid, pid} = Port.info(holder, :os_pid)
    File.write!(lock, to_string(pid))
    assert %{ok: true, waited: waited} = Run.result(dir, "test", [])
    assert waited >= 2
  end
end
