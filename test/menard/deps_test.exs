defmodule Menard.DepsTest do
  # What a function references — the read that answers "can this move?".
  use ExUnit.Case, async: true

  alias Menard.Deps

  @src """
  defmodule A do
    alias App.Cat

    @timeout 5_000

    def go(x) do
      shared(x) + only_mine(x) + Sourceror.get_range(x) + Cat.purr()
    end

    def other(x), do: shared(x) + @timeout

    defp shared(x), do: x
    defp only_mine(x), do: x
  end
  """

  test "a local helper nothing else calls is free to move" do
    report = Deps.of(@src, "go/1")
    assert %{call: "only_mine/1", shared_with: []} = Enum.find(report.locals, &(&1.call == "only_mine/1"))
  end

  test "a local helper another function shares CANNOT move, and it names who else needs it" do
    report = Deps.of(@src, "go/1")
    assert %{call: "shared/1", shared_with: ["other/1"]} = Enum.find(report.locals, &(&1.call == "shared/1"))
  end

  test "reports the remote calls and the modules whose aliases must travel" do
    report = Deps.of(@src, "go/1")

    assert "Sourceror.get_range/1" in report.remotes
    assert "Cat" in report.modules
    assert "Sourceror" in report.modules
  end

  test "reports the attributes it reads — those do NOT travel with the code" do
    assert Deps.of(@src, "other/1").attributes == [:timeout]
    assert Deps.of(@src, "go/1").attributes == []
  end

  test "Kernel and the special forms are not reported as local calls" do
    calls = Enum.map(Deps.of(@src, "go/1").locals, & &1.call)

    refute "+/2" in calls
    assert "shared/1" in calls
  end

  test "a function that isn't there is an error naming what is" do
    assert {:error, message} = Deps.of(@src, "nope/9")
    assert message =~ "go/1"
  end

  test "a `__MODULE__.X` reference is reported, not a crash" do
    src = """
    defmodule A do
      def go, do: __MODULE__.Inner.x()
    end
    """

    assert %{remotes: ["__MODULE__.Inner.x/0"], modules: ["__MODULE__.Inner"]} = Deps.of(src, "go/0")
  end
end
