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

  test "a failure nothing parsed keeps its last lines, without the command" do
    out = "error: no such step: test\nfailed command: /opt/zig/zig build --lots --of --flags\n"
    assert %{ok: false, failures: [], tail: tail} = Zig.parse(out, 1, "/work/app")
    assert tail =~ "no such step: test"
    refute tail =~ "failed command"
  end

  describe "in a zig project" do
    @describetag skip: !System.find_executable("zig") && "needs zig"

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
end
