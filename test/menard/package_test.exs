defmodule Menard.PackageTest do
  # menard as a project's dependency: what the Hex package puts in a host, and what it says there.
  # Not async: the help is read from a directory with no bin/menard, as a host's is.
  use ExUnit.Case, async: false

  alias Menard.Verbs.Help

  test "every mix task the package ships is menard's by name" do
    tasks = "lib/mix/tasks/*.ex" |> Path.wildcard() |> Enum.map(&Path.basename/1)
    assert tasks != []
    assert Enum.reject(tasks, &String.starts_with?(&1, "menard")) == []
  end

  @tag :tmp_dir
  test "with no bin/menard beside it, the help names the mix tasks", %{tmp_dir: dir} do
    File.cd!(dir, fn ->
      assert {:ok, %{text: text}} = Help.run(%{})
      refute text =~ "bin/menard"
      assert text =~ "mix menard.rename price_with_tax"
      assert text =~ "mix menard.help VERB"

      assert {:ok, %{text: text}} = Help.run(%{verb: "clause"})
      refute text =~ "bin/menard"
      assert text =~ "mix menard.clause get lib/shop/cart.ex total/2"
    end)
  end
end
