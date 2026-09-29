defmodule Desk.Hidden.ApiTest do
  use DeskWeb.ConnCase, async: false

  import Desk.Hidden

  alias Desk.Tickets

  @keys ~w(assignee due_at id inserted_at priority requester_email status subject)

  defp iso!(text) do
    assert {:ok, at, 0} = DateTime.from_iso8601(text)
    at
  end

  test "GET /api/tickets lists tickets in list_tickets' order, each in the one shape", %{conn: conn} do
    al = agent!("Al")
    low = ticket!(priority: :low)
    {:ok, high} = Tickets.assign(filed!(~U[2026-03-02 10:00:00Z], priority: :high), al)

    assert %{"data" => [first, second]} = conn |> get(~p"/api/tickets") |> json_response(200)
    assert first["id"] == high.id and second["id"] == low.id
    assert Enum.sort(Map.keys(first)) == @keys

    assert %{
             "subject" => "Printer on fire",
             "status" => "open",
             "priority" => "high",
             "requester_email" => "ann@example.com",
             "assignee" => %{"id" => id, "name" => "Al"}
           } = first

    assert id == al.id
    assert second["assignee"] == nil
    assert iso!(first["due_at"]) == ~U[2026-03-02 14:00:00Z]
    assert iso!(first["inserted_at"]) == ~U[2026-03-02 10:00:00Z]
  end

  test "GET /api/tickets narrows by status and priority", %{conn: conn} do
    _new = ticket!()
    open = through!(ticket!(priority: :high), [:open])

    ids = fn query ->
      for t <- conn |> get(~p"/api/tickets?#{query}") |> json_response(200) |> Map.fetch!("data"), do: t["id"]
    end

    assert ids.(%{status: "open"}) == [open.id]
    assert ids.(%{priority: "high", status: "open"}) == [open.id]
    assert ids.(%{priority: "high", status: "new"}) == []
    assert length(ids.(%{})) == 2
  end

  test "GET /api/tickets/:id carries the public comments, oldest first", %{conn: conn} do
    al = agent!("Al")
    ticket = ticket!()
    {:ok, %{comment: a}} = Tickets.add_comment(ticket, %{author_kind: :requester, body: "one"})

    {:ok, _} =
      Tickets.add_comment(ticket, %{author_kind: :agent, agent_id: al.id, body: "secret", internal: true})

    {:ok, %{comment: c}} = Tickets.add_comment(ticket, %{author_kind: :agent, agent_id: al.id, body: "three"})

    assert %{"data" => data} = conn |> get(~p"/api/tickets/#{ticket.id}") |> json_response(200)
    assert Enum.sort(Map.keys(data)) == Enum.sort(["comments" | @keys])
    assert data["status"] == "pending"
    assert [first, second] = data["comments"]
    assert Enum.sort(Map.keys(first)) == ~w(author_kind body id inserted_at)
    assert {first["id"], first["author_kind"], first["body"]} == {a.id, "requester", "one"}
    assert {second["id"], second["author_kind"], second["body"]} == {c.id, "agent", "three"}
    iso!(first["inserted_at"])
  end

  test "a ticket that is not there is a 404, from a number and from a word", %{conn: conn} do
    assert conn |> get(~p"/api/tickets/987654") |> json_response(404) == %{"error" => "not_found"}
    # (not asked: an id that is no number, and a move of a ticket that is not there. The prompt
    # gives the 404 to GET /api/tickets/:id)
  end

  test "POST /api/tickets files a ticket, or says what is wrong with it", %{conn: conn} do
    body = %{
      ticket: %{
        subject: "Filed",
        body: "B",
        requester_email: "Zed@Example.com",
        priority: "urgent",
        status: "closed"
      }
    }

    assert %{"data" => data} = conn |> post(~p"/api/tickets", body) |> json_response(201)

    assert %{
             "subject" => "Filed",
             "priority" => "urgent",
             "status" => "new",
             "requester_email" => "zed@example.com"
           } = data

    assert Tickets.get_ticket!(data["id"]).subject == "Filed"

    assert %{"errors" => errors} =
             conn |> post(~p"/api/tickets", %{ticket: %{subject: "x"}}) |> json_response(422)

    assert Enum.sort(Map.keys(errors)) == ["body", "requester_email"]
    assert [message | _] = errors["body"]
    assert is_binary(message)

    assert length(Tickets.list_tickets()) == 1
  end

  test "POST /api/tickets/:id/transition makes a move, or refuses it", %{conn: conn} do
    ticket = ticket!()

    assert %{"data" => %{"status" => "open"}} =
             conn |> post(~p"/api/tickets/#{ticket.id}/transition", %{to: "open"}) |> json_response(200)

    assert Tickets.get_ticket!(ticket.id).status == :open

    # a move the flow refuses, the status it has, a status that is none
    for to <- ["closed", "open", "banana"] do
      assert conn |> post(~p"/api/tickets/#{ticket.id}/transition", %{to: to}) |> json_response(422) ==
               %{"error" => "invalid_transition"}
    end

    assert Tickets.get_ticket!(ticket.id).status == :open
  end

  test "the export is CSV by the book", %{conn: conn} do
    al = agent!("Smith, Al")
    {:ok, plain} = Tickets.assign(filed!(~U[2026-03-02 10:00:00Z], subject: "Plain", priority: :urgent), al)
    quoted = filed!(~U[2026-03-02 11:00:00Z], subject: ~s(He said "no", twice), priority: :high)
    lines = filed!(~U[2026-03-02 12:00:00Z], subject: "fine", body: "two\nlines", priority: :low)

    conn = get(conn, "/tickets/export.csv")
    assert response_content_type(conn, :csv) =~ "text/csv"

    body = response(conn, 200)
    assert String.ends_with?(body, "\r\n")
    assert [header | rows] = body |> String.trim_trailing("\r\n") |> String.split("\r\n")
    assert header == "id,subject,status,priority,requester_email,assignee,inserted_at"

    # the last column is a time, in whatever form the app writes one: the prompt asks ISO 8601 of
    # the API, and of the export only that it is there
    assert Enum.map(rows, &String.replace(&1, ~r/,[^,]+$/, "")) == [
             ~s(#{plain.id},Plain,open,urgent,ann@example.com,"Smith, Al"),
             ~s(#{quoted.id},"He said ""no"", twice",new,high,ann@example.com,),
             ~s(#{lines.id},fine,new,low,ann@example.com,)
           ]

    for row <- rows, do: assert(row =~ ~r/,2026-03-02[T ]1[012]:00:00/)
  end

  test "the export of no tickets is its header", %{conn: conn} do
    assert conn |> get("/tickets/export.csv") |> response(200) ==
             "id,subject,status,priority,requester_email,assignee,inserted_at\r\n"
  end

  test "the export did not take the ticket page's place", %{conn: conn} do
    ticket = ticket!(subject: "Still has a page")
    assert conn |> get(~p"/tickets/#{ticket.id}") |> html_response(200) =~ "Still has a page"
  end
end
