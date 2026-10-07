defmodule Menard.LspTest do
  # `find calls` asks the language server what the AST cannot see. One server per project, warmed
  # once, so not async.
  use ExUnit.Case, async: false

  @root Path.expand("../..", __DIR__)

  setup do
    project = Path.join(System.tmp_dir!(), "menard-lsp-#{System.pid()}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(project, "lib"))
    File.cp!(Path.join(@root, ".tool-versions"), Path.join(project, ".tool-versions"))

    File.write!(Path.join(project, "mix.exs"), """
    defmodule Bench.MixProject do
      use Mix.Project
      def project, do: [app: :bench, version: "0.1.0"]
    end
    """)

    File.write!(Path.join(project, "lib/math.ex"), """
    defmodule Bench.Math do
      @spec total([number()]) :: number()
      def total(xs), do: Enum.sum(xs)

      defmodule Inner do
        def total(xs), do: xs
      end
    end
    """)

    File.write!(Path.join(project, "lib/callers.ex"), """
    defmodule Bench.Callers do
      import Bench.Math

      def named, do: Bench.Math.total([1])
      def imported, do: total([1, 2])
      def applied, do: apply(Bench.Math, :total, [[1]])
    end
    """)

    File.write!(Path.join(project, "lib/deleg.ex"), """
    defmodule Bench.Deleg do
      defdelegate sum(xs), to: Bench.Math, as: :total
    end
    """)

    on_exit(fn -> File.rm_rf!(project) end)
    {:ok, project: project}
  end

  test "def_sites: the name in each head of the module's own function, not a nested module's", %{
    project: project
  } do
    source = File.read!(Path.join(project, "lib/math.ex"))
    assert Menard.Find.def_sites(source, "Bench.Math", "total") == [{3, 7}]
    assert Menard.Find.def_sites(source, "Bench.Math.Inner", "total") == [{6, 9}]
  end

  test "the CLI keeps no server: find answers from the AST and says so", %{project: project} do
    # the CLI runs unsupervised, with no registry to look a server up in: that crashed once
    {out, 0} =
      System.cmd(Path.join(@root, "bin/menard"), ["find", "--json", "calls", "Bench.Math.total", "lib"],
        cd: project,
        env: [{"MIX_ENV", "dev"}, {"MENARD_CWD", project}]
      )

    reply = JSON.decode!(out)
    assert [%{"line" => 4, "kind" => "call"}] = reply["hits"]
    assert reply["lsp"] =~ "the AST's alone"
  end

  # On PATH is not enough: a broken install (e.g. a nix derivation missing its own release
  # script) still resolves but exits nonzero the instant it's run — skip with that reason too,
  # never go red for a binary that can't actually serve.
  @expert_unusable (case System.find_executable("expert") do
                      nil ->
                        "expert is not on PATH"

                      path ->
                        case System.cmd(path, ["--version"], stderr_to_stdout: true) do
                          {_, 0} -> false
                          {out, status} -> "expert on PATH but exits #{status}: #{String.slice(out, 0, 160)}"
                        end
                    end)

  @tag timeout: 180_000
  @tag skip: @expert_unusable
  test "a warm server adds what the AST cannot see, as references", %{project: project} do
    Menard.Lsp.warm(project)
    params = %{kind: "calls", target: "Bench.Math.total", files: ["lib"], root: project}

    reply = ready(params, System.monotonic_time(:millisecond) + 150_000)
    assert reply.lsp == "expert"

    found = for hit <- reply.hits, do: {Path.basename(hit.file), hit.line, hit.kind}

    # the named call is the AST's; the import, the apply and the delegate only the server sees; the
    # @spec names the function without calling it
    assert Enum.sort(found) == [
             {"callers.ex", 4, :call},
             {"callers.ex", 5, :reference},
             {"callers.ex", 6, :reference},
             {"deleg.ex", 2, :reference}
           ]
  end

  @tag :tmp_dir
  test "an answer is taken once the server has settled, not in the gap between two phases of its work", %{
    tmp_dir: dir
  } do
    # expert's engine started at 3.9s and its build began at 4.9s: between them nothing was in flight,
    # and a reference asked there got the answer of a project half built
    done = Path.join(dir, "done")
    File.write!(Path.join(dir, "mix.exs"), "")

    for {k, v} <- [{"MENARD_LSP", Path.join(@root, "test/support/fake_lsp")}, {"FAKE_LSP_DONE", done}],
        do: System.put_env(k, v)

    on_exit(fn -> for k <- ["MENARD_LSP", "FAKE_LSP_DONE"], do: System.delete_env(k) end)
    Menard.Lsp.warm(dir)

    first =
      Enum.find_value(1..150, fn _ ->
        Process.sleep(100)

        case Menard.Lsp.references(dir, Path.join(dir, "mix.exs"), 1, 1, 1_000) do
          {:ok, _} -> {:answered, File.exists?(done)}
          _ -> nil
        end
      end)

    assert first == {:answered, true}
  end

  # a server indexing answers a short list, so ready is the answer that stops changing
  defp ready(params, deadline) do
    {:ok, reply} = Menard.Verbs.Find.run(params)

    cond do
      reply.lsp == "expert" and length(reply.hits) == 4 -> reply
      System.monotonic_time(:millisecond) > deadline -> reply
      true -> Process.sleep(1_000) && ready(params, deadline)
    end
  end
end
