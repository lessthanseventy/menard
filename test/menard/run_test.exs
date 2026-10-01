defmodule Menard.RunTest do
  # The test verb's answer is the shit you care about (Andrew): counts, and per failure its name,
  # where, the assertion and its two sides — never a page of migration logs.
  use ExUnit.Case, async: true

  alias Menard.Run
  alias Menard.Test.Host

  @moduletag :tmp_dir

  @out """
  18:53:59.922 [debug] QUERY OK source="event" db=0.2ms idle=0.0ms
  DELETE FROM "event" AS e0 []
  Running ExUnit with seed: 1, max_cases: 40

  ..

    1) test move/2 refuses another workspace (Server.ChannelsTest)
       test/server/channels_test.exs:40
       Assertion with == failed
       code:  assert moved.channel_id == infra.id
       left:  3
       right: 4
       stacktrace:
         test/server/channels_test.exs:44: (test)

    2) test deleting rehomes (Server.ChannelsTest)
       test/server/channels_test.exs:50
       ** (Exqlite.Error) FOREIGN KEY constraint failed
       DELETE FROM "workspace" AS w0
       stacktrace:
         (ecto_sql 3.14.0) lib/ecto/adapters/sql.ex:1121: Ecto.Adapters.SQL.raise_sql_call_error/1

  Finished in 0.5 seconds (0.1s async, 0.4s sync)
  Result: 3/5 passed
  Failed: 2 tests
  """

  test "parses counts and each failure's name, location, assertion and error" do
    r = Run.parse_test(@out, 2)
    assert %{tests: 5, failed: 2, ok: false} = r

    # an assertion and an exception, one shape: kind, message, at — then what only a test has
    assert [
             %{
               kind: "test",
               message: "Assertion with == failed",
               at: "test/server/channels_test.exs:40",
               name: "move/2 refuses another workspace",
               module: "Server.ChannelsTest",
               code: "assert moved.channel_id == infra.id",
               left: "3",
               right: "4"
             },
             %{
               kind: "test",
               message: "(Exqlite.Error) FOREIGN KEY constraint failed\nDELETE FROM \"workspace\" AS w0",
               at: "test/server/channels_test.exs:50",
               name: "deleting rehomes"
             }
           ] = r.failures

    # the tail is the summary, not the logs
    assert r.tail == "Finished in 0.5 seconds (0.1s async, 0.4s sync)\nResult: 3/5 passed\nFailed: 2 tests"
  end

  # The test's own source, so the reader sees the assertion in context without opening the file.
  test "with_sources/2 attaches each failing test's body, read from the file under the root", %{tmp_dir: tmp} do
    File.mkdir_p!(Path.join(tmp, "test/server"))

    # the failure says line 40: pad so the test's `test` line IS line 40
    File.write!(
      Path.join(tmp, "test/server/channels_test.exs"),
      String.duplicate("\n", 38) <>
        "defmodule X do\n  test \"move/2 refuses another workspace\" do\n    assert moved.channel_id == infra.id\n  end\nend\n"
    )

    r = @out |> Run.parse_test(2) |> Run.with_sources(tmp)
    [first | _] = r.failures

    assert first.source ==
             "  test \"move/2 refuses another workspace\" do\n    assert moved.channel_id == infra.id\n  end"
  end

  test "a green run has no failures and a one-line tail" do
    r = Run.parse_test("....\n\nFinished in 0.1 seconds (0.1s async, 0.0s sync)\nResult: 4 passed\n", 0)
    assert %{ok: true, tests: 4, failed: 0, failures: []} = r
    assert r.tail == "Finished in 0.1 seconds (0.1s async, 0.0s sync)\nResult: 4 passed"
  end

  test "a test file that does not compile: the tail is the compiler's errors, not the stack trace" do
    out = """
    Compiling 1 file (.ex)
        error: undefined function thread/1 (expected Console.Panel.RailTest to define such a function)
        │
     79 │       rows = rows(thread(%{title: "build"}))
        │                   ^
        │
        └─ test/console/panel/rail_test.exs:79:19: Console.Panel.RailTest."test x"/1


    == Compilation error in file test/console/panel/rail_test.exs ==
    ** (CompileError) test/console/panel/rail_test.exs: cannot compile module Console.Panel.RailTest (errors have been logged)
        (elixir 1.20.4) lib/kernel/parallel_compiler.ex:667: Kernel.ParallelCompiler.require_file/2
        (elixir 1.20.4) lib/kernel/parallel_compiler.ex:550: anonymous fn/5 in Kernel.ParallelCompiler.spawn_workers/8
    """

    r = Run.parse_test(out, 1)
    refute r.ok
    assert r.tail =~ "error: undefined function thread/1"
    assert r.tail =~ "rail_test.exs:79:19"
    refute r.tail =~ "parallel_compiler"

    # and the error is a failure, the same shape as any other
    assert [
             %{
               kind: "error",
               at: "test/console/panel/rail_test.exs:79",
               message: "undefined function thread/1" <> _
             }
           ] =
             r.failures
  end

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

  @pinned "1.20.4-otp-29"
  @tag skip:
         !(System.find_executable("mise") &&
             File.dir?(Path.expand("~/.local/share/mise/installs/elixir/#{@pinned}")) &&
             System.version() != "1.20.4") &&
           "needs mise with elixir #{@pinned} installed, menard on another elixir"
  test "the host's mix runs on the host's toolchain, not menard's", %{tmp_dir: dir} do
    File.write!(Path.join(dir, "mise.toml"), "[tools]\nelixir = \"#{@pinned}\"\nerlang = \"29\"\n")

    File.write!(Path.join(dir, "mix.exs"), """
    defmodule Pin.MixProject do
      use Mix.Project
      def project, do: [app: :pin, version: "0.1.0", aliases: [precommit: ["run --no-start -e \\"IO.puts(System.version())\\""]]]
    end
    """)

    System.cmd("mise", ["trust", Path.join(dir, "mise.toml")], stderr_to_stdout: true)
    assert Menard.Run.result(dir, "check", []).tail =~ "1.20.4"
  end

  test "format works on a host whose mix.exs does not parse, and says what changed", %{tmp_dir: dir} do
    File.write!(Path.join(dir, "mix.exs"), "defmodule Broken do\n  this does not parse (\n")
    File.write!(Path.join(dir, ".formatter.exs"), "[inputs: [\"*.ex\"]]")
    messy = Path.join(dir, "messy.ex")
    clean = Path.join(dir, "clean.ex")
    File.write!(messy, "defmodule M do\n  def   go, do: 1\nend\n")
    File.write!(clean, "defmodule C do\nend\n")

    assert %{ok: true, changed: [^messy]} = Menard.Run.result(dir, "format", ["messy.ex", "clean.ex"])
    assert File.read!(messy) =~ "def go, do: 1"
  end

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

  test "a MatchError keeps the value it could not match" do
    # a MatchError's value is on the lines after its `**` line, and it is the whole point of the error
    out = """
    Running ExUnit with seed: 1, max_cases: 40

      1) test reads the config (App.ConfigTest)
         test/app/config_test.exs:7
         ** (MatchError) no match of right hand side value:

             {:error, :enoent}

         code: {:ok, config} = App.Config.read()
         stacktrace:
           test/app/config_test.exs:8: (test)

    Finished in 0.01 seconds
    1 test, 1 failure
    """

    assert [%{message: message}] = Run.parse_test(out, 2).failures
    assert message =~ "(MatchError) no match of right hand side value:"
    assert message =~ "{:error, :enoent}"
    refute message =~ "code:"
  end

  test "format with no files formats the project's formatter inputs", %{tmp_dir: dir} do
    # with no files named, what the project's own `mix format` would format: its inputs
    File.write!(Path.join(dir, "mix.exs"), "defmodule Broken do\n  this does not parse (\n")
    File.write!(Path.join(dir, ".formatter.exs"), "[inputs: [\"lib/**/*.ex\"]]")
    File.mkdir_p!(Path.join(dir, "lib/deep"))
    messy = Path.join(dir, "lib/deep/messy.ex")
    File.write!(messy, "defmodule M do\n  def   go, do: 1\nend\n")

    assert %{ok: true, changed: [^messy]} = Menard.Run.result(dir, "format", [])
  end

  test "format with no files formats a subdirectory's inputs too (Phoenix's migrations)", %{tmp_dir: dir} do
    # `subdirectories:` was ignored: `run format` skipped the migrations, and `run check` failed on them
    File.write!(
      Path.join(dir, ".formatter.exs"),
      ~s|[inputs: ["lib/**/*.ex"], subdirectories: ["priv/*/migrations"]]|
    )

    migrations = Path.join(dir, "priv/repo/migrations")
    File.mkdir_p!(migrations)
    File.write!(Path.join(migrations, ".formatter.exs"), ~s|[inputs: ["*.exs"]]\n|)
    messy = Path.join(migrations, "20260101_add.exs")
    File.write!(messy, "defmodule M do\n  def   change, do: 1\nend\n")

    assert %{ok: true, changed: [^messy]} = Menard.Run.result(dir, "format", [])
  end

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
    assert result.tail =~ "1 test, 0 failures"
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

  test "lean keeps what a reader looks for: ok and the counts when green, the failures and seed when red" do
    green =
      Run.parse_test(
        "Running ExUnit with seed: 7, max_cases: 4\n\n..\nFinished in 0.1 seconds\n2 tests, 0 failures\n",
        0
      )

    assert Run.lean(Map.put(green, :fetched, [])) == %{ok: true, tests: 2, failed: 0, failures: []}

    red = Run.parse_test(@out, 2)
    lean = Run.lean(red)
    assert %{ok: false, exit: 2, tests: 5, failed: 2, seed: 1, failures: [_, _]} = lean
    # the failures say what broke; the tail and a single run's count say nothing more
    refute Map.has_key?(lean, :tail) or Map.has_key?(lean, :runs)

    # a flake hunt keeps how many runs passed before the failure
    assert %{runs: 3} = Run.lean(%{red | runs: 3})

    # check has no counts: its tail is the summary, green or not
    assert %{ok: true, tail: "619 tests, 0 failures", failures: []} =
             Run.lean(%{ok: true, exit: 0, failures: [], tail: "619 tests, 0 failures", fetched: []})

    # red with nothing parsed: the tail is all there is
    assert %{tail: "boom"} = Run.lean(%{ok: false, exit: 1, failures: [], tail: "boom", fetched: []})
  end

  test "a green compile is ok and nothing else" do
    assert Run.lean(%{ok: true, exit: 0, failures: [], tail: "", fetched: []}) == %{ok: true, failures: []}
  end

  test "at is relative to the project, whichever way mix printed it", %{tmp_dir: dir} do
    # run under a precommit alias, ExUnit printed absolute paths; `run test` printed relative ones
    result = %{
      failures: [
        %{kind: "test", at: Path.join(dir, "test/a_test.exs") <> ":4"},
        %{kind: "warning", at: Path.join(dir, "lib/a.ex") <> ":2"},
        %{kind: "format", at: "lib/b.ex"}
      ]
    }

    assert ["test/a_test.exs:4", "lib/a.ex:2", "lib/b.ex"] =
             Enum.map(Run.with_sources(result, dir).failures, & &1.at)
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

    # the bound is loose on purpose: the test itself never ends, so any answer is the kill, and the
    # room past 10s is a loaded host's teardown, not slack in the deadline
    started = System.monotonic_time(:millisecond)
    result = Menard.Run.result(dir, "test", ["--seed", "0"], timeout: 10_000)
    assert System.monotonic_time(:millisecond) - started < 40_000

    refute result.ok
    assert result.tail =~ "did not finish in 10s"
    # up2 Oban: a run stopped at its deadline answered nothing of what it had. The failures so far,
    # and the test that was still running
    assert %{name: "fails first"} = Enum.find(result.failures, &(&1.kind == "test"))
    assert %{name: "slow", at: "test/slow_test.exs:5"} = Enum.find(result.failures, &(&1.kind == "timeout"))

    # `timeout` returns once its child is gone, so the VM is dead by now, not dying
    assert {_, status} = System.cmd("kill", ["-0", File.read!(pidfile)], stderr_to_stdout: true)
    assert status != 0
  end

  test "a green run still answers with the warnings its compile printed" do
    # the eval's agent finished on `run test`, ok with no failures, over an unused alias the
    # project's warnings-as-errors gate then failed on
    out = """
    Compiling 1 file (.ex)
        warning: unused alias Money
        │
      5 │   alias Shop.Money
        │   ~
        │
        └─ lib/shop/cart.ex:5:3

    Generated shop app
    Running ExUnit with seed: 1, max_cases: 8

    ....
    Finished in 0.1 seconds (0.1s async, 0.0s sync)
    4 tests, 0 failures
    """

    r = Run.parse_test(out, 0)
    assert r.ok
    assert r.failures == [%{kind: "warning", message: "unused alias Money", at: "lib/shop/cart.ex:5"}]
  end

  test "mix refusing its arguments answers with why, not the tail of its usage" do
    # the eval's agent passed `--doctest` and got back the last lines of the option list
    options = Enum.map_join(1..30, "\n", &"  --option-#{&1}, --no-option-#{&1}")

    out =
      "** (Mix) Could not invoke task \"test\": 1 error found!\n--doctest : Unknown option\n\nSupported options:\n#{options}\n"

    r = Run.parse_test(out, 1)
    refute r.ok
    assert [%{kind: "error", message: message}] = r.failures
    assert message =~ "--doctest : Unknown option"
    refute message =~ "option-30"
  end

  test "a compile error raised as an exception is a failure with its file and line" do
    # long1 cart-refactor.B.haiku got failures: [] and a raw tail for this, and never found the line
    out = """
    Compiling 9 files (.ex)

    == Compilation error in file lib/shop/cart.ex ==
    ** (ArgumentError) cannot set attribute @doc inside function/macro
        (elixir 1.19.4) lib/kernel.ex:3769: Kernel.do_at/5
        (elixir 1.19.4) expanding macro: Kernel.@/1
        lib/shop/cart.ex:285: Shop.Cart.discount/1
    """

    assert [%{kind: "error", at: "lib/shop/cart.ex:285", message: message}] = Run.parse_test(out, 1).failures
    assert message =~ "cannot set attribute @doc inside function/macro"
  end

  @kinds File.read!(Path.expand("../fixtures/ex_unit/kinds.txt", __DIR__))

  test "a failing doctest, a property and a setup_all are failures too, and count" do
    # real `mix test` output (Elixir 1.19): only `N) test …` parsed, so these came back ok: false,
    # failures: [] and the hooks had nothing to act on
    r = Run.parse_test(@kinds, 2)

    assert [
             %{kind: "test", name: "ints are small", module: "BenchTest", at: "test/bench_test.exs:10"} =
               property,
             %{kind: "test", name: "plain", code: "assert 1 + 1 == 3", left: "2", right: "3"},
             %{kind: "test", name: "Bench.one/0 (1)", at: "test/bench_test.exs:4", code: "Bench.one() === 2"},
             %{kind: "test", name: "setup_all", module: "SetupAllTest", message: setup_all}
           ] = r.failures

    assert property.message =~ "Generated: 5"
    assert setup_all =~ "(File.Error) could not read file"
    # 1 doctest, 1 property, 2 tests: 3 failures and 1 invalid
    assert {r.tests, r.failed} == {4, 4}
    # and a run that left tests out says so after the counts
    assert %{tests: 1, failed: 0} =
             Run.parse_test("Finished in 0.9 seconds\n1 test, 0 failures (22 excluded)\n", 0)
  end

  test "a host that colours its output through a pipe still has its failures read", %{tmp_dir: dir} do
    # `config :elixir, :ansi_enabled, true` colours ExUnit's report even into menard's pipe, and every
    # pattern missed the `code:`, `left:` and the location between the escapes
    Host.mix_project(dir, :colour)

    File.mkdir_p!(Path.join(dir, "config"))
    File.write!(Path.join(dir, "config/config.exs"), "import Config\nconfig :elixir, :ansi_enabled, true\n")
    File.mkdir_p!(Path.join(dir, "test"))
    File.write!(Path.join(dir, "test/test_helper.exs"), "ExUnit.start()\n")

    File.write!(
      Path.join(dir, "test/colour_test.exs"),
      "defmodule ColourTest do\n  use ExUnit.Case\n\n  test \"red\" do\n    assert 1 + 1 == 3\n  end\nend\n"
    )

    r = Menard.Run.result(dir, "test", [])
    refute r.ok

    assert [
             %{
               kind: "test",
               name: "red",
               at: "test/colour_test.exs:4",
               code: "assert 1 + 1 == 3",
               left: "2",
               right: "3"
             }
           ] =
             r.failures

    assert {r.tests, r.failed} == {1, 1}
  end

  test "a verb called past the doors (deps' compile) leaves nothing behind in its caller", %{tmp_dir: dir} do
    # the deadline and the log lived in the process dictionary: a call that did not go through the
    # door that clears them left its log for the MCP server's next call to append to
    Host.mix_project(dir, :left)

    before = Process.get()
    assert %{ok: true, log: log} = Menard.Run.result(dir, "compile", [])
    assert File.read!(log) =~ "$ mix compile"
    assert Process.get() == before
  end

  test "run test reads each failure as ExUnit holds it, not as the prose it prints", %{tmp_dir: dir} do
    # read from the CLI's prose, a `left:` that did not fit one line came back as its first line, "%{"
    Host.mix_project(dir, :held)

    File.mkdir_p!(Path.join(dir, "lib"))

    File.write!(
      Path.join(dir, "lib/held.ex"),
      ~s|defmodule Held do\n  @doc """\n      iex> Held.one()\n      2\n  """\n  def one, do: 1\nend\n|
    )

    File.mkdir_p!(Path.join(dir, "test"))
    File.write!(Path.join(dir, "test/test_helper.exs"), "ExUnit.start()\n")

    File.write!(Path.join(dir, "test/held_test.exs"), """
    defmodule HeldTest do
      use ExUnit.Case
      doctest Held

      test "big" do
        assert Map.new(1..12, &{&1, String.duplicate("x", 12)}) == %{}
      end
    end

    defmodule HeldSetupTest do
      use ExUnit.Case

      setup_all do
        File.read!("/nonexistent/menard-held")
        :ok
      end

      test "never runs", do: :ok
    end

    defmodule HeldMatchTest do
      use ExUnit.Case

      test "shape" do
        assert {:ok, _} = Function.identity({:error, 1})
      end
    end
    """)

    r = Menard.Run.result(dir, "test", ["--seed", "0"])
    refute r.ok
    assert {r.tests, r.failed} == {4, 4}
    # a match's left is its pattern, as written
    assert %{left: "{:ok, _}", right: "{:error, 1}"} = Enum.find(r.failures, &(&1.name == "shape"))

    assert [
             %{
               name: "Held.one/0 (1)",
               module: "HeldTest",
               at: "test/held_test.exs:3",
               code: "Held.one() === 2"
             } =
               doctest,
             %{name: "big", at: "test/held_test.exs:5", left: left, right: "%{}"},
             %{name: "setup_all", module: "HeldSetupTest", at: "test/held_test.exs:14", message: setup_all}
           ] = r.failures |> Enum.reject(&(&1.name == "shape")) |> Enum.sort_by(& &1.name)

    # the whole value, every line of it
    assert left =~ ~s|12 => "xxxxxxxxxxxx"|
    assert setup_all =~ "(File.Error) could not read file"
    # a doctest's source is its `doctest` line, not every line down to the next `end`
    assert doctest.source == "  doctest Held"
  end

  test "run test says how many tests were skipped, not only how many ran", %{tmp_dir: dir} do
    # a `@tag skip:` test left the counts without a word: 5 tests, 3 skipped, answered as `tests: 2`
    Host.mix_project(dir, :skips)

    File.mkdir_p!(Path.join(dir, "test"))
    File.write!(Path.join(dir, "test/test_helper.exs"), "ExUnit.start()\n")

    File.write!(Path.join(dir, "test/skips_test.exs"), """
    defmodule SkipsTest do
      use ExUnit.Case

      test "runs", do: :ok

      @tag skip: "no toolchain"
      test "skips", do: :ok
    end
    """)

    assert Run.lean(Menard.Run.result(dir, "test", [])) == %{
             ok: true,
             failures: [],
             tests: 1,
             failed: 0,
             skipped: 1
           }
  end

  test "outside a git work tree there is no tree to stamp: nil, not a crash" do
    # off the repo: ExUnit's tmp_dir sits inside menard's own checkout
    dir = Path.join(System.tmp_dir!(), "menard-tree-#{System.pid()}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    assert Run.tree(dir) == nil
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

  test "ExUnit's prose says how many skipped, the way the formatter counts them" do
    # 1.19 counts a skipped test in `N tests`, 1.20 leaves it out of `passed`: `tests` is what ran
    # either way, as the formatter counts it. An excluded test is the project's own filter, not counted.
    old = Run.parse_test("Finished in 0.02 seconds\n3 tests, 1 failure, 1 skipped (1 excluded)\n", 2)

    new =
      Run.parse_test(
        "Finished in 0.01 seconds\n\nResult: 1/2 passed, 1 skipped, 1 excluded\nFailed: 1 test\n",
        2
      )

    assert {old.tests, old.failed, old.skipped} == {2, 1, 1}
    assert {new.tests, new.failed, new.skipped} == {2, 1, 1}
  end

  test "ExUnit's prose says how many were excluded, and none run is no green" do
    out =
      "Running ExUnit with seed: 1, max_cases: 8\n\n\nFinished in 0.1 seconds\n0 tests, 0 failures (150 excluded)\n\nAll tests have been excluded.\n"

    assert %{ok: false, tests: 0, excluded: 150, failures: [%{kind: "excluded"}]} = Run.parse_test(out, 0)

    out =
      "Running ExUnit with seed: 1, max_cases: 8\n\n.\nFinished in 0.1 seconds\n1 test, 0 failures (3 excluded)\n"

    assert %{ok: true, tests: 1, excluded: 3, failures: []} = Run.parse_test(out, 0)
  end

  test "a test file's compile errors printed after the seed line are its failures" do
    # 1.19 on prints the seed first, then loads the test files: their compile errors come after it
    out = """
    Running ExUnit with seed: 335079, max_cases: 40

        error: undefined variable "dir"
        │
     753 │     Host.mix_project(dir, :excludes)
        │                      ^^^
        │
        └─ test/menard/run_test.exs:753:22: Menard.RunTest."test x"/1


    == Compilation error in file test/menard/run_test.exs ==
    ** (CompileError) test/menard/run_test.exs: cannot compile module Menard.RunTest (errors have been logged)
    """

    assert [%{kind: "error", at: "test/menard/run_test.exs:753", message: ~s(undefined variable "dir")}] =
             Run.parse_test(out, 1).failures
  end

  test "a run that excludes every test it was given is red, and says which tags to include", %{tmp_dir: dir} do
    Host.mix_project(dir, :excludes)

    File.mkdir_p!(Path.join(dir, "test"))
    File.write!(Path.join(dir, "test/test_helper.exs"), "ExUnit.start(exclude: [:slow])\n")

    File.write!(Path.join(dir, "test/slow_test.exs"), """
    defmodule SlowTest do
      use ExUnit.Case
      @moduletag :slow

      test "one", do: :ok
      test "two", do: :ok
    end
    """)

    File.write!(Path.join(dir, "test/fast_test.exs"), """
    defmodule FastTest do
      use ExUnit.Case

      test "runs", do: :ok
      @tag :slow
      test "waits", do: :ok
    end
    """)

    assert %{ok: false, tests: 0, excluded: 2, failures: [%{kind: "excluded", message: message}]} =
             Run.lean(Run.result(dir, "test", ["test/slow_test.exs"]))

    assert message =~ "no test ran"
    assert message =~ "--include slow"

    assert Run.lean(Run.result(dir, "test", ["test/fast_test.exs"])) == %{
             ok: true,
             failures: [],
             tests: 1,
             failed: 0,
             excluded: 1
           }
  end

  test "run test --slowest N answers with the N slowest tests, not only the counts", %{tmp_dir: dir} do
    Host.mix_project(dir, :slowest)

    File.mkdir_p!(Path.join(dir, "test"))
    File.write!(Path.join(dir, "test/test_helper.exs"), "ExUnit.start()\n")

    File.write!(Path.join(dir, "test/slow_test.exs"), """
    defmodule SlowTest do
      use ExUnit.Case

      test "quick", do: :ok

      test "sleeps" do
        Process.sleep(60)
      end
    end
    """)

    assert %{ok: true, slowest: [%{name: "sleeps", at: "test/slow_test.exs:6", ms: ms}]} =
             Run.lean(Run.result(dir, "test", ["--slowest", "1"]))

    assert ms >= 60
  end

  @tag :tmp_dir
  test "a file:line run does not count the tests its own line left out as excluded", %{tmp_dir: dir} do
    Host.mix_project(dir, :lines)
    File.mkdir_p!(Path.join(dir, "test"))
    File.write!(Path.join(dir, "test/test_helper.exs"), "ExUnit.start()\n")

    File.write!(
      Path.join(dir, "test/two_test.exs"),
      "defmodule TwoTest do\n  use ExUnit.Case\n\n  test \"one\", do: :ok\n\n  test \"two\", do: :ok\nend\n"
    )

    assert Run.lean(Run.result(dir, "test", ["test/two_test.exs:4"])) == %{
             ok: true,
             failures: [],
             tests: 1,
             failed: 0
           }
  end

  test "past the first few failures, each is where and what: the log has the rest" do
    # Oban 01: 12 failures, each its test's source and an inspected %Oban.Config{}, came back as 13.9k
    # characters. The first few whole; past them, where and what, its message's first line: the rest is
    # the log's
    failure = fn n ->
      %{
        kind: "test",
        name: "t#{n}",
        at: "test/a_test.exs:#{n}",
        message: "boom #{n}\nmore",
        source: "test",
        right: "%{}"
      }
    end

    lean = Run.lean(%{ok: false, exit: 2, tests: 5, failed: 5, failures: Enum.map(1..5, failure), log: "/l"})

    assert [%{source: "test"}, %{source: "test"}, %{source: "test"}, fourth, fifth] = lean.failures
    assert fourth == %{kind: "test", name: "t4", at: "test/a_test.exs:4", message: "boom 4"}
    assert fifth.name == "t5"
    assert lean.log == "/l"
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
  test "check formats the project first, and names what it formatted", %{tmp_dir: dir} do
    # Oban 01: check failed on test/test_helper.exs, unformatted upstream, and the agent spent three
    # calls on it. Formatting is mechanical: check formats the project first, and names what it did
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
    # two sessions' gates in one checkout raced in its _build and tmp/ (2026-10-01): a check waits for
    # the one already running, and says so; a lock its holder left behind dead is no wait
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
  end

  @tag :tmp_dir
end
