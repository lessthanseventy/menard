defmodule Desk.Hidden.TicketsTest do
  use Desk.DataCase, async: false

  alias Desk.Tickets
  alias Desk.Tickets.Ticket

  @valid %{subject: "Printer on fire", body: "It is.", requester_email: "ann@example.com"}

  defp errors(attrs) do
    assert {:error, %Ecto.Changeset{} = changeset} = Tickets.create_ticket(attrs)
    Keyword.keys(changeset.errors)
  end

  test "a ticket is created new, at normal priority" do
    assert {:ok, %Ticket{} = ticket} = Tickets.create_ticket(@valid)
    assert ticket.status == :new
    assert ticket.priority == :normal
    assert %DateTime{} = ticket.inserted_at
    assert Tickets.get_ticket!(ticket.id).subject == "Printer on fire"
  end

  test "string keys are taken as atom keys are" do
    attrs = %{"subject" => "S", "body" => "B", "requester_email" => "a@b.c", "priority" => "urgent"}
    assert {:ok, %Ticket{priority: :urgent}} = Tickets.create_ticket(attrs)
  end

  test "a status given at creation is ignored" do
    assert {:ok, %Ticket{status: :new}} = Tickets.create_ticket(Map.put(@valid, :status, :closed))
    assert {:ok, %Ticket{status: :new}} = Tickets.create_ticket(Map.put(@valid, :status, "resolved"))
  end

  test "subject, body and email are required" do
    assert Enum.sort(errors(%{})) == [:body, :requester_email, :subject]
    assert errors(%{@valid | subject: "   "}) == [:subject]
  end

  test "a subject is trimmed, and is 120 characters at most once trimmed" do
    assert {:ok, %Ticket{subject: "Hello"}} = Tickets.create_ticket(%{@valid | subject: "  Hello  "})
    long = String.duplicate("x", 120)
    assert {:ok, %Ticket{subject: ^long}} = Tickets.create_ticket(%{@valid | subject: " " <> long <> " "})
    assert errors(%{@valid | subject: long <> "x"}) == [:subject]
  end

  test "an email is trimmed and lowercased, and has to look like one" do
    assert {:ok, %Ticket{requester_email: "ann@example.com"}} =
             Tickets.create_ticket(%{@valid | requester_email: "  Ann@Example.COM "})

    for bad <- ["ann", "@example.com", "ann@", "an n@example.com", "ann@@example.com", "a@b@c"] do
      assert errors(%{@valid | requester_email: bad}) == [:requester_email], "#{inspect(bad)} was taken"
    end
  end

  test "a priority that is not one is refused" do
    assert errors(Map.put(@valid, :priority, "whenever")) == [:priority]
  end

  test "get_ticket! raises for an id that is not there" do
    assert_raise Ecto.NoResultsError, fn -> Tickets.get_ticket!(123_456) end
  end

  test "the list is most urgent first, and oldest first within a priority" do
    ids =
      for priority <- [:normal, :urgent, :low, :high, :urgent, :normal] do
        {:ok, ticket} = Tickets.create_ticket(Map.put(@valid, :priority, priority))
        {priority, ticket.id}
      end

    expected =
      for wanted <- [:urgent, :high, :normal, :low], {priority, id} <- ids, priority == wanted, do: id

    assert Enum.map(Tickets.list_tickets(), & &1.id) == expected
    assert Enum.map(Tickets.list_tickets([]), & &1.id) == expected
  end

  test "the list narrows by priority and by status" do
    {:ok, a} = Tickets.create_ticket(Map.put(@valid, :priority, :high))
    {:ok, _} = Tickets.create_ticket(@valid)

    assert [%Ticket{id: id}] = Tickets.list_tickets(priority: :high)
    assert id == a.id
    assert length(Tickets.list_tickets(status: :new)) == 2
    assert Tickets.list_tickets(status: :closed) == []
    assert Tickets.list_tickets(status: :new, priority: :low) == []
  end
end
