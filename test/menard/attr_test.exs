defmodule Menard.AttrTest do
  # Module attributes — the tables a module keeps at the top, which no clause verb reaches.
  use ExUnit.Case, async: true

  alias Menard.Attr

  @src """
  defmodule A do
    @moduledoc "docs"

    @kinds [:a, :b]

    @hints [
      {"x", "one"},
      {"y", "two"}
    ]

    @doc "first"
    def go(:a), do: 1

    @doc "second"
    def go(:b), do: 2
  end
  """

  test "get reads the value exactly as written, single line or block" do
    assert Attr.get(@src, "kinds") == "[:a, :b]"
    assert Attr.get(@src, :hints) =~ ~s({"x", "one"})
  end

  test "a leading @ on the name is accepted — it is how the attribute is written" do
    assert Attr.get(@src, "@kinds") == "[:a, :b]"
  end

  test "set replaces the value and leaves everything else alone" do
    out = Attr.set(@src, "kinds", "[:a, :b, :c]")

    assert out =~ "@kinds [:a, :b, :c]"
    assert out =~ ~s(@moduledoc "docs")
    assert out =~ "def go(:a), do: 1"
  end

  test "set over a MULTI-LINE value replaces the whole block, not just its first line" do
    out = Attr.set(@src, "hints", "[{\"z\", \"only\"}]")

    assert out =~ ~s(@hints [{"z", "only"}])
    refute out =~ ~s({"x", "one"})
    refute out =~ ~s({"y", "two"})
    assert out =~ "@doc \"first\""
  end

  test "a multi-line value lands as a block at the attribute's own column" do
    out = Attr.set(@src, "kinds", "[\n  :a,\n  :z\n]")

    assert out =~ "  @kinds [\n    :a,\n    :z\n  ]"
  end

  test "setting one that is missing adds it above the first definition, where tables live" do
    out = Attr.set(@src, "timeout", "5_000")

    assert out =~ "@timeout 5_000"
    # above the first def, not appended after the last
    assert String.split(out, "@timeout") |> hd() |> String.contains?("def go") == false
  end

  test "delete removes the whole attribute, block and all" do
    out = Attr.delete(@src, "hints")

    refute out =~ "@hints"
    refute out =~ ~s({"x", "one"})
    assert out =~ "@kinds [:a, :b]"
  end

  test "a name that repeats per clause is refused, with its lines, not guessed at" do
    assert {:error, message} = Attr.get(@src, "doc")
    assert message =~ "set 2 times"
    assert message =~ "clause verbs"
  end

  test "an attribute that isn't there reads as missing" do
    assert Attr.get(@src, "nope") == {:error, :missing}
  end

  test "list names what the module sets, with lines" do
    names = @src |> Attr.list() |> Enum.map(&elem(&1, 0))
    assert :kinds in names
    assert :hints in names
  end

  test "a NEW attribute lands above an existing one, because attributes read each other" do
    src = """
    defmodule A do
      @base 1
      @derived @base + 1

      def go, do: @derived
    end
    """

    out = Menard.Attr.set(src, "extra", "9")
    lines = String.split(out, "\n")
    at = fn text -> Enum.find_index(lines, &String.contains?(&1, text)) end

    # Elixir reads an attribute defined BELOW its use as nil and only warns, so the one safe
    # position for a new attribute is above every attribute, not merely above the first def.
    assert at.("@extra 9") < at.("@base 1")
    assert at.("@extra 9") < at.("@derived")
  end

  test "a NEW attribute lands below the alias its value depends on, not at the very top" do
    src = """
    defmodule A do
      @moduledoc "prose"

      alias Some.Palette, as: P

      @ground P.ground()

      def go, do: @ground
    end
    """

    out = Menard.Attr.set(src, "body", "P.body()")
    lines = String.split(out, "\n")
    at = fn text -> Enum.find_index(lines, &String.contains?(&1, text)) end

    # above the first TABLE, because @ground could read it — but below the alias and the
    # moduledoc, because `P.body()` above `alias ... as: P` is "module P is not available"
    assert at.("alias Some.Palette") < at.("@body P.body()")
    assert at.("@moduledoc") < at.("@body P.body()")
    assert at.("@body P.body()") < at.("@ground")
  end

  test "comment writes, replaces and removes the # block above an attribute" do
    src = """
    defmodule A do
      # stale
      @colors %{a: 1}

      @plain 2
    end
    """

    written = Menard.Attr.comment(src, "colors", "what the panels resolve through")
    assert written =~ "# what the panels resolve through\n  @colors"
    refute written =~ "# stale"

    # an attribute with no comment yet gets one at its own column
    assert Menard.Attr.comment(src, "plain", "why 2") =~ "  # why 2\n  @plain 2"

    # no text removes it, and takes the whole block
    removed = Menard.Attr.comment(src, "colors", nil)
    refute removed =~ "# stale"
    assert removed =~ "@colors %{a: 1}"
  end

  test "set keeps a trailing comment on the attribute line" do
    src = """
    defmodule A do
      @timeout 5_000 # ms

      def go, do: @timeout
    end
    """

    assert Attr.set(src, "timeout", "10_000") =~ "@timeout 10_000 # ms"
  end

  test "set on a heredoc keeps the line after it" do
    src = """
    defmodule A do
      @moduledoc \"\"\"
      Old.
      \"\"\"

      use B
    end
    """

    assert Attr.set(src, "moduledoc", ~s("New.")) == """
           defmodule A do
             @moduledoc "New."

             use B
           end
           """
  end

  @tag :tmp_dir
  test "the CLI says an attribute is missing instead of crashing", %{tmp_dir: dir} do
    file = Path.join(dir, "a.ex")
    File.write!(file, "defmodule A do\n  def go, do: 1\nend\n")

    assert_raise Mix.Error, ~r/no @nope/, fn -> Mix.Tasks.Menard.Attr.run(["get", file, "nope"]) end
  end

  test "a NEW attribute lands above the first node that reads it, a moduledoc or a use included" do
    # the @moduledoc and the `use` already read @dir; placed by the usual rule (above the first
    # table), @dir would land below both, and a read above a definition is nil
    src = """
    defmodule A do
      @moduledoc "templates in \#{@dir}"
      use Some.Templates, from: @dir

      @other 1

      def go, do: @other
    end
    """

    lines = src |> Menard.Attr.set("dir", ~s("priv/t")) |> String.split("\n")
    at = fn text -> Enum.find_index(lines, &String.contains?(&1, text)) end

    assert at.(~s(@dir "priv/t")) < at.("@moduledoc")
    assert at.(~s(@dir "priv/t")) < at.("use Some.Templates")
  end

  test "a NEW attribute lands above a def's @doc, @spec and comment, never between them and the def" do
    # landed between route/1's @doc and its def, the @doc belonged to nothing: `clause doc` could not
    # remove it, and setting one made a second
    src = """
    defmodule Router do
      use Some.Router

      # the one entry point
      @doc "routes a request"
      @spec route(term()) :: term()
      def route(req), do: req
    end
    """

    lines = src |> Menard.Attr.set("timeout", "5_000") |> String.split("\n")
    at = fn text -> Enum.find_index(lines, &String.contains?(&1, text)) end

    assert at.("@timeout 5_000") < at.("# the one entry point")
    assert at.("@doc \"routes") + 1 == at.("@spec route")
    assert at.("@spec route") + 1 == at.("def route")
  end

  test "delete under a def's @doc takes the blank line it leaves between them" do
    # deleting one that sat under a def's @doc took its line and left its blank: @doc, a gap, @spec
    src = """
    defmodule A do
      @doc \"\"\"
      adds
      \"\"\"
      @stray 1

      @spec add(integer()) :: integer()
      def add(a), do: a + 1

      @plain 2

      def other, do: @plain
    end
    """

    assert Menard.Attr.delete(src, "stray") =~ "  \"\"\"\n  @spec add(integer())"
    # elsewhere a blank on each side stays one blank
    assert Menard.Attr.delete(src, "plain") =~ "def add(a), do: a + 1\n\n\n  def other"
  end

  test "a multi-line value already placed deeper keeps its indentation" do
    # a multi-line value whose lines all sit deeper than the attribute, its closing included: dropping
    # their shared indent pulled a sigil's words left (ex_doc's @void_elements, credo's ~w table)
    src = """
    defmodule A do
      @words ~w(
          one two
          three
        )a

      def go, do: @words
    end
    """

    value = "~w(\n      one two\n      three\n    )a"
    assert Menard.Attr.set(src, "words", value) == src

    # code written from column 0 still lands at the attribute's column
    assert Menard.Attr.set(src, "words", "~w(\n  four\n)a") =~ "  @words ~w(\n    four\n  )a\n"
  end
end
