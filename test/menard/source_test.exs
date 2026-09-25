defmodule Menard.SourceTest do
  use ExUnit.Case, async: true

  alias Menard.Source

  describe "reindent" do
    test "code already indented is not indented twice" do
      # sliced from source: the first line lost its indent, the rest kept theirs
      code = "[\n      :a,\n      :b\n    ]"
      assert Source.reindent(code, "    ") == "[\n      :a,\n      :b\n    ]"
    end

    test "code written flush is indented once" do
      assert Source.reindent("[\n  :a\n]", "    ") == "[\n      :a\n    ]"
    end

    test "a blank line stays blank" do
      assert Source.reindent("a\n\nb", "  ") == "a\n\n  b"
    end

    test "the lines inside a multi-line string or sigil are its value, and never move" do
      # absinthe's @typedoc: a plain string whose closing quote sits at column 1
      string = "\"\n  A defined list type.\n\n  ## Options\n \""
      assert Source.reindent(string, "  ") == string

      # a sigil inside a call, as a statement placed mid-line after `->`
      call = "DOM.all(root, ~s<\n      #an id\n      :is(input)\n    >)"
      assert Source.reindent(call, "                  ") == call

      # the code around a literal still moves
      assert Source.reindent("foo(\n\"\"\"\nkept\n\"\"\",\n:x)", "  ") ==
               "foo(\n  \"\"\"\nkept\n\"\"\",\n  :x)"
    end

    test "a -> arm's literal lines stay too" do
      # an arm, `stmt`'s statement mid-line after `fn state ->`: only inside a fn does it parse
      arm = "-> DOM.all(root, ~s<\n      #an id\n    >)"
      assert Source.reindent(arm, "                  ") == arm
    end
  end

  describe "clamp" do
    test "an interpolated heredoc's end reaches past its closing quotes" do
      source = ~s(x = """\n  a \#{b}\n  """\n)
      {:ok, {:=, _, [_, heredoc]}} = Sourceror.parse_string(source)
      range = heredoc |> Sourceror.get_range() |> Source.clamp(source)
      assert Source.slice(source, range) == ~s("""\n  a \#{b}\n  """)
    end

    test "a literal that ends a line does not reach past it" do
      source = "x = false\ny\n"
      {:ok, {:__block__, _, [{:=, _, [_, literal]}, _]}} = Sourceror.parse_string(source)
      range = literal |> Sourceror.get_range() |> Source.clamp(source)
      assert range.end == [line: 1, column: 10]
    end
  end
end
