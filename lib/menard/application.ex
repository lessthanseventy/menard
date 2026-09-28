defmodule Menard.Application do
  @moduledoc false
  use Application

  # The formatters kept warm, one per project written into (Menard.Format.Worker), none until the
  # first format. `mix menard.mcp` adds the stdio server.
  @impl true
  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: Menard.Format.Registry},
      {DynamicSupervisor, name: Menard.Format.Workers, strategy: :one_for_one}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Menard.Supervisor)
  end
end
