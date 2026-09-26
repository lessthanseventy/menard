defmodule Hidden.DigestToolTest do
  # get_digest as an MCP client meets it, over the wire: listed by tools/list under that name with
  # workspace_id and days, and a tools/call answering the workspace's digest of the last `days`
  # days as JSON, 7 by default. A grep for `name: "get_digest"` would fail a tool registered
  # without `name:` (Anubis derives the name from the module), and a hidden test of the module
  # alone never exercises the tool.
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Server.Channel
  alias Server.Dossier
  alias Server.MCP
  alias Server.Repo
  alias Server.Staff
  alias Server.Tickets
  alias Server.Workspaces

  @port 48_641
  @url ~c"http://127.0.0.1:48641/mcp"

  setup_all do
    {:ok, _} = Application.ensure_all_started(:inets)
    :ok
  end

  setup do
    Server.TestDB.clean!()
    start_supervised!({MCP.Endpoint, transport: {:streamable_http, start: true}})
    start_supervised!({Bandit, plug: {Server.MCP.Gateway, []}, ip: {127, 0, 0, 1}, port: @port})
    {:ok, ws} = Workspaces.register(%{name: "Digest"})
    {:ok, thread} = Channel.open_thread(%{title: "home", workspace_id: ws.id})
    {:ok, agent} = Staff.register_agent(%{name: "Carl", mandate: "review", engine: "fresh"})
    token = MCP.Tokens.mint(thread, agent)
    %{ws: ws, token: token, session: handshake(token)}
  end

  defp age!(schema, id, days) do
    old = DateTime.utc_now() |> DateTime.add(-days * 86_400) |> DateTime.truncate(:second)
    Repo.update_all(from(r in schema, where: r.id == ^id), set: [created_at: old])
  end

  defp post!(thread, body), do: elem(Channel.post(%{thread_id: thread.id, author: "andrew", body: body}), 1)

  defp fact!(thread, text),
    do:
      elem(Dossier.bank_fact(%{kind: "learned", text: text, provenance: "derived", thread_id: thread.id}), 1)

  defp counts(digest), do: Enum.map(digest["threads"], &{&1["thread_id"], &1["messages"]})

  test "get_digest is listed, taking workspace_id and days", %{token: token, session: session} do
    {200, _, %{"result" => %{"tools" => tools}}} = post(token, session, request(2, "tools/list"))
    tool = Enum.find(tools, &(&1["name"] == "get_digest"))
    assert tool, "no tool named get_digest in tools/list; listed: #{inspect(Enum.map(tools, & &1["name"]))}"
    props = tool["inputSchema"]["properties"] || %{}
    assert Map.has_key?(props, "workspace_id"), "get_digest takes no workspace_id: #{inspect(props)}"
    assert Map.has_key?(props, "days"), "get_digest takes no days: #{inspect(props)}"
  end

  test "get_digest answers the last days' digest, a week by default", %{
    ws: ws,
    token: token,
    session: session
  } do
    {:ok, busy} = Channel.open_thread(%{title: "busy", workspace_id: ws.id})
    {:ok, quiet} = Channel.open_thread(%{title: "quiet", workspace_id: ws.id})
    for n <- 1..2, do: post!(busy, "busy #{n}")
    # in a week's window, out of a day's
    age!(Server.Message, post!(busy, "six days old").id, 6)
    # out of a week's
    age!(Server.Message, post!(quiet, "eight days old").id, 8)
    post!(quiet, "fresh")
    fact!(busy, "recent")
    age!(Server.Fact, fact!(busy, "old").id, 8)
    {:ok, _} = Tickets.file(%{workspace_id: ws.id, title: "recent"})

    week = token |> call(session, 3, "get_digest", %{"workspace_id" => ws.id}) |> decode_tool_json()
    assert counts(week) == [{busy.id, 3}, {quiet.id, 1}]
    assert hd(week["threads"])["title"] == "busy"
    assert week["facts"] == 1
    assert week["tickets_filed"] == 1

    day =
      token |> call(session, 4, "get_digest", %{"workspace_id" => ws.id, "days" => 1}) |> decode_tool_json()

    assert counts(day) == [{busy.id, 2}, {quiet.id, 1}]

    seven =
      token |> call(session, 5, "get_digest", %{"workspace_id" => ws.id, "days" => 7}) |> decode_tool_json()

    assert seven == week
  end

  # -- the raw JSON-RPC client of test/server/mcp/server_test.exs

  defp handshake(token) do
    {200, headers, _} = post(token, nil, initialize_request())
    session = header(headers, "mcp-session-id")
    post(token, session, notification("notifications/initialized"))
    session
  end

  defp call(token, session, id, tool, arguments) do
    {200, _, %{"result" => result}} =
      post(token, session, request(id, "tools/call", %{"name" => tool, "arguments" => arguments}))

    refute result["isError"], "get_digest answered an error: #{inspect(result)}"
    result
  end

  defp decode_tool_json(%{"content" => content}) do
    %{"text" => text} = Enum.find(content, &(&1["type"] == "text"))
    JSON.decode!(text)
  end

  defp initialize_request do
    request(1, "initialize", %{
      "protocolVersion" => "2025-03-26",
      "capabilities" => %{},
      "clientInfo" => %{"name" => "digest-test", "version" => "0.0.0"}
    })
  end

  defp request(id, method, params \\ nil) do
    then(
      %{"jsonrpc" => "2.0", "id" => id, "method" => method},
      &if(params, do: Map.put(&1, "params", params), else: &1)
    )
  end

  defp notification(method), do: %{"jsonrpc" => "2.0", "method" => method}

  defp post(token, session, body) do
    headers =
      [{~c"accept", ~c"application/json, text/event-stream"}] ++
        if(token, do: [{~c"authorization", String.to_charlist("Bearer " <> token)}], else: []) ++
        if session, do: [{~c"mcp-session-id", String.to_charlist(session)}], else: []

    {:ok, {{_http, status, _reason}, resp_headers, resp_body}} =
      :httpc.request(:post, {@url, headers, ~c"application/json", JSON.encode!(body)}, [],
        body_format: :binary
      )

    decoded =
      case resp_body do
        "" -> nil
        text -> text |> String.split("\n") |> Enum.find_value(&event_json/1)
      end

    {status, resp_headers, decoded}
  end

  # a JSON body, or the JSON of a `data:` line of an SSE reply
  defp event_json("data: " <> json), do: JSON.decode!(json)
  defp event_json(line), do: if(String.starts_with?(line, "{"), do: JSON.decode!(line))

  defp header(headers, name) do
    Enum.find_value(headers, fn {k, v} -> if String.downcase(to_string(k)) == name, do: to_string(v) end)
  end
end
