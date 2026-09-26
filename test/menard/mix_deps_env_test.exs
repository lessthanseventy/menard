defmodule Menard.MixDepsEnvTest do
  # Sets MIX_ENV in menard's own environment, which every process reads: not async.
  use ExUnit.Case, async: false

  alias Menard.MixDeps

  @moduletag :tmp_dir

  test "a bare name is looked up in the host's own env, not menard's", %{tmp_dir: dir} do
    # `hex.info` ran with menard's MIX_ENV, where every other host mix unsets it. The host's
    # hex.info here is an alias that says which env it ran in.
    File.write!(Path.join(dir, "mix.exs"), """
    defmodule Env.MixProject do
      use Mix.Project
      def project, do: [app: :env, version: "0.1.0", deps: [], aliases: ["hex.info": &info/1]]
      defp info(_), do: IO.puts(~s(Config: {:ran_in_\#{Mix.env()}, path: "../nowhere"}))
    end
    """)

    before = System.get_env("MIX_ENV")
    System.put_env("MIX_ENV", "prod")

    try do
      assert %{ok: false, dep: dep} = MixDeps.add_in(dir, "anything")
      assert dep =~ "ran_in_dev"
    after
      if before, do: System.put_env("MIX_ENV", before), else: System.delete_env("MIX_ENV")
    end
  end

  test "an app name that is no dependency makes no atom" do
    name = "never_an_app_#{System.unique_integer([:positive])}"
    source = "defmodule A.MixProject do\n  def project, do: [app: :a, deps: [{:jason, \"~> 1.4\"}]]\nend\n"

    assert {:error, _} = MixDeps.set_requirement(source, name, "~> 1.0")
    assert_raise ArgumentError, fn -> String.to_existing_atom(name) end
  end
end
