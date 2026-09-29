defmodule Desk.Hidden.ActorTest do
  use DeskWeb.ConnCase, async: false

  import Desk.Hidden
  import Phoenix.LiveViewTest

  alias Desk.Staff
  alias Desk.Tickets

  defp actors(ticket), do: for(e <- Tickets.list_events(ticket), do: {e.kind, e.to, e.actor})

  test "transition/2 is gone, and change_status/3 is what moves a ticket" do
    Code.ensure_loaded!(Tickets)
    refute function_exported?(Tickets, :transition, 2)
    assert function_exported?(Tickets, :change_status, 3)
    refute function_exported?(Tickets, :change_status, 2)
  end

  test "nothing in the app calls transition/2 any more, and no ticket module defines it" do
    for file <- Path.wildcard("lib/**/*.{ex,heex}"), source = File.read!(file) do
      refute source =~ ~r/Tickets\.transition\(/, "#{file} calls Tickets.transition"
    end

    # a controller's action may well be named for its route: the context's function may not
    for file <- Path.wildcard("lib/desk/**/*.ex"), source = File.read!(file) do
      refute source =~ ~r/defp? transition\(/, "#{file} defines transition"
    end
  end

  test "change_status keeps the rules, and records who moved it" do
    al = agent!("Al")
    ticket = ticket!()

    assert {:error, :invalid_transition} = Tickets.change_status(ticket, :closed, :system)
    assert {:ok, ticket} = Tickets.change_status(ticket, :open, {:agent, al.id})
    assert {:ok, ticket} = Tickets.change_status(ticket, :resolved, :system)
    assert %DateTime{} = ticket.resolved_at
    assert {:ok, ticket} = Tickets.change_status(ticket, :open, :requester)
    assert ticket.resolved_at == nil

    assert actors(ticket) == [
             {"created", "new", "system"},
             {"status", "open", "agent:#{al.id}"},
             {"status", "resolved", "system"},
             {"status", "open", "requester"}
           ]
  end

  test "a move a comment made is its author's" do
    al = agent!("Al")
    ticket = ticket!()
    {:ok, %{ticket: ticket}} = Tickets.add_comment(ticket, %{author_kind: :agent, agent_id: al.id, body: "b"})
    {:ok, %{ticket: ticket}} = Tickets.add_comment(ticket, %{author_kind: :requester, body: "b"})

    assert actors(ticket) == [
             {"created", "new", "system"},
             {"status", "pending", "agent:#{al.id}"},
             {"status", "open", "requester"}
           ]
  end

  test "what assignment records is the system's" do
    al = agent!("Al")
    bo = agent!("Bo")
    {:ok, ticket} = Tickets.assign(ticket!(), al)
    {:ok, ticket} = Tickets.unassign(ticket)
    {:ok, ticket} = Tickets.auto_assign(ticket)
    {:ok, _} = Tickets.assign(ticket, bo)
    {:ok, _} = Staff.deactivate_agent(bo)

    events = Tickets.list_events(ticket)
    assert length(events) >= 6

    for event <- events,
        do: assert(event.actor == "system", "#{event.kind} has actor #{inspect(event.actor)}")
  end

  test "the API's move is the agent's when it names one, else the system's", %{conn: conn} do
    al = agent!("Al")
    ticket = ticket!()

    assert %{"data" => %{"status" => "open"}} =
             conn
             |> post(~p"/api/tickets/#{ticket.id}/transition", %{to: "open", agent_id: al.id})
             |> json_response(200)

    assert %{"data" => %{"status" => "resolved"}} =
             conn |> post(~p"/api/tickets/#{ticket.id}/transition", %{to: "resolved"}) |> json_response(200)

    assert conn
           |> post(~p"/api/tickets/#{ticket.id}/transition", %{to: "pending", agent_id: al.id})
           |> json_response(422) ==
             %{"error" => "invalid_transition"}

    assert [_, {"status", "open", agent}, {"status", "resolved", "system"}] = actors(ticket)
    assert agent == "agent:#{al.id}"
  end

  test "the page's buttons move a ticket as the system", %{conn: conn} do
    ticket = ticket!()
    {:ok, view, _html} = live(conn, ~p"/tickets/#{ticket.id}")
    view |> element("#transition-open") |> render_click()
    assert List.last(actors(ticket)) == {"status", "open", "system"}
  end
end
