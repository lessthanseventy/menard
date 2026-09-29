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

  test "a run that is not piped, or is not alone, stands as it was written" do
    for command <- [
          "mix test",
          "mix test test/a_test.exs --trace",
          "mix test > out.log 2>&1",
          "mix test | tee out.log",
          "mix format && mix test | tail -5",
          "mix test | tail -5; git status",
          "sed -i s/a/b/ lib/a.ex && mix test 2>&1 | tail",
          "mix compile 2>&1 | tail -5",
          "mix testing | tail",
          "echo 'mix test | tail'",
          "mix test | tail -5 && echo done",
          "cat <<'EOF' | tail\nmix test\nEOF"
        ] do
      assert Piped.rewritten(command, @menard) == nil, "#{inspect(command)} was rewritten"
    end
  end

  test "it is on where the environment says so" do
    refute Piped.on?()
    assert Piped.upfront(@menard) =~ "/p/bin/menard run test"
  end
end
