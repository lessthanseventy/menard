defmodule Mix.Tasks.Menard.Mcp do
  @shortdoc "Serve Menard over stdio as an MCP server (for Claude Code / a bare pi)"
  @moduledoc """
  `mix menard.mcp` — the standalone door: the same verbs as `mix menard.*`, over stdio, every
  path scoped to `MENARD_ROOT` (else the caller's directory). Register once:

      claude mcp add menard -- mise run menard -- mcp
  """
  use Mix.Task

  @impl true
  def run(_argv) do
    Mix.Task.run("app.start", ["--no-compile"])
    {:ok, _} = Supervisor.start_child(Menard.Supervisor, {Menard.MCP, transport: :stdio})

    # The transport stops when the client closes stdin, and the VM goes with it: kept alive, the
    # server of a client that died without killing it lingers for good.
    ref = Process.monitor(Anubis.Server.Registry.transport_name(Menard.MCP, :stdio))

    receive do
      {:DOWN, ^ref, :process, _pid, _reason} -> System.halt(0)
    end
  end
end
