# An edit that writes back what is already there must leave the file as it was. Run over every
# source file in this repo and test/fixtures/weird.ex, that is the check "only the named bytes
# move" never had: a verb that drops a `rescue`, eats a line, or reshapes a neighbour fails here,
# however well its output parses. The oracle is Menard.Test.Identity, which the hex corpus
# benchmark runs over real packages too.
#
# Eight modules, the files dealt among them by size: ExUnit runs a module's tests one after another
# and its modules in parallel, and as one module of 509 CPU-bound tests this was the suite's floor,
# 206 s on its own (move.ex's stmt check alone 30 s) after every other module had finished. Not one
# module per file: 127 CPU-bound modules filled the 40 cases ExUnit runs at once and starved the
# formatter VMs the other tests boot, which then hit their 60 s. Eight hold eight cores; the rest
# stay with the tests that wait on a process.
root = Path.expand("../..", __DIR__)
files = Path.wildcard(Path.join(root, "{lib,test}/**/*.{ex,exs}"))

# the biggest file first, each to the lightest module so far: bytes stand in for edits
buckets =
  files
  |> Enum.sort_by(&(-File.stat!(&1).size))
  |> Enum.reduce(Map.new(0..7, &{&1, {0, []}}), fn path, acc ->
    {n, {bytes, paths}} = Enum.min_by(acc, fn {_, {bytes, _}} -> bytes end)
    Map.put(acc, n, {bytes + File.stat!(path).size, [path | paths]})
  end)

for {n, {_bytes, paths}} <- buckets do
  defmodule Module.concat(Menard.IdentityTest, "Part#{n}") do
    use ExUnit.Case, async: true

    # The slowest case, clause.ex's stmt check (635 edits), takes ~6s alone at load 4 (15.6s before
    # the oracle stopped holding every output), 30 s for move.ex at load 10 run beside the rest; a
    # gate at load ~40 stretched that 4x. 300 s still stops a hang.
    @moduletag timeout: 300_000

    alias Menard.Test.Identity

    for path <- paths do
      @path path

      describe Path.relative_to(path, root) do
        test "clause replace with a clause's own body" do
          assert Identity.misses(File.read!(@path), :clause) == []
        end

        test "attr set with an attribute's own value" do
          assert Identity.misses(File.read!(@path), :attr) == []
        end

        test "block replace with a block's own body" do
          assert Identity.misses(File.read!(@path), :block) == []
        end

        test "stmt replace with a statement's own text" do
          assert Identity.misses(File.read!(@path), :stmt) == []
        end
      end
    end
  end
end

defmodule Menard.IdentityTest do
  use ExUnit.Case, async: true

  alias Menard.Test.Identity

  @root Path.expand("../..", __DIR__)

  test "the oracle is not blind: on weird.ex every check makes edits it can judge" do
    # `misses == []` is also what a verb that refuses every edit gives: no edit made, none missed
    source = File.read!(Path.join(@root, "test/fixtures/weird.ex"))

    for check <- Identity.checks() do
      made = for {_label, outcome} <- Identity.run(source, check), outcome in [:same, :formatted], do: outcome
      assert made != [], "#{check}: every edit of weird.ex was refused, so no miss could be seen"
    end
  end
end
