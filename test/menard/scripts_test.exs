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
          ~s(grep -c "def " lib/cart.ex),
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
end
