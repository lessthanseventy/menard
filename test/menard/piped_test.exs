defmodule Menard.PipedTest do
  # A test run piped through tail, head or grep is run through `menard run` in its place. What is
  # rewritten is one test run and its pipe, and nothing else: a command changed under an agent that
  # was not that is worse than the pipe.
  use ExUnit.Case, async: true

  alias Menard.Piped

  @menard "/p/bin/menard"

  test "a piped test run is menard's run, with the arguments it had" do
    for {command, run} <- [
          {"mix test | tail -20", "run test"},
          {"mix test 2>&1 | tail -5", "run test"},
          {"mix test test/a_test.exs 2>&1 | tail -30", "run test test/a_test.exs"},
          {"mix test test/a_test.exs:12 --seed 0 | grep -A5 failed", "run test test/a_test.exs:12 --seed 0"},
          {"MIX_ENV=test mix test --only live 2>&1 | head -40", "run test --only live"},
          {"mix test 2>&1 | grep -v '^$' | tail -20", "run test"},
          {"mix precommit 2>&1 | tail -15", "run check"}
        ] do
      assert Piped.rewritten(command, @menard) == "/p/bin/menard " <> run, command
    end
  end

  test "the directory it ran in is the one it runs in" do
    assert Piped.rewritten("cd apps/desk && mix test test/a_test.exs | tail -3", @menard) ==
             "cd apps/desk && /p/bin/menard run test test/a_test.exs"

    assert Piped.rewritten(~s(cd "/tmp/my app" && mix test | tail), @menard) ==
             ~s(cd "/tmp/my app" && /p/bin/menard run test)
  end

  # 2026-09-30: `cd X; time (mise exec -- mix test 2>&1 | tail -15)` went through as written
  test "a cd with ;, time, a subshell and mise exec are kept around the run, the parens dropped" do
    for {command, run} <- [
          {"cd /w; mix test | tail", "cd /w; /p/bin/menard run test"},
          {"time mix test 2>&1 | tail -15", "time /p/bin/menard run test"},
          {"(mix test 2>&1 | tail -15)", "/p/bin/menard run test"},
          {"mise exec -- mix test test/a_test.exs | tail",
           "mise exec -- /p/bin/menard run test test/a_test.exs"},
          {"mise x -- mix precommit | tail", "mise x -- /p/bin/menard run check"},
          {"mise exec elixir@1.19 -- mix test | tail", "mise exec elixir@1.19 -- /p/bin/menard run test"},
          {"cd /w; time (mise exec -- mix test 2>&1 | tail -15)",
           "cd /w; time mise exec -- /p/bin/menard run test"}
        ] do
      assert Piped.rewritten(command, @menard) == run, command
    end
  end

  test "a subshell not closed, or closed and not opened, stands as it was written" do
    for command <- ["(mix test | tail", "mix test | tail)", "time (mix test | tail) && echo done"] do
      assert Piped.rewritten(command, @menard) == nil, "#{inspect(command)} was rewritten"
    end
  end

  test "a run that is not piped, or is not alone, stands as it was written" do
    for command <- [
          "mix test",
          "mix test test/a_test.exs --trace",
          "mix test > out.log 2>&1",
          "mix test | tee out.log",
          "mix test | tail -5; git status",
          "mix compile 2>&1 | tail -5",
          "mix testing | tail",
          "echo 'mix test | tail'",
          "mix test | tail -5 && echo done",
          "cat <<'EOF' | tail\nmix test\nEOF"
        ] do
      assert Piped.rewritten(command, @menard) == nil, "#{inspect(command)} was rewritten"
    end
  end

  test "the commands before a piped run are kept, the run is menard's" do
    # Symphony 01: `mix compile && mix test FILE | tail` stood as written, its raw output read, and the
    # run made again through menard
    assert Piped.rewritten("mix compile && mix test test/a_test.exs | tail -20", @menard) ==
             "mix compile && #{@menard} run test test/a_test.exs"

    assert Piped.rewritten("mix format && mix test | tail -5", @menard) == "mix format && #{@menard} run test"

    assert Piped.rewritten("sed -i 's/a;b/c/' lib/a.ex && mix test 2>&1 | tail", @menard) ==
             "sed -i 's/a;b/c/' lib/a.ex && #{@menard} run test"
  end

  test "a piped credo is menard's run credo" do
    # the agent's own `mix credo --strict … | grep -v "^Checking"`: a lint cut down to read, where
    # `run credo` is the issues as one line
    assert Piped.rewritten(
             ~s(mix credo --strict --format oneline lib/a.ex 2>&1 | grep -v "^Checking"),
             @menard
           ) ==
             "#{@menard} run credo --strict --format oneline lib/a.ex"

    assert Piped.rewritten("mix credo | tail -20", @menard) == "#{@menard} run credo"
  end
end
