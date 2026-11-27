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

  test "a column is counted in UTF-16 units for the server, and back" do
    line = ~s|  def go, do: "héllo 🎉" <> total(1)|
    column = String.length(hd(String.split(line, "total"))) + 1
    # 0-based, and the emoji before it one character and two units
    assert Menard.Lsp.character(line, column) == column
    assert Menard.Lsp.column(line, column) == column
    assert Menard.Lsp.character("  total(1)", 3) == 2
    assert Menard.Lsp.column("  total(1)", 2) == 3
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
    # the named call and, through the import, the bare one: the AST's
    assert [%{"line" => 4, "kind" => "call"}, %{"line" => 5, "kind" => "call"}] = reply["hits"]
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

  @tag timeout: 900_000
  @tag skip: @expert_unusable
  test "a warm server adds what the AST cannot see, as references", %{project: project} do
    Menard.Lsp.warm(project)
    math = Path.join(project, "lib/math.ex")

    # settled is no promise the index is built: under load expert's build began over 3s after its
    # engine, and until then it answered null or a short list. Only the index knows the delegate.
    await_server(project, 800_000, fn ->
      with {:ok, found} <- Menard.Lsp.references(project, math, 3, 7, 5_000),
           true <- Enum.any?(found, &(Path.basename(&1.file) == "deleg.ex")),
           do: :ok,
           else: (_ -> :warming)
    end)

    {:ok, reply} =
      Menard.Verbs.Find.run(%{kind: "calls", target: "Bench.Math.total", files: ["lib"], root: project})

    assert reply.lsp == "expert"

    found = for hit <- reply.hits, do: {Path.basename(hit.file), hit.line, hit.kind}

    # the named call and the one through the import are the AST's; the apply and the delegate only
    # the server sees; the @spec names the function without calling it
    assert Enum.sort(found) == [
             {"callers.ex", 4, :call},
             {"callers.ex", 5, :call},
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

  @tag :tmp_dir
  test "await_server fails at once, with the exit status, when the server is gone", %{tmp_dir: dir} do
    stand_in = Path.join(dir, "exits")
    File.write!(stand_in, "#!/bin/sh\nsleep 0.5\nexit 3\n")
    File.chmod!(stand_in, 0o755)
    File.write!(Path.join(dir, "mix.exs"), "")
    System.put_env("MENARD_LSP", stand_in)
    on_exit(fn -> System.delete_env("MENARD_LSP") end)

    Menard.Lsp.warm(dir)
    started = System.monotonic_time(:millisecond)

    ask = fn ->
      if match?({:ok, _}, Menard.Lsp.references(dir, Path.join(dir, "mix.exs"), 1, 1, 1_000)), do: :ok
    end

    error = assert_raise ExUnit.AssertionError, fn -> await_server(dir, 60_000, ask) end
    assert error.message =~ "exit_status, 3"
    assert System.monotonic_time(:millisecond) - started < 5_000
  end

  # asks until `ask` answers :ok; a server that exits is no wait at all
  defp await_server(project, ms, ask) do
    pid =
      project
      |> Path.expand()
      |> then(&Registry.lookup(Menard.Lsp.Registry, &1))
      |> then(fn
        [{pid, _}] -> pid
        [] -> flunk("the language server is not running")
      end)

    ref = Process.monitor(pid)
    ask_until(ref, System.monotonic_time(:millisecond) + ms, ask)
  end

  defp ask_until(ref, deadline, ask) do
    receive do
      {:DOWN, ^ref, _, _, reason} ->
        flunk("the language server stopped before it answered: #{inspect(reason)}")
    after
      0 ->
        cond do
          ask.() == :ok -> :ok
          System.monotonic_time(:millisecond) > deadline -> flunk("the language server never answered")
          true -> Process.sleep(100) && ask_until(ref, deadline, ask)
        end
    end
  end
end
