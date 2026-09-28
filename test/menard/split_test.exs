defmodule Menard.SplitTest do
  # `clause split`: a module into several in ONE call, the whole plan at once. riverside2: a split
  # by `clause move` was a call per new module with a refusal and two fix-ups between, twelve calls
  # where the agents' own script was one, and doubled the step.
  use ExUnit.Case, async: true

  alias Menard.Test.Host
  alias Menard.Verbs

  @moduletag :tmp_dir

  @shop """
  defmodule Split2.Shop do
    @moduledoc "A shop."

    @rate 0.2

    @doc "Every product."
    def list, do: [:a, :b]

    @doc "One product."
    def get(id), do: Enum.find(list(), &(&1 == id))

    @doc "What it costs."
    def total(prices), do: round(sum(prices) * (1 + @rate))

    @doc "What it costs, before tax."
    def net(prices), do: sum(prices)

    def open?, do: true

    defp sum(prices), do: Enum.sum(prices)
  end
  """

  defp shop(dir) do
    file = Path.join(dir, "lib/shop.ex")
    File.mkdir_p!(Path.dirname(file))
    # the project a created module is named in: `lib/shop/catalog.ex` is `Shop.Catalog`
    Host.mix_project(dir, :split2)
    File.write!(file, @shop)
    file
  end

  defp compile(files) do
    sources = Enum.map(files, &File.read!/1)
    {_modules, diagnostics} = Code.with_diagnostics(fn -> Code.compile_string(Enum.join(sources, "\n")) end)
    diagnostics
  end

  test "a whole plan in one call: every new module written, the source left a facade", %{tmp_dir: dir} do
    file = shop(dir)

    assert {:ok, reply} =
             Verbs.Clause.run(%{
               verb: "split",
               file: file,
               plan: [
                 %{
                   to: Path.join(dir, "lib/shop/catalog.ex"),
                   functions: ["list/0", "get/1"],
                   as: "Split2.Shop.Catalog"
                 },
                 %{
                   to: Path.join(dir, "lib/shop/pricing.ex"),
                   functions: ["total/1", "net/1"],
                   as: "Split2.Shop.Pricing",
                   moduledoc: "What things cost."
                 }
               ]
             })

    assert reply.did == "split shop.ex into catalog.ex, pricing.ex"
    assert [%{created: "Split2.Shop.Catalog", moved: ["list/0", "get/1"]}, pricing] = reply.modules
    assert %{created: "Split2.Shop.Pricing", moved: ["total/1", "net/1"], carried: ["sum/1"]} = pricing
    assert "sha256:" <> _ = reply.version
    assert "sha256:" <> _ = pricing.version

    source = File.read!(file)
    # a split keeps the module's API unless told not to
    # (the project's formatter may alias the new modules)
    assert source =~ ~r/defdelegate list(\(\))?, to: (Split2\.Shop\.)?Catalog/
    assert source =~ ~r/defdelegate total\(prices\), to: (Split2\.Shop\.)?Pricing/
    assert source =~ "def open?, do: true"
    refute source =~ "defp sum"
    assert File.read!(Path.join(dir, "lib/shop/pricing.ex")) =~ ~s(@moduledoc "What things cost.")

    assert compile([file, Path.join(dir, "lib/shop/catalog.ex"), Path.join(dir, "lib/shop/pricing.ex")]) == []
    # by name: the module exists once the files above are compiled, not when this one is
    shop = Module.concat(["Split2", "Shop"])
    assert shop.total([1, 2]) == 4
    assert shop.get(:b) == :b
  end

  test "a plan that cannot be finished writes nothing: a split that half lands is worse than none", %{
    tmp_dir: dir
  } do
    file = shop(dir)
    catalog = Path.join(dir, "lib/shop/catalog.ex")

    assert {:error, why} =
             Verbs.Clause.run(%{
               verb: "split",
               file: file,
               plan: [
                 %{to: catalog, functions: ["list/0", "get/1"]},
                 %{to: Path.join(dir, "lib/shop/pricing.ex"), functions: ["nope/3"]}
               ]
             })

    assert why =~ "nothing was written"
    assert why =~ "pricing.ex"
    assert why =~ "nope/3"
    assert File.read!(file) == @shop
    refute File.exists?(catalog)
  end

  test "a function the plan sends to two modules is refused, naming it", %{tmp_dir: dir} do
    file = shop(dir)

    assert {:error, why} =
             Verbs.Clause.run(%{
               verb: "split",
               file: file,
               plan: [
                 %{to: Path.join(dir, "lib/shop/a.ex"), functions: ["list/0"]},
                 %{to: Path.join(dir, "lib/shop/b.ex"), functions: ["list/0", "get/1"]}
               ]
             })

    assert why =~ "list/0"
    assert File.read!(file) == @shop
  end

  test "a split the formatter could not finish says so, module by module", %{tmp_dir: dir} do
    file = shop(dir)
    File.write!(Path.join(dir, ".formatter.exs"), "[plugins: [MenardNeverBuiltPlug]]")

    assert {:ok, %{modules: [%{unformatted: why}]}} =
             Verbs.Clause.run(%{
               verb: "split",
               file: file,
               plan: [%{to: Path.join(dir, "lib/shop/pricing.ex"), functions: ["net/1"]}]
             })

    assert why =~ "MenardNeverBuiltPlug"
  end

  test "delegate: false leaves no delegates, and names the calls left to fix", %{tmp_dir: dir} do
    file = shop(dir)

    File.write!(
      Path.join(dir, "lib/till.ex"),
      "defmodule Split2.Till do\n  def ring(p), do: Split2.Shop.net(p)\nend\n"
    )

    assert {:ok, %{modules: [%{left: left}]}} =
             Verbs.Clause.run(%{
               verb: "split",
               file: file,
               delegate: false,
               root: dir,
               plan: [%{to: "lib/shop/pricing.ex", functions: ["net/1"]}]
             })

    refute File.read!(file) =~ "defdelegate"
    assert ["lib/till.ex:2: " <> _] = left
  end

  test "the CLI's plan is a DEST=a/1,b/2 per new module, each named after its path", %{tmp_dir: dir} do
    file = shop(dir)
    catalog = Path.join(dir, "lib/shop/catalog.ex")
    pricing = Path.join(dir, "lib/shop/pricing.ex")

    out =
      ExUnit.CaptureIO.capture_io(fn ->
        Mix.Tasks.Menard.Clause.run([
          "split",
          file,
          "#{catalog}=list/0,get/1",
          # or the MCP door's object, for a moduledoc or a name
          JSON.encode!(%{to: pricing, functions: ["total/1", "net/1"], moduledoc: "What things cost."})
        ])
      end)

    assert %{
             "did" => "split shop.ex into catalog.ex, pricing.ex",
             "modules" => [%{"created" => "Shop.Catalog"}, %{"created" => "Shop.Pricing"}]
           } = JSON.decode!(out)

    # the project's formatter may alias the new module
    assert File.read!(file) =~ ~r/defdelegate net\(prices\), to: (Shop\.)?Pricing/
    assert File.read!(pricing) =~ "defp sum(prices)"
    assert File.read!(pricing) =~ ~s(@moduledoc "What things cost.")
  end
end
