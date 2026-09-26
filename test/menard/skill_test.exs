defmodule Menard.SkillTest do
  # The skill is the one copy of the reference: it must load, and name only verbs that exist.
  use ExUnit.Case, async: true

  @skill Path.expand("../../manos/skills/menard/SKILL.md", __DIR__)

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

  test "every verb a table row gives its tool is one that tool takes" do
    rows = Regex.scan(~r/^\| [^|]+ \| `(\w+) \{(.*)$/m, File.read!(@skill), capture: :all_but_first)
    assert rows != []

    for [noun, rest] <- rows, verb <- verbs(rest) do
      tool = Module.concat(Menard.MCP, Macro.camelize(noun))
      allowed = get_in(tool.input_schema(), ["properties", "verb", "enum"]) || []
      assert verb in allowed, "the skill gives `#{noun}` the verb #{verb}; it takes #{inspect(allowed)}"
    end
  end

  # `verb: "a" \| "b"` and the `{verb: "c"` of a second call on the same row
  defp verbs(row) do
    ~r/verb: "(\w+)"((?: \\\| "\w+")*)/
    |> Regex.scan(row, capture: :all_but_first)
    |> Enum.flat_map(fn [first, more] ->
      [first | Regex.scan(~r/"(\w+)"/, more, capture: :all_but_first) |> List.flatten()]
    end)
  end
end
