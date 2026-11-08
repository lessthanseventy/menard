defmodule Menard.HostFormatPluginTest do
  # the host's formatter plugins, from its last build in _build: applied, missing, unloadable, loud.
  # Apart from the other host_format tests so their host VMs boot beside each other.
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

  test "a plugin compiled into the host's _build is applied, no deps fetched", %{tmp_dir: dir} do
    plugin = plug(dir, "Plug", ~S["# plugged\n" <> contents])
    host(dir, "[inputs: [\"lib/**/*.ex\"], plugins: [#{inspect(plugin)}]]")
    file = write(dir, "b.ex", "defmodule B do\nend\n")

    assert Menard.format(file, cache: Path.join(dir, "cache")) == :ok
    assert File.read!(file) =~ "# plugged\n"
  end

  test "a plugin built by another toolchain than menard's runs on the host's own", %{tmp_dir: dir} do
    # Tlön's Quokka, built by OTP 29: an OTP 27 menard could not load it (and logged an error per
    # try). The host pins its toolchain, and the format runs there: here 27, menard being on 29.
    installs = Path.expand("~/.local/share/mise/installs")
    elixirc = Path.join(installs, "elixir/1.19.4-otp-27/bin/elixirc")
    erl_bin = Path.join(installs, "erlang/27.3.4.2/bin")
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

    File.write!(Path.join(dir, "mise.toml"), "[tools]\nelixir = \"1.19.4-otp-27\"\nerlang = \"27.3.4.2\"\n")
    System.cmd("mise", ["trust", Path.join(dir, "mise.toml")], stderr_to_stdout: true)
    host(dir, "[inputs: [\"lib/**/*.ex\"], plugins: [MenardNewerPlug]]")
    file = write(dir, "g.ex", "defmodule G do\n  def   g, do: 1\nend\n")

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        assert Menard.format(file, cache: Path.join(dir, "cache")) == :ok
      end)

    refute log =~ "Error loading module"
    # the plugin is the file's formatter, and this one formats nothing
    assert File.read!(file) == "# on 27\ndefmodule G do\n  def   g, do: 1\nend\n"
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
    <<head::binary-size(^at + 4 + 4 + 4 + 1), _e, rest::binary>> = beam
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

  test "a plugin that prints is no part of the answer", %{tmp_dir: dir} do
    # the worker's channel is its own: menard's stdout is the MCP channel, and a host's plugin may print
    plugin = plug(dir, "Loud", ~S|IO.puts("loud"); IO.puts(:stderr, "louder"); contents|)
    host(dir, "[inputs: [\"lib/**/*.ex\"], plugins: [#{inspect(plugin)}]]")
    file = write(dir, "a.ex", "defmodule A do\nend\n")

    out =
      ExUnit.CaptureIO.capture_io(fn ->
        assert {:ok, "defmodule A do\nend\n", _split} =
                 Menard.format_staged(file, File.read!(file), cache: Path.join(dir, "cache"))
      end)

    assert out == ""
  end
end
