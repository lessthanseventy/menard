defmodule Menard.HostFormatTest do
  # menard formats with the HOST project's formatter, as an OS process on the host's own
  # toolchain, while that project is as broken as it gets: a mix.exs that does not parse, deps
  # never fetched, a config that wants an env var. Plugins come from its last build in _build;
  # import_deps from deps/, else from the copy the last good format cached.
  use ExUnit.Case, async: true

  @moduletag :tmp_dir

  defp host(dir, formatter) do
    File.write!(Path.join(dir, "mix.exs"), "defmodule Broken.MixProject do\n  this does not parse (\n")
    File.write!(Path.join(dir, ".formatter.exs"), formatter)
    File.mkdir_p!(Path.join(dir, "lib"))
    dir
  end

  defp write(dir, name, code) do
    file = Path.join([dir, "lib", name])
    File.mkdir_p!(Path.dirname(file))
    File.write!(file, code)
    file
  end

  # A plugin compiled into `root`'s _build, as a host's last build would hold it. `body` is its
  # format/2, with `contents` and `opts` bound.
  defp plug(root, name, body) do
    plugin = :"Elixir.MenardTest#{name}#{System.unique_integer([:positive])}"
    ebin = Path.join(root, "_build/dev/lib/plug/ebin")
    File.mkdir_p!(ebin)

    [{^plugin, beam}] =
      Code.compile_string("""
      defmodule #{inspect(plugin)} do
        @behaviour Mix.Tasks.Format
        def features(_opts), do: [extensions: [".ex"]]

        def format(contents, opts) do
          _ = opts
          #{body}
        end
      end
      """)

    :code.purge(plugin)
    :code.delete(plugin)
    File.write!(Path.join(ebin, "#{plugin}.beam"), beam)
    plugin
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

  test "a plugin compiled into the host's _build is applied, no deps fetched", %{tmp_dir: dir} do
    plugin = plug(dir, "Plug", ~S["# plugged\n" <> contents])
    host(dir, "[inputs: [\"lib/**/*.ex\"], plugins: [#{inspect(plugin)}]]")
    file = write(dir, "b.ex", "defmodule B do\nend\n")

    assert Menard.format(file, cache: Path.join(dir, "cache")) == :ok
    assert File.read!(file) =~ "# plugged\n"
  end

  test "a plugin built by a newer toolchain than menard's runs on the host's own", %{tmp_dir: dir} do
    # Tlön's Quokka, built by OTP 29: an OTP 27 menard could not load it (and logged an error per
    # try). The host pins its toolchain, and the format runs there.
    installs = Path.expand("~/.local/share/mise/installs")
    elixirc = Path.join(installs, "elixir/1.20.4-otp-29/bin/elixirc")
    erl_bin = Path.join(installs, "erlang/29.0.6/bin")

    if System.find_executable("mise") && File.exists?(elixirc) && File.dir?(erl_bin) &&
         System.otp_release() < "29" do
      ebin = Path.join(dir, "_build/dev/lib/plug/ebin")
      File.mkdir_p!(ebin)
      src = Path.join(dir, "plug.ex")

      File.write!(src, """
      defmodule MenardNewerPlug do
        def features(_opts), do: [extensions: [".ex"]]
        def format(contents, _opts), do: "\# on \#{System.otp_release()}\\n" <> contents
      end
      """)

      {_, 0} =
        System.cmd(elixirc, ["-o", ebin, src], env: [{"PATH", erl_bin <> ":" <> System.get_env("PATH")}])

      File.write!(Path.join(dir, "mise.toml"), "[tools]\nelixir = \"1.20.4-otp-29\"\nerlang = \"29.0.6\"\n")
      System.cmd("mise", ["trust", Path.join(dir, "mise.toml")], stderr_to_stdout: true)
      host(dir, "[inputs: [\"lib/**/*.ex\"], plugins: [MenardNewerPlug]]")
      file = write(dir, "g.ex", "defmodule G do\n  def   g, do: 1\nend\n")

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert Menard.format(file, cache: Path.join(dir, "cache")) == :ok
        end)

      refute log =~ "Error loading module"
      # the plugin is the file's formatter, and this one formats nothing
      assert File.read!(file) == "# on 29\ndefmodule G do\n  def   g, do: 1\nend\n"
    end
  end

  test "a plugin whose beam cannot be read is a plugin that cannot be found, not a crash", %{tmp_dir: dir} do
    # Tlön's Quokka, built by OTP 29, read by OTP 27: beam_lib raised a MatchError over the atom
    # chunk, and the reply's reason was that crash dump. Stood in for by a beam whose first atom is
    # not UTF-8, which the loader refuses the same way.
    ebin = Path.join(dir, "_build/dev/lib/plug/ebin")
    File.mkdir_p!(ebin)
    [{MenardUnreadablePlug, beam}] = Code.compile_string("defmodule MenardUnreadablePlug do\nend\n")
    :code.purge(MenardUnreadablePlug)
    :code.delete(MenardUnreadablePlug)
    {at, _} = :binary.match(beam, "AtU8")
    # past the chunk id, its size, the atom count and the first atom's length byte: its first byte
    <<head::binary-size(at + 4 + 4 + 4 + 1), _e, rest::binary>> = beam
    File.write!(Path.join(ebin, "Elixir.MenardUnreadablePlug.beam"), <<head::binary, 0xFF, rest::binary>>)
    host(dir, "[inputs: [\"lib/**/*.ex\"], plugins: [MenardUnreadablePlug]]")
    file = write(dir, "u.ex", "defmodule U do\n  def   u, do: 1\nend\n")

    assert {:error, message} = Menard.format(file, cache: Path.join(dir, "cache"))
    assert message =~ "MenardUnreadablePlug"
    refute message =~ "no match of right hand side"
  end

  test "a plugin that will not load is never skipped silently — the file is left alone", %{tmp_dir: dir} do
    ebin = Path.join(dir, "_build/dev/lib/plug/ebin")
    File.mkdir_p!(ebin)
    File.write!(Path.join(ebin, "Elixir.MenardBadPlug.beam"), "not a beam")
    host(dir, "[inputs: [\"lib/**/*.ex\"], plugins: [MenardBadPlug]]")
    code = "defmodule F do\n  def   f, do: 1\nend\n"
    file = write(dir, "f.ex", code)

    # the host's VM logs the corrupt beam as it refuses it, on its own stderr, not menard's
    log =
      ExUnit.CaptureLog.capture_log(fn ->
        assert {:error, message} = Menard.format(file, cache: Path.join(dir, "cache"))
        assert message =~ "MenardBadPlug"
      end)

    refute log =~ "MenardBadPlug"
    assert File.read!(file) == code
  end

  test "run format passes a file its plugins cannot format when it is formatted already", %{tmp_dir: dir} do
    # the format hook blocked on files formatted at HEAD, in a project never built in place: the
    # file cannot be formatted here, but it can be checked, the plugins left out
    host(
      dir,
      "[inputs: [\"lib/**/*.ex\"], plugins: [MenardNeverBuiltPlug], locals_without_parens: [field: 2]]"
    )

    write(dir, "clean.ex", "defmodule C do\n  field :a, 1\nend\n")
    write(dir, "messy.ex", "defmodule M do\n  def   m, do: 1\nend\n")

    reply = Menard.Run.result(dir, "format", ["lib/clean.ex", "lib/messy.ex"])

    assert %{ok: false, changed: [], failures: [%{at: "lib/messy.ex", message: message}]} = reply
    assert message =~ "MenardNeverBuiltPlug"
  end

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

  test "a plugin's rewrites are their own stage, apart from the formatter's", %{tmp_dir: dir} do
    # a Styler-like plugin: it formats AND rewrites, so its rewrite must not be billed to the formatter
    plugin =
      plug(
        dir,
        "Style",
        ~S|IO.iodata_to_binary([Code.format_string!(String.replace(contents, ":old", ":new"), opts), ?\n])|
      )

    host(dir, "[inputs: [\"lib/**/*.ex\"], plugins: [#{inspect(plugin)}]]")
    file = write(dir, "b.ex", "")

    assert {:ok, reply} = Menard.write(file, "defmodule B do\n  def go,    do: :old\nend\n")
    assert File.read!(file) == "defmodule B do\n  def go, do: :new\nend\n"

    assert [
             %{stage: :patch},
             %{
               stage: :formatter,
               hunks: [%{removed: ["  def go,    do: :old"], added: ["  def go, do: :old"]}]
             },
             %{
               stage: :plugins,
               plugins: [name],
               hunks: [%{removed: ["  def go, do: :old"], added: ["  def go, do: :new"]}]
             }
           ] = reply.stages

    assert name == inspect(plugin)
  end

  test "a plugin runs in the host's directory, where it looks for its config", %{tmp_dir: dir} do
    # Quokka reads the host's .credo.exs from File.cwd!(): run from menard's directory it found none,
    # and rewrapped every file at its default line length
    plugin = plug(dir, "Cwd", ~S[contents <> "# cwd: #{File.cwd!()}\n"])
    host(dir, "[inputs: [\"lib/**/*.ex\"], plugins: [#{inspect(plugin)}]]")
    file = write(dir, "b.ex", "defmodule B do\nend\n")

    assert Menard.format(file, cache: Path.join(dir, "cache")) == :ok
    assert File.read!(file) =~ "# cwd: #{dir}\n"
  end

  test "a plugin's cached config is the host's, not the last host's", %{tmp_dir: dir} do
    # Quokka and Styler keep their config in :persistent_term and read it only when it is unset, so a
    # long-running menard (the MCP server) formatted every host with the first host's config
    plugin =
      plug(Path.join(dir, "one"), "Cached", ~S"""
      seen =
        try do
          :persistent_term.get(__MODULE__.Config)
        rescue
          ArgumentError -> :persistent_term.put(__MODULE__.Config, opts[:seen]) && opts[:seen]
        end

      contents <> "# seen: #{seen}\n"
      """)

    for name <- ["one", "two"] do
      root = Path.join(dir, name)
      # the second host has the same plugin in its own last build
      File.mkdir_p!(root)
      if name == "two", do: File.cp_r!(Path.join(dir, "one/_build"), Path.join(root, "_build"))
      host(root, "[inputs: [\"lib/**/*.ex\"], plugins: [#{inspect(plugin)}], seen: #{inspect(name)}]")
      file = write(root, "b.ex", "defmodule B do\nend\n")

      assert Menard.format(file, cache: Path.join(dir, "cache")) == :ok
      assert File.read!(file) =~ "# seen: #{name}\n"
    end
  end

  test "every file of one call is formatted by one host process", %{tmp_dir: dir} do
    # an OS process per file is a VM start per file: `run format` over a project's inputs would
    # pay it a hundred times
    plugin = plug(dir, "Pid", ~S|File.write!(opts[:pids], System.pid() <> "\n", [:append]) && contents|)

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

  test "a format out of time is killed, and nothing it spawned writes the file afterwards", %{tmp_dir: dir} do
    # the shell fallback's `mix format` ran on after menard gave up, and wrote the file after menard
    # had handed out its version: the agent's next edit was refused as stale
    plugin =
      plug(dir, "Slow", ~S"""
      File.write!(opts[:pid_file], System.pid())
      Process.sleep(10_000)
      File.write!(opts[:file], "# late\n")
      contents
      """)

    pid_file = Path.join(dir, "pid")
    file = write(dir, "s.ex", "defmodule S do\nend\n")

    host(
      dir,
      "[inputs: [\"lib/**/*.ex\"], plugins: [#{inspect(plugin)}], pid_file: #{inspect(pid_file)}, file: #{inspect(file)}]"
    )

    assert {:error, message} =
             Menard.format_staged(file, File.read!(file), cache: Path.join(dir, "cache"), timeout: 1_000)

    assert message =~ "did not finish in 1s"
    # the host's VM was stopped with the deadline, not left to finish
    pid = File.read!(pid_file)
    assert {_, status} = System.cmd("kill", ["-0", pid], stderr_to_stdout: true)
    assert status != 0, "the host's formatter (pid #{pid}) outlived its deadline"
    assert File.read!(file) == "defmodule S do\nend\n"
  end
end
