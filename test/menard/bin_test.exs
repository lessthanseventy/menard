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
  test "a verb reading stdin gets it, even when menard compiles first", %{tmp_dir: dir} do
    file = Path.join(dir, "z.ex")
    fresh_build!()

    {_out, 0} =
      System.cmd("sh", ["-c", "printf 'defmodule Z do\\nend\\n' | #{@bin} write #{file} -"],
        env: [{"MIX_ENV", "dev"}]
      )

    assert File.read!(file) == "defmodule Z do\nend\n"
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
