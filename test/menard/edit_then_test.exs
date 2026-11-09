defmodule Menard.EditThenTest do
  # `edit --then`: a run verb after the edits, in the project of the files it wrote. Apart from
  # the other edit tests: each runs the host's mix, and they run beside each other here.
  use ExUnit.Case, async: true

  import Menard.Test.Edits

  alias Menard.Test.Host
  alias Menard.Verbs

  @moduletag :tmp_dir

  setup %{tmp_dir: dir} do
    Host.mix_project(dir, :edits)
    File.mkdir_p!(Path.join(dir, "lib"))
    File.write!(Path.join(dir, ".formatter.exs"), "[inputs: [\"lib/**/*.ex\"]]")
    File.write!(Path.join(dir, "lib/a.ex"), "defmodule A do\n  def one, do: 1\n  def two, do: 2\nend\n")
    File.write!(Path.join(dir, "lib/b.ex"), "defmodule B do\n  def go, do: A.one()\nend\n")
    File.write!(Path.join(dir, "notes.md"), "one\n")
    :ok
  end

  test "then: a run verb after the edits, its answer in the reply", %{tmp_dir: dir} do
    assert {:ok, %{run: %{ok: true}} = reply} =
             edit(dir, [%{file: "lib/a.ex", old: "def two, do: 2", new: "def two, do: 22"}], %{
               then: "compile"
             })

    assert reply.did == "edit a.ex: 1 replacement, then run compile"

    # red is an answer: the edits stand, and the reply says what the compiler said of them
    assert {:ok, %{run: %{ok: false, failures: [%{message: message} | _]}}} =
             edit(dir, [%{file: "lib/b.ex", old: "A.one()", new: "A.nope()"}], %{then: "compile"})

    assert message =~ "A.nope/0"
    assert read(dir, "lib/b.ex") =~ "A.nope()"
  end

  test "then: test, for a file with no test of its own, runs the tests that name its module", %{
    tmp_dir: dir
  } do
    File.mkdir_p!(Path.join(dir, "test"))
    File.write!(Path.join(dir, "test/test_helper.exs"), "ExUnit.start()\n")
    File.write!(Path.join(dir, "lib/c.ex"), "defmodule C do\n  def three, do: 3\nend\n")
    File.write!(Path.join(dir, "lib/d.ex"), "defmodule D do\n  def four, do: 4\nend\n")

    File.write!(
      Path.join(dir, "test/uses_c_test.exs"),
      "defmodule UsesCTest do\n  use ExUnit.Case\n  test \"c\", do: assert(C.three() == 33)\nend\n"
    )

    File.write!(
      Path.join(dir, "test/elsewhere_test.exs"),
      "defmodule ElsewhereTest do\n  use ExUnit.Case\n  test \"elsewhere\", do: assert(false)\nend\n"
    )

    assert {:ok, %{run: %{ok: true, tests: 1}}} =
             edit(dir, [%{file: "lib/c.ex", old: "do: 3", new: "do: 33"}], %{then: "test"})

    # nothing names D: no run of the suite in its place, and the reply says so
    assert {:ok, %{run: %{skipped: why} = run}} =
             edit(dir, [%{file: "lib/d.ex", old: "do: 4", new: "do: 44"}], %{then: "test"})

    refute Map.has_key?(run, :tests)
    assert why =~ "D"
  end

  test "then: test, beside a file that is not Elixir, runs the tests of the Elixir one", %{tmp_dir: dir} do
    File.mkdir_p!(Path.join(dir, "test"))
    File.write!(Path.join(dir, "test/test_helper.exs"), "ExUnit.start()\n")
    File.write!(Path.join(dir, "hooks.json"), "{\n  \"a\": \"${x}\"\n}\n")
    File.write!(Path.join(dir, "lib/c.ex"), "defmodule C do\n  def three, do: 3\nend\n")

    File.write!(
      Path.join(dir, "test/uses_c_test.exs"),
      "defmodule UsesCTest do\n  use ExUnit.Case\n  test \"c\", do: assert(C.three() == 33)\nend\n"
    )

    assert {:ok, %{run: %{ok: true, tests: 1}}} =
             edit(
               dir,
               [
                 %{file: "hooks.json", old: "${x}", new: "${y}"},
                 %{file: "lib/c.ex", old: "do: 3", new: "do: 33"}
               ],
               %{then: "test"}
             )
  end

  test "then: test runs the tests of what the edit changed, not the whole suite", %{tmp_dir: dir} do
    File.mkdir_p!(Path.join(dir, "test"))
    File.write!(Path.join(dir, "test/test_helper.exs"), "ExUnit.start()\n")

    File.write!(
      Path.join(dir, "test/a_test.exs"),
      "defmodule ATest do\n  use ExUnit.Case\n  test \"two\", do: assert(A.two() == 22)\nend\n"
    )

    File.write!(
      Path.join(dir, "test/b_test.exs"),
      "defmodule BTest do\n  use ExUnit.Case\n  test \"elsewhere\", do: assert(false)\nend\n"
    )

    assert {:ok, %{run: %{ok: true, tests: 1}}} =
             edit(dir, [%{file: "lib/a.ex", old: "def two, do: 2", new: "def two, do: 22"}], %{
               then: "test"
             })

    # an edited test file is its own test
    assert {:ok, %{run: %{ok: false, tests: 1}}} =
             edit(dir, [%{file: "test/b_test.exs", old: "elsewhere", new: "still elsewhere"}], %{
               then: "test"
             })
  end

  @tag :tmp_dir
  test "every writing verb takes then, as edit does", %{tmp_dir: dir} do
    # every writing verb takes `then`, as edit does: a test added with block add was run by a second call
    File.mkdir_p!(Path.join(dir, "test"))
    File.write!(Path.join(dir, "test/test_helper.exs"), "ExUnit.start()\n")

    File.write!(
      Path.join(dir, "test/a_test.exs"),
      "defmodule ATest do\n  use ExUnit.Case\n\n  test \"one\", do: assert(A.one() == 1)\nend\n"
    )

    assert {:ok, %{run: run} = reply} =
             Verbs.call(Verbs.Block, %{
               root: dir,
               verb: "add",
               file: Path.join(dir, "test/a_test.exs"),
               name: "test",
               label: "two",
               code: "assert A.two() == 2",
               then: "test"
             })

    assert reply.did =~ "then run test"
    assert %{ok: true, tests: 2} = run

    assert {:error, why} =
             Verbs.call(Verbs.Block, %{verb: "list", file: Path.join(dir, "test/a_test.exs"), then: "lint"})

    assert why =~ "no then"
  end

  @tag :tmp_dir
  test "then runs in the mix project of the files it wrote, nested under the root or not", %{tmp_dir: dir} do
    # `then` run in the root and mapping lib/ to test/ from it would, in a repo whose mix project is
    # server/, find no test and run --stale where there is no mix.exs
    server = Path.join(dir, "server")
    File.mkdir_p!(server)
    Host.mix_project(server, :nested)
    File.mkdir_p!(Path.join(server, "lib"))
    File.mkdir_p!(Path.join(server, "test"))
    File.write!(Path.join(server, "lib/n.ex"), "defmodule N do\n  def go, do: 1\nend\n")
    File.write!(Path.join(server, "test/test_helper.exs"), "ExUnit.start()\n")

    File.write!(
      Path.join(server, "test/n_test.exs"),
      "defmodule NTest do\n  use ExUnit.Case\n  test \"go\", do: assert(N.go() == 2)\nend\n"
    )

    assert {:ok, %{run: run}} =
             edit(dir, [%{file: "server/lib/n.ex", old: "def go, do: 1", new: "def go, do: 2"}], %{
               then: "test"
             })

    assert %{ok: true, tests: 1, dir: "server"} = run
  end

  @tag :tmp_dir
  test "then takes the test files to run, where the change's are not its files' mirror", %{tmp_dir: dir} do
    # a change whose tests are not the mirror of its files (a formatter in priv/, its tests in
    # run_test.exs) named them, and ran them by a second call: `then` takes the files
    File.mkdir_p!(Path.join(dir, "test"))
    File.write!(Path.join(dir, "test/test_helper.exs"), "ExUnit.start()\n")

    File.write!(
      Path.join(dir, "test/a_test.exs"),
      "defmodule ATest do\n  use ExUnit.Case\n  test \"a\", do: :ok\nend\n"
    )

    File.write!(
      Path.join(dir, "test/b_test.exs"),
      "defmodule BTest do\n  use ExUnit.Case\n  test \"b\", do: assert(A.two() == 22)\nend\n"
    )

    assert {:ok, %{run: %{ok: true, tests: 1}}} =
             edit(dir, [%{file: "lib/a.ex", old: "def two, do: 2", new: "def two, do: 22"}], %{
               then: "test test/b_test.exs"
             })

    assert {:error, why} =
             edit(dir, [%{file: "lib/a.ex", old: "def two, do: 22", new: "def two, do: 2"}], %{
               then: "check lib"
             })

    assert why =~ "only test takes files"

    assert {:error, _} =
             edit(dir, [%{file: "lib/a.ex", old: "def two, do: 22", new: "def two, do: 2"}], %{then: "lint"})
  end
end
