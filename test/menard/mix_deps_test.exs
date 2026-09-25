defmodule Menard.MixDepsTest do
  use ExUnit.Case, async: true

  alias Menard.MixDeps

  @fn_deps """
  defmodule A.MixProject do
    use Mix.Project
    def project, do: [app: :a, deps: deps()]

    defp deps do
      [
        {:jason, "~> 1.4"},
        {:x, path: "../x"} # why x
      ]
    end
  end
  """

  describe "add" do
    test "appends to the list a `deps()` call names, keeping a trailing comment on its line" do
      assert MixDeps.add(@fn_deps, ~s({:req, "~> 0.5"})) =~
               ~s(      {:x, path: "../x"}, # why x\n      {:req, "~> 0.5"}\n    ])
    end

    test "appends to a deps list written inline in project/0" do
      src = """
      defmodule A.MixProject do
        use Mix.Project

        def project do
          [
            app: :a,
            deps: [
              {:jason, "~> 1.4"}
            ]
          ]
        end
      end
      """

      assert MixDeps.add(src, ~s({:req, "~> 0.5", only: :test})) =~
               ~s(        {:jason, "~> 1.4"},\n        {:req, "~> 0.5", only: :test}\n      ])
    end

    test "fills an empty list" do
      src = "defmodule A.MixProject do\n  def project, do: [app: :a, deps: []]\nend\n"
      assert MixDeps.add(src, ~s({:req, "~> 0.5"})) =~ ~s(deps: [{:req, "~> 0.5"}])
    end

    test "refuses a dependency already there, naming it as written" do
      assert {:error, message} = MixDeps.add(@fn_deps, ~s({:jason, "~> 2.0"}))
      assert message =~ ~s({:jason, "~> 1.4"})
    end

    test "refuses a spec that is not a dependency tuple" do
      assert {:error, _} = MixDeps.add(@fn_deps, "jason")
    end
  end

  describe "set_requirement" do
    test "changes only the requirement's bytes" do
      assert MixDeps.set_requirement(@fn_deps, "jason", "~> 2.0") ==
               String.replace(@fn_deps, ~s("~> 1.4"), ~s("~> 2.0"))
    end

    test "a path or git dependency has no requirement to change" do
      assert {:error, message} = MixDeps.set_requirement(@fn_deps, "x", "~> 2.0")
      assert message =~ "no version requirement"
    end

    test "an app that is not a dependency is refused" do
      assert {:error, _} = MixDeps.set_requirement(@fn_deps, "nope", "~> 1.0")
    end
  end

  test "lock_diff names what was added, removed and changed, by version" do
    before =
      ~s(%{"a": {:hex, :a, "1.0.0", "x", [:mix], [], "hexpm", "y"}, "b": {:hex, :b, "2.0.0", "x", [:mix], [], "hexpm", "y"}})

    after_ =
      ~s(%{"a": {:hex, :a, "1.1.0", "x", [:mix], [], "hexpm", "y"}, "c": {:git, "https://g", "0123456789abcdef", []}})

    assert MixDeps.lock_diff(before, after_) == %{
             added: [%{app: "c", version: "0123456"}],
             removed: [%{app: "b", version: "2.0.0"}],
             changed: [%{app: "a", from: "1.0.0", to: "1.1.0"}]
           }
  end

  describe "in a project" do
    @describetag :tmp_dir

    defp project(dir, deps) do
      host = Path.join(dir, "host")
      File.mkdir_p!(Path.join(host, "lib"))

      File.write!(Path.join(host, "mix.exs"), """
      defmodule Host.MixProject do
        use Mix.Project
        def project, do: [app: :host, version: "0.1.0", deps: deps()]

        defp deps do
          #{deps}
        end
      end
      """)

      dep = Path.join(dir, "dep")
      File.mkdir_p!(Path.join(dep, "lib"))

      File.write!(
        Path.join(dep, "mix.exs"),
        "defmodule Dep.MixProject do\n  use Mix.Project\n  def project, do: [app: :dep, version: \"0.1.0\"]\nend\n"
      )

      File.write!(Path.join(dep, "lib/dep.ex"), "defmodule Dep do\n  def hi, do: :hi\nend\n")
      host
    end

    test "add writes the dependency, fetches it, and answers with the lock diff and the compile", %{
      tmp_dir: dir
    } do
      host = project(dir, "[]")

      assert %{ok: true, lock: %{added: [], removed: [], changed: []}, compile: %{ok: true}} =
               MixDeps.add_in(host, ~s({:dep, path: "../dep"}))

      assert File.read!(Path.join(host, "mix.exs")) =~ ~s({:dep, path: "../dep"})
    end

    test "an add whose fetch fails puts mix.exs back as it was", %{tmp_dir: dir} do
      host = project(dir, "[]")
      before = File.read!(Path.join(host, "mix.exs"))

      assert %{ok: false, error: _} = MixDeps.add_in(host, ~s({:gone, path: "../nowhere"}))
      assert File.read!(Path.join(host, "mix.exs")) == before
    end

    test "upgrade runs the update and answers the same way", %{tmp_dir: dir} do
      host = project(dir, ~s([{:dep, path: "../dep"}]))
      assert %{ok: true, via: "deps.update", compile: %{ok: true}} = MixDeps.upgrade_in(host, [], nil)
    end
  end

  test "upgrade goes through igniter.upgrade when the host's lock has Igniter" do
    assert MixDeps.upgrade_command(~s(%{"igniter": {:hex, :igniter, "0.8.4"}}), ["ash"]) ==
             ["igniter.upgrade", "ash", "--yes"]

    assert MixDeps.upgrade_command(~s(%{"jason": {:hex, :jason, "1.4.4"}}), []) == ["deps.update", "--all"]
    assert MixDeps.upgrade_command("", ["jason"]) == ["deps.update", "jason"]
  end

  test "a bare name's spec is the Config line mix hex.info prints" do
    out = "Parses JSON.\n\nConfig: {:jason, \"~> 1.4\"}\nReleases: 1.4.4, 1.4.3\n"
    assert MixDeps.spec_from_hex_info(out) == {:ok, ~s({:jason, "~> 1.4"})}
    assert {:error, _} = MixDeps.spec_from_hex_info("No package with name nope")
  end

  test "reading a lock warns about nothing (mix.lock quotes every key)" do
    lock = ~s(%{"jason": {:hex, :jason, "1.4.4", "x", [:mix], [], "hexpm", "y"}})
    assert ExUnit.CaptureIO.capture_io(:stderr, fn -> MixDeps.lock_diff(lock, lock) end) == ""
  end
end
