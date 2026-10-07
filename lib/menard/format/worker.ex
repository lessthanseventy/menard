defmodule Menard.Format.Worker do
  @moduledoc """
  A project's formatter, kept warm: the host's own VM (`priv/format.exs serve`, on the host's
  toolchain) behind a port, one per project, started by the first format and gone after ten idle
  minutes, or with menard. The host's VM takes 0.4s to start, which a session paid on every write.

  What `Menard.Format` promises of the one-call process holds here: the host's code runs in the
  host's VM, never menard's; the real files are never touched; and past a request's deadline the
  process is killed, not abandoned, the next format starting a new one. A worker is also replaced
  when the project's `mix.exs` or `mix.lock` changed since it started: it holds the plugins as it
  first loaded them.

  The port talks over fds 3 and 4, and the host's stdout goes to a log: menard's own stdout is the
  MCP channel, and a plugin may print.
  """
  use GenServer, restart: :temporary

  @idle 10 * 60_000

  @doc """
  `request` (what `priv/format.exs` takes) answered by `project`'s worker within `ms`: `{:ok,
  results}`, `:timeout` (the worker killed), `{:error, said}` when the host's VM died, with what
  it said, or `:unavailable` where menard runs unsupervised (a library host, a bare script).
  """
  @spec format(String.t(), map(), pos_integer()) ::
          {:ok, map()} | :timeout | {:error, String.t()} | :unavailable
  def format(project, request, ms) do
    with pid when is_pid(pid) <- Process.whereis(Menard.Format.Workers),
         {:ok, worker} <- worker(project) do
      GenServer.call(worker, {:format, request, ms}, :infinity)
    else
      _ -> :unavailable
    end
  catch
    # stopped idle between the lookup and the call
    :exit, _ -> :unavailable
  end

  @doc """
  Stop `project`'s worker now, killing its host VM — the idle timeout otherwise waiting out
  `@idle`. A no-op where none is running. For a caller that cannot wait out an idle worker it
  started (a test's `tmp_dir` project, gone when the test ends): `DynamicSupervisor.terminate_child/2`
  blocks for `terminate/2` to run, so the host VM is dead before this returns.
  """
  @spec stop(String.t()) :: :ok
  def stop(project) do
    case Registry.lookup(Menard.Format.Registry, project) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(Menard.Format.Workers, pid)
      [] -> :ok
    end

    :ok
  end

  defp worker(project) do
    case DynamicSupervisor.start_child(Menard.Format.Workers, {__MODULE__, project}) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      _ -> :error
    end
  end

  @doc false
  def start_link(project),
    do: GenServer.start_link(__MODULE__, project, name: {:via, Registry, {Menard.Format.Registry, project}})

  @impl true
  def init(project) do
    Process.flag(:trap_exit, true)
    {:ok, %{project: project, port: nil, os_pid: nil, vm: nil, print: nil, log: nil}, @idle}
  end

  @impl true
  def handle_call({:format, request, ms}, _from, state) do
    state = state |> current() |> open()
    %{port: port} = state
    Port.command(port, :erlang.term_to_binary(request))

    await(state, System.monotonic_time(:millisecond) + ms)
  end

  defp await(%{port: port} = state, deadline) do
    receive do
      {^port, {:data, data}} ->
        case :erlang.binary_to_term(data) do
          # the host VM's hello, before its first answer
          {:pid, pid} -> await(%{state | vm: pid}, deadline)
          results -> {:reply, {:ok, results}, state, @idle}
        end

      {^port, {:exit_status, _status}} ->
        said = said(state)
        {:reply, {:error, said}, closed(state), @idle}
    after
      max(deadline - System.monotonic_time(:millisecond), 0) -> {:reply, :timeout, close(state), @idle}
    end
  end

  @impl true
  def handle_info(:timeout, state), do: {:stop, :normal, state}
  # the host's VM went between requests: the next one starts another
  def handle_info({port, {:exit_status, _}}, %{port: port} = state), do: {:noreply, closed(state), @idle}
  def handle_info(_other, state), do: {:noreply, state, @idle}

  @impl true
  def terminate(_reason, state), do: close(state)

  defp current(%{port: nil} = state), do: state
  defp current(state), do: if(print(state.project) == state.print, do: state, else: close(state))

  defp open(%{port: nil, project: project} = state) do
    script = Application.app_dir(:menard, "priv/format.exs")
    {argv, _note} = Menard.host_argv(project, ["elixir", script, "serve"])
    name = "menard-format-#{System.pid()}-#{System.unique_integer([:positive])}.log"
    log = Path.join(System.tmp_dir!(), name)

    port =
      Port.open({:spawn_executable, System.find_executable("sh")}, [
        :binary,
        :nouse_stdio,
        :exit_status,
        {:packet, 4},
        args: ["-c", ~s(log=$1; shift; exec "$@" </dev/null >"$log" 2>&1), "sh", log | argv],
        cd: project
      ])

    {:os_pid, os_pid} = Port.info(port, :os_pid)
    %{state | port: port, os_pid: os_pid, print: print(project), log: log}
  end

  defp open(state), do: state

  # killed, not closed: a plugin mid-format does not read its port, and the VM would stay
  defp close(%{port: nil} = state), do: state

  defp close(state) do
    pids = for pid <- [state.os_pid, state.vm], pid, do: "#{pid}"
    System.cmd("kill", ["-KILL" | pids], stderr_to_stdout: true)
    port = state.port

    # gone, not only signalled: a caller that checks finds no process
    receive do
      {^port, {:exit_status, _status}} -> :ok
    after
      5_000 -> :ok
    end

    closed(state)
  end

  defp closed(state) do
    if state.port && Port.info(state.port), do: Port.close(state.port)
    if state.log, do: File.rm(state.log)
    %{state | port: nil, os_pid: nil, vm: nil, log: nil}
  end

  defp said(%{log: log}) do
    case File.read(log) do
      {:ok, out} -> out
      _ -> ""
    end
  end

  defp print(project) do
    for name <- ["mix.exs", "mix.lock"] do
      case File.stat(Path.join(project, name), time: :posix) do
        {:ok, %{mtime: mtime, size: size}} -> {mtime, size}
        _ -> nil
      end
    end
  end
end
