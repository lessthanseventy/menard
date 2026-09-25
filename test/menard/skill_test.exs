defmodule Menard.SkillTest do
  # The skill is the one copy of the reference: it must load, and name only verbs that exist.
  use ExUnit.Case, async: true

  @skill Path.expand("../../skills/menard/SKILL.md", __DIR__)

  test "has the frontmatter Claude Code loads it by" do
    ["", front, _body] = @skill |> File.read!() |> String.split("---\n", parts: 3)
    assert front =~ ~r/^name: menard$/m
    assert front =~ ~r/^description: \S/m
  end

  test "every verb its table names is a verb menard has" do
    nouns =
      ~r/^\| [^|]+ \| `(\w+)/m
      |> Regex.scan(File.read!(@skill), capture: :all_but_first)
      |> List.flatten()
      |> Enum.uniq()

    assert nouns != []

    for noun <- nouns do
      assert Mix.Task.get("menard.#{noun}"), "the skill names `#{noun}`, and there is no menard.#{noun}"
    end
  end
end
