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
      assert text =~ "/p/bin/menard edit --then test - <<'EOF'"
      assert text =~ "<<<<<<< SEARCH"
    end

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
  test "reading code a menard verb reads exactly is refused with that call; every other grep runs",
       %{tmp_dir: dir} do
    # the transcripts: 1,045 `sed -n N,Mp` and 233 `grep -n "def NAME" -A N` on modules since 09-18,
    # against 9 outlines; a nudge was not enough, a refusal that names the call is what agents learn from
    File.mkdir_p!(Path.join(dir, "lib"))

    File.write!(
      Path.join(dir, "lib/cart.ex"),
      "defmodule Shop.Cart do\n  def total(c) do\n    c\n  end\n\n  def count(c), do: c\nend\n"
    )

    why = &Scripts.refused(&1, @menard, dir)

    assert why.(~s(grep -n "def total" -A 20 lib/cart.ex)) =~ "#{@menard} clause get lib/cart.ex total"
    assert why.(~s(sed -n '/def total/,/^  end/p' lib/cart.ex)) =~ "#{@menard} clause get lib/cart.ex total"
    # a line range inside one function is that function; one over several is a page of the file,
    # which Read reads as well, and runs
    assert why.("sed -n '2,4p' lib/cart.ex") =~
             "lines 2-4 of lib/cart.ex are Shop.Cart.total/1: #{@menard} clause get lib/cart.ex total/1"

    assert why.("sed -n '2,6p' lib/cart.ex") == nil
    # a test file's are its tests
    File.mkdir_p!(Path.join(dir, "test"))

    File.write!(
      Path.join(dir, "test/cart_test.exs"),
      "defmodule CartTest do\n  use ExUnit.Case\n\n  test \"adds\" do\n    assert 1\n  end\nend\n"
    )

    assert why.("sed -n '4,6p' test/cart_test.exs") =~
             ~s(#{@menard} block get test/cart_test.exs test --label "adds")

    assert why.("sed -n '1,7p' test/cart_test.exs") == nil
    assert why.(~s(grep -rn "Shop.Cart.total" lib test)) =~ "#{@menard} find calls Shop.Cart.total lib test"
    assert why.(~s(cd lib && grep -rn 'Cart\\.total(' .)) =~ "find calls"

    for innocent <- [
          ~s(grep -rn "tax_rate" config),
          ~s(grep -rn "TODO" lib),
          ~s(grep -c "TODO" lib/cart.ex),
          ~s(grep -n "def total" lib/cart.ex),
          ~s(grep -rn "def total" -A 5 README.md),
          "sed -n '1,20p' mix.exs",
          "sed -n '1,20p' notes.txt",
          ~s(git log --grep "Shop.Cart.total"),
          "cat > lib/new.ex <<'X'\ngrep -n \"def a\" -A 3 lib/cart.ex\nX"
        ] do
      assert Scripts.refused(innocent, @menard, dir) == nil, innocent
    end
  end

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
          "python3 eval/run.py desk5 --suite eval/helpdesk",
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
  test "a test read by its label with grep -A is refused with block get; a pattern over several labels runs",
       %{tmp_dir: dir} do
    # desk5: `grep -n "records a created event" -A 8 test/desk/tickets_test.exs` went through, the read
    # refusal knowing only `def NAME`: a test, read by its label, is block get's
    File.mkdir_p!(Path.join(dir, "test"))

    File.write!(
      Path.join(dir, "test/cart_test.exs"),
      "defmodule CartTest do\n  use ExUnit.Case\n\n  test \"records a created event\" do\n    assert 1\n  end\n\n  test \"records a moved event\" do\n    assert 2\n  end\nend\n"
    )

    assert Scripts.refused(~s(grep -n "records a created event" -A 8 test/cart_test.exs), @menard, dir) =~
             ~s(#{@menard} block get test/cart_test.exs test --label "records a created event")

    # a describe read by its label is block get's too
    File.write!(
      Path.join(dir, "test/desc_test.exs"),
      "defmodule DescTest do\n  use ExUnit.Case\n\n  describe \"add_comment/3\" do\n    test \"adds\" do\n      assert 1\n    end\n  end\nend\n"
    )

    assert Scripts.refused(~s(grep -n "describe \\"add_comment" -A 25 test/desc_test.exs), @menard, dir) =~
             ~s(#{@menard} block get test/desc_test.exs describe --label "add_comment/3")

    # a pattern over two labels reads neither, and runs; so does one without context
    assert Scripts.refused(~s(grep -n "records a" -A 3 test/cart_test.exs), @menard, dir) == nil
    assert Scripts.refused(~s(grep -n "records a created event" test/cart_test.exs), @menard, dir) == nil

    # the file's structure, listed or counted (every test, every describe, every def), is its outline:
    # a count of `test "` also counts one in a string
    for listing <- [
          ~s(grep -n "test \\"" -A 3 test/cart_test.exs),
          ~s(grep -n 'describe "' test/cart_test.exs),
          ~s(grep -c "test \\"" test/cart_test.exs),
          ~s(grep -n "def " test/cart_test.exs),
          # desk7: a component's functions with their attrs and slots, the outline's now
          ~s{grep -n "^  def \\\\|^  attr\\\\|^  slot" test/cart_test.exs},
          ~s{grep -nE "^  (def|attr|slot) " test/cart_test.exs}
        ] do
      assert Scripts.refused(listing, @menard, dir) =~ "#{@menard} outline test/cart_test.exs", listing
    end

    # a count of text, and a list of files, read no code
    assert Scripts.refused(~s(grep -c "TODO" test/cart_test.exs), @menard, dir) == nil
    assert Scripts.refused(~s(grep -l "test \\"" test/cart_test.exs), @menard, dir) == nil
  end

  test "a subagent sent to find a function's callers is answered with find calls" do
    # desk5 step 08: an Explore subagent, 1,404 characters of prompt, to list the calls of
    # Desk.Tickets.transition/2 apart from the event name and element ids that share its word: what
    # find calls does in one call, strings and comments never matched
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
  end

  @tag :tmp_dir
  test "a grep for a function's callers is find calls however it is written: an alternative, a file list, an args pattern",
       %{tmp_dir: dir} do
    # desk7 step 08 found the callers of Tickets.transition with three greps the refusal let through
    for command <- [
          ~s{grep -rn "Tickets\\.transition\\|def transition\\|transition(" lib test},
          ~s{grep -rl "Tickets\\.transition(" test},
          ~s{grep -rhoE "Tickets\\.transition\\([a-zA-Z_0-9]+, :[a-z]+\\)" test}
        ] do
      assert Scripts.refused(command, @menard, dir) =~ "#{@menard} find calls Tickets.transition", command
    end

    # a list of files that hold some text is no callers query, and runs
    assert Scripts.refused(~s{grep -rl "TODO" lib}, @menard, dir) == nil
  end

  test "menard's reply piped through a filter is refused: it is read whole" do
    # a filter over the reply drops what the caller did not think to ask for (the formatter's changes
    # in an edit's `stages`, a failure past the first): what it holds is the answer, whole
    for command <- [
          "/p/bin/menard edit - <<'EOF' | jq -c .did\nlib/a.ex\n<<<<<<< SEARCH\na\n=======\nb\n>>>>>>> REPLACE\nEOF",
          "/p/bin/menard run test test/a_test.exs | jq -c '.failures[]'",
          "cd /x && bin/menard --frozen clause get lib/a.ex go/1 | jq -r .code",
          "/p/bin/menard outline lib/a.ex 2>&1 | head -40",
          "menard find calls A.go lib | grep b.ex",
          "for f in lib/a.ex lib/b.ex; do bin/menard module layout $f | jq -c .did; done",
          "test -f x && /p/bin/menard outline x | head",
          "/p/bin/menard block add t.exs test --label x 'assert 1' >/dev/null",
          "/p/bin/menard outline lib/a.ex > /dev/null 2>&1",
          "if true; then bin/menard outline lib/a.ex | head; fi",
          "ls lib/*.ex | xargs -n1 /p/bin/menard outline | grep defp"
        ] do
      assert (Scripts.refused(command, @menard) || "") =~ "whole", command
    end

    refute refused?("for f in a b; do echo $f | grep a; done")
    refute refused?("/p/bin/menard run check > gate.json")
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

  @tag :tmp_dir
  test "a code read is refused only toward a call that gives what was read", %{tmp_dir: dir} do
    # a refusal that points at a call that answers nothing, or answers less than was asked, is wrong
    File.mkdir_p!(Path.join(dir, "lib"))

    File.write!(
      Path.join(dir, "lib/app.ex"),
      "defmodule App do\n  defstruct auto_approve_requests: false\n\n  def go(s), do: s.auto_approve_requests\nend\n"
    )

    why = &Scripts.refused(&1, @menard, dir)

    # Symphony 08: no function of that name, only a field: the grep runs
    assert why.(~s(grep -n "defp auto_approve" -A4 lib/app.ex)) == nil
    assert why.(~s(grep -n "def go" -A4 lib/app.ex)) =~ "clause get lib/app.ex go"

    # Oban 03: lines 1-20 of a test file take in its module head, which block get does not give
    File.mkdir_p!(Path.join(dir, "test"))
    body = Enum.map_join(1..14, "", &"    x#{&1} = #{&1}\n")

    File.write!(
      Path.join(dir, "test/app_test.exs"),
      "defmodule AppTest do\n  use ExUnit.Case, async: true\n\n  alias App\n\n  test \"runs\" do\n" <>
        body <> "  end\nend\n"
    )

    assert why.("sed -n '1,20p' test/app_test.exs") == nil
    assert why.("sed -n '6,20p' test/app_test.exs") =~ ~s(block get test/app_test.exs test --label "runs")
  end

  @tag :tmp_dir
  test "a read with one menard call in its place is run as that call, the rest of the command beside it", %{
    tmp_dir: dir
  } do
    # a read a verb reads exactly runs as that verb, the rest of the command beside it: refused whole,
    # nothing in it ran, and every part of it was sent again (Oban 03, 05)
    File.mkdir_p!(Path.join(dir, "lib"))

    File.write!(
      Path.join(dir, "lib/cart.ex"),
      "defmodule Shop.Cart do\n  def total(c) do\n    c\n  end\nend\n"
    )

    assert Scripts.in_place(~s(cat lib/cart.ex; grep -n "def total" -A 20 lib/cart.ex), @menard, dir) ==
             ~s(cat lib/cart.ex; #{@menard} clause get lib/cart.ex total)

    assert Scripts.in_place(~s(ls lib && grep -rn "Shop.Cart.total" lib), @menard, dir) ==
             ~s(ls lib && #{@menard} find calls Shop.Cart.total lib)

    # no one call in its place: refused as before
    assert Scripts.in_place(~s(grep -rn "def total" -A 3 lib), @menard, dir) == nil
    assert Scripts.in_place("python3 -c 'print(1)'", @menard, dir) == nil
    assert Scripts.in_place("ls lib", @menard, dir) == nil
  end

  @tag :tmp_dir
  test "a read is put in a function's place only where the function is not much more than was asked", %{
    tmp_dir: dir
  } do
    # a few lines asked of a long function are a few lines: rewritten to the whole function, a read of
    # 7 lines came back as 27 (and could come back as 300). The function in their place only where it
    # is not much more than was asked
    File.mkdir_p!(Path.join(dir, "lib"))
    body = Enum.map_join(1..40, "", &"    x#{&1} = #{&1}\n")
    File.write!(Path.join(dir, "lib/long.ex"), "defmodule Long do\n  def go do\n" <> body <> "  end\nend\n")
    why = &Scripts.refused(&1, @menard, dir)

    assert why.("sed -n '3,9p' lib/long.ex") == nil
    assert why.(~s(grep -n "def go" -A 5 lib/long.ex)) == nil
    assert why.("sed -n '2,40p' lib/long.ex") =~ "clause get lib/long.ex go/0"
    assert why.(~s(grep -n "def go" -A 35 lib/long.ex)) =~ "clause get lib/long.ex go"
  end
end
