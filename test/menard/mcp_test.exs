defmodule Menard.MCPTest do
  # MENARD_ROOT is process-wide, so not async.
  use ExUnit.Case, async: false

  alias Anubis.Server.Frame
  alias Menard.MCP.Reply

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

  @root Path.expand("../..", __DIR__)

  defp call(tool, params) do
    {:reply, response, _frame} = tool.execute(params, Frame.new())
    response
  end

  test "module replace swaps one module of several; an unknown verb is refused, not treated as add", %{
    root: root
  } do
    file = Path.join(root, "lib/two.ex")
    File.write!(file, "defmodule One do\n  def a, do: 1\nend\n\ndefmodule Two do\n  def b, do: 2\nend\n")

    refute call(Menard.MCP.Module, %{
             verb: "replace",
             file: "lib/two.ex",
             module: "Two",
             code: "defmodule Two do\n  def b, do: :two\nend"
           }).isError

    assert File.read!(file) =~ "def a, do: 1"
    assert File.read!(file) =~ "def b, do: :two"

    assert call(Menard.MCP.Module, %{verb: "nope", file: "lib/two.ex"}).isError
  end

  test "deps add writes, fetches and compiles a dependency, answering with the lock diff", %{root: root} do
    File.write!(Path.join(root, "mix.exs"), """
    defmodule Host.MixProject do
      use Mix.Project
      def project, do: [app: :host, version: "0.1.0", deps: []]
    end
    """)

    dep = Path.join(root, "dep")
    File.mkdir_p!(Path.join(dep, "lib"))

    File.write!(
      Path.join(dep, "mix.exs"),
      "defmodule Dep.MixProject do\n  use Mix.Project\n  def project, do: [app: :dep, version: \"0.1.0\"]\nend\n"
    )

    File.write!(Path.join(dep, "lib/dep.ex"), "defmodule Dep do\nend\n")

    response = call(Menard.MCP.Deps, %{verb: "add", spec: ~s({:dep, path: "dep"})})

    refute response.isError
    assert File.read!(Path.join(root, "mix.exs")) =~ ~s({:dep, path: "dep"})
  end

  test "the plugin's MCP server waits out a first start: deps fetch and compile, on a slow network" do
    [server] =
      Map.values(JSON.decode!(File.read!(Path.join(@root, "manos/.claude-plugin/plugin.json")))["mcpServers"])

    # an integer: nil compares greater than any number, so `>=` alone passes on a missing field
    assert is_integer(server["timeout"]) and server["timeout"] >= 120_000
  end

  @tag :tmp_dir
  test "the plugin's MCP server, started from the plugin root, works in the project MENARD_ROOT names", %{
    tmp_dir: dir
  } do
    File.mkdir_p!(Path.join(dir, "lib"))
    File.write!(Path.join(dir, "lib/a.ex"), "defmodule A do\n  def go, do: 1\nend\n")

    [server] =
      Map.values(JSON.decode!(File.read!(Path.join(@root, "manos/.claude-plugin/plugin.json")))["mcpServers"])

    assert server["command"] == "${CLAUDE_PLUGIN_ROOT}/../bin/menard"
    assert server["env"]["MENARD_ROOT"] == "${CLAUDE_PROJECT_DIR}"
    assert server["args"] == ["mcp"]

    messages =
      [
        %{
          jsonrpc: "2.0",
          id: 1,
          method: "initialize",
          params: %{protocolVersion: "2025-06-18", capabilities: %{}, clientInfo: %{name: "t", version: "0"}}
        },
        %{jsonrpc: "2.0", method: "notifications/initialized"},
        %{
          jsonrpc: "2.0",
          id: 2,
          method: "tools/call",
          params: %{name: "outline", arguments: %{file: "lib/a.ex"}}
        }
      ]
      |> Enum.map_join("\n", &JSON.encode!/1)

    input = Path.join(dir, "in.jsonl")
    File.write!(input, messages <> "\n")

    # built first, so the server answers inside the window below instead of compiling through it
    System.cmd(Path.join(@root, "bin/menard"), ["version"], env: [{"MIX_ENV", "dev"}])

    # as Claude Code starts it: cwd the plugin root, the project in MENARD_ROOT, stdin held open briefly
    {out, _} =
      System.cmd("sh", ["-c", ~S[(cat "$IN"; sleep 5) | "$BIN" mcp]],
        cd: @root,
        env: [
          {"MENARD_ROOT", dir},
          {"MIX_ENV", "dev"},
          {"IN", input},
          {"BIN", Path.join(@root, "bin/menard")}
        ],
        stderr_to_stdout: true
      )

    assert out =~ ~s("id":2)
    # no failed call and no crash; the word "error" alone is in the server's own instructions
    refute out =~ ~s("isError":true)
    refute out =~ "** ("
    assert out =~ "go"
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

    # both files' replies, as any write gives: the version for the next edit, and what changed
    reply = response.content |> hd() |> Map.fetch!("text") |> JSON.decode!()
    assert %{"created" => "B", "to" => to, "from" => from} = reply
    assert to["file"] == Path.join(root, "lib/b.ex")
    assert from["file"] == Path.join(root, "lib/a.ex")

    for {one, path} <- [{to, "lib/b.ex"}, {from, "lib/a.ex"}] do
      assert one["version"] == Menard.remember(File.read!(Path.join(root, path)))
      assert [%{"stage" => "patch", "hunks" => [_ | _]} | _] = one["stages"]
    end
  end

  test "a move with no `to`, or refs with no `file`, is refused by name, not read as the root", %{
    root: root
  } do
    File.write!(Path.join(root, "lib/a.ex"), "defmodule A do\n  def go, do: 1\nend\n")
    text = &(&1.content |> hd() |> Map.fetch!("text"))

    moved = call(Menard.MCP.Clause, %{verb: "move", file: "lib/a.ex", name_arity: "go/0"})
    assert moved.isError
    assert text.(moved) =~ "clause move needs to"

    refs = call(Menard.MCP.Deps, %{verb: "refs", name_arity: "go/0"})
    assert refs.isError
    assert text.(refs) =~ "deps refs needs file"
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

  test "stdout carries only the protocol, even with debug logs on", %{root: root} do
    # the task sets this up itself: a host that takes menard as a dep never loads menard's config/
    # the task sets this up itself: a host that takes menard as a dep never loads menard's config/
    input = Path.join(root, "in.jsonl")

    File.write!(
      input,
      JSON.encode!(%{
        jsonrpc: "2.0",
        id: 1,
        method: "initialize",
        params: %{protocolVersion: "2025-06-18", capabilities: %{}, clientInfo: %{name: "t", version: "0"}}
      }) <> "\n"
    )

    System.cmd(Path.join(@root, "bin/menard"), ["version"], env: [{"MIX_ENV", "dev"}])

    {out, _} =
      System.cmd("sh", ["-c", ~S[(cat "$IN"; sleep 3) | "$BIN" mcp 2>"$ERR"]],
        cd: @root,
        env: [
          {"MENARD_ROOT", root},
          {"MENARD_LOG_LEVEL", "debug"},
          {"MIX_ENV", "dev"},
          {"IN", input},
          {"ERR", Path.join(root, "err.log")},
          {"BIN", Path.join(@root, "bin/menard")}
        ]
      )

    lines = String.split(out, "\n", trim: true)
    assert [_ | _] = lines
    for line <- lines, do: assert({:ok, _} = JSON.decode(line), "not protocol on stdout: #{line}")
    # and the logs did happen, where they belong
    assert File.read!(Path.join(root, "err.log")) =~ "[debug]"
  end

  test "a stale version is refused through the door, and force writes anyway", %{root: root} do
    file = Path.join(root, "lib/v.ex")
    text = fn response -> response.content |> hd() |> Map.fetch!("text") end

    # `write` answers with the staged reply like every other writing tool, version included
    first = call(Menard.MCP.Write, %{file: "lib/v.ex", code: "defmodule V do\n  def go, do: 1\nend\n"})
    refute first.isError
    version = JSON.decode!(text.(first))["version"]
    assert "sha256:" <> _ = version

    File.write!(file, "defmodule V do\n  def go, do: 2\nend\n")

    stale =
      call(Menard.MCP.Clause, %{
        verb: "replace",
        file: "lib/v.ex",
        name_arity: "go/0",
        head: "",
        code: "3",
        version: version
      })

    assert stale.isError
    assert text.(stale) =~ "stale"
    assert File.read!(file) =~ "do: 2"

    forced =
      call(Menard.MCP.Clause, %{
        verb: "replace",
        file: "lib/v.ex",
        name_arity: "go/0",
        head: "",
        code: "3",
        version: version,
        force: true
      })

    refute forced.isError
    assert File.read!(file) =~ "do: 3"
  end

  test "a tool that never returns still gets an answer out of the door, in time" do
    # a verb stuck on a lock, or a format that never returns, must still get an answer out of the door
    defmodule Stuck do
      def call(_params, frame) do
        Process.sleep(:infinity)
        {:reply, :never, frame}
      end
    end

    {us, {:reply, response, _frame}} =
      :timer.tc(fn -> Reply.bounded(Stuck, %{}, Frame.new(), 200) end)

    assert response.isError
    assert response.content |> hd() |> Map.fetch!("text") =~ "did not finish in"
    assert us < 2_000_000
  end

  test "a tool that exits, or loses a process it linked, answers why; the door lives on" do
    # the tool ran in a Task linked to the server: an exit it did not catch took the server's process
    # with it, and one that was caught was reported as a timeout
    defmodule Exits do
      def call(%{how: :exit}, _frame), do: exit(:gave_up)

      def call(%{how: :link}, _frame) do
        spawn_link(fn -> exit(:helper_died) end)
        Process.sleep(:infinity)
      end

      def call(%{how: :raise}, _frame), do: raise("menard bug")
    end

    text = &(&1.content |> hd() |> Map.fetch!("text"))

    for {how, why} <- [exit: "gave_up", link: "helper_died", raise: "menard bug"] do
      {:reply, response, _frame} = Reply.bounded(Exits, %{how: how}, Frame.new(), 2_000)
      assert response.isError
      assert text.(response) =~ why
      refute text.(response) =~ "did not finish"
    end

    # a raise keeps where it came from: the trace is what fixes a bug in menard
    {:reply, raised, _frame} = Reply.bounded(Exits, %{how: :raise}, Frame.new(), 2_000)
    assert text.(raised) =~ "Exits.call/2"
  end

  test "every tool answers through the deadline" do
    # every tool answers through bounded/4: its body is call/2, and execute/2 only puts a deadline on it
    for %{handler: tool} <- Menard.MCP.__components__(:tool) do
      assert function_exported?(tool, :call, 2), "#{inspect(tool)} answers without a deadline"
    end
  end

  test "rename through the door checks each file's version first", %{root: root} do
    file = Path.join(root, "lib/r.ex")
    File.write!(file, "defmodule R do\n  def old, do: 1\nend\n")
    text = fn response -> response.content |> hd() |> Map.fetch!("text") end

    version = JSON.decode!(text.(call(Menard.MCP.Outline, %{file: "lib/r.ex"})))["version"]
    File.write!(file, "defmodule R do\n  def old, do: 2\nend\n")

    stale =
      call(Menard.MCP.Rename, %{
        old: "old",
        new: "new",
        files: ["lib/r.ex"],
        versions: ["lib/r.ex=#{version}"]
      })

    assert stale.isError
    assert text.(stale) =~ "stale"
    assert File.read!(file) =~ "def old, do: 2"
  end

  test "the door answers under --frozen too", %{root: root} do
    # `--frozen` runs the last build with no mix project, and app.start in the mcp task died there
    input = Path.join(root, "in.jsonl")

    File.write!(
      input,
      JSON.encode!(%{
        jsonrpc: "2.0",
        id: 1,
        method: "initialize",
        params: %{protocolVersion: "2025-06-18", capabilities: %{}, clientInfo: %{name: "t", version: "0"}}
      }) <> "\n"
    )

    System.cmd(Path.join(@root, "bin/menard"), ["version"], env: [{"MIX_ENV", "dev"}])

    {out, _} =
      System.cmd("sh", ["-c", ~S[(cat "$IN"; sleep 3) | "$BIN" --frozen mcp 2>/dev/null]],
        cd: @root,
        env: [
          {"MENARD_ROOT", root},
          {"MIX_ENV", "dev"},
          {"IN", input},
          {"BIN", Path.join(@root, "bin/menard")}
        ]
      )

    assert out =~ ~s("id":1)
  end

  test "attr set names the attribute once, whether or not it was given with its @", %{root: root} do
    File.write!(Path.join(root, "lib/a.ex"), "defmodule A do\n  @t 1\n\n  def go, do: @t\nend\n")

    for name <- ["t", "@t"] do
      text =
        call(Menard.MCP.Attr, %{verb: "set", file: "lib/a.ex", name: name, value: "2"}).content
        |> hd()
        |> Map.fetch!("text")

      assert text =~ "set @t in a.ex"
      refute text =~ "@@"
    end
  end

  test "rename's versions: a path outside the root is refused as that, not as a bad FILE=SHA", %{
    root: root
  } do
    File.write!(Path.join(root, "lib/r.ex"), "defmodule R do\n  def old, do: 1\nend\n")
    text = &(&1.content |> hd() |> Map.fetch!("text"))
    rename = &call(Menard.MCP.Rename, %{old: "old", new: "fresh", files: ["lib/r.ex"], versions: [&1]})

    assert text.(rename.("../elsewhere.ex=sha256:00")) =~ "refused: ../elsewhere.ex is outside"
    assert text.(rename.("lib/r.ex")) =~ "versions are FILE=SHA"
  end

  test "rename names a file it could not parse, apart from the ones it had nothing to do in", %{
    root: root
  } do
    # both were "unchanged": an agent took a file with the old name still in it for one without
    File.write!(Path.join(root, "lib/ok.ex"), "defmodule Ok do\n  def old, do: 1\nend\n")
    File.write!(Path.join(root, "lib/none.ex"), "defmodule None do\nend\n")
    File.write!(Path.join(root, "lib/broken.ex"), "defmodule Broken do\n  def old, do: (\nend\n")

    response =
      call(Menard.MCP.Rename, %{
        old: "old",
        new: "fresh",
        files: ["lib/ok.ex", "lib/none.ex", "lib/broken.ex"]
      })

    reply = response.content |> hd() |> Map.fetch!("text") |> JSON.decode!()
    assert reply["changed"] == [Path.join(root, "lib/ok.ex")]
    assert reply["unchanged"] == [Path.join(root, "lib/none.ex")]
    assert [%{"file" => broken, "why" => why}] = reply["skipped"]
    assert broken == Path.join(root, "lib/broken.ex")
    assert why =~ "not parseable"
  end

  test "rename takes globs in files, and a glob that matches nothing is refused by name", %{root: root} do
    File.mkdir_p!(Path.join(root, "lib/sub"))
    File.write!(Path.join(root, "lib/a.ex"), "defmodule A do\n  def old, do: 1\nend\n")
    File.write!(Path.join(root, "lib/sub/b.ex"), "defmodule B do\n  def go, do: A.old()\nend\n")

    refute call(Menard.MCP.Rename, %{old: "old", new: "fresh", files: ["lib/**/*.ex"]}).isError
    assert File.read!(Path.join(root, "lib/a.ex")) =~ "def fresh"
    assert File.read!(Path.join(root, "lib/sub/b.ex")) =~ "A.fresh()"

    # beside one that matches, an empty glob is no reason to refuse: the eval's agent wrote
    # `test/**/*.ex` for tests that are .exs, and lost a turn to it
    refute call(Menard.MCP.Rename, %{old: "fresh", new: "fine", files: ["lib/**/*.ex", "test/**/*.ex"]}).isError

    assert File.read!(Path.join(root, "lib/a.ex")) =~ "def fine"

    response = call(Menard.MCP.Rename, %{old: "fine", new: "x", files: ["lib/**/*.exs"]})
    assert response.isError
    assert response.content |> hd() |> Map.fetch!("text") =~ "no file matches lib/**/*.exs"
  end

  test "block add in a test file writes a test when no name is given", %{root: root} do
    File.write!(
      Path.join(root, "lib/a_test.exs"),
      "defmodule ATest do\n  use ExUnit.Case\n\n  test \"one\" do\n    assert true\n  end\nend\n"
    )

    refute call(Menard.MCP.Block, %{verb: "add", file: "lib/a_test.exs", label: "two", code: "assert 2"}).isError

    assert File.read!(Path.join(root, "lib/a_test.exs")) =~ "test \"two\" do\n    assert 2\n  end"
  end

  test "the server tells an agent up front what its tools are for, starting from outline" do
    # the guard is gone (bench5: a formatting hook alone gave the clean output), so the instructions
    # say where the tools win over a plain Edit, not that Edit is refused
    text = Menard.MCP.server_instructions()
    assert text =~ "rename"
    assert text =~ "outline"
    assert text =~ "run"
  end

  test "a clause verb with no head takes a function's only clause, and among several names their heads", %{
    root: root
  } do
    # the eval's haiku left `head` out of a `doc` on a one-clause function and got a KeyError back
    File.write!(
      Path.join(root, "lib/a.ex"),
      "defmodule A do\n  def one(x), do: x\n\n  def two(1), do: 1\n  def two(n), do: n\nend\n"
    )

    refute call(Menard.MCP.Clause, %{verb: "doc", file: "lib/a.ex", name_arity: "one/1", text: "The one."}).isError

    assert File.read!(Path.join(root, "lib/a.ex")) =~ "@doc \"\"\"\n  The one.\n  \"\"\"\n  def one(x)"

    response = call(Menard.MCP.Clause, %{verb: "replace", file: "lib/a.ex", name_arity: "two/1", code: "0"})
    assert response.isError
    assert response.content |> hd() |> Map.fetch!("text") =~ "n"
    refute response.content |> hd() |> Map.fetch!("text") =~ "KeyError"

    response = call(Menard.MCP.Clause, %{verb: "replace", file: "lib/a.ex", head: "x", code: "0"})
    assert response.isError
    assert response.content |> hd() |> Map.fetch!("text") =~ "name_arity"
  end

  test "clause delete with no head deletes the whole function, and names the calls it left", %{root: root} do
    # a function of eight clauses took eight deletes; and what still calls it is the agent's to fix
    File.write!(
      Path.join(root, "lib/a.ex"),
      "defmodule A do\n  def keep, do: two(1)\n\n  def two(1), do: 1\n  def two(n), do: n\nend\n"
    )

    File.mkdir_p!(Path.join(root, "test"))

    File.write!(
      Path.join(root, "test/a_test.exs"),
      "defmodule ATest do\n  use ExUnit.Case\n\n  test \"two\" do\n    assert A.two(2) == 2\n  end\nend\n"
    )

    response = call(Menard.MCP.Clause, %{verb: "delete", file: "lib/a.ex", name_arity: "two/1"})
    refute response.isError
    refute File.read!(Path.join(root, "lib/a.ex")) =~ "def two"
    left = response.content |> hd() |> Map.fetch!("text") |> JSON.decode!() |> Map.fetch!("left")
    assert "lib/a.ex:2: two(1)" in left
    assert ~s(test/a_test.exs:5, in test "two": A.two(2\)) in left
  end

  test "a call the schema refuses answers with why, as a tool error the agent can read", %{root: root} do
    # bench2 bug-receipt-total.B.haiku asked clause for verb "get" (none then) and got "Invalid params": the
    # detail rides in the error's data, which Claude Code does not show
    File.write!(Path.join(root, "lib/a.ex"), "defmodule A do\n  def a, do: 1\nend\n")

    request = %{
      "method" => "tools/call",
      "params" => %{"name" => "clause", "arguments" => %{"file" => "lib/a.ex", "verb" => "fetch"}}
    }

    assert {:reply, %{"isError" => true, "content" => [%{"text" => text}]}, _frame} =
             Menard.MCP.handle_request(request, Frame.new())

    assert text =~ "verb"
    assert text =~ "replace"
  end

  test "clause get answers with the function as written and the file's version, and writes nothing", %{
    root: root
  } do
    file = Path.join(root, "lib/a.ex")
    File.write!(file, "defmodule A do\n  def keep, do: 1\n\n  def two(1), do: 1\n  def two(n), do: n\nend\n")
    before = File.read!(file)

    response = call(Menard.MCP.Clause, %{verb: "get", file: "lib/a.ex", name_arity: "two/1"})
    refute response.isError
    got = response.content |> hd() |> Map.fetch!("text") |> JSON.decode!()
    assert got["code"] == "def two(1), do: 1\ndef two(n), do: n"
    assert got["lines"] == [4, 5]
    assert got["version"] =~ "sha256:"
    assert File.read!(file) == before
  end

  test "attr replace is set, as every other tool calls it", %{root: root} do
    # bench3 bug-receipt-total.B.haiku: attr {verb: "replace"} was refused
    File.write!(Path.join(root, "lib/a.ex"), "defmodule A do\n  @t 1\n\n  def go, do: @t\nend\n")
    refute call(Menard.MCP.Attr, %{verb: "replace", file: "lib/a.ex", name: "t", value: "2"}).isError
    assert File.read!(Path.join(root, "lib/a.ex")) =~ "@t 2"
  end

  test "block get with no label, among several, answers with every one", %{root: root} do
    File.write!(
      Path.join(root, "lib/a_test.exs"),
      "defmodule ATest do\n  use ExUnit.Case\n\n  test \"a\" do\n    assert 1\n  end\n\n  test \"b\" do\n    assert 2\n  end\nend\n"
    )

    response = call(Menard.MCP.Block, %{verb: "get", file: "lib/a_test.exs", name: "test"})
    refute response.isError
    blocks = response.content |> hd() |> Map.fetch!("text") |> JSON.decode!() |> Map.fetch!("blocks")
    assert Enum.map(blocks, & &1["label"]) == ["a", "b"]
    response = call(Menard.MCP.Block, %{verb: "get", file: "lib/a_test.exs", name: "test", label: "b"})

    assert response.content |> hd() |> Map.fetch!("text") |> JSON.decode!() |> Map.fetch!("body") ==
             "assert 2"
  end
end
