defmodule Menard.Lsp do
  @moduledoc """
  A project's language server, kept warm: `bin/lsp` (expert unless `MENARD_LSP` names another)
  behind a port, one per project, started by `warm/1` and gone after ten idle minutes, or with
  menard. What a verb gets from it is what the AST cannot see: who calls a function through an
  `import`, a `defdelegate`, a `use` or an `apply`.

  Only a long-lived door warms one (the MCP server, for its root): a server takes seconds to start
  and index, which a one-shot CLI call would pay and throw away. A verb only asks, and never waits
  on a server that is not ready: it answers from the AST alone and says so.

  Ready is generic LSP, not one server's log lines: the server has reported work-done progress,
  and none is still running. Until its index is built a server answers `null` or a short list,
  which read as "no callers".
  """
  use GenServer, restart: :temporary

  @idle 10 * 60_000

  @type location :: %{file: String.t(), line: pos_integer(), column: pos_integer()}

  @doc "The server `bin/lsp` runs: `MENARD_LSP`, else expert."
  @spec server() :: String.t()
  def server, do: System.get_env("MENARD_LSP") || "expert"

  @doc "Start `project`'s server, if menard runs supervised and none is up; returns at once."
  @spec warm(String.t()) :: :ok
  def warm(project) do
    if Process.whereis(Menard.Lsp.Workers),
      do: DynamicSupervisor.start_child(Menard.Lsp.Workers, {__MODULE__, Path.expand(project)})

    :ok
  end

  @doc """
  Where the function whose name is at `line`:`column` (1-based) of `file` is referred to, its
  definition left out: `{:ok, locations}`, `:warming` while the server starts or indexes (or did
  not answer within `ms`), or `:off` when no server was warmed for `project`.
  """
  @spec references(String.t(), String.t(), pos_integer(), pos_integer(), pos_integer()) ::
          {:ok, [location()]} | :warming | :off
  def references(project, file, line, column, ms) do
    # no registry where menard runs unsupervised (the CLI, a library host)
    with registry when is_pid(registry) <- Process.whereis(Menard.Lsp.Registry),
         [{pid, _}] <- Registry.lookup(Menard.Lsp.Registry, Path.expand(project)) do
      GenServer.call(pid, {:references, file, line, column, ms}, ms + 1_000)
    else
      _ -> :off
    end
  catch
    # stopped idle between the lookup and the call, or a call past its deadline
    :exit, _ -> :off
  end

  @doc false
  def start_link(project),
    do: GenServer.start_link(__MODULE__, project, name: {:via, Registry, {Menard.Lsp.Registry, project}})

  @impl true
  def init(project) do
    Process.flag(:trap_exit, true)
    lsp = Path.join(Path.dirname(Menard.bin()), "lsp")

    # the server's stderr is its own business: menard's is only refusals and real errors
    port =
      Port.open({:spawn_executable, System.find_executable("sh")}, [
        :binary,
        :exit_status,
        args: ["-c", ~s(exec "$0" 2>/dev/null), lsp],
        cd: project
      ])

    state = %{
      project: project,
      port: port,
      buffer: "",
      next: 1,
      pending: %{},
      progress: MapSet.new(),
      seen: false
    }

    uri = "file://" <> project

    state =
      send_request(state, "initialize", %{
        processId: String.to_integer(System.pid()),
        rootUri: uri,
        workspaceFolders: [%{uri: uri, name: Path.basename(project)}],
        capabilities: %{window: %{workDoneProgress: true}}
      })

    {:ok, state, @idle}
  end

  @impl true
  def handle_call({:references, file, line, column, ms}, from, state) do
    if ready?(state) do
      state =
        send_request(state, "textDocument/references", %{
          textDocument: %{uri: "file://" <> file},
          position: %{line: line - 1, character: column - 1},
          context: %{includeDeclaration: false}
        })

      id = state.next - 1
      Process.send_after(self(), {:deadline, id}, ms)
      {:noreply, put_in(state.pending[id], from), @idle}
    else
      {:reply, :warming, state, @idle}
    end
  end

  @impl true
  def handle_info({port, {:data, data}}, %{port: port} = state),
    do: {:noreply, frames(%{state | buffer: state.buffer <> data}), @idle}

  def handle_info({port, {:exit_status, _}}, %{port: port} = state), do: {:stop, :normal, state}

  def handle_info({:deadline, id}, state) do
    {from, pending} = Map.pop(state.pending, id)
    if from, do: GenServer.reply(from, :warming)
    {:noreply, %{state | pending: pending}, @idle}
  end

  def handle_info(:timeout, state), do: {:stop, :normal, state}
  def handle_info(_other, state), do: {:noreply, state, @idle}

  # stdin closed is the server's cue to stop, and its engine with it
  @impl true
  def terminate(_reason, state), do: if(Port.info(state.port), do: Port.close(state.port))

  defp ready?(state), do: state.seen and MapSet.size(state.progress) == 0

  defp frames(state) do
    with [head, rest] <- :binary.split(state.buffer, "\r\n\r\n"),
         [_, n] <- Regex.run(~r/Content-Length: (\d+)/i, head),
         n = String.to_integer(n),
         <<body::binary-size(^n), more::binary>> <- rest do
      frames(handle(JSON.decode!(body), %{state | buffer: more}))
    else
      _ -> state
    end
  end

  # the answer to initialize, always the first request
  defp handle(%{"id" => 1} = msg, state) when not is_map_key(msg, "method"),
    do: notify(state, "initialized", %{})

  # a response to a references request, unless its deadline answered first
  defp handle(%{"id" => id} = msg, state) when not is_map_key(msg, "method") do
    {from, pending} = Map.pop(state.pending, id)
    if from, do: GenServer.reply(from, locations(msg["result"]))
    %{state | pending: pending}
  end

  defp handle(%{"method" => "$/progress", "params" => %{"token" => token, "value" => value}}, state) do
    case value["kind"] do
      "begin" -> %{state | seen: true, progress: MapSet.put(state.progress, token)}
      "end" -> %{state | progress: MapSet.delete(state.progress, token)}
      _ -> state
    end
  end

  # every request the server makes (registerCapability, workDoneProgress/create) is answered
  # `null`: an error made expert 0.1.10 stop answering for good (expert #904)
  defp handle(%{"id" => id, "method" => _}, state), do: reply(state, id)
  defp handle(_notification, state), do: state

  # null is the server not ready, not "none"
  defp locations(nil), do: :warming

  defp locations(list) do
    locations =
      for %{"uri" => "file://" <> file, "range" => %{"start" => %{"line" => l, "character" => c}}} <- list,
          do: %{file: URI.decode(file), line: l + 1, column: c + 1}

    {:ok, locations}
  end

  defp send_request(state, method, params) do
    write(state, %{jsonrpc: "2.0", id: state.next, method: method, params: params})
    %{state | next: state.next + 1}
  end

  defp notify(state, method, params) do
    write(state, %{jsonrpc: "2.0", method: method, params: params})
    state
  end

  defp reply(state, id) do
    write(state, %{jsonrpc: "2.0", id: id, result: nil})
    state
  end

  defp write(state, msg) do
    body = JSON.encode!(msg)
    Port.command(state.port, "Content-Length: #{byte_size(body)}\r\n\r\n" <> body)
  end
end
