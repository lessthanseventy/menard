defmodule Acme.EventsTest do
  use ExUnit.Case, async: true

  alias Acme.Events

  test "a charge's row names its source as it always has" do
    assert %{"source" => "Acme.Billing", "amount" => 700} =
             Events.record(Acme.Billing.charge("acct", 700))
  end

  test "a stored row reads back" do
    assert {:charge, "ch_1", 700} =
             Events.from_row(%{"source" => "Acme.Billing", "id" => "ch_1", "amount" => 700})

    assert {:unknown, "Acme.Other"} = Events.from_row(%{"source" => "Acme.Other"})
  end
end
