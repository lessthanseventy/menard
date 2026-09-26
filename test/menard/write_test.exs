defmodule Menard.WriteTest do
  # The parse check every write goes through: its one job beyond the trailing newline is refusing
  # bytes that do not parse, so a syntax error never reaches disk.
  use ExUnit.Case, async: true

  alias Menard.Write

  test "refuses Elixir that does not parse" do
    assert {:error, message} = Write.checked("a.ex", "defmodule A do\n  def go, do: (\nend")
    assert message =~ "not parseable"
  end

  test "a non-Elixir file is passed as-is — menard writes fixtures too" do
    assert {:ok, ~s({"not": "elixir"}\n)} = Write.checked("fixture.json", ~s({"not": "elixir"}))
  end

  test "always ends with exactly one trailing newline" do
    assert {:ok, "defmodule A do\nend\n"} = Write.checked("a.ex", "defmodule A do\nend")
    assert {:ok, "defmodule A do\nend\n"} = Write.checked("a.ex", "defmodule A do\nend\n")
  end

  @tag :tmp_dir
  test "an empty stdin is refused, not written over the file", %{tmp_dir: dir} do
    file = Path.join(dir, "a.ex")
    File.write!(file, "defmodule A do\nend\n")

    assert_raise Mix.Error, ~r/stdin was empty/, fn ->
      ExUnit.CaptureIO.capture_io("", fn -> Mix.Tasks.Menard.Write.run([file, "-"]) end)
    end

    assert File.read!(file) == "defmodule A do\nend\n"
  end

  test "a parse error that carries a hint is refused with it, not crashed on" do
    # a stray `end`: the parser's message is a {prefix, hint} tuple
    assert {:error, message} = Write.checked("a.ex", "defmodule A do\n  x\n  end\nend\nend")
    assert message =~ "not parseable at line"
    assert message =~ "hint"
  end
end
