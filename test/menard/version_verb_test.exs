defmodule Menard.VersionVerbTest do
  # `menard version`: which menard, on which toolchain — the first question of any install.
  use ExUnit.Case, async: true

  test "names menard's version and the Elixir and OTP it runs on" do
    line = ExUnit.CaptureIO.capture_io(fn -> Mix.Tasks.Menard.Version.run([]) end)

    assert line ==
             "menard #{Mix.Project.config()[:version]} on Elixir #{System.version()} / OTP #{System.otp_release()}\n"
  end
end
