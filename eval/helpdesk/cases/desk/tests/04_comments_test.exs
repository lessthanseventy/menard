defmodule Desk.Hidden.CommentsTest do
  use Desk.DataCase, async: false

  import Desk.Hidden

  alias Desk.Tickets
  alias Desk.Tickets.Comment

  defp agent_says(ticket, agent, attrs \\ %{}) do
    Tickets.add_comment(ticket, Map.merge(%{author_kind: :agent, agent_id: agent.id, body: "On it."}, attrs))
  end

  defp requester_says(ticket, attrs \\ %{}) do
    Tickets.add_comment(ticket, Map.merge(%{author_kind: :requester, body: "Still broken."}, attrs))
  end

  defp moves(ticket), do: for(e <- Tickets.list_events(ticket), e.kind == "status", do: {e.from, e.to})

  test "a comment comes back with the ticket as it left it" do
    al = agent!("Al")
    ticket = ticket!()

    assert {:ok, %{comment: %Comment{} = comment, ticket: after_it}} = agent_says(ticket, al)
    assert comment.ticket_id == ticket.id
    assert comment.author_kind == :agent
    assert comment.agent_id == al.id
    assert comment.internal == false
    assert after_it.id == ticket.id
    assert after_it.status == :pending
  end

  test "string keys are taken as atom keys are" do
    al = agent!("Al")

    assert {:ok, %{comment: %Comment{internal: true, author_kind: :agent}}} =
             Tickets.add_comment(ticket!(), %{
               "author_kind" => "agent",
               "agent_id" => al.id,
               "body" => "note",
               "internal" => "true"
             })
  end

  test "an agent's public comment on a new or an open ticket makes it pending" do
    al = agent!("Al")

    for path <- [[], [:open]] do
      ticket = through!(ticket!(), path)
      from = Atom.to_string(ticket.status)
      assert {:ok, %{ticket: %{status: :pending}}} = agent_says(ticket, al)
      assert Tickets.get_ticket!(ticket.id).status == :pending
      assert List.last(moves(ticket)) == {from, "pending"}
    end
  end

  test "an agent's public comment moves no ticket that is pending or resolved" do
    al = agent!("Al")

    for path <- [[:open, :pending], [:open, :resolved]] do
      ticket = through!(ticket!(), path)
      before = moves(ticket)
      assert {:ok, %{ticket: after_it}} = agent_says(ticket, al)
      assert after_it.status == ticket.status
      assert moves(ticket) == before
    end
  end

  test "a requester's comment on a pending or a resolved ticket opens it" do
    pending = through!(ticket!(), [:open, :pending])
    assert {:ok, %{ticket: %{status: :open}}} = requester_says(pending)
    assert List.last(moves(pending)) == {"pending", "open"}

    resolved = through!(ticket!(), [:open, :resolved])
    assert %DateTime{} = resolved.resolved_at
    assert {:ok, %{ticket: %{status: :open, resolved_at: nil}}} = requester_says(resolved)
    assert Tickets.get_ticket!(resolved.id).resolved_at == nil
    assert List.last(moves(resolved)) == {"resolved", "open"}
  end

  test "a requester's comment moves no ticket that is new or open" do
    for path <- [[], [:open]] do
      ticket = through!(ticket!(), path)
      assert {:ok, %{ticket: after_it}} = requester_says(ticket)
      assert after_it.status == ticket.status
    end
  end

  test "an internal note moves nothing, and is an agent's alone" do
    al = agent!("Al")
    ticket = through!(ticket!(), [:open])

    assert {:ok, %{comment: %{internal: true}, ticket: %{status: :open}}} =
             agent_says(ticket, al, %{internal: true})

    assert Tickets.get_ticket!(ticket.id).first_response_at == nil

    assert {:error, %Ecto.Changeset{} = changeset} = requester_says(ticket, %{internal: true})
    assert Keyword.keys(changeset.errors) == [:internal]
    assert length(Tickets.list_comments(ticket)) == 1
  end

  test "a comment needs a body, a kind of author, and an agent when it is an agent's" do
    ticket = ticket!()
    assert {:error, %Ecto.Changeset{} = changeset} = Tickets.add_comment(ticket, %{})
    assert :body in Keyword.keys(changeset.errors)
    assert :author_kind in Keyword.keys(changeset.errors)

    assert {:error, %Ecto.Changeset{} = changeset} =
             Tickets.add_comment(ticket, %{author_kind: :agent, body: "b"})

    assert Keyword.keys(changeset.errors) == [:agent_id]

    assert Tickets.get_ticket!(ticket.id).status == :new
    assert Tickets.list_comments(ticket) == []
  end

  test "a closed ticket takes no comment of any kind" do
    al = agent!("Al")
    closed = through!(ticket!(), [:open, :resolved, :closed])

    assert {:error, :closed} = agent_says(closed, al)
    assert {:error, :closed} = agent_says(closed, al, %{internal: true})
    assert {:error, :closed} = requester_says(closed)
    assert Tickets.list_comments(closed) == []
  end

  test "first_response_at is the first public comment from an agent, and stays" do
    al = agent!("Al")
    ticket = ticket!()
    assert ticket.first_response_at == nil

    {:ok, %{ticket: ticket}} = requester_says(ticket)
    assert ticket.first_response_at == nil
    {:ok, %{ticket: ticket}} = agent_says(ticket, al, %{internal: true})
    assert ticket.first_response_at == nil

    {:ok, %{ticket: ticket}} = agent_says(ticket, al)
    assert %DateTime{} = first = ticket.first_response_at

    # set by hand to a time no later comment could give it
    past = ~U[2020-01-01 10:00:00Z]
    ticket |> Ecto.Changeset.change(first_response_at: past) |> Desk.Repo.update!()
    {:ok, %{ticket: ticket}} = agent_says(Tickets.get_ticket!(ticket.id), al)
    assert ticket.first_response_at == past
    assert first != past
  end

  test "comments are listed oldest first, the internal ones left out when asked" do
    al = agent!("Al")
    ticket = ticket!()
    {:ok, %{comment: a}} = requester_says(ticket, %{body: "one"})
    {:ok, %{comment: b}} = agent_says(ticket, al, %{body: "two", internal: true})
    {:ok, %{comment: c}} = agent_says(ticket, al, %{body: "three"})

    assert Enum.map(Tickets.list_comments(ticket), & &1.id) == [a.id, b.id, c.id]
    assert Enum.map(Tickets.list_comments(ticket, internal: false), & &1.id) == [a.id, c.id]
    assert Tickets.list_comments(ticket!()) == []
  end
end
