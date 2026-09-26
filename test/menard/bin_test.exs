defmodule Menard.BinTest do
  # bin/menard's stdout is the verb's answer and nothing else: tools read it (`attr get` → a value,
  # `run` → one JSON line). Not async: it rebuilds menard's dev build.
  use ExUnit.Case, async: false

  @root Path.expand("../..", __DIR__)
  @bin Path.join(@root, "bin/menard")

  defp fresh_build!, do: File.rm_rf!(Path.join(@root, "_build/dev/lib/menard"))

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

    {out, 0} = System.cmd(@bin, ["attr", "get", file, "limit"], env: [{"MIX_ENV", "dev"}])
    assert out == "5_000\n"
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
      System.cmd("sh", ["-c", "printf 'defmodule Z do\\nend\\n' | #{@bin} write #{file} -"],
        env: [{"MIX_ENV", "dev"}]
      )

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
    File.mkdir_p!(Path.join(dir, "deps/sourceror"))

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

  test "runs on menard's own pinned toolchain, whatever the caller's PATH puts first" do
    installs = Path.expand("~/.local/share/mise/installs")
    caller = [Path.join(installs, "elixir/1.20.4-otp-29/bin"), Path.join(installs, "erlang/29.0.6/bin")]

    if System.find_executable("mise") && Enum.all?(caller, &File.dir?/1) do
      path = Enum.join(caller ++ [System.get_env("PATH")], ":")
      {out, 0} = System.cmd(@bin, ["version"], env: [{"PATH", path}, {"MIX_ENV", "dev"}])
      assert out =~ "on Elixir 1.19.4 / OTP 27"
    end
  end
end
