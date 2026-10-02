defmodule Menard.DoorsTest do
  # One verb layer under both doors (Menard.Verbs): for every noun, the CLI's one JSON line and
  # the MCP tool's reply are the same map, and a refusal is the same sentence. MENARD_ROOT and
  # MENARD_CWD are process-wide, so not async.
  use ExUnit.Case, async: false

  alias Anubis.Server.Frame
  alias Menard.Verbs.Noun
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

  test "a move of several functions with delegates is one reply at both doors: a list, or a/1,b/2",
       %{tmp_dir: dir} do
    a = Path.join(dir, "lib/a.ex")
    before = File.read!(a)

    assert {:ok, from_mcp} =
             mcp(Menard.MCP.Clause, %{
               verb: "move",
               file: "lib/a.ex",
               name_arity: ["go/1", "two/1"],
               to: "lib/b.ex",
               as: "B",
               delegate: true
             })

    after_mcp = {File.read!(a), File.read!(Path.join(dir, "lib/b.ex"))}
    File.write!(a, before)
    File.rm!(Path.join(dir, "lib/b.ex"))

    assert {:ok, from_cli} =
             cli(Mix.Tasks.Menard.Clause, [
               "move",
               "lib/a.ex",
               "go/1,two/1",
               "--to",
               "lib/b.ex",
               "--as",
               "B",
               "--delegate"
             ])

    assert {File.read!(a), File.read!(Path.join(dir, "lib/b.ex"))} == after_mcp
    files = &(&1 |> Map.update!("to", fn r -> same(r) end) |> Map.update!("from", fn r -> same(r) end))
    assert files.(from_mcp) == files.(from_cli)

    assert %{
             "moved" => ["go/1", "two/1"],
             "delegated" => ["go/1", "two/1"],
             "did" => "move go/1, two/1 to b.ex"
           } = from_mcp

    assert elem(after_mcp, 0) =~ "defdelegate go(x), to: B\n"
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

  test "every door is made from a noun, or calls the verb layer itself" do
    assert length(Noun.modules()) >= 13
    listed = for tool <- Menard.MCP.__components__(:tool), do: {tool.handler, tool.name}

    for verbs <- Noun.modules(), noun = verbs.noun() do
      assert function_exported?(verbs, :run, 1), "#{inspect(verbs)} has no run/1"
      tool = Module.concat(Menard.MCP, Macro.camelize(noun.name))
      assert Code.ensure_loaded?(tool), "no MCP tool for #{noun.name}"
      assert {tool, noun.name} in listed, "the server does not list #{noun.name}"

      if noun[:cli] do
        task = Module.concat(Mix.Tasks.Menard, Macro.camelize(noun.name))
        assert Code.ensure_loaded?(task), "no mix task for #{noun.name}"
        # every verb the schema names has a shape, and none it does not
        named = for {:verb, :enum, opts} <- noun.fields, verb <- opts[:values], do: verb
        shaped = for {verb, _args} <- noun.cli.shapes, verb, uniq: true, do: verb
        assert Enum.sort(shaped) == Enum.sort(named), "#{noun.name}'s shapes and its verbs differ"
      end
    end

    # the tasks written by hand call the verb layer, as the ones made from a noun do
    for task <- Path.wildcard(Path.expand("../../lib/mix/tasks/menard.*.ex", __DIR__)),
        Path.basename(task) != "menard.mcp.ex" do
      # a writing verb's through `Verbs.call/2`, where its `then` runs
      assert File.read!(task) =~ ~r/\bVerbs\.([A-Z]\w+\.run|call)\(/,
             "#{Path.basename(task)} does not call the verb layer"
    end

    tools = Path.expand("../../lib/menard/mcp/tools.ex", __DIR__)

    refute File.read!(tools) =~
             ~r/Menard\.(Clause|Stmt|Attr|Block|Directive|Module|Rename|Find|Outline|Deps|Run|MixDeps)\./
  end

  test "a flag a verb cannot read is refused, not dropped", %{tmp_dir: dir} do
    # Found 2026-09-26: `block add … --label "--frozen still runs…"` read the label as another flag,
    # dropped both, and wrote `test %{tmp_dir: dir} do`: a nameless test, answered as a success
    for {task, argv} <- [
          {Mix.Tasks.Menard.Block, ["add", "lib/a_test.exs", "test", "assert 1", "--label", "--frozen two"]},
          {Mix.Tasks.Menard.Clause, ["get", "lib/a.ex", "two/1", "--modul", "A"]},
          {Mix.Tasks.Menard.Attr, ["get", "lib/a.ex", "limit", "--nope"]},
          {Mix.Tasks.Menard.Stmt, ["get", "lib/a.ex", "go/1", "0", "--nth", "x"]},
          {Mix.Tasks.Menard.Directive, ["list", "lib/a.ex", "--nope"]},
          {Mix.Tasks.Menard.Module, ["list", "lib/a.ex", "--nope"]},
          {Mix.Tasks.Menard.Outline, ["lib/a.ex", "--nope"]},
          {Mix.Tasks.Menard.Find, ["calls", "two", "lib/a.ex", "--nope"]},
          {Mix.Tasks.Menard.Rename, ["lib/a.ex", "two", "three", "--nope"]},
          {Mix.Tasks.Menard.Write, ["lib/w.ex", "x", "--nope"]},
          {Mix.Tasks.Menard.Deps, ["refs", "lib/a.ex", "go/1", "--nope"]}
        ] do
      assert {:error, "usage: " <> why} = cli(task, argv), "#{inspect(task)} took #{inspect(argv)}"
      assert why =~ ~r/--(label|modul|nope|nth)/
    end

    assert File.read!(Path.join(dir, "lib/a_test.exs")) =~ ~s(test "one")
    refute File.exists?(Path.join(dir, "lib/w.ex"))
  end

  test "edit is one reply at both doors, from a list and from search/replace blocks", %{tmp_dir: dir} do
    a = Path.join(dir, "lib/a.ex")
    before = File.read!(a)

    assert {:ok, from_mcp} =
             mcp(Menard.MCP.Edit, %{
               edits: [
                 %{file: "lib/a.ex", old: "  @limit 5", new: "  @limit 6"},
                 %{file: "lib/a.ex", old: "def two(n), do: n", new: "def two(n), do: n + 0"}
               ]
             })

    after_mcp = File.read!(a)
    File.write!(a, before)

    blocks =
      "lib/a.ex\n<<<<<<< SEARCH\n  @limit 5\n=======\n  @limit 6\n>>>>>>> REPLACE\n" <>
        "lib/a.ex\n<<<<<<< SEARCH\ndef two(n), do: n\n=======\ndef two(n), do: n + 0\n>>>>>>> REPLACE\n"

    assert {:ok, from_cli} = cli(Mix.Tasks.Menard.Edit, [blocks])
    assert File.read!(a) == after_mcp
    assert from_mcp["did"] == "edit a.ex: 2 replacements"
    strip = &Map.update!(&1, "changed", fn files -> Enum.map(files, fn file -> same(file) end) end)
    assert strip.(from_mcp) == strip.(from_cli)

    # and a refusal is the same sentence
    miss = [%{file: "lib/a.ex", old: "def three", new: "x"}]
    assert {:error, why} = mcp(Menard.MCP.Edit, %{edits: miss})
    assert why =~ "lib/a.ex: this text is not there"

    assert {:error, ^why} =
             cli(Mix.Tasks.Menard.Edit, ["lib/a.ex\n<<<<<<< SEARCH\ndef three\n=======\nx\n>>>>>>> REPLACE\n"])
  end
end
