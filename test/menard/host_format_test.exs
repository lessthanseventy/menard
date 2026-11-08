defmodule Menard.HostFormatTest do
  # menard formats with the HOST project's formatter, as an OS process on the host's own
  # toolchain, while that project is as broken as it gets: a mix.exs that does not parse, deps
  # never fetched, a config that wants an env var. Plugins come from its last build in _build;
  # import_deps from deps/, else from the copy the last good format cached.
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

  test "formats with the host's own options though its mix.exs is broken", %{tmp_dir: dir} do
    host(dir, "[inputs: [\"lib/**/*.ex\"], line_length: 30]")
    file = write(dir, "a.ex", "defmodule A do\n  def go, do: [:alpha, :beta, :gamma, :delta]\nend\n")

    assert Menard.format(file, cache: Path.join(dir, "cache")) == :ok
    assert File.read!(file) =~ "[\n      :alpha,\n"
  end

  test "a host whose config wants an env var it does not have is formatted all the same", %{tmp_dir: dir} do
    # live_beats: `mix format` loads the config first, and config/dev.exs fetched a GitHub secret
    # from the environment; the host's own formatter never got to run
    File.write!(Path.join(dir, "mix.exs"), """
    defmodule Env.MixProject do
      use Mix.Project
      def project, do: [app: :env, version: "0.1.0"]
    end
    """)

    File.mkdir_p!(Path.join(dir, "config"))

    File.write!(
      Path.join(dir, "config/config.exs"),
      "import Config\nSystem.fetch_env!(\"MENARD_NO_SUCH_VAR\")\n"
    )

    File.write!(Path.join(dir, ".formatter.exs"), "[inputs: [\"lib/**/*.ex\"]]")
    file = write(dir, "a.ex", "defmodule A do\n  def   go, do: 1\nend\n")

    assert Menard.format(file, cache: Path.join(dir, "cache")) == :ok
    assert File.read!(file) == "defmodule A do\n  def go, do: 1\nend\n"
  end

  test "a project with a mix.exs and no formatter config formats with the defaults", %{tmp_dir: dir} do
    File.write!(Path.join(dir, "mix.exs"), "defmodule Bare.MixProject do\n  use Mix.Project\nend\n")
    file = write(dir, "a.ex", "defmodule A do\n  def   go, do: 1\nend\n")

    assert Menard.format(file, cache: Path.join(dir, "cache")) == :ok
    assert File.read!(file) == "defmodule A do\n  def go, do: 1\nend\n"
  end

  @tag skip:
         !(System.find_executable("mise") &&
             File.exists?(Path.expand("~/.local/share/mise/installs/elixir/1.19.4-otp-27/bin/elixirc")) &&
             File.dir?(Path.expand("~/.local/share/mise/installs/erlang/27.3.4.2/bin")) &&
             System.otp_release() != "27") &&
           "needs mise with elixir 1.19.4-otp-27 and erlang 27.3.4.2 installed, menard on another OTP"

  test "import_deps come from the cache once the dep is gone", %{tmp_dir: dir} do
    host(dir, "[inputs: [\"lib/**/*.ex\"], import_deps: [:dsl]]")
    dep = Path.join(dir, "deps/dsl")
    File.mkdir_p!(dep)
    File.write!(Path.join(dep, ".formatter.exs"), "[export: [locals_without_parens: [field: 2]]]")
    cache = Path.join(dir, "cache")

    first = write(dir, "c.ex", "defmodule C do\n  field :a, :b\nend\n")
    assert Menard.format(first, cache: cache) == :ok

    File.rm_rf!(Path.join(dir, "deps"))
    second = write(dir, "d.ex", "defmodule D do\n  field :c, :d\nend\n")
    assert Menard.format(second, cache: cache) == :ok
    assert File.read!(second) =~ "field :c, :d"
  end

  test "a missing dep with no cache leaves the file alone and says why", %{tmp_dir: dir} do
    host(dir, "[inputs: [\"lib/**/*.ex\"], import_deps: [:dsl]]")
    code = "defmodule E do\n  field   :e, :f\nend\n"
    file = write(dir, "e.ex", code)

    assert {:error, message} = Menard.format(file, cache: Path.join(dir, "cache"))
    assert message =~ "dsl"
    assert File.read!(file) == code
  end

  test "a subdirectory's own import_deps resolve, and its formatter takes content not yet on disk",
       %{tmp_dir: dir} do
    # live_beats: priv/repo/migrations/.formatter.exs imports :ecto_sql, which the root's does not,
    # and every file in the project failed on "Unknown dependency :ecto_sql"
    host(dir, "[inputs: [\"lib/**/*.ex\"], subdirectories: [\"priv/*/migrations\"]]")
    migrations = Path.join(dir, "priv/repo/migrations")
    File.mkdir_p!(migrations)
    File.write!(Path.join(migrations, ".formatter.exs"), "[inputs: [\"*.exs\"], import_deps: [:dsl]]")
    File.mkdir_p!(Path.join(dir, "deps/dsl"))
    File.write!(Path.join(dir, "deps/dsl/.formatter.exs"), "[export: [locals_without_parens: [field: 2]]]")
    file = write(dir, "a.ex", "defmodule A do\n  def   go, do: 1\nend\n")

    assert Menard.format(file, cache: Path.join(dir, "cache")) == :ok
    assert File.read!(file) == "defmodule A do\n  def go, do: 1\nend\n"

    staged = Path.join(migrations, "1_create.exs")
    content = "defmodule Create do\n  field   :a, :b\nend\n"

    assert {:ok, "defmodule Create do\n  field :a, :b\nend\n", nil} =
             Menard.format_staged(staged, content, cache: Path.join(dir, "cache"))

    refute File.exists?(staged)
  end

  test "every file of one call is formatted by one host process", %{tmp_dir: dir} do
    # an OS process per file is a VM start per file: `run format` over a project's inputs would
    # pay it a hundred times
    plugin = plug(dir, "Pid", ~S|File.write!(opts[:pids], System.pid() <> "\n", [:append]); contents|)

    host(
      dir,
      "[inputs: [\"lib/**/*.ex\"], plugins: [#{inspect(plugin)}], pids: #{inspect(Path.join(dir, "pids"))}]"
    )

    files = for name <- ~w(a.ex b.ex c.ex), do: write(dir, name, "defmodule M do\n  def   m, do: 1\nend\n")

    assert Enum.map(Menard.Format.files(files, cache: Path.join(dir, "cache")), &elem(&1, 1)) == [
             :ok,
             :ok,
             :ok
           ]

    assert [pid, pid, pid] = dir |> Path.join("pids") |> File.read!() |> String.split("\n", trim: true)
  end
end
