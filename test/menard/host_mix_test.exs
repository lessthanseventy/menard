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
end
