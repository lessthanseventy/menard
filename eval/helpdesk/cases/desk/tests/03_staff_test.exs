defmodule Desk.Hidden.StaffTest do
  use Desk.DataCase, async: false

  import Desk.Hidden

  alias Desk.Staff
  alias Desk.Staff.Agent
  alias Desk.Tickets

  defp kinds(ticket), do: for(e <- Tickets.list_events(ticket), do: {e.kind, e.from, e.to})

  test "an agent is active, its email lowercased and its own" do
    assert {:ok, %Agent{active: true, email: "bo@desk.example"} = bo} =
             Staff.create_agent(%{name: "Bo", email: " Bo@Desk.Example "})

    assert Staff.get_agent!(bo.id).name == "Bo"
    assert {:error, changeset} = Staff.create_agent(%{"name" => "Other", "email" => "BO@desk.example"})
    assert Keyword.keys(changeset.errors) == [:email]
    assert {:error, changeset} = Staff.create_agent(%{})
    assert Enum.sort(Keyword.keys(changeset.errors)) == [:email, :name]
  end

  test "agents are listed by name" do
    for name <- ["Cy", "Al", "Bo"], do: agent!(name)
    assert Enum.map(Staff.list_agents(), & &1.name) == ["Al", "Bo", "Cy"]
  end

  test "assigning a new ticket opens it, and both are recorded" do
    al = agent!("Al")
    ticket = ticket!()

    assert {:ok, assigned} = Tickets.assign(ticket, al)
    assert assigned.assignee_id == al.id
    assert assigned.status == :open

    assert Enum.sort(kinds(ticket)) ==
             Enum.sort([
               {"created", nil, "new"},
               {"status", "new", "open"},
               {"assigned", nil, "#{al.id}"}
             ])
  end

  test "an assignment moves no ticket that is past new, and says whose it was" do
    al = agent!("Al")
    bo = agent!("Bo")
    {:ok, ticket} = Tickets.assign(through!(ticket!(), [:open, :pending]), al)
    assert ticket.status == :pending

    assert {:ok, ticket} = Tickets.assign(ticket, bo)
    assert ticket.assignee_id == bo.id
    assert {"assigned", "#{al.id}", "#{bo.id}"} in kinds(ticket)
  end

  test "an inactive agent and a closed ticket are refused" do
    al = agent!("Al")
    {:ok, gone} = Staff.deactivate_agent(agent!("Bo"))
    refute gone.active

    assert {:error, :inactive_agent} = Tickets.assign(ticket!(), gone)
    closed = through!(ticket!(), [:open, :resolved, :closed])
    assert {:error, :closed} = Tickets.assign(closed, al)
    assert Tickets.get_ticket!(closed.id).assignee_id == nil
  end

  test "unassign takes the assignee off and records it, once" do
    al = agent!("Al")
    {:ok, ticket} = Tickets.assign(ticket!(), al)

    assert {:ok, free} = Tickets.unassign(ticket)
    assert free.assignee_id == nil
    assert {"unassigned", "#{al.id}", nil} in kinds(ticket)

    before = length(Tickets.list_events(ticket))
    assert {:ok, still} = Tickets.unassign(free)
    assert still.assignee_id == nil
    assert length(Tickets.list_events(ticket)) == before
  end

  test "auto_assign takes the active agent with the fewest tickets at work, the lowest id among equals" do
    assert {:error, :no_agents} = Tickets.auto_assign(ticket!())

    al = agent!("Al")
    bo = agent!("Bo")
    cy = agent!("Cy")

    assert {:ok, %{assignee_id: first}} = Tickets.auto_assign(ticket!())
    assert first == al.id
    assert {:ok, %{assignee_id: second}} = Tickets.auto_assign(ticket!())
    assert second == bo.id

    # a resolved ticket is no load: Cy has one resolved, and is still the least loaded
    {:ok, done} = Tickets.assign(ticket!(), cy)
    through!(done, [:resolved])
    assert {:ok, %{assignee_id: third}} = Tickets.auto_assign(ticket!())
    assert third == cy.id

    # all at one: the lowest id
    assert {:ok, %{assignee_id: fourth}} = Tickets.auto_assign(ticket!())
    assert fourth == al.id

    {:ok, _} = Staff.deactivate_agent(bo)
    {:ok, _} = Staff.deactivate_agent(cy)
    {:ok, _} = Staff.deactivate_agent(al)
    assert {:error, :no_agents} = Tickets.auto_assign(ticket!())
  end

  test "deactivating an agent frees their tickets at work, and leaves the finished ones theirs" do
    al = agent!("Al")
    {:ok, open} = Tickets.assign(ticket!(), al)
    {:ok, pending} = Tickets.assign(through!(ticket!(), [:open, :pending]), al)
    {:ok, resolved} = Tickets.assign(ticket!(), al)
    resolved = through!(resolved, [:resolved])
    {:ok, closed} = Tickets.assign(ticket!(), al)
    closed = through!(closed, [:resolved, :closed])

    assert {:ok, %Agent{active: false}} = Staff.deactivate_agent(al)

    assert Tickets.get_ticket!(open.id).assignee_id == nil
    assert Tickets.get_ticket!(pending.id).assignee_id == nil
    assert Tickets.get_ticket!(resolved.id).assignee_id == al.id
    assert Tickets.get_ticket!(closed.id).assignee_id == al.id
    # its status is what it was
    assert Tickets.get_ticket!(pending.id).status == :pending
  end

  test "the list narrows by assignee, and to the tickets with none" do
    al = agent!("Al")
    bo = agent!("Bo")
    {:ok, a} = Tickets.assign(ticket!(), al)
    {:ok, b} = Tickets.assign(ticket!(), bo)
    c = ticket!()

    assert Enum.map(Tickets.list_tickets(assignee: al.id), & &1.id) == [a.id]
    assert Enum.map(Tickets.list_tickets(assignee: bo.id, status: :open), & &1.id) == [b.id]
    assert Enum.map(Tickets.list_tickets(assignee: :none), & &1.id) == [c.id]
    assert length(Tickets.list_tickets()) == 3
  end
end
