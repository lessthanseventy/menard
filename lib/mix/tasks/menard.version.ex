defmodule Mix.Tasks.Menard.Version do
  @shortdoc "Which menard, on which Elixir and OTP"
  @moduledoc """
  `mix menard.version` — `menard 0.2.0 on Elixir 1.19.4 / OTP 27`. The first question of any
  install: menard runs on its own pinned toolchain (`.tool-versions`), not the caller's.
  """
  use Mix.Task

  @impl true
  def run(_argv) do
    version = Application.spec(:menard, :vsn) || Mix.Project.config()[:version]
    Mix.shell().info("menard #{version} on Elixir #{System.version()} / OTP #{System.otp_release()}")
  end
end
