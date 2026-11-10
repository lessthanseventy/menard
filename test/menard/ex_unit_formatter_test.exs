defmodule Menard.ExUnitFormatterTest do
  # The formatter `run test` requires into a host's VM (priv/ex_unit_formatter.exs), by its
  # callbacks: what it leaves in its file is the whole of what the reply says of the tests.
  use ExUnit.Case, async: true

  @moduletag :tmp_dir

  # required into the VM below, not compiled with the project: named so the compiler does not look
  @formatter Menard.ExUnitFormatter

  setup_all do
    if not Code.ensure_loaded?(Menard.ExUnitFormatter),
      do: Code.require_file(Application.app_dir(:menard, "priv/ex_unit_formatter.exs"))

    :ok
  end

  test "a snapshot due as the suite ends does not write the emptied state over the suite's", %{tmp_dir: dir} do
    out = Path.join(dir, "held")
    {:ok, state} = @formatter.init([])
    state = %{state | out: out, tests: 3, failed: 1}

    {:noreply, state} = @formatter.handle_cast({:suite_finished, %{}}, state)
    {:noreply, _state} = @formatter.handle_info(:snapshot, state)

    assert %{tests: 3, failed: 1} = out |> File.read!() |> :erlang.binary_to_term()
  end
end
