defmodule Menard.BlockModuleParentTest do
  # `--in` names a parent to append inside; a module is as obvious a parent as a labelled block.
  use ExUnit.Case, async: true

  alias Menard.Block

  @src """
  defmodule InMod do
    test "existing" do
      assert true
    end
  end
  """

  test "--in accepts a MODULE, not only a labelled block" do
    out = Block.add(@src, "describe", "a new describe", "assert true", in: "InMod")

    assert out =~ ~s(describe "a new describe" do)
    assert out =~ ~s(test "existing")
  end

  test "adding a defmodule is refused — a --label would become a string module name" do
    assert {:error, message} = Block.add(@src, "defmodule", "InMod", "assert true", [])
    assert message =~ "menard.module add"
  end
end
