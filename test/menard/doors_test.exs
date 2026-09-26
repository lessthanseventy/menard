defmodule Menard.DoorsTest do
  # One verb layer under both doors (Menard.Verbs): for every noun, the CLI's one JSON line and
  # the MCP tool's reply are the same map, and a refusal is the same sentence. MENARD_ROOT and
  # MENARD_CWD are process-wide, so not async.
  use ExUnit.Case, async: false

  alias Anubis.Server.Frame
  alias Mix.Tasks.Menard.Where

  @moduletag :tmp_dir

  setup %{tmp_dir: dir} do
    File.mkdir_p!(Path.join(dir, "lib"))
    previous = {System.get_env("MENARD_ROOT"), System.get_env("MENARD_CWD")}
    System.put_env("MENARD_ROOT", dir)
    System.put_env("MENARD_CWD", dir)

    on_exit(fn ->
      for {name, value} <- Enum.zip(["MENARD_ROOT", "MENARD_CWD"], Tuple.to_list(previous)) do
        if value, do: System.put_env(name, value), else: System.delete_env(name)
      end
    end)

    File.write!(
      Path.join(dir, "lib/a.ex"),
      "defmodule A do\n  @limit 5\n\n  alias A.B\n\n  def go(x) do\n    y = x + 1\n    y\n  end\n\n  def two(1), do: 1\n  def two(n), do: n\nend\n"
    )

    File.write!(
      Path.join(dir, "lib/a_test.exs"),
      "defmodule ATest do\n  use ExUnit.Case\n\n  test \"one\" do\n    assert 1\n  end\nend\n"
    )

    File.write!(Path.join(dir, "lib/bad.ex"), "defmodule Bad do\n  def go, do: (\nend\n")
    :ok
  end

  # the MCP door's reply, decoded; a refusal as {:error, text}
  defp mcp(tool, params) do
    {:reply, response, _frame} = tool.execute(params, Frame.new())
    text = response.content |> hd() |> Map.fetch!("text")
    if response.isError, do: {:error, text}, else: {:ok, JSON.decode!(text)}
  end

  # the CLI door's one line, decoded; a Mix.Error as {:error, text}
  defp cli(task, argv) do
    {:ok, ExUnit.CaptureIO.capture_io(fn -> task.run(argv) end) |> String.trim() |> JSON.decode!()}
  rescue
    e in Mix.Error -> {:error, Exception.message(e)}
  end

  # a version differs per write, and a note is prose: the rest is the reply
  defp same(reply), do: reply |> Map.drop(["version", "note"]) |> put_in(["stages"], nil)

  test "every noun answers the same map at both doors, on success and on a refusal" do
    reads = [
      {Menard.MCP.Attr, Mix.Tasks.Menard.Attr, %{verb: "get", file: "lib/a.ex", name: "limit"},
       ["get", "lib/a.ex", "limit"]},
      {Menard.MCP.Attr, Mix.Tasks.Menard.Attr, %{verb: "list", file: "lib/a.ex"}, ["list", "lib/a.ex"]},
      {Menard.MCP.Attr, Mix.Tasks.Menard.Attr, %{verb: "get", file: "lib/a.ex", name: "nope"},
       ["get", "lib/a.ex", "nope"]},
      {Menard.MCP.Stmt, Mix.Tasks.Menard.Stmt,
       %{verb: "list", file: "lib/a.ex", name_arity: "go/1", head: "x"}, ["list", "lib/a.ex", "go/1", "x"]},
      {Menard.MCP.Block, Mix.Tasks.Menard.Block, %{verb: "list", file: "lib/a_test.exs"},
       ["list", "lib/a_test.exs"]},
      {Menard.MCP.Block, Mix.Tasks.Menard.Block, %{verb: "get", file: "lib/a_test.exs", name: "test"},
       ["get", "lib/a_test.exs", "test"]},
      {Menard.MCP.Directive, Mix.Tasks.Menard.Directive, %{verb: "list", file: "lib/a.ex"},
       ["list", "lib/a.ex"]},
      {Menard.MCP.Module, Mix.Tasks.Menard.Module, %{verb: "list", file: "lib/a.ex"}, ["list", "lib/a.ex"]},
      {Menard.MCP.Deps, Mix.Tasks.Menard.Deps, %{verb: "refs", file: "lib/a.ex", name_arity: "go/1"},
       ["lib/a.ex", "go/1"]},
      {Menard.MCP.Clause, Mix.Tasks.Menard.Clause, %{verb: "get", file: "lib/a.ex", name_arity: "two/1"},
       ["get", "lib/a.ex", "two/1"]},
      {Menard.MCP.Outline, Mix.Tasks.Menard.Outline, %{file: "lib/a.ex"}, ["--json", "lib/a.ex"]},
      {Menard.MCP.Find, Mix.Tasks.Menard.Find, %{kind: "calls", target: "two", files: ["lib/a.ex"]},
       ["calls", "two", "lib/a.ex", "--json"]},
      # a parse error names the file, at both doors
      {Menard.MCP.Outline, Mix.Tasks.Menard.Outline, %{file: "lib/bad.ex"}, ["--json", "lib/bad.ex"]},
      # a miss is the same sentence
      {Menard.MCP.Clause, Mix.Tasks.Menard.Clause,
       %{verb: "replace", file: "lib/a.ex", name_arity: "nope/1", head: "x", code: "1"},
       ["replace", "lib/a.ex", "nope/1", "x", "1"]},
      # and so is a field left out, checked once, in the verb layer
      {Menard.MCP.Clause, Mix.Tasks.Menard.Clause, %{verb: "move", file: "lib/a.ex", name_arity: "go/1"},
       ["move", "lib/a.ex", "go/1"]}
    ]

    for {tool, task, params, argv} <- reads do
      assert mcp(tool, params) == cli(task, argv), "#{inspect(tool)} #{inspect(params)}"
    end

    # a write: the same staged reply (its version differs only by the two writes)
    edit = %{verb: "replace", file: "lib/a.ex", name_arity: "two/1", head: "n", code: "n + 0"}
    assert {:ok, from_mcp} = mcp(Menard.MCP.Clause, edit)
    assert {:ok, from_cli} = cli(Mix.Tasks.Menard.Clause, ["replace", "lib/a.ex", "two/1", "n", "n + 0"])
    assert same(from_mcp) == same(from_cli)
    assert from_mcp["did"] == "replace two/1 `n` in a.ex"
  end

  test "attr names a Phoenix component declaration for what it is, at both doors", %{tmp_dir: dir} do
    File.write!(
      Path.join(dir, "lib/c.ex"),
      "defmodule C do\n  use Phoenix.Component\n\n  attr :product, :map\n\n  def card(assigns), do: assigns\nend\n"
    )

    assert {:error, why} = mcp(Menard.MCP.Attr, %{verb: "delete", file: "lib/c.ex", name: "product"})
    assert why =~ "Phoenix component declaration"
    assert {:error, ^why} = cli(Mix.Tasks.Menard.Attr, ["delete", "lib/c.ex", "product"])
  end

  test "the MCP door refuses a path outside its root; the CLI resolves against the caller's directory" do
    assert {:error, "refused: ../x.ex is outside" <> _} = mcp(Menard.MCP.Outline, %{file: "../x.ex"})
    assert {:error, "cannot read " <> _} = cli(Mix.Tasks.Menard.Outline, ["--json", "../x.ex"])
  end

  test "map and where are outline's verbs at the MCP door, the CLI's map and where" do
    assert {:ok, %{"modules" => [%{"module" => "A", "file" => "lib/a.ex", "functions" => ["go/1", "two/1"]}]}} =
             mcp(Menard.MCP.Outline, %{verb: "map"})

    assert ExUnit.CaptureIO.capture_io(fn -> Mix.Tasks.Menard.Map.run([]) end) == "A  lib/a.ex  go/1 two/1\n"

    assert {:ok, %{"at" => [%{"file" => "lib/a.ex", "line" => 7, "in" => "A.go/1"}]}} =
             mcp(Menard.MCP.Outline, %{verb: "where", at: ["lib/a.ex:7"]})

    assert ExUnit.CaptureIO.capture_io(fn -> Where.run(["lib/a.ex:7"]) end) ==
             "lib/a.ex:7  A.go/1\n"
  end

  test "a write the formatter could not finish is said on the CLI's stderr too, from the reply" do
    # the core no longer prints: the door does, from `unformatted`
    reply = %{did: "x", file: "f.ex", version: "sha256:0", stages: [], unformatted: "no plugin"}

    assert ExUnit.CaptureIO.capture_io(:stderr, fn ->
             ExUnit.CaptureIO.capture_io(fn -> Menard.CLI.answer({:ok, reply}) end)
           end) =~ "menard: no plugin"
  end

  test "every MCP tool is a verb module's run/1 behind a deadline, and every mix task calls one" do
    verbs = Path.wildcard(Path.expand("../../lib/menard/verbs/*.ex", __DIR__))
    assert length(verbs) >= 14

    for path <- verbs do
      module = Module.concat(Menard.Verbs, path |> Path.basename(".ex") |> Macro.camelize())

      assert Code.ensure_loaded?(module), "no module #{inspect(module)}"
      assert function_exported?(module, :run, 1), "#{inspect(module)} has no run/1"
    end

    for task <- Path.wildcard(Path.expand("../../lib/mix/tasks/menard.*.ex", __DIR__)),
        Path.basename(task) != "menard.mcp.ex" do
      assert File.read!(task) =~ ~r/\bVerbs\.[A-Z]\w+\.run\(/,
             "#{Path.basename(task)} does not call the verb layer"
    end

    tools = Path.expand("../../lib/menard/mcp/tools.ex", __DIR__)

    refute File.read!(tools) =~
             ~r/Menard\.(Clause|Stmt|Attr|Block|Directive|Module|Rename|Find|Outline|Deps|Run|MixDeps)\./
  end
end
