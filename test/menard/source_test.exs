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
