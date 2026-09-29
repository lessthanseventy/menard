defmodule Desk.Hidden.LiveTest do
  use DeskWeb.ConnCase, async: false

  import Desk.Hidden
  import Phoenix.LiveViewTest

  alias Desk.Tickets

  # the ids of the tickets listed, in the page's order
  defp listed(html) do
    ~r/id="ticket-(\d+)"/
    |> Regex.scan(html, capture: :all_but_first)
    |> List.flatten()
    |> Enum.map(&String.to_integer/1)
  end

  test "the list holds every ticket, in list_tickets' order, with its subject and status", %{conn: conn} do
    low = ticket!(subject: "Low thing", priority: :low)
    urgent = ticket!(subject: "Urgent thing", priority: :urgent)
    open = through!(ticket!(subject: "Open thing"), [:open])

    {:ok, view, html} = live(conn, ~p"/tickets")
    assert listed(html) == [urgent.id, open.id, low.id]
    assert view |> element("#ticket-#{open.id}") |> render() =~ "Open thing"
    assert view |> element("#ticket-#{open.id}") |> render() =~ "open"
    assert view |> element("#ticket-#{low.id}") |> render() =~ "new"
    assert html =~ ~s(href="/tickets/new")
  end

  test "the status filter narrows the list, and its empty value is all of it", %{conn: conn} do
    new = ticket!()
    open = through!(ticket!(), [:open])

    {:ok, view, _html} = live(conn, ~p"/tickets")
    assert view |> form("#filters", %{status: "open"}) |> render_change() |> listed() == [open.id]
    assert view |> form("#filters", %{status: "closed"}) |> render_change() |> listed() == []

    assert view |> form("#filters", %{status: ""}) |> render_change() |> listed() |> Enum.sort() ==
             Enum.sort([new.id, open.id])
  end

  test "the form files a ticket and goes to its page", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/tickets/new")

    view
    |> form("#ticket-form", %{
      ticket: %{subject: "From the form", body: "B", requester_email: "zed@example.com", priority: "high"}
    })
    |> render_submit()

    assert [ticket] = Tickets.list_tickets()
    assert %{subject: "From the form", priority: :high, status: :new} = ticket
    assert_redirect(view, "/tickets/#{ticket.id}")
  end

  test "an invalid ticket stays on the form, with its errors", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/tickets/new")

    html =
      view
      |> form("#ticket-form", %{ticket: %{subject: "", body: "B", requester_email: "nope"}})
      |> render_submit()

    # the errors are the changeset's, whatever the app has them say
    assert {:error, changeset} = Tickets.create_ticket(%{subject: "", body: "B", requester_email: "nope"})

    messages =
      for {_field, {message, _opts}} <- changeset.errors,
          do: message |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

    assert Enum.any?(messages, &(html =~ &1)), "none of #{inspect(messages)} is on the page"
    assert has_element?(view, "#ticket-form")
    assert Tickets.list_tickets() == []
  end

  test "a ticket's page offers the moves it may make, and makes the one clicked", %{conn: conn} do
    ticket = through!(ticket!(), [:open])
    {:ok, view, _html} = live(conn, ~p"/tickets/#{ticket.id}")

    assert view |> element("#ticket-status") |> render() =~ "open"
    assert has_element?(view, "#transition-pending")
    assert has_element?(view, "#transition-resolved")
    refute has_element?(view, "#transition-open")
    refute has_element?(view, "#transition-closed")

    view |> element("#transition-resolved") |> render_click()
    assert Tickets.get_ticket!(ticket.id).status == :resolved
    assert view |> element("#ticket-status") |> render() =~ "resolved"
    assert has_element?(view, "#transition-closed")
    assert has_element?(view, "#transition-open")
    refute has_element?(view, "#transition-pending")

    view |> element("#transition-closed") |> render_click()
    for status <- ~w(open pending resolved closed), do: refute(has_element?(view, "#transition-#{status}"))
  end

  test "the page names the assignee, and auto-assign gives it one", %{conn: conn} do
    al = agent!("Al Assigned")
    ticket = ticket!()
    {:ok, view, _html} = live(conn, ~p"/tickets/#{ticket.id}")
    assert view |> element("#assignee") |> render() =~ "Unassigned"

    view |> element("#auto-assign") |> render_click()
    assert Tickets.get_ticket!(ticket.id).assignee_id == al.id
    assert view |> element("#assignee") |> render() =~ "Al Assigned"
    # assigned, a new ticket is open
    assert view |> element("#ticket-status") |> render() =~ "open"
  end

  test "the comment form adds the agent's comment, and the page shows what it did", %{conn: conn} do
    al = agent!("Al")
    {:ok, gone} = Desk.Staff.deactivate_agent(agent!("Gone Agent"))
    ticket = through!(ticket!(), [:open])
    {:ok, %{comment: first}} = Tickets.add_comment(ticket, %{author_kind: :requester, body: "First words"})

    {:ok, view, html} = live(conn, ~p"/tickets/#{ticket.id}")
    assert view |> element("#comments #comment-#{first.id}") |> render() =~ "First words"
    # the agents to pick from are the active ones
    # in the select, not anywhere on the page: an id is a small number, and a page has many
    agents = view |> element(~s(#comment-form select[name="comment[agent_id]"])) |> render()
    assert agents =~ ~s(value="#{al.id}")
    refute agents =~ ~s(value="#{gone.id}")
    assert html =~ "First words"

    view
    |> form("#comment-form", %{comment: %{body: "A note between us", agent_id: al.id, internal: "true"}})
    |> render_submit()

    view
    |> form("#comment-form", %{comment: %{body: "Have you tried", agent_id: al.id, internal: "false"}})
    |> render_submit()

    assert [^first, note, reply] = Tickets.list_comments(ticket)
    assert %{internal: true, author_kind: :agent, body: "A note between us"} = note
    assert %{internal: false, agent_id: agent_id, body: "Have you tried"} = reply
    assert agent_id == al.id

    html = render(view)
    assert html =~ "A note between us"

    assert ~r/id="comment-(\d+)"/ |> Regex.scan(html, capture: :all_but_first) |> List.flatten() ==
             Enum.map([first, note, reply], &"#{&1.id}")

    # the public comment made the ticket pending
    assert view |> element("#ticket-status") |> render() =~ "pending"
    assert has_element?(view, "#transition-open")
  end
end
