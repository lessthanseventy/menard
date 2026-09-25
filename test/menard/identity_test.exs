defmodule Menard.IdentityTest do
  # An edit that writes back what is already there must leave the file as it was. Run over every
  # source file in this repo and test/fixtures/weird.ex, that is the check "only the named bytes
  # move" never had: a verb that drops a `rescue`, eats a line, or reshapes a neighbour fails here,
  # however well its output parses. One describe per file, so the files run in parallel. The
  # oracle is Menard.Test.Identity, which the hex corpus benchmark runs over real packages too.
  use ExUnit.Case, async: true

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
end
