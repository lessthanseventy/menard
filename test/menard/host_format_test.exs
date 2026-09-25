defmodule Menard.HostFormatTest do
  # menard formats with the HOST project's formatter while that project is as broken as it gets:
  # a mix.exs that does not parse, deps never fetched. Plugins come from its last build in
  # _build; import_deps from deps/, else from the copy the last good format cached.
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

  test "a plugin built by a newer OTP is passed over without the VM's load error", %{tmp_dir: dir} do
    installs = Path.expand("~/.local/share/mise/installs")
    elixirc = Path.join(installs, "elixir/1.20.4-otp-29/bin/elixirc")
    erl_bin = Path.join(installs, "erlang/29.0.6/bin")

    if File.exists?(elixirc) and File.dir?(erl_bin) and System.otp_release() < "29" do
      ebin = Path.join(dir, "_build/dev/lib/plug/ebin")
      File.mkdir_p!(ebin)
      src = Path.join(dir, "plug.ex")

      File.write!(src, """
      defmodule MenardNewerPlug do
        def features(_opts), do: [extensions: [".ex"]]
        def format(contents, _opts), do: contents
      end
      """)

      {_, 0} =
        System.cmd(elixirc, ["-o", ebin, src], env: [{"PATH", erl_bin <> ":" <> System.get_env("PATH")}])

      host(dir, "[inputs: [\"lib/**/*.ex\"], plugins: [MenardNewerPlug]]")
      code = "defmodule G do\n  def   g, do: 1\nend\n"
      file = write(dir, "g.ex", code)

      log = ExUnit.CaptureLog.capture_log(fn -> Menard.format(file, cache: Path.join(dir, "cache")) end)

      refute log =~ "Error loading module"
      assert File.read!(file) == code
    end
  end

  test "a plugin that will not load is never skipped silently — the file is left alone", %{tmp_dir: dir} do
    ebin = Path.join(dir, "_build/dev/lib/plug/ebin")
    File.mkdir_p!(ebin)
    File.write!(Path.join(ebin, "Elixir.MenardBadPlug.beam"), "not a beam")
    host(dir, "[inputs: [\"lib/**/*.ex\"], plugins: [MenardBadPlug]]")
    code = "defmodule F do\n  def   f, do: 1\nend\n"
    file = write(dir, "f.ex", code)

    # the VM logs the corrupt beam as it refuses it — expected here, and noise in every gate run
    ExUnit.CaptureLog.capture_log(fn ->
      assert {:error, message} = Menard.format(file, cache: Path.join(dir, "cache"))
      assert message =~ "MenardBadPlug"
    end)

    assert File.read!(file) == code
  end

  test "formats with the host's own options though its mix.exs is broken", %{tmp_dir: dir} do
    host(dir, "[inputs: [\"lib/**/*.ex\"], line_length: 30]")
    file = write(dir, "a.ex", "defmodule A do\n  def go, do: [:alpha, :beta, :gamma, :delta]\nend\n")

    assert Menard.format(file, cache: Path.join(dir, "cache")) == :ok
    assert File.read!(file) =~ "[\n      :alpha,\n"
  end

  test "a plugin compiled into the host's _build is applied, no deps fetched", %{tmp_dir: dir} do
    plugin = :"Elixir.MenardTestPlug#{System.unique_integer([:positive])}"
    ebin = Path.join(dir, "_build/dev/lib/plug/ebin")
    File.mkdir_p!(ebin)

    [{^plugin, beam}] =
      Code.compile_string("""
      defmodule #{inspect(plugin)} do
        @behaviour Mix.Tasks.Format
        def features(_opts), do: [extensions: [".ex"]]
        def format(contents, _opts), do: "# plugged\\n" <> contents
      end
      """)

    :code.purge(plugin)
    :code.delete(plugin)
    File.write!(Path.join(ebin, "#{plugin}.beam"), beam)

    host(dir, "[inputs: [\"lib/**/*.ex\"], plugins: [#{inspect(plugin)}]]")
    file = write(dir, "b.ex", "defmodule B do\nend\n")

    assert Menard.format(file, cache: Path.join(dir, "cache")) == :ok
    assert File.read!(file) =~ "# plugged\n"
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

  test "a plugin's rewrites are their own stage, apart from the formatter's", %{tmp_dir: dir} do
    # a Styler-like plugin: it formats AND rewrites, so its rewrite must not be billed to the formatter
    plugin = :"Elixir.MenardTestStyle#{System.unique_integer([:positive])}"
    ebin = Path.join(dir, "_build/dev/lib/style/ebin")
    File.mkdir_p!(ebin)

    [{^plugin, beam}] =
      Code.compile_string("""
      defmodule #{inspect(plugin)} do
        @behaviour Mix.Tasks.Format
        def features(_opts), do: [extensions: [".ex"]]

        def format(contents, opts),
          do: IO.iodata_to_binary([Code.format_string!(String.replace(contents, ":old", ":new"), opts), ?\\n])
      end
      """)

    :code.purge(plugin)
    :code.delete(plugin)
    File.write!(Path.join(ebin, "#{plugin}.beam"), beam)

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
    # Quokka and Styler keep their config in :persistent_term and read it only when it is unset, so a
    # long-running menard (the MCP server) formatted every host with the first host's config
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

  test "a write the format could not finish says so in its reply", %{tmp_dir: dir} do
    # a write the format could not finish said so on stderr only, and the reply looked clean
    ebin = Path.join(dir, "_build/dev/lib/plug/ebin")
    File.mkdir_p!(ebin)
    File.write!(Path.join(ebin, "Elixir.MenardBadPlug.beam"), "not a beam")
    host(dir, "[inputs: [\"lib/**/*.ex\"], plugins: [MenardBadPlug]]")
    file = write(dir, "f.ex", "defmodule F do\nend\n")

    ExUnit.CaptureLog.capture_log(fn ->
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        send(self(), {:reply, Menard.write(file, "defmodule F do\n  def   f, do: 1\nend\n")})
      end)
    end)

    assert_received {:reply, {:ok, reply}}
    assert reply.unformatted =~ "MenardBadPlug"
    assert %{error: _} = Enum.find(reply.stages, &(&1.stage == :formatter))
    assert File.read!(file) =~ "def   f"
  end

  test "a format out of time says which formatter it was waiting on", %{tmp_dir: dir} do
    # out of time, the reply says where the time went: menard's VM, or the host's own `mix format`
    plugin = plug(dir, "Slow", "Process.sleep(2_000)\ncontents")
    host(dir, "[inputs: [\"lib/**/*.ex\"], plugins: [#{inspect(plugin)}]]")
    file = write(dir, "s.ex", "defmodule S do\nend\n")

    assert {:error, message} =
             Menard.format_content(file, File.read!(file), cache: Path.join(dir, "cache"), timeout: 300)

    assert message =~ "did not finish in 0.3s"
    assert message =~ "in menard's VM"
  end
end
