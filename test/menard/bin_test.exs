defmodule Menard.BinTest do
  # bin/menard's stdout is the verb's answer and nothing else: tools read it (`attr get` → a value,
  # `run` → one JSON line). Not async: it deletes and rebuilds a build of menard's, its own env's.
  use ExUnit.Case, async: false

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
  defp fresh_build!, do: File.rm_rf!(Path.join(@root, "_build/bintest/lib/menard"))

  # this checkout's tracked files, its deps and its dev build, at DIR/menard
  defp checkout_copy!(dir) do
    copy = Path.join(dir, "menard")
    {files, 0} = System.cmd("git", ["-C", @root, "ls-files"])

    for f <- String.split(files, "\n", trim: true) do
      File.mkdir_p!(Path.dirname(Path.join(copy, f)))
      File.cp!(Path.join(@root, f), Path.join(copy, f))
    end

    File.cp_r!(Path.join(@root, "deps"), Path.join(copy, "deps"))
    File.mkdir_p!(Path.join(copy, "_build"))
    File.cp_r!(Path.join(@root, "_build/dev"), Path.join(copy, "_build/dev"))
    copy
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

    tasks =
      for task <- Path.wildcard(Path.join(@root, "lib/mix/tasks/menard.*.ex")),
          do: task |> Path.basename(".ex") |> String.replace_prefix("menard.", "")

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

  @caller [
    Path.expand("~/.local/share/mise/installs/elixir/1.20.4-otp-29/bin"),
    Path.expand("~/.local/share/mise/installs/erlang/29.0.6/bin")
  ]
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
end
