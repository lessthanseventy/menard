defmodule Menard.MapWhereTest do
  # `map`: the project's modules and public functions, one line each. `where`: the function a grep
  # hit sits in. Both read the caller's directory, which is process-wide: not async.
  use ExUnit.Case, async: false

  @tag :tmp_dir
  setup %{tmp_dir: dir} do
    previous = System.get_env("MENARD_CWD")
    System.put_env("MENARD_CWD", dir)

    on_exit(fn ->
      if previous, do: System.put_env("MENARD_CWD", previous), else: System.delete_env("MENARD_CWD")
    end)

    File.mkdir_p!(Path.join(dir, "app/lib/app"))
    File.mkdir_p!(Path.join(dir, "deps/dep/lib"))

    File.write!(Path.join(dir, "app/lib/app/cart.ex"), """
    defmodule App.Cart do
      def new, do: %{}

      def add(cart, sku), do: Map.update(cart, sku, 1, &(&1 + 1))

      defp secret, do: :x

      defmodule Line do
        def total(line), do: line
      end
    end
    """)

    File.write!(Path.join(dir, "deps/dep/lib/dep.ex"), "defmodule Dep do\n  def f, do: 1\nend\n")
    :ok
  end

  @tag :tmp_dir
  test "map lists each module under a lib/ with its file and public functions, deps left out" do
    out = ExUnit.CaptureIO.capture_io(fn -> Mix.Tasks.Menard.Map.run([]) end)

    assert out =~ "App.Cart  app/lib/app/cart.ex  new/0 add/2\n"
    assert out =~ "App.Cart.Line  app/lib/app/cart.ex  total/1\n"
    refute out =~ "secret"
    refute out =~ "Dep"
  end

  @tag :tmp_dir
  test "where names the function each grep hit sits in, the module for a line outside every def" do
    out =
      ExUnit.CaptureIO.capture_io(fn ->
        Mix.Tasks.Menard.Where.run([
          "app/lib/app/cart.ex:4:  def add",
          "app/lib/app/cart.ex:9",
          "app/lib/app/cart.ex:1"
        ])
      end)

    assert out =~ "app/lib/app/cart.ex:4  App.Cart.add/2\n"
    assert out =~ "app/lib/app/cart.ex:9  App.Cart.Line.total/1\n"
    assert out =~ "app/lib/app/cart.ex:1  App.Cart\n"
  end
end
