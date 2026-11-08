defmodule Menard.RunTest do
  # The test verb's answer is the shit you care about (Andrew): counts, and per failure its name,
  # where, the assertion and its two sides — never a page of migration logs.
  use ExUnit.Case, async: true

  alias Menard.Run
  alias Menard.Test.Host

  # Most of this module's tests run a real `check` (compile+format+test) in a tmp mix project —
  # genuine subprocess work, not CPU-bound test logic. Timed at 15.1s alone, same as bin_test.exs's
  # documented "28s cold at load average 17, past ExUnit's 60s default" (1ff3ab2): under this box's
  # concurrent-session load, 60s isn't enough headroom and times out mid-`os.find_executable`.
  @moduletag timeout: 150_000
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

  @pinned "1.19.4-otp-27"
  @tag skip:
         !(System.find_executable("mise") &&
             File.dir?(Path.expand("~/.local/share/mise/installs/elixir/#{@pinned}")) &&
             System.version() != "1.19.4") &&
           "needs mise with elixir #{@pinned} installed, menard on another elixir"

  describe "a repo with no mix.exs" do
    # outside menard's own repo: mise walks up, and menard has a `check` task of its own
    setup do
      dir = Path.join(System.tmp_dir!(), "menard-task-#{System.pid()}-#{System.unique_integer([:positive])}")
      File.mkdir_p!(Path.join(dir, ".mise/tasks"))
      File.write!(Path.join(dir, "a.nix"), "{ a = 1; }\n")
      on_exit(fn -> File.rm_rf!(dir) end)
      %{dir: dir}
    end

    defp mise_task(dir, name, body) do
      path = Path.join(dir, ".mise/tasks/#{name}")
      File.write!(path, "#!/bin/sh\n#{body}\n")
      File.chmod!(path, 0o755)
    end

    test "check runs its mise task, and red is its tail", %{dir: dir} do
      mise_task(dir, "check", "echo gate-said-no; exit 3")

      assert %{ok: false, exit: 3, ran: "mise run check", failures: [], tail: tail} =
               Menard.Run.result(dir, "check", [])

      assert tail =~ "gate-said-no"
    end

    test "no such task is said in menard's words, not mix's", %{dir: dir} do
      assert %{ok: false, failures: [], tail: tail} = Menard.Run.result(dir, "compile", [])
      assert tail =~ "no mix.exs in #{dir}, and no mise task compile"
      refute tail =~ "Mix.Project"
    end

    test "a config mise will not read is mise's answer, not a missing task", %{dir: dir} do
      # tasks alone need no trust; an env does
      File.write!(Path.join(dir, "mise.toml"), "[env]\nA = \"1\"\n\n[tasks.check]\nrun = \"true\"\n")

      assert %{ok: false, failures: [], tail: tail} = Menard.Run.result(dir, "check", [])
      assert tail =~ "not trusted"
      refute tail =~ "no mise task"
    end

    test "edit's then runs the task, and hands it no mix test flags", %{dir: dir} do
      mise_task(dir, "test", ~s(echo "ran with [$*]"))

      assert {:ok, %{run: %{ok: true, ran: "mise run test", tail: tail}}} =
               Menard.Verbs.call(Menard.Verbs.Edit, %{
                 root: dir,
                 then: "test",
                 edits: [%{file: "a.nix", old: "a = 1", new: "a = 2"}]
               })

      assert tail =~ "ran with []"
    end
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

  @tag :tmp_dir
  test "a dependency's warnings are not the project's failures", %{tmp_dir: dir} do
    # tlon's deps (styler, doctest_formatter) warn under Elixir 1.20; 33 green `run test` replies in
    # three weeks carried them as the project's `failures`, with `ok: true` over a non-empty list
    File.mkdir_p!(Path.join(dir, "lib/shop"))
    File.write!(Path.join(dir, "lib/shop/cart.ex"), "defmodule Shop.Cart do\nend\n")

    out = """
    ==> doctest_formatter
    Compiling 3 files (.ex)
        warning: the following conditional expression:
        │
     44 │       if x, do: 1
        │
        └─ lib/doctest_formatter/parser.ex:44:7

    ==> shop
    Compiling 1 file (.ex)
        warning: unused alias Money
        │
      5 │   alias Shop.Money
        │   ~
        │
        └─ lib/shop/cart.ex:5:3

    Running ExUnit with seed: 1, max_cases: 8

    ....
    Finished in 0.1 seconds (0.1s async, 0.0s sync)
    4 tests, 0 failures
    """

    r = Run.parse_test(out, 0, nil, dir)
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

  test "run test FILE:LINE names the test the line ran, green as red", %{tmp_dir: dir} do
    # ExUnit's line rule runs the closest test at or before the line: a line that has drifted runs
    # another test, and a green of counts alone says nothing of which
    Host.mix_project(dir, :ranline)
    File.mkdir_p!(Path.join(dir, "test"))
    File.write!(Path.join(dir, "test/test_helper.exs"), "ExUnit.start()\n")

    File.write!(Path.join(dir, "test/l_test.exs"), """
    defmodule LTest do
      use ExUnit.Case

      test "first" do
        assert true
      end

      test "second" do
        assert true
      end
    end
    """)

    assert %{ok: true, tests: 1, ran: [%{name: "first", at: "test/l_test.exs:4"}]} =
             Run.lean(Run.result(dir, "test", ["test/l_test.exs:7"]))

    assert %{ok: true, tests: 2} = reply = Run.lean(Run.result(dir, "test", ["test/l_test.exs"]))
    refute Map.has_key?(reply, :ran)
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
             failed: 0,
             ran: [%{name: "one", at: "test/two_test.exs:4"}]
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
  test "run test --slowest-modules N answers with the N test files that took longest, their tests counted", %{
    tmp_dir: dir
  } do
    # what a suite's time goes to, by file: 1,080 tests' times were no way to read it
    Host.mix_project(dir, :modules)
    File.mkdir_p!(Path.join(dir, "test"))
    File.write!(Path.join(dir, "test/test_helper.exs"), "ExUnit.start()\n")

    File.write!(
      Path.join(dir, "test/slow_test.exs"),
      "defmodule SlowTest do\n  use ExUnit.Case\n  test \"a\", do: Process.sleep(60)\n  test \"b\", do: Process.sleep(60)\nend\n"
    )

    File.write!(
      Path.join(dir, "test/quick_test.exs"),
      "defmodule QuickTest do\n  use ExUnit.Case\n  test \"c\", do: :ok\nend\n"
    )

    assert %{slowest_modules: [%{file: "test/slow_test.exs", tests: 2, ms: ms}]} =
             Run.lean(Run.result(dir, "test", ["--slowest-modules", "1"]))

    assert ms >= 120
  end

  @tag :tmp_dir
end
