defmodule Menard.BinCopyTest do
  # bin/menard on a copy of this checkout, built there: a test that breaks menard's source, or its
  # mix.lock, breaks the copy's. Nothing here touches this checkout's own builds, so these run
  # beside every other async module; in Menard.BinTest (not async: it rebuilds a build of
  # menard's) their 160 s ran one after another, the bulk of the suite's serial half.
  use ExUnit.Case, async: true

  # a copy builds menard from its deps: 22 s at load 55 for the first verb; the cold mcp case
  # past 60 s there
  @moduletag timeout: 300_000

  @root Path.expand("../..", __DIR__)

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
  test "--frozen still runs the last good build after a `run compile` of menard itself failed", %{
    tmp_dir: dir
  } do
    # 2026-10-20: `--frozen edit --then compile` on an edit that broke lib/mix/tasks/menard.edit.ex
    # compiled through the verb, not through this file's own build step, so nothing put the beams
    # back; the next `--frozen edit` said the task menard.edit could not be found
    copy = checkout_copy!(dir)
    bin = Path.join(copy, "bin/menard")
    env = [{"MIX_ENV", "dev"}]
    file = Path.join(dir, "a.ex")
    File.write!(file, "defmodule A do\n  def go, do: 1\nend\n")
    {_, 0} = System.cmd(bin, ["version"], env: env, stderr_to_stdout: true)

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

    assert {out, 1} =
             System.cmd(bin, ["--frozen", "run", "compile", "--in", copy], env: env, stderr_to_stdout: true)

    assert out =~ "not_there_yet"

    assert {out, 0} = System.cmd(bin, ["--frozen", "outline", file], env: env, stderr_to_stdout: true)
    assert out =~ "go/0"
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
end
