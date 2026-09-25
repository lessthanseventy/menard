defmodule Menard.MCPTest do
  # MENARD_ROOT is process-wide, so not async.
  use ExUnit.Case, async: false

  alias Anubis.Server.Frame

  setup do
    root = Path.join(System.tmp_dir!(), "menard-mcp-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(root, "lib"))
    previous = System.get_env("MENARD_ROOT")
    System.put_env("MENARD_ROOT", root)

    on_exit(fn ->
      if previous, do: System.put_env("MENARD_ROOT", previous), else: System.delete_env("MENARD_ROOT")
      File.rm_rf!(root)
    end)

    {:ok, root: root}
  end

  defp call(tool, params) do
    {:reply, response, _frame} = tool.execute(params, Frame.new())
    response
  end

  test "block add takes a test's context, and block delete removes one", %{root: root} do
    file = Path.join(root, "lib/a_test.exs")

    File.write!(
      file,
      "defmodule ATest do\n  use ExUnit.Case\n\n  test \"one\" do\n    assert 1\n  end\nend\n"
    )

    refute call(Menard.MCP.Block, %{
             verb: "add",
             file: "lib/a_test.exs",
             name: "test",
             label: "ctx",
             args: "%{ws: ws}",
             code: "assert ws"
           }).isError

    refute call(Menard.MCP.Block, %{verb: "delete", file: "lib/a_test.exs", name: "test", label: "one"}).isError

    out = File.read!(file)
    assert out =~ ~s(test "ctx", %{ws: ws} do)
    refute out =~ ~s(test "one")
  end

  test "stmt comment and module comment reach the comments no other verb can", %{root: root} do
    File.write!(
      Path.join(root, "lib/a.ex"),
      "defmodule A do\n  use B\n\n  def go(x) do\n    step(x)\n  end\nend\n"
    )

    refute call(Menard.MCP.Stmt, %{
             verb: "comment",
             file: "lib/a.ex",
             name_arity: "go/1",
             head: "x",
             match: "step(x)",
             text: "why"
           }).isError

    refute call(Menard.MCP.Module, %{verb: "comment", file: "lib/a.ex", text: "what A is"}).isError

    out = File.read!(Path.join(root, "lib/a.ex"))
    assert out =~ "  # what A is\n  use B"
    assert out =~ "    # why\n    step(x)"
  end

  test "a root given with a trailing slash still admits paths under it", %{root: root} do
    System.put_env("MENARD_ROOT", root <> "/")
    assert {:ok, _} = Menard.MCP.resolve("lib/a.ex")
  end

  test "clause move carries a function to another file", %{root: root} do
    File.write!(Path.join(root, "lib/a.ex"), "defmodule A do\n  def go, do: 1\n\n  def stay, do: 2\nend\n")

    response =
      call(Menard.MCP.Clause, %{verb: "move", file: "lib/a.ex", name_arity: "go/0", to: "lib/b.ex", as: "B"})

    refute response.isError
    refute File.read!(Path.join(root, "lib/a.ex")) =~ "def go"
    assert File.read!(Path.join(root, "lib/b.ex")) =~ "defmodule B do\n  def go, do: 1"
  end

  test "attr comment writes the # line above an attribute", %{root: root} do
    File.write!(Path.join(root, "lib/a.ex"), "defmodule A do\n  @t 1\n\n  def go, do: @t\nend\n")

    refute call(Menard.MCP.Attr, %{verb: "comment", file: "lib/a.ex", name: "t", text: "why"}).isError
    assert File.read!(Path.join(root, "lib/a.ex")) =~ "  # why\n  @t 1"
  end

  test "block relabel renames a test", %{root: root} do
    File.write!(
      Path.join(root, "lib/a_test.exs"),
      "defmodule ATest do\n  use ExUnit.Case\n\n  test \"old\" do\n    assert true\n  end\nend\n"
    )

    response =
      call(Menard.MCP.Block, %{
        verb: "relabel",
        file: "lib/a_test.exs",
        name: "test",
        label: "old",
        new_label: "new"
      })

    refute response.isError
    assert File.read!(Path.join(root, "lib/a_test.exs")) =~ ~s(test "new" do)
  end
end
