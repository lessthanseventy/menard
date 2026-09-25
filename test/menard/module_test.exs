defmodule Menard.ModuleTest do
  # Whole modules inside a file — the multi-module shape the MCP tool components use.
  use ExUnit.Case, async: true

  @src """
  defmodule A do
    def a, do: 1
  end

  defmodule B do
    def b, do: 2
  end
  """

  test "add appends a module after the last one" do
    out = Menard.Module.add(@src, "defmodule C do\n  def c, do: 3\nend")

    assert out =~ "defmodule B do\n  def b, do: 2\nend\n\ndefmodule C do"
    assert String.ends_with?(out, "end\n")
  end

  test "a name the file already defines is refused" do
    assert {:error, message} = Menard.Module.add(@src, "defmodule B do\nend")
    assert message =~ "already defined"
  end

  test "anything that is not a whole module is refused" do
    assert {:error, message} = Menard.Module.add(@src, "def loose, do: 1")
    assert message =~ "whole `defmodule"
  end

  test "list names the modules in source order" do
    assert Menard.Module.list(@src) == ["A", "B"]
  end

  test "comment sets the # comment at the top of a module's body" do
    src = """
    defmodule ATest do
      # old header
      use ExUnit.Case
    end
    """

    out = Menard.Module.comment(src, nil, "what these tests are about")
    assert out =~ "defmodule ATest do\n  # what these tests are about\n  use ExUnit.Case"
    refute out =~ "old header"
  end
end
