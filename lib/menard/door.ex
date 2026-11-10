defmodule Menard.Door do
  @moduledoc """
  The launcher's way into the session's running hooks server, so a CLI verb boots no VM.

  Every `bin/menard VERB` started a VM of its own: mise and mix, menard's compile check, then the
  host formatter's VM. Idle that is 1.4 s, and far more under load, where the MCP door's `edit`,
  warm, takes 1 s. The hooks server (`mcp --hooks`) runs for the whole session with the formatters warm, so it listens on
  a port of localhost's and leaves the port, then its checkout's root, in `$TMPDIR/menard-door-KEY`, KEY the session's id
  (`CLAUDE_CODE_SESSION_ID`, which the harness gives its servers and its shells alike) or, without
  one, its parent's PID (the harness). `bin/menard` looks for the session's file, then walks up its
  ancestors, and sends the verb there over bash's `/dev/tcp`: no VM of its own.

  The door says `menard LF` to whoever connects, so a launcher knows in seconds that a server is
  there to answer. The request: `TOKEN NUL CWD NUL VERB NUL N NUL ARG1 NUL … ARGN NUL LEN NUL`, then
  LEN bytes of stdin. The reply: `STDOUT NUL STDERR NUL STATUS LF`. A door that does not answer (a
  stale file, a server gone or wedged) costs the launcher one try, and it runs the verb itself as
  before.

  The door writes files and runs code as the session's user, on a port any local process can reach:
  TOKEN is the third line of the door file, which only its user can read, and a request without it
  is closed unanswered.

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

  # the launcher's own, and no door's: minutes of mix, the server itself, the harness's plumbing
  @kept ~w(run mcp hook guard)
  # a request is a verb's arguments and a file's worth of stdin
  @most 64 * 1024 * 1024
  @day 24 * 3600 * 1000

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

  @doc "Start the door, registered as this module; what `open/1` has the supervisor call."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    {:ok, listen} = :gen_tcp.listen(0, [:binary, ip: {127, 0, 0, 1}, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(listen)
    key = opts[:key] || System.get_env("CLAUDE_CODE_SESSION_ID") || parent_pid()
    file = Path.join(opts[:dir] || System.tmp_dir!(), "menard-door-#{key}")
    # the checkout this server runs from (bin/menard starts it there): a launcher of another build
    # leaves the door alone
    token = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
    File.write!(file, "")
    File.chmod!(file, 0o600)
    File.write!(file, "#{port}\n#{File.cwd!()}\n#{token}\n")
    door = self()
    {:ok, _} = Task.start_link(fn -> accept(listen, door, token) end)
    # touched daily: the hook's sweep of week-old files would take a long session's door
    :timer.send_interval(@day, :touch)
    {:ok, %{listen: listen, file: file, port: port, served: 0}}
  end

  @impl true
  def handle_call(:served, _from, state), do: {:reply, state.served, state}

  @impl true
  def handle_cast(:served, state), do: {:noreply, %{state | served: state.served + 1}}

  @impl true
  def handle_info(:touch, state) do
    File.touch(state.file)
    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  # the file goes only while it is still this door's: a server started for the same session since
  # has written its own port there
  @impl true
  def terminate(_reason, %{file: file, listen: listen, port: port}) do
    with {:ok, content} <- File.read(file),
         true <- String.starts_with?(content, "#{port}\n"),
         do: File.rm(file)

    :gen_tcp.close(listen)
  end

  # the harness that started this server: Linux's /proc, else ps
  defp parent_pid do
    case File.read("/proc/self/stat") do
      {:ok, stat} -> stat |> String.replace(~r/^.*\) /, "") |> String.split() |> Enum.at(1)
      _ -> System.cmd("ps", ["-o", "ppid=", "-p", System.pid()]) |> elem(0) |> String.trim()
    end
  end

  defp accept(listen, door, token) do
    case :gen_tcp.accept(listen) do
      {:ok, socket} ->
        pid = spawn(fn -> receive(do: (:go -> serve(socket, door, token))) end)
        :ok = :gen_tcp.controlling_process(socket, pid)
        send(pid, :go)
        accept(listen, door, token)

      {:error, :closed} ->
        :ok

      # out of descriptors for now: a loop that ended here left a port that took connections and
      # answered none
      {:error, _other} ->
        Process.sleep(200)
        accept(listen, door, token)
    end
  end

  defp serve(socket, door, token) do
    :gen_tcp.send(socket, "menard\n")

    with {:ok, request} <- request(socket, "", System.monotonic_time(:millisecond) + 30_000),
         true <- byte_size(request.token) == byte_size(token) and :crypto.hash_equals(request.token, token),
         true <- request.verb not in @kept do
      {out, err, status} = run(request)
      :gen_tcp.send(socket, [out, 0, err, 0, Integer.to_string(status), "\n"])
      GenServer.cast(door, :served)
    end

    :gen_tcp.close(socket)
  end

  # whole within 30 s of the connection and under @most, however it is sent
  defp request(socket, buffer, deadline) do
    left = deadline - System.monotonic_time(:millisecond)

    case parse(buffer) do
      {:ok, request} ->
        {:ok, request}

      :more when left <= 0 or byte_size(buffer) > @most ->
        {:error, :refused}

      :more ->
        case :gen_tcp.recv(socket, 0, left) do
          {:ok, data} -> request(socket, buffer <> data, deadline)
          {:error, _} = error -> error
        end
    end
  end

  # the header is whole once its last field, the stdin's length, has its NUL; then the stdin itself
  defp parse(buffer) do
    parts = String.split(buffer, <<0>>)

    with [_token, _cwd, _verb, n | _] when length(parts) > 4 <- parts,
         {n, ""} <- Integer.parse(n),
         true <- length(parts) > n + 5,
         {[token, cwd, verb, _n | args] = header, [len | _]} <- Enum.split(parts, n + 4),
         {len, ""} <- Integer.parse(len) do
      skip = Enum.sum(Enum.map(header, &byte_size/1)) + byte_size(Integer.to_string(len)) + n + 5
      stdin = binary_part(buffer, skip, byte_size(buffer) - skip)

      if byte_size(stdin) >= len,
        do: {:ok, %{token: token, cwd: cwd, verb: verb, args: args, stdin: binary_part(stdin, 0, len)}},
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
