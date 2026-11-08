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

  @other if System.version() =~ "1.20", do: {"1.19.4-otp-27", "27.3.4.2"}, else: {"1.20.4-otp-29", "29.0.6"}
  @tag skip:
         !(System.find_executable("mise") &&
             File.dir?(Path.expand("~/.local/share/mise/installs/elixir/#{elem(@other, 0)}"))) &&
           "needs mise with elixir #{elem(@other, 0)} installed"
  test "a host that pins nothing runs the mix on PATH, not mise's global default", %{dir: dir} do
    # bench1: the agent's own `mix` was PATH's (1.19), menard's was mise's global (1.20), and each
    # rebuilt every dep the other had built, until a `run check` took ten minutes
    {other, erlang} = @other

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

  @tag skip: !System.find_executable("mise") && "needs mise"
  test "a host config mise does not load is refused, not a run on menard's toolchain", %{dir: dir} do
    # tlon, 2026-11-04: server/'s mix ran on menard's OTP 27 under tlon's mise.toml pinning 29,
    # recompiling server/_build, and its crash dump said so; mise had listed no pin for it. There is a
    # right toolchain, a `mise trust` away: a run on the wrong one is never the one wanted
    config = Path.join(dir, "mise.toml")
    File.write!(config, "[tools]\nerlang = \"29.0.6\"\nelixir = \"1.20.4-otp-29\"\n")
    server = Path.join(dir, "server")
    File.mkdir_p!(server)
    System.put_env("MISE_IGNORED_CONFIG_PATHS", config)

    try do
      assert {:refused, why} = Menard.host_argv(server, ["mix", "test"])
      assert why =~ config
      assert why =~ "mise trust #{config}"

      # nothing runs: no mix printed its version
      assert {out, 1} = Menard.host_mix(server, ["--version"])
      assert out =~ "mise trust #{config}"
      refute out =~ "Mix "
    after
      System.delete_env("MISE_IGNORED_CONFIG_PATHS")
    end
  end

  @tag skip: !System.find_executable("mise") && "needs mise"
  test "a host whose mise refuses to run: the reply carries mise's own reason", %{dir: dir} do
    # the eval bench's Tlön copy: the host's mise refused to run, and the reply ended in mise's
    # "Version: …" and "Run with --verbose" lines, not the one that said why. An untrusted config
    # was the refusal until mise 2026.10, which runs it (and reads its [env]) with an error printed;
    # a config it cannot parse it still refuses, the reason in a `×` line above a drawing of the file
    File.write!(Path.join(dir, "mise.toml"), "[tools\nerlang = \"27\"\n")
    File.write!(Path.join(dir, "mix.exs"), "defmodule T.MixProject do\n  use Mix.Project\nend\n")
    File.write!(Path.join(dir, ".formatter.exs"), "[inputs: [\"*.ex\"]]")
    file = Path.join(dir, "t.ex")
    File.write!(file, "defmodule T do\nend\n")

    assert {:error, message} = Menard.format(file, cache: Path.join(dir, "cache"))
    assert message =~ "Invalid TOML in config file"
    refute message =~ "╰"
  end
end
