defmodule Menard.RunTest do
  # The test verb's answer is the shit you care about (Andrew): counts, and per failure its name,
  # where, the assertion and its two sides — never a page of migration logs.
  use ExUnit.Case, async: true

  alias Menard.Run

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
    assert r.tests == 5 and r.failed == 2 and r.ok == false

    assert [
             %{
               name: "move/2 refuses another workspace",
               module: "Server.ChannelsTest",
               at: "test/server/channels_test.exs:40",
               code: "assert moved.channel_id == infra.id",
               left: "3",
               right: "4"
             },
             %{
               name: "deleting rehomes",
               at: "test/server/channels_test.exs:50",
               error: "(Exqlite.Error) FOREIGN KEY constraint failed\nDELETE FROM \"workspace\" AS w0"
             }
           ] = Enum.map(r.failures, &Map.take(&1, [:name, :module, :at, :code, :left, :right, :error]))

    # the tail is the summary, not the logs
    assert r.tail == "Finished in 0.5 seconds (0.1s async, 0.4s sync)\nResult: 3/5 passed\nFailed: 2 tests"
  end

  # The test's own source, so the reader sees the assertion in context without opening the file.
  test "with_sources/2 attaches each failing test's body, read from the file under the root" do
    tmp = Path.join(System.tmp_dir!(), "menard-run-#{System.unique_integer([:positive])}")
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

    File.rm_rf!(tmp)
  end

  test "a green run has no failures and a one-line tail" do
    r = Run.parse_test("....\n\nFinished in 0.1 seconds (0.1s async, 0.0s sync)\nResult: 4 passed\n", 0)
    assert r.ok and r.tests == 4 and r.failed == 0 and r.failures == []
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
  end

  @tag :tmp_dir
  test "compile reports a warning left by an earlier compile", %{tmp_dir: dir} do
    File.write!(Path.join(dir, "mix.exs"), """
    defmodule Warm.MixProject do
      use Mix.Project
      def project, do: [app: :warm, version: "0.1.0"]
    end
    """)

    File.mkdir_p!(Path.join(dir, "lib"))
    File.write!(Path.join(dir, "lib/warm.ex"), "defmodule Warm do\n  def go(x), do: 1\nend\n")
    System.cmd("mix", ["compile"], cd: dir, stderr_to_stdout: true, env: [{"MIX_ENV", nil}])

    result = Menard.Run.result(dir, "compile", [])
    refute result.ok
    assert [%{severity: "warning", file: "lib/warm.ex", line: 2}] = result.diagnostics
  end

  @tag :tmp_dir
  test "the host's mix runs on the host's toolchain, not menard's", %{tmp_dir: dir} do
    pinned = "1.20.4-otp-29"
    installed = Path.expand("~/.local/share/mise/installs/elixir/#{pinned}")

    if System.find_executable("mise") && File.dir?(installed) && System.version() != "1.20.4" do
      File.write!(Path.join(dir, "mise.toml"), "[tools]\nelixir = \"#{pinned}\"\nerlang = \"29\"\n")

      File.write!(Path.join(dir, "mix.exs"), """
      defmodule Pin.MixProject do
        use Mix.Project
        def project, do: [app: :pin, version: "0.1.0", aliases: [precommit: ["run --no-start -e \\"IO.puts(System.version())\\""]]]
      end
      """)

      System.cmd("mise", ["trust", Path.join(dir, "mise.toml")], stderr_to_stdout: true)
      assert Menard.Run.result(dir, "check", []).tail =~ "1.20.4"
    end
  end

  @tag :tmp_dir
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

  @tag :tmp_dir
  test "hunts a flake: repeats until it fails, and answers with that run, its seed and the run count", %{
    tmp_dir: dir
  } do
    File.write!(Path.join(dir, "mix.exs"), """
    defmodule Flaky.MixProject do
      use Mix.Project
      def project, do: [app: :flaky, version: "0.1.0"]
    end
    """)

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

    assert [%{error: error}] = Run.parse_test(out, 2).failures
    assert error =~ "(MatchError) no match of right hand side value:"
    assert error =~ "{:error, :enoent}"
    refute error =~ "code:"
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

  test "check with no precommit alias runs format, warnings-as-errors and tests itself", %{tmp_dir: dir} do
    # `run check` is format + warnings-as-errors + tests; a host with no precommit alias still gets them
    # `run check` is format + warnings-as-errors + tests; a host with no precommit alias still gets them
    File.write!(Path.join(dir, "mix.exs"), """
    defmodule Plain.MixProject do
      use Mix.Project
      def project, do: [app: :plain, version: "0.1.0"]
    end
    """)

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
end
