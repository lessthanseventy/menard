defmodule Hidden.SwitcherTitlesTest do
  use ExUnit.Case, async: true

  alias Console.Fuzzy
  alias Console.Picker

  @sidebar [
    %{
      workspace: %{id: 1, name: "Machine"},
      projects: [%{id: 7, name: "Tlön"}],
      threads: [
        %{id: 11, title: "rail redesign", project_id: 7},
        %{id: 12, title: "cockpit slice", project_id: 7}
      ]
    }
  ]

  defp labels(query),
    do:
      Picker.entries(%{kind: :switcher, query: query, cursor: 0}, %{sidebar: @sidebar})
      |> Enum.map(& &1.label)

  test "a thread is found by part of its title" do
    assert "rail redesign" in labels("redesign")
  end

  test "a thread is found by its title's initials, however long the path in front of it" do
    assert hd(labels("rr")) == "rail redesign"
  end

  test "a scattered match far down a long subject is still a match" do
    assert Fuzzy.filter(["Machine · Tlön · rail redesign"], "rr") == ["Machine · Tlön · rail redesign"]
  end
end
