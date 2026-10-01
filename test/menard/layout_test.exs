defmodule Menard.LayoutTest do
  # A new private function goes below the module's public ones, whatever verb wrote it and wherever
  # the agent put it: the layout most Elixir is written in, kept by the tool rather than asked of
  # the agent.
  use ExUnit.Case, async: true

  alias Menard.Layout

  @before """
  defmodule T do
    def a, do: 1

    def b, do: 2

    defp c, do: 3
  end
  """

  test "a new defp above a public def goes to the module's end, with its comment and spec" do
    after_edit = """
    defmodule T do
      def a, do: helped(1)

      # what helps
      @spec helped(integer()) :: integer()
      defp helped(x), do: x
      defp helped(x, y), do: x + y

      def b, do: 2

      defp c, do: 3
    end
    """

    assert {code,
            [
              "helped/1 to the module's end, below its public functions",
              "helped/2 to the module's end, below its public functions"
            ]} = Layout.private_last(@before, after_edit)

    assert code == """
           defmodule T do
             def a, do: helped(1)

             def b, do: 2

             defp c, do: 3

             # what helps
             @spec helped(integer()) :: integer()
             defp helped(x), do: x

             defp helped(x, y), do: x + y
           end
           """
  end

  test "a defp renamed or given another arity stays where it is: no private function was added" do
    renamed = """
    defmodule T do
      defp z, do: 0

      def a, do: 1

      def b, do: 2
    end
    """

    was = String.replace(renamed, "defp z", "defp y")
    assert Layout.private_last(was, renamed) == {renamed, []}
  end

  test "a new defp already below every public def stays" do
    code = String.replace(@before, "defp c, do: 3", "defp c, do: 3\n\n  defp d, do: 4")
    assert Layout.private_last(@before, code) == {code, []}
  end

  test "a nested module's new defp goes to that module's end" do
    was = "defmodule O do\n  defmodule I do\n    def a, do: 1\n  end\n\n  def o, do: 0\nend\n"

    now =
      "defmodule O do\n  defmodule I do\n    defp h, do: 2\n    def a, do: h()\n  end\n\n  def o, do: 0\nend\n"

    assert {code, ["h/0 to the module's end, below its public functions"]} = Layout.private_last(was, now)

    assert code ==
             "defmodule O do\n  defmodule I do\n    def a, do: h()\n\n    defp h, do: 2\n  end\n\n  def o, do: 0\nend\n"
  end

  test "code that does not parse is left to the parse check" do
    assert Layout.private_last(@before, "defmodule T do\n") == {"defmodule T do\n", []}
  end

  test "a new clause of a function, written apart from its others, joins them on the side it was written" do
    was = """
    defmodule T do
      def a, do: c(:x)

      def b, do: 2

      defp c(:x), do: 1
      defp c(_), do: 0
    end
    """

    # written above its others: it goes before them, where a catch-all last still comes last
    now = String.replace(was, "  def b, do: 2\n", "  defp c(:y), do: 2\n\n  def b, do: 2\n")
    assert {code, ["c/1: the new clause beside its others"]} = Layout.private_last(was, now)
    assert code =~ "  def b, do: 2\n\n  defp c(:y), do: 2\n\n  defp c(:x), do: 1\n  defp c(_), do: 0\nend\n"

    # written below them: after the last
    now =
      String.replace(
        was,
        "  defp c(_), do: 0\n",
        "  defp c(_), do: 0\n\n  def d, do: 4\n\n  defp c(:z), do: 3\n"
      )

    assert {code, ["c/1: the new clause beside its others"]} = Layout.private_last(was, now)
    assert code =~ "  defp c(_), do: 0\n\n  defp c(:z), do: 3\n\n  def d, do: 4\n"
  end
end
