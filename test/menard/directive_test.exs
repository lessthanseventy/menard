defmodule Menard.DirectiveTest do
  # alias/import/require/use, added and removed where they belong. The placement is the whole
  # point: a directive dropped at a guessed line gets moved by the next format pass.
  use ExUnit.Case, async: true

  alias Menard.Directive

  @src """
  defmodule A do
    @moduledoc "docs"

    use GenServer

    import Bar

    alias App.Cat
    alias App.Emu

    require Logger

    def go, do: :ok
  end
  """

  test "an alias lands in sorted position inside the existing alias block" do
    out = Directive.add(@src, :alias, "App.Dog")
    assert out =~ "alias App.Cat\n  alias App.Dog\n  alias App.Emu"
  end

  test "one that sorts last goes at the end of its block, not into the requires" do
    out = Directive.add(@src, :alias, "App.Zebra")
    assert out =~ "alias App.Emu\n  alias App.Zebra\n\n  require Logger"
  end

  test "one that sorts first goes at the head of its block, below the imports" do
    out = Directive.add(@src, :alias, "App.Ant")
    assert out =~ "import Bar\n\n  alias App.Ant\n  alias App.Cat"
  end

  test "adding one that is already there changes nothing — never a duplicate line" do
    assert Directive.add(@src, :alias, "App.Cat") == @src
  end

  test "a kind with no block yet opens one in conventional order" do
    src = """
    defmodule A do
      use GenServer

      alias App.Cat

      def go, do: :ok
    end
    """

    # import outranks alias and is outranked by use
    out = Directive.add(src, :import, "Bar")
    assert out =~ "use GenServer\n  import Bar"

    # require sorts after alias
    out = Directive.add(src, :require, "Logger")
    assert out =~ "alias App.Cat\n  require Logger"
  end

  test "with no directives at all it goes under the @moduledoc" do
    src = """
    defmodule A do
      @moduledoc "docs"

      def go, do: :ok
    end
    """

    out = Directive.add(src, :alias, "App.Cat")
    assert out =~ ~s(@moduledoc "docs"\n\n  alias App.Cat)
    assert out =~ "def go, do: :ok"
  end

  test "with no moduledoc either it becomes the module's first line" do
    out = Directive.add("defmodule A do\n  def go, do: :ok\nend\n", :alias, "App.Cat")
    assert out =~ "defmodule A do\n  alias App.Cat"
  end

  test "options ride along as written" do
    out = Directive.add(@src, :import, "App.Panel", args: "only: [pad: 3]")
    assert out =~ "import App.Panel, only: [pad: 3]"
  end

  test "remove takes the line out and leaves the rest" do
    out = Directive.remove(@src, :alias, "App.Cat")
    refute out =~ "App.Cat"
    assert out =~ "alias App.Emu"
    assert out =~ "require Logger"
  end

  test "removing one that isn't there leaves the source alone" do
    assert Directive.remove(@src, :alias, "App.Nope") == @src
  end

  test "list reads what the module already pulls in, in source order" do
    assert Directive.list(@src) == [
             use: "GenServer",
             import: "Bar",
             alias: "App.Cat",
             alias: "App.Emu",
             require: "Logger"
           ]
  end

  test "names the module in a file that has several" do
    src = "defmodule A do\n  def a, do: 1\nend\n\ndefmodule B do\n  def b, do: 2\nend\n"
    out = Directive.add(src, :alias, "App.Cat", module: "B")

    assert out =~ "defmodule B do\n  alias App.Cat"
    refute out =~ "defmodule A do\n  alias"
  end

  test "an unknown kind is refused rather than written" do
    assert {:error, message} = Directive.add(@src, :bogus, "App.Cat")
    assert message =~ "alias"
  end

  test "add survives an existing `alias __MODULE__.X`" do
    src = """
    defmodule A do
      alias __MODULE__.Inner

      def go, do: Inner.x()
    end
    """

    assert Directive.add(src, :alias, "B") =~ "alias B"
    assert Directive.list(src) == [{:alias, "__MODULE__.Inner"}]
  end

  test "the multi form `alias Foo.{Bar, Baz}` counts as each alias it names" do
    src = """
    defmodule A do
      alias Foo.{Bar, Baz}

      def go, do: Bar.x()
    end
    """

    assert Directive.add(src, :alias, "Foo.Bar") == src
    assert Directive.list(src) == [{:alias, "Foo.Bar"}, {:alias, "Foo.Baz"}]
    assert {:error, message} = Directive.remove(src, :alias, "Foo.Bar")
    assert message =~ "Foo.{Bar, Baz}"
    assert Directive.add(src, :alias, "Zed") =~ "alias Foo.{Bar, Baz}\n  alias Zed\n"
  end

  test "replace changes a directive's options in place, in one step" do
    src = """
    defmodule A do
      use B, version: "1"

      def go, do: 1
    end
    """

    assert Directive.replace(src, :use, "B", args: ~s(version: "2")) == """
           defmodule A do
             use B, version: "2"

             def go, do: 1
           end
           """

    assert {:error, message} = Directive.replace(src, :alias, "Nope", args: nil)
    assert message =~ "no alias Nope"
  end

  test "doctest is a directive: added after use and the aliases, listed, removed" do
    # a test module's `doctest Mod` is a directive in all but name: added after `use` and the aliases
    src = """
    defmodule FooTest do
      use ExUnit.Case, async: true

      alias Foo.Bar

      test "a", do: assert(true)
    end
    """

    out = Directive.add(src, :doctest, "Foo")
    assert out =~ "  alias Foo.Bar\n  doctest Foo\n"
    assert {:doctest, "Foo"} in Directive.list(out)
    assert Directive.add(out, :doctest, "Foo") == out
    assert Directive.remove(out, :doctest, "Foo") =~ "  alias Foo.Bar\n\n  test"
  end
end
