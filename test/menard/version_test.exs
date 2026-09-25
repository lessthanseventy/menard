defmodule Menard.VersionTest do
  # Claude Code updates an installed plugin only when its version changes, so a bump that misses
  # one of these leaves every install on the old hooks without a word.
  use ExUnit.Case, async: true

  @root Path.expand("../..", __DIR__)

  test "every version menard states is mix.exs's" do
    version = Mix.Project.config()[:version]
    read = &(@root |> Path.join(&1) |> File.read!())

    assert JSON.decode!(read.(".claude-plugin/plugin.json"))["version"] == version
    assert JSON.decode!(read.(".claude-plugin/marketplace.json"))["metadata"]["version"] == version
    assert read.("lib/menard/mcp.ex") =~ ~s(version: "#{version}")
    assert read.("CHANGELOG.md") =~ "## #{version}"
  end
end
