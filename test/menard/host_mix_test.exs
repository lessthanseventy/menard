defmodule Menard.HostMixTest do
  # The host's mix, on the host's toolchain — unless the host pins one that is not installed. Then
  # mise would build it (Erlang from source, through kerl: minutes, and a failure on a machine
  # without its build deps) before `run` answered ok:false with no reason.
  use ExUnit.Case, async: true

  @moduletag :tmp_dir

  test "a pinned toolchain that is not installed is never built: the mix on PATH runs, and says so",
       %{tmp_dir: dir} do
    if System.find_executable("mise") do
      File.write!(Path.join(dir, ".tool-versions"), "erlang 26.2.3\nelixir 1.16.2-otp-26\n")

      {us, {out, status}} = :timer.tc(fn -> Menard.host_mix(dir, ["--version"]) end)

      assert status == 0
      assert out =~ "Mix"
      assert out =~ "erlang 26.2.3"
      assert out =~ "not installed"
      assert us < 20_000_000
    end
  end

  test "the host's mix reads no stdin: a prompt gets end of input, not a wait", %{tmp_dir: dir} do
    # `mix deps.get` asking "Shall I install Hex? [Yn]" waited forever on the CLI door: the port's
    # stdin stays open and never says anything
    File.write!(Path.join(dir, "mix.exs"), """
    defmodule Asks.MixProject do
      use Mix.Project
      def project, do: [app: :asks, version: "0.1.0"]
    end
    """)

    {out, status} = Menard.host_mix(dir, ["run", "-e", ~s|IO.inspect(IO.gets("go? "))|], timeout: 20_000)
    assert status == 0, out
    assert out =~ ":eof"
  end

  test "a deadline a millisecond short of a second is that second, not one less", %{tmp_dir: dir} do
    # a verb's deadline is what is left of it when each mix starts: 10_000ms given, 9_999 left a
    # millisecond later, and the kill came at 9s
    File.write!(Path.join(dir, "mix.exs"), """
    defmodule Waits.MixProject do
      use Mix.Project
      def project, do: [app: :waits, version: "0.1.0"]
    end
    """)

    {out, _status} = Menard.host_mix(dir, ["run", "-e", "Process.sleep(:infinity)"], timeout: 1_999)
    assert out =~ "did not finish in 2s"
  end
end
