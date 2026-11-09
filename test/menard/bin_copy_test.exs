defmodule Menard.BinCopyTest do
  # bin/menard on a copy of this checkout, built there: a test that breaks menard's source, or its
  # mix.lock, breaks the copy's. Nothing here touches this checkout's own builds, so these run
  # beside every other async module; in Menard.BinTest (not async: it rebuilds a build of
  # menard's) their 160 s ran one after another, the bulk of the suite's serial half.
  use ExUnit.Case, async: true

  # a copy builds menard from its deps: 22 s at load 55 for the first verb; the cold mcp case
  # past 60 s there
  @moduletag timeout: 300_000

  import Menard.Test.Checkout

  # no deadline of its own: a server that never answers is the test's timeout
  defp recv_until(port, needle, out) do
    receive do
      {^port, {:data, {:eol, line}}} ->
        out = out <> line <> "\n"
        if out =~ needle, do: out, else: recv_until(port, needle, out)

      {^port, {:data, {:noeol, part}}} ->
        recv_until(port, needle, out <> part)

      {^port, {:exit_status, status}} ->
        flunk("the server exited #{status} before its answer #{needle}:\n#{out}")
    end
  end

  @tag :tmp_dir
  test "mcp answers initialize fast, from a cold build that would otherwise outrun a client's connect timeout",
       %{tmp_dir: dir} do
    # menard's own build gone: a compile stands behind the stub's answer, as a fresh install's does.
    # The deps' too ran the real server's answer past the test's timeout at a load of 46
    copy = checkout_copy!(dir)
    File.rm_rf!(Path.join(copy, "_build/dev/lib/menard"))

    root = Path.join(dir, "project")
    File.mkdir_p!(Path.join(root, "lib"))
    File.write!(Path.join(root, "lib/a.ex"), "defmodule A do\n  def go, do: 1\nend\n")

    messages = [
      %{
        jsonrpc: "2.0",
        id: 1,
        method: "initialize",
        params: %{protocolVersion: "2025-06-18", capabilities: %{}, clientInfo: %{name: "t", version: "0"}}
      },
      %{jsonrpc: "2.0", method: "notifications/initialized"},
      %{
        jsonrpc: "2.0",
        id: 2,
        method: "tools/call",
        params: %{name: "outline", arguments: %{file: "lib/a.ex"}}
      }
    ]

    env = [
      {~c"BIN", String.to_charlist(Path.join(copy, "bin/menard"))},
      {~c"MIX_ENV", ~c"dev"},
      {~c"MENARD_ROOT", String.to_charlist(root)}
    ]

    port =
      Port.open({:spawn_executable, "/bin/sh"}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        {:line, 65_536},
        args: ["-c", ~S[exec "$BIN" mcp 2>/dev/null]],
        cd: copy,
        env: env
      ])

    started = System.monotonic_time(:millisecond)
    Port.command(port, Enum.map_join(messages, &(JSON.encode!(&1) <> "\n")))

    first = recv_until(port, ~s("id":1), "")
    answered_init_in = System.monotonic_time(:millisecond) - started
    rest = recv_until(port, ~s("id":2), "")
    Port.close(port)

    # well under Claude Code's 30 s connect timeout, even though the compile behind it is ~28 s
    assert answered_init_in < 10_000, "initialize took #{answered_init_in}ms:\n#{first}"
    assert rest =~ "go"
    refute first <> rest =~ "** ("
  end
end
