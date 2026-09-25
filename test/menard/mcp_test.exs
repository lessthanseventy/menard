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
      Map.values(JSON.decode!(File.read!(Path.join(@root, ".claude-plugin/plugin.json")))["mcpServers"])

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
      Map.values(JSON.decode!(File.read!(Path.join(@root, ".claude-plugin/plugin.json")))["mcpServers"])

    assert server["command"] == "${CLAUDE_PLUGIN_ROOT}/bin/menard"
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
    refute out =~ "error"
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
      :timer.tc(fn -> Menard.MCP.Reply.bounded(Stuck, %{}, Frame.new(), 200) end)

    assert response.isError
    assert response.content |> hd() |> Map.fetch!("text") =~ "did not finish in"
    assert us < 2_000_000
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
end
