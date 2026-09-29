defmodule Desk.Hidden.ApiKeptTest do
  use ExUnit.Case, async: true

  # what Desk.Tickets answered to before the split, by the tickets that asked for each
  @kept [
    create_ticket: 1,
    get_ticket!: 1,
    list_tickets: 0,
    list_tickets: 1,
    allowed_transitions: 1,
    change_status: 3,
    list_events: 1,
    assign: 2,
    unassign: 1,
    auto_assign: 1,
    add_comment: 2,
    list_comments: 1,
    list_comments: 2,
    list_breached: 1
  ]

  test "Desk.Tickets still answers to every function it had" do
    Code.ensure_loaded!(Desk.Tickets)
    missing = for {name, arity} <- @kept, not function_exported?(Desk.Tickets, name, arity), do: "#{name}/#{arity}"
    assert missing == []
    refute function_exported?(Desk.Tickets, :transition, 2)
  end
end
