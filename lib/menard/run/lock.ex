defmodule Menard.Run.Lock do
  @moduledoc "One check or test run at a time in a project: the lock a run takes, waits on, and leaves."

  alias Menard.Run

  @doc """
  `check` run with the project's lock held, its reply given `waited` where it waited. Two runs in
  one checkout raced in its `_build` and its `tmp/`: the next waits for the one running, up to
  `run.deadline`, and answers that it is busy past it; a lock whose holder is dead is no wait.
  """
  @spec one_at_a_time(%{dir: String.t(), deadline: integer() | nil}, (-> map())) :: map()
  def one_at_a_time(%{dir: dir} = run, check) do
    lock = Path.join(dir, "_build/.menard-check.lock")
    _ = File.mkdir_p(Path.dirname(lock))

    case take(lock, run.deadline, 0) do
      # a _build this user cannot write (a sandbox, another user's checkout): said, not a crash
      {:error, reason} ->
        message =
          "cannot take the run lock #{lock}: #{:file.format_error(reason)}. Nothing ran: the run needs " <>
            "to write the project's _build"

        %{ok: false, exit: 1, failures: [%{kind: "error", message: message}]}

      {:taken, waited} ->
        try do
          reply = check.()
          if waited > 0, do: Map.put(reply, :waited, waited), else: reply
        after
          :global.unregister_name({Run, :check, lock})
          File.rm(lock)
        end

      # the lock is its holder's: nothing is run beside it, and it is not this run's to remove
      {:busy, waited} ->
        message =
          "another run in this project (pid #{lock |> File.read() |> elem(1) |> to_string() |> String.trim()}) " <>
            "was still going after the #{waited}s this one could wait: nothing ran. Wait for it, or " <>
            "give this run longer"

        %{ok: false, exit: 124, waited: waited, failures: [%{kind: "error", message: message}]}
    end
  end

  defp take(lock, deadline, waited) do
    case File.open(lock, [:write, :exclusive]) do
      {:ok, io} ->
        # the holder in this VM, by name: a check the MCP server killed at its deadline never ran
        # its `after`, and its lock, the server's own (live) OS pid, would have stood for good.
        # Named before the pid is written, so no waiter of this VM reads the pid with no name
        :global.register_name({Run, :check, lock}, self())
        IO.write(io, System.pid())
        File.close(io)
        {:taken, waited}

      {:error, :eexist} ->
        cond do
          not held?(lock) ->
            unstale(lock)
            take(lock, deadline, waited)

          deadline && System.monotonic_time(:millisecond) > deadline ->
            {:busy, waited}

          true ->
            Process.sleep(1_000)
            take(lock, deadline, waited + 1)
        end

      {:error, _reason} = error ->
        error
    end
  end

  # A dead holder's lock out of the way. Two waiters that both found it dead each removed "the"
  # lock, and the second's would be the first's new one: moved aside by a rename only one of them
  # wins, and given back when what it moved is a live holder's after all.
  defp unstale(lock) do
    aside = "#{lock}.#{System.pid()}-#{System.unique_integer([:positive])}"

    with :ok <- File.rename(lock, aside),
         true <- held?(lock, aside),
         do: File.ln(aside, lock)

    File.rm(aside)
    true
  end

  # by another VM that is alive, or by a check of this one that still runs (`file`: the lock's
  # contents, moved aside)
  defp held?(lock, file \\ nil) do
    case File.read(file || lock) do
      # made and not yet written: its holder is between the two
      {:ok, ""} ->
        case File.stat(file || lock, time: :posix) do
          {:ok, %{mtime: at}} -> System.os_time(:second) - at < 5
          _ -> false
        end

      {:ok, pid} ->
        if String.trim(pid) == System.pid(),
          do: :global.whereis_name({Run, :check, lock}) != :undefined,
          else: match?({_, 0}, System.cmd("kill", ["-0", String.trim(pid)], stderr_to_stdout: true))

      _ ->
        false
    end
  end
end
