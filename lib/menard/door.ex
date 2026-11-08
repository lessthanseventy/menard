defmodule Menard.Door do
  @moduledoc """
  The launcher's way into the session's running hooks server, so a CLI verb boots no VM.

  Every `bin/menard VERB` started a VM of its own: mise and mix, menard's compile check, then the
  host formatter's VM. Idle that is 1.4 s; under the seats' load it was 24 s at the median for an
  `edit`, where the MCP door's `edit`, warm, took 1 s (docs/review/2026-11-08-transcripts.md). The
  hooks server (`mcp --hooks`) runs for the whole session with the formatters warm, so it listens on
  a port of localhost's and leaves the port in `$TMPDIR/menard-door-KEY`, KEY the session's id
  (`CLAUDE_CODE_SESSION_ID`, which the harness gives its servers and its shells alike) or, without
  one, its parent's PID (the harness). `bin/menard` looks for the session's file, then walks up its
  ancestors, and sends the verb there over bash's `/dev/tcp`: no VM of its own.

  The request: `CWD NUL VERB NUL N NUL ARG1 NUL … ARGN NUL LEN NUL`, then LEN bytes of stdin. The
  reply: `STDOUT NUL STDERR NUL STATUS LF`. A door that does not answer (a stale file, a server gone)
  costs the launcher one refused connection, and it runs the verb itself as before.

  The launcher keeps `run` to itself (minutes of mix would hold the server), `mcp`, `hook` and the
  trivial verbs, and every verb from inside menard's own checkout, where the running server is the
  installed plugin's build and `--frozen` means the working tree's.

  The verb runs in a process of its own with a `StringIO` for its group leader: what it reads as
  stdin is the request's, and what it prints lands there, never on the server's stdout, which is the
  MCP channel. `Mix.shell/0` is `Mix.Shell.Process` in the hooks server, so a task's `info` and
  `error` are messages to that process, and the caller's directory rides its dictionary
  (`Menard.caller_dir/0`).
  """
  use GenServer

  @doc "Listen for the launcher, under `Menard.Supervisor`; `key:` and `dir:` for a test's own."
  @spec open(keyword()) :: Supervisor.on_start_child()
  def open(opts \\ []), do: Supervisor.start_child(Menard.Supervisor, {__MODULE__, opts})

  @doc "Stop listening and remove the door file."
  @spec close() :: :ok
  def close do
    case Process.whereis(__MODULE__) do
      nil -> :ok
      pid -> GenServer.stop(pid)
    end
  end

  @doc "How many requests this door has answered."
  @spec served() :: non_neg_integer()
  def served, do: GenServer.call(__MODULE__, :served)

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    {:ok, listen} = :gen_tcp.listen(0, [:binary, ip: {127, 0, 0, 1}, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(listen)
    key = opts[:key] || System.get_env("CLAUDE_CODE_SESSION_ID") || parent_pid()
    file = Path.join(opts[:dir] || System.tmp_dir!(), "menard-door-#{key}")
    File.write!(file, "#{port}\n")
    door = self()
    {:ok, _} = Task.start_link(fn -> accept(listen, door) end)
    {:ok, %{listen: listen, file: file, served: 0}}
  end

  @impl true
  def handle_call(:served, _from, state), do: {:reply, state.served, state}

  @impl true
  def handle_cast(:served, state), do: {:noreply, %{state | served: state.served + 1}}

  @impl true
  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %{file: file, listen: listen}) do
    File.rm(file)
    :gen_tcp.close(listen)
  end

  # the harness that started this server: Linux's /proc, else ps
  defp parent_pid do
    case File.read("/proc/self/stat") do
      {:ok, stat} -> stat |> String.replace(~r/^.*\) /, "") |> String.split() |> Enum.at(1)
      _ -> System.cmd("ps", ["-o", "ppid=", "-p", System.pid()]) |> elem(0) |> String.trim()
    end
  end

  defp accept(listen, door) do
    case :gen_tcp.accept(listen) do
      {:ok, socket} ->
        pid = spawn(fn -> receive(do: (:go -> serve(socket, door))) end)
        :ok = :gen_tcp.controlling_process(socket, pid)
        send(pid, :go)
        accept(listen, door)

      {:error, _closed} ->
        :ok
    end
  end

  defp serve(socket, door) do
    with {:ok, request} <- request(socket, "") do
      {out, err, status} = run(request)
      :gen_tcp.send(socket, [out, 0, err, 0, Integer.to_string(status), "\n"])
      GenServer.cast(door, :served)
    end

    :gen_tcp.close(socket)
  end

  defp request(socket, buffer) do
    case parse(buffer) do
      {:ok, request} ->
        {:ok, request}

      :more ->
        case :gen_tcp.recv(socket, 0, 30_000) do
          {:ok, data} -> request(socket, buffer <> data)
          {:error, _} = error -> error
        end
    end
  end

  # the header is whole once its last field, the stdin's length, has its NUL; then the stdin itself
  defp parse(buffer) do
    parts = String.split(buffer, <<0>>)

    with [_cwd, _verb, n | _] when length(parts) > 3 <- parts,
         {n, ""} <- Integer.parse(n),
         true <- length(parts) > n + 4,
         {[cwd, verb, _n | args] = header, [len | _]} <- Enum.split(parts, n + 3),
         {len, ""} <- Integer.parse(len) do
      skip = Enum.sum(Enum.map(header, &byte_size/1)) + byte_size(Integer.to_string(len)) + n + 4
      stdin = binary_part(buffer, skip, byte_size(buffer) - skip)

      if byte_size(stdin) >= len,
        do: {:ok, %{cwd: cwd, verb: verb, args: args, stdin: binary_part(stdin, 0, len)}},
        else: :more
    else
      _ -> :more
    end
  end

  # the verb as `bin/menard`'s own VM runs it: a Mix.Error is the one line the task raised, a
  # `then` that is red exits 1, anything else is the exception, printed
  defp run(%{cwd: cwd, verb: verb, args: args, stdin: stdin}) do
    {:ok, io} = StringIO.open(stdin)
    Process.group_leader(self(), io)
    Process.put(:menard_cwd, cwd)

    status =
      try do
        Mix.Task.get!("menard." <> verb).run(args)
        0
      rescue
        e in Mix.Error ->
          Mix.shell().error("** (Mix) " <> Exception.message(e))
          1

        e ->
          Mix.shell().error(Exception.format(:error, e, __STACKTRACE__))
          1
      catch
        :exit, {:shutdown, n} when is_integer(n) ->
          n

        :exit, reason ->
          Mix.shell().error("** (exit) " <> Exception.format_exit(reason))
          1
      end

    {_unread, printed} = StringIO.contents(io)
    {infos, errors} = said([], [])
    {printed <> infos, errors, status}
  end

  defp said(infos, errors) do
    receive do
      {:mix_shell, :info, [message]} -> said([message | infos], errors)
      {:mix_shell, :error, [message]} -> said(infos, [message | errors])
    after
      0 -> {lines(infos), lines(errors)}
    end
  end

  defp lines(messages), do: messages |> Enum.reverse() |> Enum.map_join("", &(&1 <> "\n"))
end
