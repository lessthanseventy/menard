defmodule Menard.RunZigTest do
  # A repo with a build.zig and no mix.exs runs through `zig build`, and what zig printed is read
  # as mix's is: the counts, each failure's file, line and message, and no command dump.
  use ExUnit.Case, async: true

  alias Menard.Run.Zig

  @failed """
  test
  +- run test 1 pass, 2 fail (3 total)
  error: 'root.test.sum is wrong' failed:
         expected 5, found 4
         /opt/zig/lib/std/testing.zig:93:17: 0x1254aa4 in expectEqualInner__func_962 (std.zig)
                         return error.TestExpectedEqual;
                         ^
         /opt/zig/lib/std/testing.zig:57:5: 0x1254b2b in expectEqual (root.zig)
             return expectEqualInner(T, expected, actual);
             ^
         /work/app/src/root.zig:21:5: 0x1254b72 in test.sum is wrong (root.zig)
             try std.testing.expectEqual(@as(i32, 5), add(2, 2));
             ^
  error: 'root.test.boom' failed:
         /work/app/src/root.zig:25:5: 0x1254a5c in test.boom (root.zig)
             return error.Boom;
             ^
  failed command: ./.zig-cache/o/db6b21cbfef0845330cdb384881bdfad/test --cache-dir=./.zig-cache --seed=0xdca2099d --listen=-

  Build Summary: 3/5 steps succeeded (1 failed); 3/5 tests passed (2 failed)
  test transitive failure
  +- run test 1 pass, 2 fail (3 total)
  |  +- compile test debug native success 654ms MaxRSS:143M
  +- run test 2 pass (2 total) 10ms MaxRSS:4M
     +- compile test debug native success 668ms MaxRSS:143M
  """

  @broken """
  test
  +- run test
     +- compile test debug native 1 errors
  src/root.zig:30:12: error: use of undeclared identifier 'y'
      return y;
             ^
  error: 1 compilation errors
  failed command: /opt/zig/zig test -Mroot=src/root.zig --cache-dir .zig-cache --global-cache-dir /home/me/.cache/zig --build-root . --name test --listen=-

  test
  +- run test
     +- compile test debug native 1 errors
  src/root.zig:30:12: error: use of undeclared identifier 'y'
      return y;
             ^
  error: 1 compilation errors
  failed command: /opt/zig/zig test -Odebug --dep app -Mroot=src/main.zig -Mapp=src/root.zig --cache-dir .zig-cache --listen=-

  Build Summary: 0/5 steps succeeded (2 failed)
  test transitive failure
  +- run test transitive failure
  |  +- compile test debug native 1 errors
  +- run test transitive failure
     +- compile test debug native 1 errors
  """

  test "failed tests: the counts, and each test's name, place and message" do
    assert %{ok: false, tests: 5, failed: 2, failures: [sum, boom]} = Zig.parse(@failed, 1, "/work/app")

    assert sum == %{
             kind: "test",
             name: "root.test.sum is wrong",
             at: "src/root.zig:21",
             message: "expected 5, found 4",
             code: "try std.testing.expectEqual(@as(i32, 5), add(2, 2));"
           }

    assert boom == %{
             kind: "test",
             name: "root.test.boom",
             at: "src/root.zig:25",
             message: "return error.Boom;"
           }
  end

  test "a test that failed without output is a failure with its name and its declaration's line" do
    dir =
      Path.join(System.tmp_dir!(), "menard-zig-silent-#{System.pid()}-#{System.unique_integer([:positive])}")

    File.mkdir_p!(Path.join(dir, "src"))
    on_exit(fn -> File.rm_rf!(dir) end)

    File.write!(
      Path.join(dir, "src/draw.zig"),
      "const std = @import(\"std\");\n\ntest \"no output\" {\n    return error.Nope;\n}\n"
    )

    out = """
    test
    +- run test 227 pass, 1 fail (228 total)
    error: 'draw.test.no output' failed without output
    Build Summary: 3/5 steps succeeded (1 failed); 227/228 tests passed (1 failed)
    """

    assert %{ok: false, tests: 228, failed: 1, failures: [failure]} = Zig.parse(out, 1, dir)

    assert failure == %{
             kind: "test",
             name: "draw.test.no output",
             at: "src/draw.zig:3",
             message: "failed without output"
           }
  end

  test "a compile error is said once, with its place, and no command line" do
    reply = Zig.parse(@broken, 1, "/work/app")

    assert reply.failures == [
             %{kind: "compile", at: "src/root.zig:30", message: "use of undeclared identifier 'y'"}
           ]

    refute inspect(reply) =~ "failed command"
  end

  test "green: the counts; cached, the steps and that nothing ran" do
    ran =
      "Build Summary: 5/5 steps succeeded; 3/3 tests passed\ntest success\n+- run test 1 pass (1 total) 6ms\n"

    assert %{ok: true, tests: 3, failed: 0, failures: []} = Zig.parse(ran, 0, "/work/app")

    cached = "Build Summary: 5/5 steps succeeded\ntest success\n+- run test cached\n"
    assert %{ok: true, failures: [], tail: tail} = reply = Zig.parse(cached, 0, "/work/app")
    assert tail =~ "5/5 steps succeeded"
    assert tail =~ "cached"
    refute Map.has_key?(reply, :tests)
  end

  test "green with some test steps cached: the reply counts them beside the tests that ran" do
    out =
      "Build Summary: 7/7 steps succeeded; 4/4 tests passed\ntest success\n" <>
        "+- run test 4 pass (4 total) 6ms\n+- run test cached\n+- run test cached\n"

    assert %{ok: true, tests: 4, cached: 2} = Zig.parse(out, 0, "/work/app")

    ran =
      "Build Summary: 5/5 steps succeeded; 3/3 tests passed\ntest success\n+- run test 3 pass (3 total) 6ms\n"

    refute Map.has_key?(Zig.parse(ran, 0, "/work/app"), :cached)
  end

  test "a failure nothing parsed keeps its last lines, without the command" do
    out = "error: no such step: test\nfailed command: /opt/zig/zig build --lots --of --flags\n"
    assert %{ok: false, failures: [], tail: tail} = Zig.parse(out, 1, "/work/app")
    assert tail =~ "no such step: test"
    refute tail =~ "failed command"
  end

  describe "in a zig project" do
    @describetag skip: !System.find_executable("zig") && "needs zig"
    # zig's first run on a cold global cache, as CI's always is, takes two minutes
    @describetag timeout: 600_000

    setup do
      # outside this repo, whose own mise `test` task a directory under it would answer with
      dir = Path.join(System.tmp_dir!(), "menard-zig-#{System.pid()}-#{System.unique_integer([:positive])}")
      zig = Path.join(dir, "native")
      File.mkdir_p!(zig)
      on_exit(fn -> File.rm_rf!(dir) end)
      {_, 0} = System.cmd("zig", ["init"], cd: zig, stderr_to_stdout: true)
      %{dir: dir, zig: zig}
    end

    test "run test answers its failed test", %{zig: zig} do
      root = Path.join(zig, "src/root.zig")
      File.write!(root, File.read!(root) <> "\ntest \"menard fails\" {\n    return error.Nope;\n}\n")

      assert %{ok: false, failures: [failure], ran: "zig build test"} = Menard.Run.result(zig, "test", [])
      assert failure.name =~ "menard fails"
      assert failure.at =~ ~r/^src\/root\.zig:\d+$/
      assert failure.message == "return error.Nope;"
    end

    test "an edit's then: test runs the tests of the zig project the file is in", %{dir: dir} do
      File.write!(Path.join(dir, "native/src/more.zig"), "const a = 1;\n")

      assert {:ok, %{run: %{ran: "zig build test", dir: "native"}}} =
               Menard.Verbs.call(Menard.Verbs.Edit, %{
                 root: dir,
                 edits: [%{file: "native/src/more.zig", old: "const a = 1;", new: "const a = 2;"}],
                 then: "test"
               })
    end
  end

  describe "reap" do
    test "kills a process left in a deleted menard-zigc dir, and only that" do
      dir =
        Path.join(System.tmp_dir!(), "menard-zigc-reap-#{System.pid()}-#{System.unique_integer([:positive])}")

      File.mkdir_p!(dir)

      port =
        Port.open({:spawn_executable, System.find_executable("sh")}, [
          :exit_status,
          args: ["-c", ~s(cd "$1" && rm -rf "$1" && exec sleep 300), "sh", dir]
        ])

      {:os_pid, pid} = Port.info(port, :os_pid)
      other = Port.open({:spawn_executable, System.find_executable("sleep")}, [:exit_status, args: ["300"]])
      {:os_pid, other_pid} = Port.info(other, :os_pid)

      assert wait_until(fn ->
               match?({:ok, <<_::binary>>}, File.read_link("/proc/#{pid}/cwd")) and deleted?(pid)
             end)

      assert pid in Zig.reap()
      assert_receive {^port, {:exit_status, _}}, 5_000
      refute other_pid in Zig.reap()
      Port.close(other)
      System.cmd("kill", ["#{other_pid}"])
    end

    @tag :tmp_dir
    test "kills a zig compiler whose build runner is gone, not one whose runner is there", %{tmp_dir: dir} do
      zig = Path.join(dir, "zig")
      File.ln_s!(System.find_executable("sh"), zig)
      pid_file = Path.join(dir, "pid")

      {_, 0} =
        System.cmd("sh", [
          "-c",
          ~s("$1" -c "sleep 300; :" zig --listen=- </dev/null >/dev/null 2>&1 & echo $! >"$2"),
          "sh",
          zig,
          pid_file
        ])

      orphan = pid_file |> File.read!() |> String.trim() |> String.to_integer()

      runner =
        Port.open({:spawn_executable, zig}, [:exit_status, args: ["-c", "sleep 300; :", "zig", "--listen=-"]])

      {:os_pid, child} = Port.info(runner, :os_pid)

      assert wait_until(fn -> ppid(orphan) == 1 end)
      reaped = Zig.reap()
      assert orphan in reaped
      refute child in reaped
      Port.close(runner)
      System.cmd("kill", ["#{child}"])
    end
  end

  describe "watch_locks" do
    @describetag skip: !System.find_executable("flock") && "needs flock"

    @tag :tmp_dir
    test "ends a wait on a lock whose holder does no work, and names the holder", %{tmp_dir: dir} do
      lock = Path.join(dir, "lock")
      holder = hold(lock, ["sleep", "300"])

      {micros, {{_, status}, [failure]}} =
        :timer.tc(fn ->
          Zig.watch_locks(dir, fn -> System.cmd("flock", [lock, "true"], cd: dir) end, 1_000)
        end)

      assert status != 0
      assert failure.kind == "lock"
      assert failure.message =~ "held by pid #{holder} (flock"
      assert micros < 5_000_000
      System.cmd("pkill", ["-P", "#{holder}"])
    end

    @tag :tmp_dir
    test "keeps waiting on a lock whose holder is working", %{tmp_dir: dir} do
      lock = Path.join(dir, "lock")
      hold(lock, ["timeout", "3", "sh", "-c", "while :; do :; done"])

      assert {{_, 0}, []} =
               Zig.watch_locks(dir, fn -> System.cmd("flock", [lock, "true"], cd: dir) end, 1_000)
    end
  end

  defp hold(lock, command) do
    port =
      Port.open({:spawn_executable, System.find_executable("flock")}, [:exit_status, args: [lock | command]])

    {:os_pid, pid} = Port.info(port, :os_pid)
    assert wait_until(fn -> File.read!("/proc/locks") =~ ~r/FLOCK\s+ADVISORY\s+WRITE #{pid} / end)
    pid
  end

  defp ppid(pid) do
    case File.read("/proc/#{pid}/stat") do
      {:ok, stat} ->
        stat |> String.split(") ") |> List.last() |> String.split(" ") |> Enum.at(1) |> String.to_integer()

      {:error, _} ->
        nil
    end
  end

  defp deleted?(pid), do: File.read_link!("/proc/#{pid}/cwd") =~ "(deleted)"

  defp wait_until(fun, tries \\ 100) do
    cond do
      fun.() -> true
      tries == 0 -> false
      true -> Process.sleep(50) && wait_until(fun, tries - 1)
    end
  end

  describe "compile in a zig project is a fast check" do
    @describetag skip: !System.find_executable("zig") && "needs zig"
    @describetag timeout: 30_000

    setup do
      dir = Path.join(System.tmp_dir!(), "menard-zigc-#{System.pid()}-#{System.unique_integer([:positive])}")
      File.mkdir_p!(Path.join(dir, "src"))
      # a build.zig that would hang the test if compile ran it
      File.write!(
        Path.join(dir, "build.zig"),
        "pub fn build(b: *@import(\"std\").Build) void {\n    _ = b;\n    while (true) {}\n}\n"
      )

      File.write!(Path.join(dir, "src/root.zig"), "pub const a = 1;\n")
      on_exit(fn -> File.rm_rf!(dir) end)
      %{dir: dir}
    end

    test "run compile ast-checks the files named, and says where the error is", %{dir: dir} do
      File.write!(Path.join(dir, "src/root.zig"), "pub const a = b;\n")

      {micros, reply} = :timer.tc(fn -> Menard.Run.result(dir, "compile", ["src/root.zig"]) end)

      assert %{ok: false, ran: "zig ast-check", failures: [failure]} = reply
      assert failure.at == "src/root.zig:1"
      assert failure.message =~ "undeclared identifier"
      assert micros < 10_000_000
    end

    test "an edit's then: compile checks the files it wrote, green and red", %{dir: dir} do
      edit = fn old, new ->
        Menard.Verbs.call(Menard.Verbs.Edit, %{
          root: dir,
          edits: [%{file: "src/root.zig", old: old, new: new}],
          then: "compile"
        })
      end

      assert {:ok, %{run: %{ok: true, ran: "zig ast-check"}}} = edit.("pub const a = 1;", "pub const a = 2;")

      assert {:ok, %{run: %{ok: false, failures: [%{at: "src/root.zig:1"}]}}} =
               edit.("pub const a = 2;", "pub const a = nope;")
    end
  end
end
