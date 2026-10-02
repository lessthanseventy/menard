defmodule Menard.MCPTest do
  # MENARD_ROOT is process-wide, so not async.
  use ExUnit.Case, async: false

  alias Anubis.Server.Frame
  alias Menard.MCP.Reply
  alias Menard.Verbs

  setup do
    root = Path.join(System.tmp_dir!(), "menard-mcp-#{System.pid()}-#{System.unique_integer([:positive])}")
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

  # The server as Claude Code runs it: cwd the plugin root, stdin held open, until its answer to
  # request `id` is out. A Port, not a pipe with a `sleep` holding stdin: no build first so the
  # answer lands inside a window, and no window to wait out once it has.
  defp serve(script, env, messages, id) do
    env = [{"BIN", Path.join(@root, "bin/menard")}, {"MIX_ENV", "dev"} | env]

    port =
      Port.open({:spawn_executable, "/bin/sh"}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        {:line, 65_536},
        args: ["-c", script],
        cd: @root,
        env: for({k, v} <- env, do: {String.to_charlist(k), String.to_charlist(v)})
      ])

    Port.command(port, Enum.map_join(messages, &(JSON.encode!(&1) <> "\n")))
    out = answer(port, ~s("id":#{id}), "")
    Port.close(port)
    out
  end

  # no deadline of its own: a server that never answers is the test's timeout
  defp answer(port, needle, out) do
    receive do
      {^port, {:data, {:eol, line}}} ->
        out = out <> line <> "\n"
        if out =~ needle, do: out, else: answer(port, needle, out)

      {^port, {:data, {:noeol, part}}} ->
        answer(port, needle, out <> part)

      {^port, {:exit_status, status}} ->
        flunk("the server exited #{status} before its answer #{needle}:\n#{out}")
    end
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

    refute response.isError, inspect(response.content)
    assert File.read!(Path.join(root, "mix.exs")) =~ ~s({:dep, path: "dep"})
  end

  test "the plugin's MCP server waits out a first start: deps fetch and compile, on a slow network" do
    # the verbs' server and the hooks', each
    for server <-
          Map.values(JSON.decode!(File.read!(Path.join(@root, ".claude-plugin/plugin.json")))["mcpServers"]) do
      # an integer: nil compares greater than any number, so `>=` alone passes on a missing field
      assert is_integer(server["timeout"]) and server["timeout"] >= 120_000
    end
  end

  @tag :tmp_dir
  test "the plugin's MCP server, started from the plugin root, works in the project MENARD_ROOT names", %{
    tmp_dir: dir
  } do
    File.mkdir_p!(Path.join(dir, "lib"))
    File.write!(Path.join(dir, "lib/a.ex"), "defmodule A do\n  def go, do: 1\nend\n")

    server = JSON.decode!(File.read!(Path.join(@root, ".claude-plugin/plugin.json")))["mcpServers"]["menard"]

    assert server["command"] == "${CLAUDE_PLUGIN_ROOT}/bin/menard"
    assert server["env"]["MENARD_ROOT"] == "${CLAUDE_PROJECT_DIR}"
    assert server["args"] == ["mcp"]

    messages = [
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

    # as Claude Code starts it: cwd the plugin root, the project in MENARD_ROOT
    out = serve(~S[exec "$BIN" mcp], [{"MENARD_ROOT", dir}], messages, 2)

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

  test "a root given with a trailing slash still admits paths under it", %{root: root} do
    System.put_env("MENARD_ROOT", root <> "/")
    assert {:ok, _} = Menard.MCP.resolve("lib/a.ex")
  end

  test "a symlink under the root that points outside it is refused", %{root: root} do
    outside =
      Path.join(System.tmp_dir!(), "menard-outside-#{System.pid()}-#{System.unique_integer([:positive])}")

    File.mkdir_p!(outside)
    on_exit(fn -> File.rm_rf!(outside) end)
    File.ln_s!(outside, Path.join(root, "lib/out"))

    assert {:error, "refused: lib/out/x.ex" <> _} = Menard.MCP.resolve("lib/out/x.ex")
    assert {:error, "refused: lib/out" <> _} = Menard.MCP.resolve_all(["lib/a.ex", "lib/out"])
    # a link that stays inside is as good as its target
    File.ln_s!(Path.join(root, "lib"), Path.join(root, "src"))
    assert {:ok, _} = Menard.MCP.resolve("src/a.ex")
  end

  test "resolving many files costs each once" do
    # counted in reductions, the VM's own measure of work done, not by the clock: a wall-clock
    # bound failed on a loaded host with the code linear (3-4 s against 2 s)
    cost = fn n ->
      paths = for i <- 1..n, do: "lib/m#{i}.ex"
      {:reductions, before} = Process.info(self(), :reductions)
      {:ok, resolved} = Menard.MCP.resolve_all(paths)
      {:reductions, done} = Process.info(self(), :reductions)
      assert length(resolved) == n
      done - before
    end

    # eight times the files is about eight times the work (8.4 measured); an append or a
    # membership test per file, what took 20,000 paths to 6 s, grows it past 12
    assert cost.(20_000) / cost.(2_500) < 12
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
    # named from the root
    assert to["file"] == "lib/b.ex"
    assert from["file"] == "lib/a.ex"

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

  test "stmt and attr get answer through the door", %{root: root} do
    file = Path.join(root, "lib/s.ex")
    File.write!(file, "defmodule S do\n  @limit 5\n\n  def go(x) do\n    y = x + 1\n    y\n  end\nend\n")

    refute call(Menard.MCP.Stmt, %{
             verb: "insert_after",
             file: "lib/s.ex",
             name_arity: "go/1",
             head: "x",
             match: "y = x + 1",
             code: "IO.inspect(y)"
           }).isError

    assert File.read!(file) =~ "    IO.inspect(y)\n    y\n"

    value = call(Menard.MCP.Attr, %{verb: "get", file: "lib/s.ex", name: "limit"})
    assert value.content |> hd() |> Map.fetch!("text") |> JSON.decode!() == %{"value" => "5"}
  end

  test "clause insert_at takes at: top/bottom through the door", %{root: root} do
    file = Path.join(root, "lib/t.ex")
    File.write!(file, "defmodule T do\n  def one, do: 1\n\n  defp helper, do: :h\nend\n")

    refute call(Menard.MCP.Clause, %{verb: "insert_at", file: "lib/t.ex", at: "top", code: "def zero, do: 0"}).isError

    refute call(Menard.MCP.Clause, %{
             verb: "insert_at",
             file: "lib/t.ex",
             at: "bottom",
             code: "def last, do: 9"
           }).isError

    assert File.read!(file) =~ "def zero, do: 0\n\n  def one, do: 1"
    assert File.read!(file) =~ "defp helper, do: :h\n\n  def last, do: 9"
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
    initialize = %{
      jsonrpc: "2.0",
      id: 1,
      method: "initialize",
      params: %{protocolVersion: "2025-06-18", capabilities: %{}, clientInfo: %{name: "t", version: "0"}}
    }

    err = Path.join(root, "err.log")

    # up to the answer to a second request: the logger writes stderr from a process of its own, and
    # the first frame's lines are well out by then
    out =
      serve(
        ~S[exec "$BIN" mcp 2>"$ERR"],
        [{"MENARD_ROOT", root}, {"MENARD_LOG_LEVEL", "debug"}, {"ERR", err}],
        [initialize, %{jsonrpc: "2.0", id: 2, method: "ping"}],
        2
      )

    lines = String.split(out, "\n", trim: true)
    assert [_ | _] = lines
    for line <- lines, do: assert({:ok, _} = JSON.decode(line), "not protocol on stdout: #{line}")
    # and the logs did happen, where they belong
    assert File.read!(err) =~ "[debug]"
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
    # a verb stuck on a lock, or a format that never returns: the answer names the deadline it was
    # given, and the stuck tool is killed, not left running. No clock bound: a deadline not kept
    # hangs this test, and ExUnit's own timeout fails it.
    defmodule Stuck do
      def call(%{test: test}, frame) do
        send(test, {:stuck, self()})
        Process.sleep(:infinity)
        {:reply, :never, frame}
      end
    end

    {:reply, response, _frame} = Reply.bounded(Stuck, %{test: self()}, Frame.new(), 200)

    assert response.isError
    assert response.content |> hd() |> Map.fetch!("text") =~ "did not finish in 0.2s"
    assert_received {:stuck, stuck}
    refute Process.alive?(stuck)
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

    version = JSON.decode!(text.(call(Menard.MCP.Outline, %{file: "lib/r.ex", json: true})))["version"]
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
    initialize = %{
      jsonrpc: "2.0",
      id: 1,
      method: "initialize",
      params: %{protocolVersion: "2025-06-18", capabilities: %{}, clientInfo: %{name: "t", version: "0"}}
    }

    # --frozen runs a build that must be there already: in a fresh checkout nothing else made it
    {_, 0} = System.cmd(Path.join(@root, "bin/menard"), ["version"], env: [{"MIX_ENV", "dev"}])

    assert serve(~S[exec "$BIN" --frozen mcp 2>/dev/null], [{"MENARD_ROOT", root}], [initialize], 1) =~
             ~s("id":1)
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
    # each file changed carries its own write reply: the version for the next edit, and its stages
    assert [%{"file" => changed, "version" => "sha256:" <> _, "stages" => [_ | _]}] = reply["changed"]
    assert changed == "lib/ok.ex"
    assert reply["unchanged"] == ["lib/none.ex"]
    assert [%{"file" => broken, "why" => why}] = reply["skipped"]
    assert broken == "lib/broken.ex"
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
    # the eval's haiku left `head` out of an edit of a one-clause function and got a KeyError back
    File.write!(
      Path.join(root, "lib/a.ex"),
      "defmodule A do\n  def one(x), do: x\n\n  def two(1), do: 1\n  def two(n), do: n\nend\n"
    )

    refute call(Menard.MCP.Clause, %{verb: "replace", file: "lib/a.ex", name_arity: "one/1", code: "x + 0"}).isError

    assert File.read!(Path.join(root, "lib/a.ex")) =~ "def one(x), do: x + 0"

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

    assert response.content |> hd() |> Map.fetch!("text") |> JSON.decode!() |> Map.fetch!("code") ==
             "assert 2"
  end

  test "clause delete takes several functions: one call, and the calls left to each", %{root: root} do
    # deleting four dead helpers took an `edit` that cut them out by hand, with no `left` to say whether
    # they were dead: one function a call was a call each
    File.write!(
      Path.join(root, "lib/b.ex"),
      "defmodule B do\n  def keep, do: one()\n\n  defp one, do: 1\n  defp two, do: 2\n  defp three, do: two()\nend\n"
    )

    response =
      call(Menard.MCP.Clause, %{verb: "delete", file: "lib/b.ex", name_arity: ["one/0", "two/0", "three/0"]})

    refute response.isError
    assert File.read!(Path.join(root, "lib/b.ex")) == "defmodule B do\n  def keep, do: one()\nend\n"
    reply = response.content |> hd() |> Map.fetch!("text") |> JSON.decode!()
    assert reply["did"] =~ "delete one/0, two/0, three/0"
    # what is still called: one/0, by keep; two/0's caller went with it
    assert reply["left"] == ["lib/b.ex:2: one()"]
  end

  test "an edit with no then is bounded as any verb, not by the tests a then would run" do
    # 2026-10-01 00:50: an edit of three small writes, no `then`, went silent past the client's 120s.
    # Its 600s are for the tests a `then` runs; without one it is bounded as any verb
    assert Reply.deadline(600_000, Verbs.Edit, %{edits: []}) == 90_000
    assert Reply.deadline(600_000, Verbs.Edit, %{edits: [], then: "test"}) == 600_000
    assert Reply.deadline(600_000, Verbs.Run, %{verb: "check"}) == 600_000
  end

  test "the MCP outline answers the CLI's text, json: true the map", %{root: root} do
    # Fable 2026-10-01: MCP's outline was JSON, the CLI's text, 26,710 against 18,190 characters for one
    # 1,950-line file. MCP answers the text; `json: true` is the map
    File.write!(Path.join(root, "lib/o.ex"), "defmodule O do\n  def go(x), do: x\nend\n")

    text = call(Menard.MCP.Outline, %{file: "lib/o.ex"}).content |> hd() |> Map.fetch!("text")
    assert text =~ "def go/1 (x)  L2-2"
    refute text =~ ~s("defs")

    json = call(Menard.MCP.Outline, %{file: "lib/o.ex", json: true}).content |> hd() |> Map.fetch!("text")
    assert %{"modules" => [_]} = JSON.decode!(json)
  end
end
