defmodule Menard.GuardTest do
  # `menard guard FILE`: the enforcement logic any harness's pre-edit hook calls — exit 2 with the
  # reason on stderr for an Elixir module, 0 for everything else.
  use ExUnit.Case, async: true

  @moduletag :tmp_dir
  @bin Path.expand("../../bin/menard", __DIR__)

  defp guard(file), do: System.cmd(@bin, ["guard", file], stderr_to_stdout: true, env: [{"MIX_ENV", "dev"}])

  test "an existing module is refused, with the verbs to use instead", %{tmp_dir: dir} do
    file = Path.join(dir, "a.ex")
    File.write!(file, "defmodule A do\nend\n")

    assert {out, 2} = guard(file)
    assert out =~ "an Elixir module"
    assert out =~ "clause replace"
  end

  test "a new file, a non-module script and other languages pass", %{tmp_dir: dir} do
    script = Path.join(dir, "run.exs")
    File.write!(script, "IO.puts(:hi)\n")
    other = Path.join(dir, "a.ts")
    File.write!(other, "defmodule\n")

    assert {_, 0} = guard(Path.join(dir, "new.ex"))
    assert {_, 0} = guard(script)
    assert {_, 0} = guard(other)
  end

  test "config, deps, _build and .formatter.exs are exempt", %{tmp_dir: dir} do
    for rel <- ["config/config.exs", "deps/x/lib/x.ex", "_build/dev/x.ex", ".formatter.exs"] do
      file = Path.join(dir, rel)
      File.mkdir_p!(Path.dirname(file))
      File.write!(file, "defmodule X do\nend\n")
      assert {_, 0} = guard(file), rel
    end
  end
end
