defmodule Menard.MoveTest do
  # `clause move` to a file that does not exist yet: the module is named after the path, the way a
  # generator would, and with no mix project to name it from the move is refused toward `--as`.
  use ExUnit.Case, async: true

  alias Menard.Test.Host

  @moduletag :tmp_dir

  test "a missing destination in a mix project is created as the module its path names", %{tmp_dir: dir} do
    Host.mix_project(dir, :app)
    File.mkdir_p!(Path.join(dir, "lib"))
    from = Path.join(dir, "lib/a.ex")
    File.write!(from, "defmodule A do\n  def go, do: 1\n\n  def stays, do: 2\nend\n")
    dest = Path.join(dir, "lib/my_app/foo_bar.ex")

    assert {:ok, %{created: "MyApp.FooBar"}} = Menard.Move.run(from, dest, "go/0")
    assert File.read!(dest) == "defmodule MyApp.FooBar do\n  def go, do: 1\nend\n"
    assert File.read!(from) == "defmodule A do\n  def stays, do: 2\nend\n"
  end

  test "a missing destination outside any mix project is refused, and nothing is written" do
    # off the repo: ExUnit's tmp_dir sits inside menard's own project, whose mix.exs would name it
    dir = Path.join(System.tmp_dir!(), "menard-move-#{System.pid()}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    from = Path.join(dir, "a.ex")
    File.write!(from, "defmodule A do\n  def go, do: 1\nend\n")
    dest = Path.join(dir, "b.ex")

    assert {:error, message} = Menard.Move.run(from, dest, "go/0")
    assert message == "#{dest} does not exist and is not inside a mix project — name it with --as Mod.Name"
    refute File.exists?(dest)
    assert File.read!(from) == "defmodule A do\n  def go, do: 1\nend\n"
  end
end
