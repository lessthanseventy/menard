defmodule Menard.MCPReplacedTest do
  # A plugin reinstall replaces the install's directory under the servers of every open session.
  # Such a server built itself from the new files on its next call, crashed where they were not
  # yet there, and its session died with no module on disk to say so with: every call after went
  # unanswered, and every hook waited out its timeout (130 s a Bash call).
  use ExUnit.Case, async: true

  import Menard.Test.Checkout

  @moduletag timeout: 300_000
  @moduletag :tmp_dir

  defp answer(port, id) do
    receive do
      {^port, {:data, {_eol, line}}} -> if line =~ ~s("id":#{id}), do: line, else: answer(port, id)
      {^port, {:exit_status, status}} -> flunk("the server exited #{status} before it answered #{id}")
    end
  end

  defp hook(id, dir) do
    arguments = %{
      hook_event_name: "PreToolUse",
      tool: "Bash",
      session_id: "replaced",
      cwd: dir,
      tool_input: %{command: "ls"}
    }

    JSON.encode!(%{
      jsonrpc: "2.0",
      id: id,
      method: "tools/call",
      params: %{name: "hook", arguments: arguments}
    }) <>
      "\n"
  end

  test "a hooks server whose install is replaced under it stops, where it went silent", %{tmp_dir: dir} do
    copy = checkout_copy!(dir)

    port =
      Port.open({:spawn_executable, "/bin/sh"}, [
        :binary,
        :exit_status,
        {:line, 65_536},
        args: ["-c", ~S[exec "$BIN" mcp --hooks 2>/dev/null]],
        cd: copy,
        env: [{~c"BIN", String.to_charlist(Path.join(copy, "bin/menard"))}, {~c"MIX_ENV", ~c"dev"}]
      ])

    initialize = %{
      jsonrpc: "2.0",
      id: 1,
      method: "initialize",
      params: %{protocolVersion: "2025-06-18", capabilities: %{}, clientInfo: %{name: "t", version: "0"}}
    }

    Port.command(port, JSON.encode!(initialize) <> "\n")
    answer(port, 1)
    Port.command(port, JSON.encode!(%{jsonrpc: "2.0", method: "notifications/initialized"}) <> "\n")
    Port.command(port, hook(2, dir))
    assert answer(port, 2) =~ ~s("isError":false)

    # the reinstall: another directory where the server's was
    File.rename!(copy, copy <> "-before")
    File.mkdir_p!(copy)

    Port.command(port, hook(3, dir))
    assert_receive {^port, {:exit_status, 0}}, 30_000
  end
end
