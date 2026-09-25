defmodule Menard.HexCorpusTest do
  # The identity corpus over real hex packages: every clause, attribute, block and statement in
  # their lib/ replaced with itself. Not part of the gate — it fetches, and it takes minutes:
  # `mise run bench:identity` (`mix test --only corpus`). Versions are pinned, so the numbers
  # compare across runs; each package's source is fetched once, into menard's user cache.
  use ExUnit.Case, async: false

  alias Menard.Test.Identity

  @moduletag :corpus
  @moduletag timeout: :infinity

  @packages [
    absinthe: "1.12.0",
    bandit: "1.12.5",
    broadway: "1.3.0",
    credo: "1.7.19",
    decimal: "3.1.1",
    ecto: "3.14.2",
    ecto_sql: "3.14.0",
    ex_doc: "0.40.4",
    finch: "0.23.0",
    gettext: "1.0.2",
    igniter: "0.8.4",
    jason: "1.4.5",
    mint: "1.10.1",
    nimble_options: "1.1.1",
    oban: "2.24.1",
    phoenix: "1.8.15",
    phoenix_live_view: "1.2.12",
    plug: "1.20.3",
    postgrex: "0.22.4",
    req: "0.7.4",
    styler: "1.12.2",
    telemetry: "1.4.2"
  ]

  test "every identity edit over the hex corpus leaves its file as it was" do
    started = System.monotonic_time(:millisecond)
    files = Enum.flat_map(@packages, fn {name, version} -> sources(name, version) end)

    results =
      files
      |> Task.async_stream(&check_file/1, timeout: :infinity, ordered: false)
      |> Enum.map(fn {:ok, result} -> result end)

    seconds = (System.monotonic_time(:millisecond) - started) / 1000
    {checked, skipped} = Enum.split_with(results, &match?({:checked, _, _}, &1))

    edits =
      for {:checked, file, per_check} <- checked,
          {check, outcomes} <- per_check,
          o <- outcomes,
          do: {file, check, o}

    IO.puts("""

    hex corpus: #{length(@packages)} packages, #{length(checked)} files \
    (#{length(skipped)} not parseable, skipped), #{length(edits)} identity edits in #{Float.round(seconds, 1)}s

    #{table(edits)}
    """)

    bad =
      for {file, check, {label, outcome}} <- edits,
          outcome in [:changed, :crashed],
          do: {file, check, label, outcome}

    for {file, check, label, outcome} <- Enum.take(bad, 300),
        do: IO.puts("  #{outcome} #{check} #{file}: #{label}")

    assert bad == []
  end

  defp sources(name, version) do
    dir = Path.join(corpus(), "#{name}-#{version}")

    unless File.dir?(dir) do
      {out, status} =
        System.cmd("mix", ["hex.package", "fetch", "#{name}", version, "--unpack", "--output", dir],
          stderr_to_stdout: true
        )

      if status != 0, do: flunk("fetching #{name} #{version}: #{out}")
    end

    Path.wildcard(Path.join(dir, "lib/**/*.{ex,exs}"))
  end

  defp check_file(path) do
    source = File.read!(path)
    label = Path.relative_to(path, corpus())

    case Sourceror.parse_string(source) do
      {:ok, _} -> {:checked, label, Enum.map(Identity.checks(), &{&1, run(source, &1)})}
      {:error, _} -> {:skipped, label}
    end
  end

  # A verb that raises on real code is a finding too, not a reason to stop counting.
  defp run(source, check) do
    Identity.run(source, check)
  rescue
    e -> [{"raised #{inspect(e.__struct__)}: #{e |> Exception.message() |> String.slice(0, 120)}", :crashed}]
  end

  defp table(edits) do
    outcomes = [:same, :formatted, :changed, :refused, :crashed]
    header = ["check", "edits", "same bytes", "same formatted", "changed", "refused", "crashed"]

    rows =
      for check <- Identity.checks() do
        mine = for {_, ^check, {_, o}} <- edits, do: o
        counts = Enum.frequencies(mine)
        [to_string(check), to_string(length(mine)) | Enum.map(outcomes, &to_string(counts[&1] || 0))]
      end

    total = Enum.frequencies(for {_, _, {_, o}} <- edits, do: o)
    all = ["all", to_string(length(edits)) | Enum.map(outcomes, &to_string(total[&1] || 0))]

    [header | rows ++ [all]]
    |> Enum.map_join("\n", fn cells -> Enum.map_join(cells, "  ", &String.pad_leading(&1, 14)) end)
  end

  defp corpus, do: Path.join(:filename.basedir(:user_cache, "menard"), "corpus")
end
