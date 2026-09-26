defmodule Hidden.CockpitApiTest do
  use ExUnit.Case, async: true

  # every public function Console.Cockpit had before the split, apart from the GenServer callbacks
  # `use GenServer` defines by default (child_spec, code_change, handle_*, terminate), which any
  # module keeps for free; init/1 it does not
  @api ~w(context_entry/3 delete_flash/1 drop_stale_session/2 init/1 initial_state/1 reset_scrolls/2 run/0 thread_title/1 toggle_center_view/1 typing_only?/2)

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
