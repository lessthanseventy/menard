defmodule Menard.BinTest do
  # bin/menard's stdout is the verb's answer and nothing else: tools read it (`attr get` → a value,
  # `run` → one JSON line). Not async: it deletes and rebuilds a build of menard's, its own env's.
  use ExUnit.Case, async: false

  alias Menard.Test.Host
  alias Menard.Verbs.Noun

  # A verb run without --frozen compiles menard first, and in a fresh worktree every dep with it:
  # 28 s cold at load average 17, past ExUnit's 60 s default on a host loaded 60 and more
  @moduletag timeout: 300_000

  @root Path.expand("../..", __DIR__)
  @bin Path.join(@root, "bin/menard")

  # A build of its own to delete: the dev build is the one the hooks, the agent's verbs and the gate
  # running this suite all run from, and deleting it under them printed "redefining module" warnings
  # into the gate's reply and "The task menard.run could not be found" (reproduced: a gate while the
  # dev build was deleted and rebuilt beside it)
  @fresh [{"MIX_ENV", "bintest"}]
  @caller [
    Path.expand("~/.local/share/mise/installs/elixir/1.20.4-otp-29/bin"),
    Path.expand("~/.local/share/mise/installs/erlang/29.0.6/bin")
  ]

  defp fresh_build!, do: File.rm_rf!(Path.join(@root, "_build/bintest/lib/menard"))

  # this checkout's tracked files, its deps and its dev build, at DIR/menard
  defp checkout_copy!(dir) do
    copy = Path.join(dir, "menard")
    {files, 0} = System.cmd("git", ["-C", @root, "ls-files"])

    for f <- String.split(files, "\n", trim: true) do
      File.mkdir_p!(Path.dirname(Path.join(copy, f)))
      src = Path.join(@root, f)

      # a tracked symlink is a link in the copy too (eval's desk-tdd links desk's dirs: cp! refuses one)
      case File.read_link(src) do
        {:ok, target} -> File.ln_s!(target, Path.join(copy, f))
        {:error, _} -> File.cp!(src, Path.join(copy, f))
      end
    end

    File.cp_r!(Path.join(@root, "deps"), Path.join(copy, "deps"))
    File.mkdir_p!(Path.join(copy, "_build"))
    File.cp_r!(Path.join(@root, "_build/dev"), Path.join(copy, "_build/dev"))
    copy
  end

  # no deadline of its own: a server that never answers is the test's timeout
  defp recv_until(port, needle, out) do
    receive do
      {^port, {:data, {:eol, line}}} ->
        out = out <> line <> "\n"
        if out =~ needle, do: out, else: recv_until(port, needle, out)

      {^port, {:data, {:noeol, part}}} ->
        recv_until(port, needle, out <> part)

      {^port, {:exit_status, status}} ->
        flunk("the server exited #{status} before its answer #{needle}:\n#{out}")
    end
  end

  @tag :tmp_dir
  test "--stdin passes the last argument on stdin, quotes and backslashes intact", %{tmp_dir: dir} do
    file = Path.join(dir, "a.ex")
    File.write!(file, "defmodule A do\n  def go, do: 1\nend\n")
    code = Path.join(dir, "code.txt")
    File.write!(code, ~S|"it's" <> "\\\\n"|)

    {_out, 0} =
      System.cmd("sh", ["-c", "#{@bin} clause replace #{file} go/0 \"\" --stdin < #{code}"],
        env: [{"MIX_ENV", "dev"}]
      )

    assert File.read!(file) =~ ~S|def go, do: "it's" <> "\\\\n"|
  end

  @tag :tmp_dir
  test "a verb run right after menard's own source changed answers without the compile log", %{tmp_dir: dir} do
    file = Path.join(dir, "a.ex")
    File.write!(file, "defmodule A do\n  @limit 5_000\n\n  def go, do: @limit\nend\n")

    # nothing built: the next verb has to compile menard before it answers. The whole app dir, not
    # just its manifest — stale beams left behind get loaded and then "redefined", 43 warnings.
    fresh_build!()

    {out, 0} = System.cmd(@bin, ["attr", "get", file, "limit"], env: @fresh)
    assert out == ~s({"value":"5_000"}\n)
  end

  @tag :tmp_dir
  test "a build changed under menard between its compile and the verb leaves the answer alone", %{
    tmp_dir: dir
  } do
    # Found 2026-09-26: another process deleted and rebuilt _build between bin/menard's own compile
    # and the verb's mix, and the verb's mix compiled again, "Generated menard app" onto stdout
    # where the answer belongs. Deterministically: a dep's build gone after the last compile is what
    # the verb's own mix rebuilt, "==> sourceror … Generated menard app" ahead of the answer.
    file = Path.join(dir, "a.ex")
    File.write!(file, "defmodule A do\n  @limit 5_000\n\n  def go, do: @limit\nend\n")
    {_, 0} = System.cmd(@bin, ["version"], env: @fresh)
    File.rm_rf!(Path.join(@root, "_build/bintest/lib/sourceror"))

    {out, 0} = System.cmd(@bin, ["attr", "get", file, "limit"], env: @fresh, stderr_to_stdout: true)
    assert out == ~s({"value":"5_000"}\n)
  end

  @tag :tmp_dir
  test "a reader that stops early (`| head`) gets its lines and no crash", %{tmp_dir: dir} do
    # the BEAM's writer crashes on a closed stdout (:epipe) and printed a stack trace for it
    File.mkdir_p!(Path.join(dir, "lib"))

    for n <- 1..400,
        do: File.write!(Path.join(dir, "lib/m#{n}.ex"), "defmodule M#{n} do\n  def f, do: 1\nend\n")

    {out, status} =
      System.cmd("bash", ["-c", ~s("$0" map | head -1), @bin],
        cd: dir,
        env: [{"MIX_ENV", "dev"}, {"MENARD_CWD", dir}],
        stderr_to_stdout: true
      )

    assert status == 0
    assert out =~ ~r/\AM\d+  lib\/m\d+\.ex  f\/0\n\z/
  end

  @tag :tmp_dir
  test "a verb reading stdin gets it, even when menard compiles first", %{tmp_dir: dir} do
    file = Path.join(dir, "z.ex")
    fresh_build!()

    {_out, 0} =
      System.cmd("sh", ["-c", "printf 'defmodule Z do\\nend\\n' | #{@bin} write #{file} -"], env: @fresh)

    assert File.read!(file) == "defmodule Z do\nend\n"
  end

  test "a verb menard does not have is refused with the list of those it has, every one" do
    # it went to `mix menard.VERB` for mix's "could not be found", and the list left out two verbs
    {out, status} =
      System.cmd(@bin, ["--frozen", "nosuch"], stderr_to_stdout: true, env: [{"MIX_ENV", "dev"}])

    assert status == 2
    assert out =~ "menard: no verb nosuch"
    [_, listed] = Regex.run(~r/\(([a-z|]+)\)/, out)

    # the tasks written by hand, and the ones made from a noun (lib/mix/tasks/menard.ex)
    written =
      for task <- Path.wildcard(Path.join(@root, "lib/mix/tasks/menard.*.ex")),
          do: task |> Path.basename(".ex") |> String.replace_prefix("menard.", "")

    made = for verbs <- Noun.modules(), noun = verbs.noun(), noun[:cli], do: noun.name
    tasks = written ++ made

    assert Enum.sort(String.split(listed, "|")) == Enum.sort(tasks)
  end

  test "--frozen names its version" do
    # the version came from the app spec, never loaded under --frozen, or mix.exs, not there either
    {out, 0} = System.cmd(@bin, ["--frozen", "version"], env: [{"MIX_ENV", "dev"}])
    assert out =~ "menard #{Mix.Project.config()[:version]} on Elixir"
  end

  @tag :tmp_dir
  test "--frozen runs the build of MIX_ENV (dev by default), not whichever _build globs first", %{
    tmp_dir: dir
  } do
    # a checkout with dev, docs and test builds: all three were on the code path, and the glob's
    # order picked the module. Each build's `version` here names its env.
    File.mkdir_p!(Path.join(dir, "bin"))
    File.cp!(@bin, Path.join(dir, "bin/menard"))
    File.cp!(Path.join(@root, ".tool-versions"), Path.join(dir, ".tool-versions"))

    for env <- ["dev", "docs", "test"] do
      ebin = Path.join(dir, "_build/#{env}/lib/fake/ebin")
      File.mkdir_p!(ebin)
      src = Path.join(dir, "#{env}.ex")

      File.write!(src, """
      defmodule Mix.Tasks.Menard.Version do
        def run(_argv), do: IO.puts("built for #{env}")
      end
      """)

      {_, 0} = System.cmd("elixirc", ["--ignore-module-conflict", "-o", ebin, src], stderr_to_stdout: true)
    end

    frozen = &System.cmd(Path.join(dir, "bin/menard"), ["--frozen", "version"], env: &1)
    assert {"built for dev\n", 0} = frozen.([{"MIX_ENV", nil}])
    assert {"built for test\n", 0} = frozen.([{"MIX_ENV", "test"}])
  end

  test "a build mix finds nothing to do in is not stale on the next call" do
    System.cmd(@bin, ["version"], env: [{"MIX_ENV", "dev"}])
    # same content, newer mtime: mix recompiles nothing, and must not be asked to again
    File.touch!(Path.join(@root, "lib/menard/source.ex"))
    System.cmd(@bin, ["version"], env: [{"MIX_ENV", "dev"}])

    manifest = Path.join(@root, "_build/dev/lib/menard/.mix/compile.elixir")

    newer =
      for f <- Path.wildcard(Path.join(@root, "lib/**/*.ex")),
          File.stat!(f).mtime > File.stat!(manifest).mtime,
          do: f

    assert newer == []
  end

  @tag skip:
         !(System.find_executable("mise") && Enum.all?(@caller, &File.dir?/1)) &&
           "needs mise with elixir 1.20.4-otp-29 and erlang 29.0.6 installed"
  test "runs on menard's own pinned toolchain, whatever the caller's PATH puts first" do
    path = Enum.join(@caller ++ [System.get_env("PATH")], ":")
    {out, 0} = System.cmd(@bin, ["version"], env: [{"PATH", path}, {"MIX_ENV", "dev"}])
    assert out =~ "on Elixir 1.19.4 / OTP 27"
  end

  @tag :tmp_dir
  test "a checkout whose mix.lock gained a dep since its first run fetches it, and says nothing", %{
    tmp_dir: dir
  } do
    # Found 2026-09-26: a worktree first run at an older commit, then moved to one whose mix.lock
    # has more deps. deps/ is untracked, so it kept the old ones, and the first-run check (one dep's
    # directory) passed: the compile died on "dependency not available". The same after any pull that
    # adds a dep. Here: a copy of this checkout, its deps and dev build, with one dep taken away.
    copy = checkout_copy!(dir)
    File.rm_rf!(Path.join(copy, "deps/jason"))
    # fetched for a mix.lock that had no jason yet
    lock = File.read!(Path.join(@root, "mix.lock"))
    old = lock |> String.split("\n") |> Enum.reject(&(&1 =~ ~s("jason":))) |> Enum.join("\n")
    File.write!(Path.join(copy, "deps/.menard-mix-lock"), old)

    # stdout the answer, stderr nothing: fetching and building itself is menard's business
    assert {"menard " <> _, 0} =
             System.cmd(Path.join(copy, "bin/menard"), ["version"],
               env: [{"MIX_ENV", "dev"}],
               stderr_to_stdout: true
             )

    assert File.dir?(Path.join(copy, "deps/jason"))
  end

  @tag :tmp_dir
  test "--frozen still runs the last good build after a verb without it failed to compile menard", %{
    tmp_dir: dir
  } do
    # Found 2026-09-26: one verb run without --frozen mid-edit (menard not compiling) failed its
    # compile, and the compiler had already removed the beams of the modules it was recompiling;
    # every --frozen verb after it died on "module Menard.Source is not available".
    copy = checkout_copy!(dir)
    bin = Path.join(copy, "bin/menard")
    env = [{"MIX_ENV", "dev"}]
    file = Path.join(dir, "a.ex")
    File.write!(file, "defmodule A do\n  def go, do: 1\nend\n")
    {_, 0} = System.cmd(bin, ["version"], env: env, stderr_to_stdout: true)

    # a half-applied edit: a clause calling a helper the next call adds
    source = Path.join(copy, "lib/menard/source.ex")

    File.write!(
      source,
      String.replace(
        File.read!(source),
        "defmodule Menard.Source do\n",
        "defmodule Menard.Source do\n  def half, do: not_there_yet()\n",
        global: false
      )
    )

    assert {_, 1} = System.cmd(bin, ["outline", file], env: env, stderr_to_stdout: true)

    assert {out, 0} = System.cmd(bin, ["--frozen", "outline", file], env: env, stderr_to_stdout: true)
    assert out =~ "go/0"
  end

  @tag :tmp_dir
  test "every VM menard starts has its schedulers' busy wait off, the caller's flags after", %{tmp_dir: dir} do
    # A VM's schedulers spin while they wait: a one-test `mix test` was 4 CPU-seconds in half a second,
    # every core busy, and the gate's hundreds of VMs 2,450 CPU-seconds. Every VM menard starts, and
    # every one those start, has them off; the caller's own ERL_FLAGS come after them, and win
    Host.mix_project(dir, :quiet)
    File.mkdir_p!(Path.join(dir, "test"))
    File.write!(Path.join(dir, "test/test_helper.exs"), "ExUnit.start()\n")

    File.write!(Path.join(dir, "test/quiet_test.exs"), """
    defmodule QuietTest do
      use ExUnit.Case
      test "busy wait is off", do: assert(System.get_env("ERL_FLAGS") =~ ~r/^\\+sbwt none .*\\+S 2$/)
    end
    """)

    {out, 0} =
      System.cmd(@bin, ["run", "test", "--in", dir], env: [{"ERL_FLAGS", "+S 2"}], stderr_to_stdout: true)

    assert out =~ ~s("ok":true)
  end

  @tag :tmp_dir
  test "mcp answers initialize fast, from a cold build that would otherwise outrun a client's connect timeout",
       %{tmp_dir: dir} do
    # a fresh install has no _build at all: deps/ untouched (fetching needs the network), but
    # every dep's compile gone too, so `mix compile` has to rebuild all of it, the slow part a
    # cold install pays (bin_test.exs's own note above: 28s at load average 17)
    copy = checkout_copy!(dir)
    File.rm_rf!(Path.join(copy, "_build/dev"))

    root = Path.join(dir, "project")
    File.mkdir_p!(Path.join(root, "lib"))
    File.write!(Path.join(root, "lib/a.ex"), "defmodule A do\n  def go, do: 1\nend\n")

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

    env = [
      {~c"BIN", String.to_charlist(Path.join(copy, "bin/menard"))},
      {~c"MIX_ENV", ~c"dev"},
      {~c"MENARD_ROOT", String.to_charlist(root)}
    ]

    port =
      Port.open({:spawn_executable, "/bin/sh"}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        {:line, 65_536},
        args: ["-c", ~S[exec "$BIN" mcp 2>/dev/null]],
        cd: copy,
        env: env
      ])

    started = System.monotonic_time(:millisecond)
    Port.command(port, Enum.map_join(messages, &(JSON.encode!(&1) <> "\n")))

    first = recv_until(port, ~s("id":1), "")
    answered_init_in = System.monotonic_time(:millisecond) - started
    rest = recv_until(port, ~s("id":2), "")
    Port.close(port)

    # well under Claude Code's 30 s connect timeout, even though the compile behind it is ~28 s
    assert answered_init_in < 10_000, "initialize took #{answered_init_in}ms:\n#{first}"
    assert rest =~ "go"
    refute first <> rest =~ "** ("
  end

  @tag :tmp_dir
  test "edit --then at the CLI runs the then, as the MCP door does", %{tmp_dir: dir} do
    # 2026-10-01 19:15: `then` moved to Verbs.call, the edit task still called Verbs.Edit.run, and
    # `--then test` was dropped without a word at the CLI. Held at the door the agent types
    Host.mix_project(dir, :thencli)
    File.mkdir_p!(Path.join(dir, "lib"))
    File.write!(Path.join(dir, "lib/t.ex"), "defmodule T do\n  def go, do: 1\nend\n")
    blocks = "lib/t.ex\n<<<<<<< SEARCH\ndef go, do: 1\n=======\ndef go, do: 2\n>>>>>>> REPLACE\n"

    # MENARD_CWD unset: a suite run by `bin/menard run test` inherits the caller's, and `cd:` is ours
    {out, 0} =
      System.cmd(@bin, ["edit", "--then", "compile", blocks],
        cd: dir,
        env: [{"MENARD_CWD", nil}],
        stderr_to_stdout: true
      )

    assert out =~ ~s("did":"edit t.ex: 1 replacement, then run compile")
    assert out =~ ~s("run":{"ok":true)
  end
end
