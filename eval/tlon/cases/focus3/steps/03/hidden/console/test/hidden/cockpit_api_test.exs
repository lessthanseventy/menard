defmodule Hidden.CockpitApiTest do
  use ExUnit.Case, async: true

  # every public function Console.Cockpit had before the split
  @api ~w(child_spec/1 code_change/3 context_entry/3 delete_flash/1 drop_stale_session/2 handle_call/3 handle_cast/2 handle_info/2 init/1 initial_state/1 reset_scrolls/2 run/0 terminate/2 thread_title/1 toggle_center_view/1 typing_only?/2)

  test "the split keeps Console.Cockpit's public functions" do
    Code.ensure_loaded!(Console.Cockpit)

    missing =
      for fa <- @api,
          [name, arity] = String.split(fa, "/"),
          not function_exported?(Console.Cockpit, String.to_atom(name), String.to_integer(arity)),
          do: fa

    assert missing == []
  end
end
