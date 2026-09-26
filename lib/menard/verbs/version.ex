defmodule Menard.Verbs.Version do
  @moduledoc "The `version` verb (`Menard.Verbs`): which menard, on which Elixir and OTP. The first question of any install: menard runs on its own pinned toolchain, not the caller's."

  @spec run(Menard.Verbs.params()) :: Menard.Verbs.result()
  def run(_params) do
    # loaded, not assumed: under `bin/menard --frozen` nothing has loaded the app, and there is no
    # mix.exs to fall back on, so the version printed empty
    Application.load(:menard)
    version = Application.spec(:menard, :vsn) || Mix.Project.config()[:version]
    {:ok, %{menard: to_string(version), elixir: System.version(), otp: System.otp_release()}}
  end

  @doc "The reply as one line: `menard 0.5.0 on Elixir 1.19.4 / OTP 27`."
  @spec line(map()) :: String.t()
  def line(%{menard: menard, elixir: elixir, otp: otp}),
    do: "menard #{menard} on Elixir #{elixir} / OTP #{otp}"
end
