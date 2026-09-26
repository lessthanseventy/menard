defmodule Menard.IdentityTest do
  # An edit that writes back what is already there must leave the file as it was. Run over every
  # source file in this repo and test/fixtures/weird.ex, that is the check "only the named bytes
  # move" never had: a verb that drops a `rescue`, eats a line, or reshapes a neighbour fails here,
  # however well its output parses. One describe per file, so the files run in parallel. The
  # oracle is Menard.Test.Identity, which the hex corpus benchmark runs over real packages too.
  use ExUnit.Case, async: true

  # The slowest case, clause.ex's stmt check (635 edits), takes ~6s alone at load 4 (15.6s before
  # the oracle stopped holding every output). A gate at load ~40 stretched it 4x, past ExUnit's 60s;
  # 120s is ~5x that stretch of today's cost, and still stops a hang.
  @moduletag timeout: 120_000

  alias Menard.Test.Identity

  @root Path.expand("../..", __DIR__)

  for path <- Path.wildcard(Path.join(@root, "{lib,test}/**/*.{ex,exs}")) do
    @path path

    describe Path.relative_to(path, @root) do
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

  test "the oracle is not blind: on weird.ex every check makes edits it can judge" do
    # `misses == []` is also what a verb that refuses every edit gives: no edit made, none missed
    source = File.read!(Path.join(@root, "test/fixtures/weird.ex"))

    for check <- Identity.checks() do
      made = for {_label, outcome} <- Identity.run(source, check), outcome in [:same, :formatted], do: outcome
      assert made != [], "#{check}: every edit of weird.ex was refused, so no miss could be seen"
    end
  end
end
