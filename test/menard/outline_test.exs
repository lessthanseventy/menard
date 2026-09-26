defmodule Menard.OutlineTest do
  # The outline is what an agent reads before it edits: every module's defs with arity, kind,
  # the spec/doc it carries, and the lines it spans — as data, from the source alone.
  use ExUnit.Case, async: true

  alias Menard.Outline

  @src """
  defmodule Demo.A do
    @moduledoc "the demo"

    @doc "adds one"
    @spec inc(integer()) :: integer()
    def inc(n), do: n + 1

    def inc(n, m) do
      n + m
    end

    defp hidden(_x), do: :ok

    defmodule Inner do
      def z, do: 1
    end
  end
  """

  test "modules, defs with arity and kind, the doc's first line, line spans" do
    assert {:ok, [a]} = Outline.run(@src)
    assert a.module == "Demo.A"
    assert a.doc == "the demo"
    assert a.lines == {1, 17}

    assert [
             %{
               name: :inc,
               arity: 1,
               kind: :def,
               doc: "adds one",
               spec: "inc(integer()) :: integer()",
               lines: {6, 6}
             },
             %{name: :inc, arity: 2, kind: :def, doc: nil, spec: nil, lines: {8, 10}},
             %{name: :hidden, arity: 1, kind: :defp, lines: {12, 12}}
           ] = Enum.map(a.defs, &Map.take(&1, [:name, :arity, :kind, :doc, :spec, :lines]))

    assert [%{module: "Demo.A.Inner", defs: [%{name: :z, arity: 0}]}] = a.modules
  end

  test "an unparseable source is an error" do
    assert {:error, _} = Outline.run("defmodule (")
  end

  @tag :tmp_dir
  test "a file that does not parse fails the verb, after the others are outlined", %{tmp_dir: dir} do
    # it said so on stderr and exited 0, so a caller that went by the status read nothing as fine
    good = Path.join(dir, "good.ex")
    bad = Path.join(dir, "bad.ex")
    File.write!(good, "defmodule Good do\n  def go, do: 1\nend\n")
    File.write!(bad, "defmodule (")

    out =
      ExUnit.CaptureIO.capture_io(fn ->
        assert_raise Mix.Error, ~r/bad\.ex: not parseable/, fn ->
          Mix.Tasks.Menard.Outline.run([bad, good])
        end
      end)

    assert out =~ "Good  L1-3"
  end

  test "outline --json answers with the version, and line spans JSON can carry" do
    dir = Path.join(System.tmp_dir!(), "menard-outline-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    file = Path.join(dir, "a.ex")
    File.write!(file, "defmodule A do\n  def go, do: 1\nend\n")

    out = ExUnit.CaptureIO.capture_io(fn -> Mix.Tasks.Menard.Outline.run(["--json", file]) end)
    reply = JSON.decode!(out)

    # the version an agent passes back on its first edit, and line spans as lists: JSON has no tuple
    assert "sha256:" <> _ = reply["version"]
    assert [%{"lines" => [1, 3]}] = reply["modules"]
  end

  test "each def carries its head, as the clause verbs address it: no defaults, guard kept" do
    src = """
    defmodule H do
      def lines(%{items: items}), do: items
      def f(source, opts \\\\ []) when is_binary(source), do: {source, opts}
      def z, do: 1
    end
    """

    assert {:ok, [h]} = Outline.run(src)
    assert Enum.map(h.defs, & &1.head) == ["%{items: items}", "source, opts when is_binary(source)", ""]

    # the address the verbs take: every printed head finds its clause
    for d <- h.defs do
      assert {:ok, _} = Menard.Clause.find(src, "#{d.name}/#{d.arity}", d.head, [])
    end
  end
end
