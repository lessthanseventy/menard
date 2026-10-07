defmodule Mix.Tasks.TestNoLeaks do
  @shortdoc "mix test, then fail if a beam.smp it started still runs under tmp/"
  @moduledoc """
  Runs `mix test` as its own OS process, so THIS task's own BEAM can check what is left once
  it is well and truly gone — an `ExUnit.after_suite` callback cannot: it runs inside the very
  process it would be asking "are you still here?", so every warm worker a test left running
  on purpose (not yet orphaned — its owner, `mix test`'s BEAM, hasn't exited yet) would look
  indistinguishable from a real leak.

  Fails if a `beam.smp` survives that `mix test` with a cwd under this project's `tmp/`: the
  signature of a kept-warm host VM (`Menard.Format.Worker`, `priv/format.exs serve`) that
  outlived its owner despite the VM's own watchdog (test/menard/host_format_test.exs proves the
  watchdog itself; this is the whole-suite net). `mix precommit` runs this instead of bare
  `test`.
  """
  use Mix.Task

  @impl true
  def run(argv) do
    {_, status} =
      System.cmd("mix", ["test" | argv],
        into: IO.stream(:stdio, :line),
        stderr_to_stdout: true,
        env: [{"MIX_ENV", "test"}]
      )

    leaked = leaked_vms()

    if leaked != [] do
      Mix.shell().error("leaked host VM(s), cwd under tmp/: #{Enum.join(leaked, ", ")}")
      System.cmd("kill", ["-KILL" | leaked], stderr_to_stdout: true)
    end

    if status != 0 or leaked != [], do: exit({:shutdown, 1})
  end

  defp leaked_vms do
    case System.cmd("pgrep", ["-x", "beam.smp"], stderr_to_stdout: true) do
      {out, 0} ->
        out
        |> String.split("\n", trim: true)
        |> Enum.filter(&under_tmp?/1)

      _ ->
        []
    end
  end

  defp under_tmp?(pid) do
    case cwd(pid) do
      nil -> false
      dir -> String.starts_with?(dir, Path.expand("tmp"))
    end
  end

  defp cwd(pid) do
    case File.read_link(Path.join(["/proc", pid, "cwd"])) do
      {:ok, path} -> path
      _ -> fallback_cwd(pid)
    end
  end

  # no /proc (macOS)
  defp fallback_cwd(pid) do
    case System.cmd("lsof", ["-a", "-d", "cwd", "-p", pid, "-Fn"], stderr_to_stdout: true) do
      {out, 0} ->
        out
        |> String.split("\n", trim: true)
        |> Enum.find_value(fn
          "n" <> path -> path
          _ -> nil
        end)

      _ ->
        nil
    end
  end
end
