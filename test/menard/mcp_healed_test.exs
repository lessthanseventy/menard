defmodule Menard.MCPHealedTest do
  # A stdio session that ended (anubis ends an idle one, and never starts another) answered nothing
  # more, and Claude Code initializes a server once: every hook after waited out its timeout. The
  # server starts the session again itself, initialized as the client left it.
  use ExUnit.Case, async: true

  @moduletag timeout: 300_000
  @moduletag :tmp_dir

  @bin Path.expand("../../bin/menard", __DIR__)

  defp answer(port, id, stderr) do
    receive do
      {^port, {:data, {_eol, line}}} -> if line =~ ~s("id":#{id}), do: line, else: answer(port, id, stderr)
      {^port, {:exit_status, status}} -> flunk("the server exited #{status}:\n" <> File.read!(stderr))
    after
      60_000 -> flunk("no answer to #{id}:\n" <> File.read!(stderr))
    end
  end

  defp hook(id, dir) do
    arguments = %{event: "PreToolUse", tool: "Bash", session: "healed", cwd: dir, input: ~s({"command":"ls"})}

    JSON.encode!(%{
      jsonrpc: "2.0",
      id: id,
      method: "tools/call",
      params: %{name: "hook", arguments: arguments}
    }) <> "\n"
  end

  # A hook answered, within a few tries: the test's idle timeout is seconds, and a call still in
  # flight when it runs out is answered that the session is ending.
  defp hooked!(port, id, dir, stderr, tries \\ 5) do
    Port.command(port, hook(id, dir))

    cond do
      answer(port, id, stderr) =~ ~s("isError":false) -> :ok
      tries > 1 -> hooked!(port, id + 100, dir, stderr, tries - 1)
      true -> flunk("no hook answered in 5 tries:\n" <> File.read!(stderr))
    end
  end

  # the server's own word that a session ended and was started again, `n` times by now
  defp healed!(stderr, n, left \\ 600) do
    times =
      stderr
      |> File.read!()
      |> String.split("the MCP session ended ({:shutdown, :session_expired})")
      |> length()

    cond do
      times > n -> :ok
      left == 0 -> flunk("the session was not started again #{n} times:\n" <> File.read!(stderr))
      true -> Process.sleep(100) && healed!(stderr, n, left - 1)
    end
  end

  test "a hooks server whose session ended answers the next hook", %{tmp_dir: dir} do
    stderr = Path.join(dir, "stderr")

    port =
      Port.open({:spawn_executable, "/bin/sh"}, [
        :binary,
        :exit_status,
        {:line, 65_536},
        args: ["-c", ~S[exec "$BIN" mcp --hooks 2>"$ERR"]],
        cd: dir,
        env: [
          {~c"BIN", String.to_charlist(@bin)},
          {~c"ERR", String.to_charlist(stderr)},
          {~c"MIX_ENV", ~c"dev"},
          {~c"TMPDIR", String.to_charlist(dir)},

          # the session ends 2 s after its last request arrived, answered or not
          {~c"MENARD_MCP_IDLE_MS", ~c"2000"}
        ]
      ])

    initialize = %{
      jsonrpc: "2.0",
      id: 1,
      method: "initialize",
      params: %{protocolVersion: "2025-06-18", capabilities: %{}, clientInfo: %{name: "t", version: "0"}}
    }

    Port.command(port, JSON.encode!(initialize) <> "\n")
    answer(port, 1, stderr)
    Port.command(port, JSON.encode!(%{jsonrpc: "2.0", method: "notifications/initialized"}) <> "\n")
    hooked!(port, 2, dir, stderr)

    # the session ended and was started again, twice over: each time the next hook is answered
    for n <- [1, 2] do
      healed!(stderr, n)
      hooked!(port, 2 + n, dir, stderr)
    end
  end
end
