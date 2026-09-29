defmodule Menard.HelpTest do
  # `--help`: what the verbs are for, by example. What it shows is held to what menard takes: an
  # example that is refused teaches the wrong call.
  use ExUnit.Case, async: true

  alias Menard.Verbs.Help
  alias Menard.Verbs.Noun

  @bin Path.expand("../../bin/menard", __DIR__)

  test "every verb a caller runs is in the help, and the plumbing is not" do
    {out, 2} = System.cmd(@bin, ["--frozen", "nosuch"], stderr_to_stdout: true)
    [_, listed] = Regex.run(~r/\(([a-z|]+)\)/, out)
    assert Enum.sort(Help.verbs()) == Enum.sort(String.split(listed, "|") -- ~w(mcp guard hook help))
  end

  test "the overview names each verb, what it is for, and a call by this menard's path" do
    assert {:ok, %{text: text}} = Help.run(%{})

    for verb <- Help.verbs() do
      assert text =~ ~r/^  #{verb}\s+\S/m, "no line for #{verb}"
      assert text =~ "#{Menard.bin()} #{verb}", "no example of #{verb}"
    end

    refute text =~ ~r/(?<![\w\/])menard (edit|rename|run|clause) /
  end

  test "a verb's help is its examples, the calls it takes and what it says of itself" do
    assert {:ok, %{text: text}} = Help.run(%{verb: "clause"})
    assert text =~ "#{Menard.bin()} clause split lib/shop.ex"
    assert text =~ "#{Menard.bin()} clause insert_at FILE MODULE CODE"
    assert text =~ "the clause's CURRENT head"

    assert {:ok, %{text: text}} = Help.run(%{verb: "edit"})
    assert text =~ "<<<<<<< SEARCH"
    assert text =~ "found exactly once"

    assert {:error, why} = Help.run(%{verb: "nope"})
    assert why =~ "no verb nope"
  end

  test "a verb named in an example's call is one its noun takes" do
    for verbs <- Noun.modules(), noun = Noun.of(verbs), noun[:cli], noun.name in Help.verbs() do
      {:ok, %{text: text}} = Help.run(%{verb: noun.name})
      takes = for {verb, _args} <- noun.cli.shapes, verb, do: String.replace(verb, "_", "-")

      for [_, verb] <- Regex.scan(~r/bin\/menard #{noun.name} ([a-z-]+) \S/, text), takes != [] do
        assert verb in takes, "#{noun.name}'s help shows `#{verb}`, and it takes #{inspect(takes)}"
      end
    end
  end

  test "--help is the help, before a verb and after one" do
    assert {out, 0} = System.cmd(@bin, ["--frozen", "--help"], stderr_to_stdout: true)
    assert out =~ "rename  "
    assert {^out, 0} = System.cmd(@bin, ["--frozen", "help"], stderr_to_stdout: true)
    assert {out, 0} = System.cmd(@bin, ["--frozen", "rename", "--help"], stderr_to_stdout: true)
    assert out =~ "rename: a name changed everywhere it is used"
  end
end
