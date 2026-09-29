defmodule Menard.ScriptsTest do
  # The two bans on scripts in another language: which commands each refuses, and which it must not.
  # A guard that refuses an innocent command gets switched off.
  use ExUnit.Case, async: true

  alias Menard.Scripts

  @menard "/p/bin/menard"
  @edit "python3 - <<'E'\np='lib/shop/cart.ex'\ns=open(p).read()\nopen(p,'w').write(s.replace('a','b'))\nE"

  defp refused?(command, mode), do: Scripts.refused(command, mode, @menard) != nil

  test "off refuses nothing" do
    refute refused?(@edit, :off)
    assert Scripts.upfront(:off, @menard) == nil
  end

  test "full refuses a command that runs an interpreter, wherever in it" do
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
      assert refused?(command, :full), "#{inspect(command)} ran"
    end
  end

  test "full lets a command through that only names one" do
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
      refute refused?(command, :full),
             "#{inspect(command)} was refused: #{Scripts.refused(command, :full, @menard)}"
    end
  end

  test "narrow refuses a script that names an Elixir file, and sed -i on one" do
    for command <- [
          @edit,
          "perl -pi -e 's/transition/change_status/g' lib/desk/tickets.ex test/desk/tickets_test.exs",
          "sed -i 's/a/b/' lib/a.ex",
          "cd app && sed -i -e 's/a/b/' lib/a_web/live/show.html.heex",
          "ruby -e 'File.write(\"config/runtime.exs\", \"x\")'",
          "for f in lib/*.ex; do python3 fix.py $f; done"
        ] do
      assert refused?(command, :narrow), "#{inspect(command)} ran"
    end
  end

  test "narrow lets a script through that names none, and what is no script" do
    for command <- [
          "python3 -c 'import json; print(json.load(open(\"a.json\")))'",
          "python3 - <<'E'\nopen('notes.md','w').write('x')\nE",
          "node assets/build.js",
          "sed -i 's/a/b/' README.md",
          "sed -n '1,20p' lib/a.ex",
          "cat > lib/new.ex <<'EOF'\ndefmodule New do\nend\nEOF",
          "grep -rn python lib/a.ex",
          "mix format lib/a.ex",
          "mix test test/a_test.exs"
        ] do
      refute refused?(command, :narrow), "#{inspect(command)} was refused"
    end
  end

  test "a refusal, and what is said up front, name this menard by its path and show an edit" do
    for text <- [
          Scripts.refused(@edit, :full, @menard),
          Scripts.refused(@edit, :narrow, @menard),
          Scripts.upfront(:full, @menard),
          Scripts.upfront(:narrow, @menard)
        ] do
      assert text =~ "/p/bin/menard edit --then test - <<'EOF'"
      assert text =~ "<<<<<<< SEARCH"
    end

    assert Scripts.refused(@edit, :full, @menard) =~ "python3 does not run here"
    assert Scripts.refused(@edit, :narrow, @menard) =~ "python3 does not edit Elixir here (lib/shop/cart.ex)"
    assert Scripts.upfront(:full, @menard) =~ "There is no python"
    assert Scripts.upfront(:full, @menard) =~ "elixir -e"
    assert Scripts.upfront(:narrow, @menard) =~ "Scripts for anything else run"
  end
end
