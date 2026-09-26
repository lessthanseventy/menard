defmodule Menard.HostToolchainTest do
  # MISE_GLOBAL_CONFIG_FILE is process-wide, so not async.
  use ExUnit.Case, async: false

  # Off the repo, whose own .tool-versions would pin every dir under it
  setup do
    dir =
      Path.join(System.tmp_dir!(), "menard-toolchain-#{System.pid()}-#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, dir: dir}
  end

  test "a host that pins nothing runs the mix on PATH, not mise's global default", %{dir: dir} do
    # bench1: the agent's own `mix` was PATH's (1.19), menard's was mise's global (1.20), and each
    # rebuilt every dep the other had built, until a `run check` took ten minutes
    {other, erlang} =
      if System.version() =~ "1.20", do: {"1.19.4-otp-27", "27.3.4.2"}, else: {"1.20.4-otp-29", "29.0.6"}

    installed = Path.expand("~/.local/share/mise/installs/elixir/#{other}")

    if System.find_executable("mise") && File.dir?(installed) do
      # beside the host, not above it: a config above it is the host's own pin
      global = Path.join([dir, "global", "config.toml"])
      File.mkdir_p!(Path.dirname(global))
      File.write!(global, "[tools]\nelixir = \"#{other}\"\nerlang = \"#{erlang}\"\n")
      previous = System.get_env("MISE_GLOBAL_CONFIG_FILE")
      System.put_env("MISE_GLOBAL_CONFIG_FILE", global)

      try do
        host = Path.join(dir, "host")
        File.mkdir_p!(host)
        {path_mix, 0} = System.cmd("mix", ["--version"], cd: host)
        {out, 0} = Menard.host_mix(host, ["--version"])
        assert out =~ path_mix |> String.split("\n") |> Enum.find(&(&1 =~ "Mix "))
      after
        if previous,
          do: System.put_env("MISE_GLOBAL_CONFIG_FILE", previous),
          else: System.delete_env("MISE_GLOBAL_CONFIG_FILE")
      end
    end
  end

  test "a host whose mise config is not trusted: the reply carries mise's own reason", %{dir: dir} do
    # the eval bench's Tlön copy: the host's mise refused to run, and the reply ended in mise's
    # "Version: …" and "Run with --verbose" lines, not the one that said why
    if System.find_executable("mise") do
      # [env] is what mise refuses to read from an untrusted file; [tools] alone it reads
      File.write!(Path.join(dir, "mise.toml"), "[tools]\nerlang = \"27\"\n\n[env]\nMENARD_TRUST = \"1\"\n")
      File.write!(Path.join(dir, "mix.exs"), "defmodule T.MixProject do\n  use Mix.Project\nend\n")
      ebin = Path.join(dir, "_build/dev/lib/plug/ebin")
      File.mkdir_p!(ebin)
      File.write!(Path.join(ebin, "Elixir.MenardBadPlug.beam"), "not a beam")
      File.write!(Path.join(dir, ".formatter.exs"), "[inputs: [\"*.ex\"], plugins: [MenardBadPlug]]")
      file = Path.join(dir, "t.ex")
      File.write!(file, "defmodule T do\nend\n")

      ExUnit.CaptureLog.capture_log(fn ->
        send(self(), {:format, Menard.format(file, cache: Path.join(dir, "cache"))})
      end)

      assert_received {:format, {:error, message}}
      assert message =~ "are not trusted"
    end
  end
end
