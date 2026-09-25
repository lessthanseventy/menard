defmodule Mix.Tasks.Menard.Mcp do
  @shortdoc "Serve Menard over stdio as an MCP server (for Claude Code / a bare pi)"
  @moduledoc """
  `mix menard.mcp` — the standalone door: the same verbs as `mix menard.*`, over stdio, every
  path scoped to `MENARD_ROOT` (else the caller's directory). Register once:

      claude mcp add menard -- mise run menard -- mcp
  """
  use Mix.Task

  # anubis_mcp is optional: a library host has no Registry, and never reaches the call
  @compile {:no_warn_undefined, Anubis.Server.Registry}

  @impl true
  def run(_argv) do
    Code.ensure_loaded?(Menard.MCP) ||
      Mix.raise(
        ~s(the MCP door needs the optional anubis_mcp: add {:anubis_mcp, "~> 2.0"} to your deps, ) <>
          "then `mix deps.compile menard --force` if menard was built without it"
      )

    # `--frozen` runs outside any mix project, where app.start dies; the line below starts menard
    if Mix.Project.get(), do: Mix.Task.run("app.start", ["--no-compile"])
    # a host takes menard `runtime: false`, and app.start leaves it (and anubis) stopped
    {:ok, _} = Application.ensure_all_started(:menard)

    logs_to_stderr()
    {:ok, _} = Supervisor.start_child(Menard.Supervisor, {Menard.MCP, transport: :stdio})

    # The transport stops when the client closes stdin, and the VM goes with it: kept alive, the
    # server of a client that died without killing it lingers for good.
    ref = Process.monitor(Anubis.Server.Registry.transport_name(Menard.MCP, :stdio))

    receive do
      {:DOWN, ^ref, :process, _pid, _reason} -> System.halt(0)
    end
  end

  # STDOUT IS THE PROTOCOL CHANNEL: a stdio server writes nothing there that is not an MCP message,
  # and Elixir logs to stdout by default. Set up here, not in config/, which a host that takes menard
  # as a dep never loads. Quiet unless MENARD_LOG_LEVEL (one of Logger's levels) asks: the transport
  # logs every frame at :debug, and an unknown level falls back to :warning rather than crashing.
  defp logs_to_stderr do
    _ = :logger.remove_handler(:default)

    :ok =
      :logger.add_handler(:default, :logger_std_h, %{
        config: %{type: :standard_error},
        formatter: Logger.default_formatter()
      })

    name = System.get_env("MENARD_LOG_LEVEL")
    levels = [:emergency, :alert, :critical, :error, :warning, :notice, :info, :debug]
    Logger.configure(level: Enum.find(levels, :warning, &(Atom.to_string(&1) == name)))
  end
end
