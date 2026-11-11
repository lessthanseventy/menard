defmodule Menard.MCPReplacedTest do
  # A plugin reinstall replaces the install's directory under the servers of every open session,
  # and Claude Code does not start again a server that stopped. So the server goes on: from the
  # code it has loaded while the new install is not there yet, from the new install once it is.
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

  # a server that died says why: its stderr, kept beside the test's files
  defp tell(port, line, stderr) do
    Port.command(port, line)
  rescue
    ArgumentError -> flunk("the server is gone:\n" <> File.read!(stderr))
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

  test "a hooks server whose install is replaced under it goes on answering", %{tmp_dir: dir} do
    copy = checkout_copy!(dir)
    stderr = Path.join(dir, "stderr")

    port =
      Port.open({:spawn_executable, "/bin/sh"}, [
        :binary,
        :exit_status,
        {:line, 65_536},
        args: ["-c", ~S[exec "$BIN" mcp --hooks 2>"$ERR"]],
        cd: copy,
        env: [
          {~c"BIN", String.to_charlist(Path.join(copy, "bin/menard"))},
          {~c"ERR", String.to_charlist(stderr)},
          {~c"MIX_ENV", ~c"dev"},
          {~c"MENARD_LOG_LEVEL", ~c"info"}
        ]
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

    # the reinstall, under way: another directory where the server's was, nothing in it yet
    File.rename!(copy, copy <> "-before")
    File.mkdir_p!(copy)
    tell(port, hook(3, dir), stderr)
    assert answer(port, 3) =~ ~s("isError":false)

    # and done: the install is there again, as other files
    File.rm_rf!(copy)
    File.cp_r!(copy <> "-before", copy)
    tell(port, hook(4, dir), stderr)
    assert answer(port, 4) =~ ~s("isError":false)
    tell(port, hook(5, dir), stderr)
    assert answer(port, 5) =~ ~s("isError":false)
  end
end
