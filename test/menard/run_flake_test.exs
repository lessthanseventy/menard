defmodule Menard.RunFlakeTest do
  # a failed test run once more: a flake named, a flake hunted, --stale warmed. Apart from the
  # other run tests: each is several runs of a host's mix, and they run beside each other here.
  use ExUnit.Case, async: true

  alias Menard.Run
  alias Menard.Test.Host

  # real mix runs in a tmp project, stretched by the box's load (see Menard.RunTest)
  @moduletag timeout: 150_000
  @moduletag :tmp_dir

  test "hunts a flake: repeats until it fails, and answers with that run, its seed and the run count", %{
    tmp_dir: dir
  } do
    Host.mix_project(dir, :flaky)

    File.mkdir_p!(Path.join(dir, "test"))
    File.write!(Path.join(dir, "test/test_helper.exs"), "ExUnit.start()\n")
    counter = Path.join(dir, "runs")

    # passes on the first run, fails on the second: a flake that one run never shows
    File.write!(Path.join(dir, "test/flaky_test.exs"), """
    defmodule FlakyTest do
      use ExUnit.Case
      test "sometimes" do
        n = case File.read(#{inspect(counter)}) do
          {:ok, s} -> String.to_integer(s) + 1
          _ -> 1
        end
        File.write!(#{inspect(counter)}, Integer.to_string(n))
        assert n < 2
      end
    end
    """)

    bin = Path.expand("../../bin/menard", __DIR__)

    {out, 1} =
      System.cmd(bin, ["run", "--in", dir, "test", "--repeat-until-failure", "5"], env: [{"MIX_ENV", "dev"}])

    answer = out |> String.split("\n", trim: true) |> List.last() |> JSON.decode!()

    assert answer["ok"] == false
    assert answer["runs"] == 2
    assert is_integer(answer["seed"])
    assert [%{"name" => "sometimes"}] = answer["failures"]
    assert answer["failed"] == 1
  end

  @tag :tmp_dir
  test "a test that fails once and passes on its rerun is named a flake, not the change's failure", %{
    tmp_dir: dir
  } do
    # Oban 01, 04, Symphony 01: a failure that was the suite's own flake read as the change's, and the
    # agent stashed its work to run a baseline. Failed once, it runs again; passed, it is named a flake
    Host.mix_project(dir, :flakes)
    File.mkdir_p!(Path.join(dir, "test"))
    File.write!(Path.join(dir, "test/test_helper.exs"), "ExUnit.start()\n")

    File.write!(Path.join(dir, "test/flaky_test.exs"), """
    defmodule FlakyTest do
      use ExUnit.Case

      test "steady", do: :ok

      test "once" do
        marker = Path.join(__DIR__, "ran")
        first? = not File.exists?(marker)
        File.write!(marker, "")
        refute first?
      end

      test "broken", do: assert(1 == 2)
    end
    """)

    assert %{ok: false, flaky: [%{name: "once", at: "test/flaky_test.exs:6"}], failures: [%{name: "broken"}]} =
             Run.lean(Run.result(dir, "test", []))

    # every failure passing on its rerun: green, the flakes named
    File.rm!(Path.join(dir, "test/ran"))

    File.write!(
      Path.join(dir, "test/flaky_test.exs"),
      String.replace(File.read!(Path.join(dir, "test/flaky_test.exs")), "assert(1 == 2)", ":ok")
    )

    assert %{ok: true, flaky: [%{name: "once"}]} = Run.lean(Run.result(dir, "test", []))
  end

  @tag :tmp_dir
  test "a check's failed tests run once more; one that passes is a flake, not the change's", %{tmp_dir: dir} do
    # up4 Oban 01: run check red twice on the notifier's flake, no rerun, and the agent stashed its work
    # for a baseline; run test said `flaky` in the same step. A check reruns its failed tests too
    flaky = """
    defmodule FlakyTest do
      use ExUnit.Case

      test "once" do
        marker = Path.join(__DIR__, "ran")
        first? = not File.exists?(marker)
        File.write!(marker, "")
        refute first?
      end
    end
    """

    Host.mix_project(dir, :flakes)
    File.write!(Path.join(dir, ".formatter.exs"), ~s([inputs: ["test/**/*.exs"]]\n))
    File.mkdir_p!(Path.join(dir, "test"))
    File.write!(Path.join(dir, "test/test_helper.exs"), "ExUnit.start()\n")
    File.write!(Path.join(dir, "test/flaky_test.exs"), flaky)

    # no precommit alias: every step ran, so a check whose only failures were flakes is green
    assert %{ok: true, flaky: [%{name: "once"}]} = Run.lean(Run.result(dir, "check", []))

    # an alias stops at its failing step: the steps after it are run here, each its own mix, and
    # the check is green (it said "run check again", a second whole gate: Fable's review, 2026-10-01)
    File.rm!(Path.join(dir, "test/ran"))

    File.write!(Path.join(dir, "mix.exs"), """
    defmodule Flakes.MixProject do
      use Mix.Project
      def project, do: [app: :flakes, version: "0.1.0", aliases: [precommit: ["test", "compile", "cmd true"]]]
      def cli, do: [preferred_envs: [precommit: :test]]
    end
    """)

    assert %{ok: true, flaky: [%{name: "once"}], failures: [], note: note} =
             Run.lean(Run.result(dir, "check", []))

    assert note =~ "the precommit steps after the tests ran, and passed"

    # a step after the tests that is red: that step, named
    File.rm!(Path.join(dir, "test/ran"))

    File.write!(Path.join(dir, "mix.exs"), """
    defmodule Flakes.MixProject do
      use Mix.Project
      def project, do: [app: :flakes, version: "0.1.0", aliases: [precommit: ["test", "cmd sh -c 'echo nope; exit 3'"]]]
      def cli, do: [preferred_envs: [precommit: :test]]
    end
    """)

    assert %{ok: false, flaky: [%{name: "once"}], failures: [%{kind: "step", message: message}]} =
             Run.lean(Run.result(dir, "check", []))

    assert message =~ "mix cmd sh -c echo nope; exit 3 failed:"
    assert message =~ "nope"
  end

  @tag :tmp_dir
  test "a green full run warms --stale, so the next is the tests the change touches", %{tmp_dir: dir} do
    # `--stale` is the tests a change touches since the last `--stale` run, and nothing ran one: cold,
    # it was every test (1,084 here). A green full run warms it, so `then test`'s fallback is the change's
    Host.mix_project(dir, :warm)
    File.mkdir_p!(Path.join(dir, "lib"))
    File.mkdir_p!(Path.join(dir, "test"))
    File.write!(Path.join(dir, "lib/a.ex"), "defmodule A do\n  def a, do: 1\nend\n")
    File.write!(Path.join(dir, "lib/b.ex"), "defmodule B do\n  def b, do: 2\nend\n")
    File.write!(Path.join(dir, "test/test_helper.exs"), "ExUnit.start()\n")

    File.write!(
      Path.join(dir, "test/a_test.exs"),
      "defmodule ATest do\n  use ExUnit.Case\n  test \"a\", do: assert(A.a() == 1)\nend\n"
    )

    File.write!(
      Path.join(dir, "test/b_test.exs"),
      "defmodule BTest do\n  use ExUnit.Case\n  test \"b\", do: assert(B.b() == 2)\nend\n"
    )

    assert %{ok: true, tests: 2} = Run.lean(Run.result(dir, "test", []))
    Process.sleep(1_100)
    File.write!(Path.join(dir, "lib/a.ex"), "defmodule A do\n  def a, do: 1 + 0\nend\n")
    assert %{ok: true, tests: 1} = Run.lean(Run.result(dir, "test", ["--stale"]))
  end

  @tag :tmp_dir
  test "a failing test the agent is writing carries no source and is not run again; an older one keeps both",
       %{tmp_dir: dir} do
    # Fable 2026-10-01: a failure's `source` was 44% of red replies, in a TDD loop the test written one
    # call before; and every expected red was run a second time for flakes. A test file changed since
    # HEAD is the agent's own: no source, no rerun. One unchanged keeps both
    Host.mix_project(dir, :tdd)
    File.mkdir_p!(Path.join(dir, "test"))
    File.write!(Path.join(dir, "test/test_helper.exs"), "ExUnit.start()\n")

    File.write!(
      Path.join(dir, "test/old_test.exs"),
      "defmodule OldTest do\n  use ExUnit.Case\n  test \"old\", do: assert(1 == 2)\nend\n"
    )

    git = &System.cmd("git", ["-C", dir | &1], stderr_to_stdout: true)
    git.(["init", "-q"])
    git.(["add", "."])
    git.(["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "x"])

    File.write!(
      Path.join(dir, "test/new_test.exs"),
      "defmodule NewTest do\n  use ExUnit.Case\n  test \"new\", do: assert(1 == 3)\nend\n"
    )

    # the new test alone: expected red, no source, and run once
    log = Run.result(dir, "test", ["test/new_test.exs"])
    assert [%{name: "new"} = new] = log.failures
    refute Map.has_key?(new, :source)
    refute File.exists?(log.log <> ".rerun.exunit")

    # the old one: its source, as a regression's
    assert %{failures: [%{name: "old", source: _}]} = Run.result(dir, "test", ["test/old_test.exs"])
  end
end
