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

  test "replace swaps one whole module in a file of several, and only its bytes" do
    src = """
    defmodule A do
      def a, do: 1
    end

    # about B
    defmodule B do
      def b, do: 2
    end

    defmodule C do
      def c, do: 3
    end
    """

    assert Menard.Module.replace(src, "B", "defmodule B do\n  def b, do: :two\nend") ==
             String.replace(src, "def b, do: 2", "def b, do: :two")
  end

  test "replace refuses code that is not that module" do
    src = "defmodule A do\nend\n\ndefmodule B do\nend\n"
    assert {:error, message} = Menard.Module.replace(src, "B", "defmodule Z do\nend")
    assert message =~ "B"
    assert {:error, _} = Menard.Module.replace(src, "Nope", "defmodule Nope do\nend")
  end

  test "comment with above: sets the # comment above defmodule, not in its body" do
    src = """
    # old note
    defmodule ATest do
      # the body's header, not this one's
      use ExUnit.Case
    end
    """

    out = Menard.Module.comment(src, nil, "why this module exists", above: true)
    assert out =~ "# why this module exists\ndefmodule ATest do\n  # the body's header"
    refute out =~ "old note"

    # no text removes it, and only it
    assert Menard.Module.comment(out, nil, nil, above: true) =~
             ~r/\Adefmodule ATest do\n  # the body's header/
  end
end
