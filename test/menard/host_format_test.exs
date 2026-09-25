defmodule Menard.HostFormatTest do
  # menard formats with the HOST project's formatter while that project is as broken as it gets:
  # a mix.exs that does not parse, deps never fetched. Plugins come from its last build in
  # _build; import_deps from deps/, else from the copy the last good format cached.
  use ExUnit.Case, async: true

  @moduletag :tmp_dir

  defp host(dir, formatter) do
    File.write!(Path.join(dir, "mix.exs"), "defmodule Broken.MixProject do\n  this does not parse (\n")
    File.write!(Path.join(dir, ".formatter.exs"), formatter)
    File.mkdir_p!(Path.join(dir, "lib"))
    dir
  end

  defp write(dir, name, code) do
    file = Path.join([dir, "lib", name])
    File.write!(file, code)
    file
  end

  test "a plugin that will not load is never skipped silently — the file is left alone", %{tmp_dir: dir} do
    ebin = Path.join(dir, "_build/dev/lib/plug/ebin")
    File.mkdir_p!(ebin)
    File.write!(Path.join(ebin, "Elixir.MenardBadPlug.beam"), "not a beam")
    host(dir, "[inputs: [\"lib/**/*.ex\"], plugins: [MenardBadPlug]]")
    code = "defmodule F do\n  def   f, do: 1\nend\n"
    file = write(dir, "f.ex", code)

    assert {:error, message} = Menard.format(file, cache: Path.join(dir, "cache"))
    assert message =~ "MenardBadPlug"
    assert File.read!(file) == code
  end

  test "formats with the host's own options though its mix.exs is broken", %{tmp_dir: dir} do
    host(dir, "[inputs: [\"lib/**/*.ex\"], line_length: 30]")
    file = write(dir, "a.ex", "defmodule A do\n  def go, do: [:alpha, :beta, :gamma, :delta]\nend\n")

    assert Menard.format(file, cache: Path.join(dir, "cache")) == :ok
    assert File.read!(file) =~ "[\n      :alpha,\n"
  end

  test "a plugin compiled into the host's _build is applied, no deps fetched", %{tmp_dir: dir} do
    plugin = :"Elixir.MenardTestPlug#{System.unique_integer([:positive])}"
    ebin = Path.join(dir, "_build/dev/lib/plug/ebin")
    File.mkdir_p!(ebin)

    [{^plugin, beam}] =
      Code.compile_string("""
      defmodule #{inspect(plugin)} do
        @behaviour Mix.Tasks.Format
        def features(_opts), do: [extensions: [".ex"]]
        def format(contents, _opts), do: "# plugged\\n" <> contents
      end
      """)

    :code.purge(plugin)
    :code.delete(plugin)
    File.write!(Path.join(ebin, "#{plugin}.beam"), beam)

    host(dir, "[inputs: [\"lib/**/*.ex\"], plugins: [#{inspect(plugin)}]]")
    file = write(dir, "b.ex", "defmodule B do\nend\n")

    assert Menard.format(file, cache: Path.join(dir, "cache")) == :ok
    assert File.read!(file) =~ "# plugged\n"
  end

  test "import_deps come from the cache once the dep is gone", %{tmp_dir: dir} do
    host(dir, "[inputs: [\"lib/**/*.ex\"], import_deps: [:dsl]]")
    dep = Path.join(dir, "deps/dsl")
    File.mkdir_p!(dep)
    File.write!(Path.join(dep, ".formatter.exs"), "[export: [locals_without_parens: [field: 2]]]")
    cache = Path.join(dir, "cache")

    first = write(dir, "c.ex", "defmodule C do\n  field :a, :b\nend\n")
    assert Menard.format(first, cache: cache) == :ok

    File.rm_rf!(Path.join(dir, "deps"))
    second = write(dir, "d.ex", "defmodule D do\n  field :c, :d\nend\n")
    assert Menard.format(second, cache: cache) == :ok
    assert File.read!(second) =~ "field :c, :d"
  end

  test "a missing dep with no cache leaves the file alone and says why", %{tmp_dir: dir} do
    host(dir, "[inputs: [\"lib/**/*.ex\"], import_deps: [:dsl]]")
    code = "defmodule E do\n  field   :e, :f\nend\n"
    file = write(dir, "e.ex", code)

    assert {:error, message} = Menard.format(file, cache: Path.join(dir, "cache"))
    assert message =~ "dsl"
    assert File.read!(file) == code
  end
end
