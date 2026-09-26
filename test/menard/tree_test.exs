defmodule Menard.TreeTest do
  # The one tree every verb walks: what a definition is must be the same to outline, find, clause,
  # deps, attr, rename and block, or a def one verb lists is one another cannot reach.
  use ExUnit.Case, async: true

  alias Menard.Tree

  @root Path.expand("../..", __DIR__)

  # every kind a definition is written as, in one module
  @src """
  defmodule K do
    def a(x), do: x
    defp b(x), do: x
    defmacro c(x), do: x
    defmacrop d(x), do: x
    defguard e(x) when is_integer(x)
    defguardp f(x) when is_integer(x)
    defdelegate g(x), to: Enum, as: :count
  end
  """

  test "one def-kinds list: no module spells its own" do
    for path <- Path.wildcard(Path.join(@root, "lib/**/*.ex")), Path.basename(path) != "tree.ex" do
      refute File.read!(path) =~ ~r/\[:def\b[^\]]*:defmacrop/,
             "#{Path.relative_to(path, @root)} carries its own def-kinds list — Menard.Tree.def_kinds/0 is the one"
    end
  end

  test "every verb sees each kind, a defdelegate included" do
    names = ~w(a b c d e f g)

    {:ok, [k]} = Menard.Outline.run(@src)
    assert Enum.map(k.defs, &to_string(&1.name)) == names

    for name <- names do
      assert [%{kind: _}] = Menard.Find.defs(@src, name <> "/1"), "find defs misses #{name}"
      assert {:ok, %{code: _}} = Menard.Clause.get(@src, name <> "/1", nil), "clause get misses #{name}"
    end

    # a delegate is a function of this module: a call to it is a local, not a free helper
    src = String.replace(@src, "def a(x), do: x", "def a(x), do: g(x)")
    assert [%{call: "g/1"}] = Menard.Deps.of(src, "a/1").locals

    # a table lands above the first definition, whatever kind it is
    src = "defmodule T do\n  defdelegate g(x), to: Enum, as: :count\nend\n"

    assert Menard.Attr.set(src, "t", "1") ==
             "defmodule T do\n  @t 1\n\n  defdelegate g(x), to: Enum, as: :count\nend\n"
  end

  test "name_arity: the guard looked through, no parens is arity 0, an unquoted name is no name" do
    assert Tree.name_arity({:when, [], [{:go, [], [1, 2]}, true]}) == {:go, 2}
    assert Tree.name_arity({:go, [], nil}) == {:go, 0}
    assert {{:unquote, _, _}, 1} = Tree.name_arity({{:unquote, [], [:n]}, [], [1]})
  end

  test "modules names a nested module as Elixir does, and module_scope refuses several unnamed" do
    {:ok, ast} = Menard.Source.parse("defmodule A do\n  defmodule B do\n  end\nend\ndefmodule C do\nend\n")
    assert Enum.map(Tree.modules(ast), &elem(&1, 0)) == ["A", "A.B", "C"]
    assert {:error, "several modules here — name one: A, A.B, C"} = Tree.module_scope(ast, nil)
    assert {:ok, {:defmodule, _, _}} = Tree.module_scope(ast, "A.B")
    assert {:error, "no module D in this file — have: A, A.B, C"} = Tree.module_scope(ast, "D")
  end
end
