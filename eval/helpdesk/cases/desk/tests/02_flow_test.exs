defmodule Desk.Hidden.FlowTest do
  use Desk.DataCase, async: false

  import Desk.Hidden

  alias Desk.Tickets

  @statuses [:new, :open, :pending, :resolved, :closed]
  @allowed %{
    new: [:open],
    open: [:pending, :resolved],
    pending: [:open, :resolved],
    resolved: [:open, :closed],
    closed: []
  }
  # the moves that put a new ticket in each status
  @path %{
    new: [],
    open: [:open],
    pending: [:open, :pending],
    resolved: [:open, :resolved],
    closed: [:open, :resolved, :closed]
  }

  test "every move the table allows is made, and every other refused" do
    for from <- @statuses, to <- @statuses do
      ticket = through!(ticket!(), @path[from])
      assert ticket.status == from

      if to in @allowed[from] do
        assert {:ok, moved} = move(ticket, to)
        assert moved.status == to
        assert Tickets.get_ticket!(ticket.id).status == to
      else
        assert {:error, :invalid_transition} = move(ticket, to), "#{from} -> #{to} was made"
        assert Tickets.get_ticket!(ticket.id).status == from
      end
    end
  end

  test "allowed_transitions is the table, in the order open, pending, resolved, closed" do
    for from <- @statuses, do: assert(Tickets.allowed_transitions(from) == @allowed[from])
  end

  test "resolved_at is set on resolving, kept on closing, cleared on reopening" do
    ticket = ticket!()
    assert ticket.resolved_at == nil and ticket.closed_at == nil

    resolved = through!(ticket, [:open, :resolved])
    assert %DateTime{} = resolved.resolved_at
    assert resolved.closed_at == nil

    reopened = through!(resolved, [:open])
    assert reopened.resolved_at == nil
    assert Tickets.get_ticket!(ticket.id).resolved_at == nil

    closed = through!(reopened, [:resolved, :closed])
    assert %DateTime{} = closed.resolved_at
    assert %DateTime{} = closed.closed_at
  end

  test "a ticket's events are its creation and each move made, oldest first" do
    ticket = through!(ticket!(), [:open, :pending])
    assert {:error, :invalid_transition} = move(ticket, :closed)
    through!(ticket, [:resolved])

    assert for(e <- Tickets.list_events(ticket), do: {e.kind, e.from, e.to}) == [
             {"created", nil, "new"},
             {"status", "new", "open"},
             {"status", "open", "pending"},
             {"status", "pending", "resolved"}
           ]
  end

  test "one ticket's events are not another's" do
    a = through!(ticket!(), [:open])
    b = ticket!()
    assert length(Tickets.list_events(a)) == 2
    assert [%{kind: "created", ticket_id: id}] = Tickets.list_events(b)
    assert id == b.id
  end
end
