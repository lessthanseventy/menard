defmodule Desk.Hidden.SLATest do
  use Desk.DataCase, async: false

  import Desk.Hidden

  alias Desk.SLA
  alias Desk.Tickets

  # 2026-03-02 is a Monday
  test "the targets" do
    assert for(p <- [:urgent, :high, :normal, :low], do: SLA.target_minutes(p)) == [60, 240, 480, 1440]
  end

  test "business minutes, inside one day" do
    assert SLA.add_business_minutes(~U[2026-03-02 09:00:00Z], 0) == ~U[2026-03-02 09:00:00Z]
    assert SLA.add_business_minutes(~U[2026-03-02 09:00:00Z], 60) == ~U[2026-03-02 10:00:00Z]
    assert SLA.add_business_minutes(~U[2026-03-02 13:15:30Z], 90) == ~U[2026-03-02 14:45:30Z]
  end

  test "a result at closing time is that day's 17:00" do
    assert SLA.add_business_minutes(~U[2026-03-02 09:00:00Z], 480) == ~U[2026-03-02 17:00:00Z]
    assert SLA.add_business_minutes(~U[2026-03-02 16:00:00Z], 60) == ~U[2026-03-02 17:00:00Z]
  end

  test "what does not fit the day goes on the next morning" do
    assert SLA.add_business_minutes(~U[2026-03-02 16:00:00Z], 61) == ~U[2026-03-03 09:01:00Z]
    assert SLA.add_business_minutes(~U[2026-03-02 16:30:00Z], 240) == ~U[2026-03-03 12:30:00Z]
    assert SLA.add_business_minutes(~U[2026-03-02 16:59:30Z], 1) == ~U[2026-03-03 09:00:30Z]
  end

  test "time outside business hours does not count" do
    # before opening, after closing, and at closing itself
    assert SLA.add_business_minutes(~U[2026-03-02 06:00:00Z], 60) == ~U[2026-03-02 10:00:00Z]
    assert SLA.add_business_minutes(~U[2026-03-02 20:00:00Z], 60) == ~U[2026-03-03 10:00:00Z]
    assert SLA.add_business_minutes(~U[2026-03-02 17:00:00Z], 30) == ~U[2026-03-03 09:30:00Z]
    assert SLA.add_business_minutes(~U[2026-03-02 20:10:45Z], 0) == ~U[2026-03-03 09:00:00Z]
  end

  test "a weekend is skipped, from inside it and across it" do
    # Saturday noon, Sunday night
    assert SLA.add_business_minutes(~U[2026-03-07 12:00:00Z], 60) == ~U[2026-03-09 10:00:00Z]
    assert SLA.add_business_minutes(~U[2026-03-08 23:59:59Z], 480) == ~U[2026-03-09 17:00:00Z]
    # Friday afternoon into Monday
    assert SLA.add_business_minutes(~U[2026-03-06 16:00:00Z], 120) == ~U[2026-03-09 10:00:00Z]
    assert SLA.add_business_minutes(~U[2026-03-06 18:00:00Z], 1) == ~U[2026-03-09 09:01:00Z]
  end

  test "three business days, over a weekend and a month's end" do
    assert SLA.add_business_minutes(~U[2026-03-02 09:00:00Z], 1440) == ~U[2026-03-04 17:00:00Z]
    assert SLA.add_business_minutes(~U[2026-03-05 11:00:00Z], 1440) == ~U[2026-03-10 11:00:00Z]
    assert SLA.add_business_minutes(~U[2026-02-27 15:00:00Z], 1440) == ~U[2026-03-04 15:00:00Z]
  end

  test "a ticket is due its priority's target after it was filed" do
    assert SLA.due_at(filed!(~U[2026-03-02 10:00:00Z], priority: :urgent)) == ~U[2026-03-02 11:00:00Z]
    assert SLA.due_at(filed!(~U[2026-03-02 10:00:00Z], priority: :high)) == ~U[2026-03-02 14:00:00Z]
    assert SLA.due_at(filed!(~U[2026-03-02 10:00:00Z])) == ~U[2026-03-03 10:00:00Z]
    assert SLA.due_at(filed!(~U[2026-03-06 10:00:00Z], priority: :low)) == ~U[2026-03-11 10:00:00Z]
  end

  test "breached: no response by the time it is due, or one that came after" do
    ticket = filed!(~U[2026-03-02 10:00:00Z], priority: :urgent)

    refute SLA.breached?(ticket, ~U[2026-03-02 10:30:00Z])
    refute SLA.breached?(ticket, ~U[2026-03-02 11:00:00Z])
    assert SLA.breached?(ticket, ~U[2026-03-02 11:00:01Z])

    in_time = %{ticket | first_response_at: ~U[2026-03-02 11:00:00Z]}
    refute SLA.breached?(in_time, ~U[2026-03-09 09:00:00Z])
    late = %{ticket | first_response_at: ~U[2026-03-02 11:00:01Z]}
    assert SLA.breached?(late, ~U[2026-03-02 10:00:00Z])
  end

  test "list_breached: the tickets at work that are breached, the earliest due first" do
    now = ~U[2026-03-04 12:00:00Z]
    low = filed!(~U[2026-03-02 09:00:00Z], priority: :low)
    normal = filed!(~U[2026-03-02 09:30:00Z])
    urgent = filed!(~U[2026-03-03 16:00:00Z], priority: :urgent)
    _not_yet = filed!(~U[2026-03-04 11:30:00Z], priority: :urgent)

    # breached, and finished: not listed
    through!(filed!(~U[2026-03-02 09:00:00Z], priority: :urgent), [:open, :resolved])
    # answered in time: not breached
    answered = filed!(~U[2026-03-02 09:00:00Z], priority: :urgent)
    answered |> Ecto.Changeset.change(first_response_at: ~U[2026-03-02 09:20:00Z]) |> Desk.Repo.update!()
    # answered late, and still at work: breached for good
    late = filed!(~U[2026-03-02 09:00:00Z], priority: :high)
    late |> Ecto.Changeset.change(first_response_at: ~U[2026-03-02 14:00:00Z]) |> Desk.Repo.update!()

    # due: late Mon 13:00, normal Mon 17:30 -> Tue 09:30, urgent Tue 17:00, low Wed 17:00 (not yet)
    assert Enum.map(Tickets.list_breached(now), & &1.id) == [late.id, normal.id, urgent.id]
    assert low.id in Enum.map(Tickets.list_breached(~U[2026-03-04 17:00:01Z]), & &1.id)
    # a response that came late is late whatever the time asked about; nothing else is, this early
    assert Enum.map(Tickets.list_breached(~U[2026-03-02 09:00:00Z]), & &1.id) == [late.id]
  end
end
