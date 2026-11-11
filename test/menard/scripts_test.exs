defmodule Menard.ScriptsTest do
  # What a command may not do where menard is: which commands are refused, and which must not be. A
  # guard that refuses an innocent command gets switched off.
  use ExUnit.Case, async: true

  alias Menard.Scripts

  @menard "/p/bin/menard"
  @edit "python3 - <<'E'\np='lib/shop/cart.ex'\ns=open(p).read()\nopen(p,'w').write(s.replace('a','b'))\nE"

  defp refused?(command), do: Scripts.refused(command, @menard) != nil

  test "a command that runs an interpreter is refused, wherever in it" do
    for command <- [
          @edit,
          "python3 -c 'print(1)'",
          "python script.py",
          "python3.12 x.py",
          "/usr/bin/python3 x.py",
          "cd lib && python3 ../x.py",
          "mix test; perl -pi -e 's/a/b/' notes.md",
          "FOO=1 ruby x.rb",
          "timeout 30 node x.js",
          "nohup python3 x.py &",
          "cat data.json | python3 -m json.tool",
          "echo $(python3 -c 'print(1)')",
          "(node x.js)",
          "if true; then\n  python3 x.py\nfi"
        ] do
      assert refused?(command), "#{inspect(command)} ran"
    end
  end

  test "a command that only names an interpreter runs" do
    for command <- [
          "grep -rn python lib",
          "echo 'run python3 later'",
          "ls node_modules",
          "mix test test/python_test.exs",
          "cat > notes.md <<'EOF'\npython3 x.py\nEOF",
          "git commit -m 'drop the perl script'",
          "git commit -q -m \"a version runs\n\nNot taken: a module run,\npython3 -m json.tool, stays refused\"",
          "which python3 || true",
          "rg 'node' assets/",
          "mix run -e 'IO.puts(1)'",
          "elixir -e 'IO.puts(:ruby)'"
        ] do
      refute refused?(command), "#{inspect(command)} was refused: #{Scripts.refused(command, @menard)}"
    end
  end

  test "a refusal, and what is said up front, name this menard by its path and show an edit" do
    for text <- [Scripts.refused(@edit, @menard), Scripts.upfront(@menard)] do
      assert text =~ "`mcp__plugin_menard_menard__edit`"
      assert text =~ "/p/bin/menard edit --then compile - <<'EOF'"
      assert text =~ "<<<<<<< SEARCH"
      assert text =~ "is from the shell's directory"
    end

    # each shows the edit where its reader stands: the tool's at a start, the shell's to a refused command
    assert Scripts.upfront(@menard) =~ ~s({"edits": [{"file": "lib/a.ex")
    assert Scripts.refused(@edit, @menard) =~ "  lib/a.ex\n  <<<<<<< SEARCH\n  the text to find\n"

    assert Scripts.refused(@edit, @menard) =~ "python3 does not run here"
    assert Scripts.upfront(@menard) =~ "There is no python"
    assert Scripts.upfront(@menard) =~ "elixir -e"
    # a script is not always an edit: waiting on a process was a python loop, refused as one
    assert Scripts.refused(@edit, @menard) =~ "until ! pgrep"
    assert Scripts.refused(@edit, @menard) =~ "jq"
    assert Scripts.upfront(@menard) =~ "/p/bin/menard clause get FILE NAME"
    # no menard is named but by its path: a bare one is whichever the PATH holds first
    refute Scripts.upfront(@menard) =~ ~r/(?<![\w\/])menard (edit|rename|run|clause|outline|find)/
  end

  @tag :tmp_dir

  @tag :tmp_dir
  test "a program the project tracks runs; inline code and a file it does not track are refused", %{
    tmp_dir: dir
  } do
    # eval/run.py, menard's own runner, was refused as a script: a project's committed program is no
    # script written to get around edit. One the agent writes is untracked until committed, and stays refused.
    {_, 0} = System.cmd("git", ["init", "-q", dir])
    File.mkdir_p!(Path.join(dir, "eval"))
    File.write!(Path.join(dir, "eval/run.py"), "print(1)\n")
    File.write!(Path.join(dir, "fix.py"), "print(2)\n")
    {_, 0} = System.cmd("git", ["-C", dir, "add", "eval/run.py"])

    for ok <- [
          "python3 eval/run.py x --suite eval/helpdesk",
          # quoted: a tmp_dir holds the test's name, `;` and all
          "cd '#{dir}' && python3 eval/run.py x > out 2>&1",
          "FOO=1 nohup python3 eval/run.py &"
        ] do
      assert Scripts.refused(ok, @menard, dir) == nil, ok
    end

    for no <- [
          "python3 fix.py",
          "python3 -c 'print(1)'",
          "python3 - <<'E'\nprint(1)\nE",
          "python3 eval/missing.py"
        ] do
      assert Scripts.refused(no, @menard, dir) =~ "does not run here", no
    end
  end

  @tag :tmp_dir

  test "a subagent sent to find a function's callers is answered with find calls" do
    # an Explore subagent to list the calls of Desk.Tickets.transition/2 apart from the event name
    # and element ids that share its word: what find calls does in one call, strings and comments
    # never matched
    prompt =
      "search the whole codebase (lib/ and test/) for every reference to `Tickets.transition`, `transition(` " <>
        "(the Desk.Tickets.transition/2 function), and any place that calls it. List findings as file:line."

    why = Scripts.delegated(prompt, @menard)
    assert why =~ "#{@menard} find calls Desk.Tickets.transition lib test"

    # a job that is more than a search runs, callers mentioned or not; so does a search of no function
    assert Scripts.delegated(
             "Implement the export feature. " <> String.duplicate("Keep its callers working. ", 100),
             @menard
           ) == nil

    assert Scripts.delegated("Find every reference to the word transition in the docs", @menard) == nil
    assert Scripts.delegated("Review Desk.Tickets.transition/2 for bugs", @menard) == nil

    # a brief with work in it is no search, though it names a function and its callers
    for prompt <- [
          "Read lib/billing.ex, refactor Billing.charge/2 to take a struct, then update all callers of " <>
            "Billing.charge and fix the tests",
          "Research on hexdocs how Ecto.Changeset.cast handles empty strings, and summarize usage examples"
        ] do
      assert Scripts.delegated(prompt, @menard) == nil, prompt
    end

    # a build brief that TELLS the subagent to use find calls is no search
    assert Scripts.delegated(
             "Fix the bug in Server.Staffing.explain/1 and add a test. To find its callers use " <>
               "`menard find calls Server.Staffing.explain lib test`, then update each.",
             @menard
           ) == nil
  end

  @tag :tmp_dir

  # `menard … | head -c N` ending the line: what was asked is run, the filter dropped, no call lost
  # to the refusal
  test "menard's reply piped through a filter that ends the line runs bare, the filter dropped" do
    for {command, bare} <- [
          {"/p/bin/menard run test test/a_test.exs | jq -c '.failures[]'",
           "/p/bin/menard run test test/a_test.exs"},
          {"cd /x && bin/menard --frozen clause get lib/a.ex go/1 | jq -r .code",
           "cd /x && bin/menard --frozen clause get lib/a.ex go/1"},
          {"/p/bin/menard outline lib/a.ex 2>&1 | head -40", "/p/bin/menard outline lib/a.ex 2>&1"},
          {"menard find calls A.go lib | grep b.ex", "menard find calls A.go lib"},
          {"test -f x && /p/bin/menard outline x | head", "test -f x && /p/bin/menard outline x"},
          {"ls lib/*.ex | xargs -n1 /p/bin/menard outline | grep defp | head -3",
           "ls lib/*.ex | xargs -n1 /p/bin/menard outline"},
          {"timeout 580 ~/p/bin/menard run check --in server 2>&1 | tail -c 1500",
           "timeout 580 ~/p/bin/menard run check --in server 2>&1"},
          {"( time bin/menard --frozen run credo --changed lib/a.ex ) 2>&1 | tail -3",
           "( time bin/menard --frozen run credo --changed lib/a.ex ) 2>&1"},
          {"cd /x && MIX_ENV=test nohup bin/menard run check | tail -5",
           "cd /x && MIX_ENV=test nohup bin/menard run check"},
          {"bin/menard find calls 'A.go|B.go' lib | grep 'x | y'", "bin/menard find calls 'A.go|B.go' lib"}
        ] do
      assert Scripts.unfiltered(command) == bare, command
      refute refused?(bare), bare
    end

    for command <- [
          "/p/bin/menard outline lib/a.ex",
          "/p/bin/menard outline lib/a.ex | wc -l",
          "/p/bin/menard outline lib/a.ex | head; echo done",
          "git log | head -5",
          "/p/bin/menard run test && git diff | head",
          "echo menard | grep m"
        ] do
      assert Scripts.unfiltered(command) == nil, command
    end
  end

  test "a refused script is told the shell's edit first: the agent refused is in the shell" do
    why = Scripts.refused("python3 -c 'print(1)'", @menard)

    [shell, tool] =
      for text <- ["#{@menard} edit --then compile - <<'EOF'", Scripts.edit_tool()], do: place(why, text)

    assert shell < tool, why

    # at a session's start no one is anywhere yet: the tool, then the shell
    upfront = Scripts.upfront(@menard)
    assert place(upfront, Scripts.edit_tool()) < place(upfront, "#{@menard} edit --then compile - <<'EOF'")
  end

  defp place(text, part) do
    {at, _} = :binary.match(text, part)
    at
  end

  test "menard's help through a filter runs as written: a help has no reply to drop" do
    for command <- [
          "/p/bin/menard --help | head -40",
          "cd /x && ~/p/bin/menard edit --help 2>&1 | head -30",
          "grep -n floki mix.exs; bin/menard --help 2>&1 | head -40; bin/menard edit -h | head -40",
          "bin/menard help run | grep then"
        ] do
      assert Scripts.unfiltered(command) == nil, command
      refute refused?(command), command
    end

    # a help beside a reply that is cut is still that reply cut
    assert refused?("bin/menard --help | head; bin/menard outline lib/a.ex | head; echo done")
    assert Scripts.unfiltered("bin/menard --help | head; bin/menard outline lib/a.ex | head") != nil
  end

  test "menard's reply piped through a filter is refused where dropping it changes what runs" do
    # a filter over the reply drops what the caller did not think to ask for (the formatter's changes
    # in an edit's `stages`, a failure past the first): what it holds is the answer, whole
    for command <- [
          "/p/bin/menard edit - <<'EOF' | jq -c .did\nlib/a.ex\n<<<<<<< SEARCH\na\n=======\nb\n>>>>>>> REPLACE\nEOF",
          "for f in lib/a.ex lib/b.ex; do bin/menard module layout $f | jq -c .did; done",
          "/p/bin/menard outline lib/a.ex | head; echo done",
          "/p/bin/menard block add t.exs test --label x 'assert 1' >/dev/null",
          "/p/bin/menard outline lib/a.ex > /dev/null 2>&1",
          "if true; then bin/menard outline lib/a.ex | head; fi",
          # wrapped, as the script ban reads them
          "timeout 180 bin/menard run test test/menard/bin_test.exs:301 2>&1 | tail -60 && echo ok",
          "cd /x && MIX_ENV=test nohup bin/menard run check | tail -5 | wc -l"
        ] do
      assert Scripts.unfiltered(command) == nil, command
      assert (Scripts.refused(command, @menard) || "") =~ "whole", command
    end

    refute refused?("for f in a b; do echo $f | grep a; done")
    refute refused?("/p/bin/menard run check > gate.json")
    # only stderr thrown away, the reply kept
    refute refused?("/p/bin/menard clause get lib/a.ex go/0 2>/dev/null || sed -n 1,40p lib/a.ex")
    # both thrown away is the reply thrown away, and the refusal says that is what it saw
    assert Scripts.refused("/p/bin/menard outline lib/a.ex &>/dev/null", @menard) =~ "/dev/null"
    assert Scripts.refused("/p/bin/menard outline lib/a.ex > /dev/null 2>&1", @menard) =~ "/dev/null"
    refute Scripts.refused("/p/bin/menard outline lib/a.ex | head", @menard) =~ "/dev/null"
    refute refused?(~s[mix run -e 'IO.inspect(Scripts.refused("bin/menard outline x | head", "m"))'])

    for command <- [
          "/p/bin/menard outline lib/a.ex",
          "/p/bin/menard run test && git diff | head",
          "git log | head -5; /p/bin/menard outline lib/a.ex",
          "echo menard | grep m"
        ] do
      refute refused?(command), command
    end
  end

  test "an interpreter's version, help or module run is no script, and runs" do
    # a version or help is no script (a module run is: `python3 -m json.tool` is jq's here)
    for command <- ["node --version", "python3 -V", "ruby -v", "python3 --help"] do
      refute refused?(command), command
    end

    assert refused?("python3 -c 'print(1)'")
    assert refused?("node -e 'console.log(1)'")
  end

  @tag :tmp_dir

  @tag :tmp_dir

  @tag :tmp_dir
end
