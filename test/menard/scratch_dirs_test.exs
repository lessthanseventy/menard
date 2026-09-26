defmodule Menard.ScratchDirsTest do
  # Two checkouts' suites at once share the OS tmp dir, and System.unique_integer restarts in every
  # VM: one run's on_exit removed the other's `/tmp/menard-X-1` mid-test (mcp_test, three tests).
  # A scratch path under the OS tmp dir carries the OS pid; @tag :tmp_dir needs none.
  use ExUnit.Case, async: true

  test "every scratch path under the OS tmp dir carries the OS pid" do
    shared =
      for file <- Path.wildcard(Path.expand("../**/*_test.exs", __DIR__)),
          {line, n} <- file |> File.read!() |> String.split("\n") |> Enum.with_index(1),
          line =~ "System.tmp_dir!()" and not (line =~ "System.pid()"),
          do: "#{Path.relative_to(file, Path.expand("../..", __DIR__))}:#{n}"

    assert shared == []
  end
end
