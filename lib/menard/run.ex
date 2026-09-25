defmodule Menard.Run do
  @moduledoc """
  The run verbs' parsers: ExUnit's output → the counts and each failure as data (name, module,
  where, the assertion's code/left/right or the error), and a tail that is the summary, not the
  logs a suite prints on its way. `mix menard.run` prints what these return, as one JSON line.
  """

  @doc """
  A run verb in the mix project at `dir` — `"check"` (its `mix precommit`), `"test"` (args: files,
  file:line), `"format"` (args: files; reports what changed), `"compile"` (warnings as
  diagnostics) — as one map with `ok`. Both doors (`mix menard.run`, the MCP `run` tool) call this.
  """
  def result(dir, "check", _args) do
    {out, status, fetched} = mix_fetching(dir, ["precommit"])

    if status != 0 and out =~ ~s(The task "precommit" could not be found),
      do: check_steps(dir),
      else: %{ok: status == 0, exit: status, tail: tail(out), fetched: fetched}
  end

  def result(dir, "test", args) do
    {out, status, fetched} = mix_fetching(dir, ["test" | args])
    out |> parse_test(status) |> with_sources(dir) |> Map.put(:fetched, fetched)
  end

  def result(dir, "format", files) do
    # no files named: what the project's own `mix format` would take, its formatter inputs. Given
    # none, this formatted nothing and answered ok, while the project's check failed.
    files = if files == [], do: formatter_inputs(dir), else: Enum.map(files, &Path.expand(&1, dir))
    before = Map.new(files, &{&1, File.read!(&1)})

    # menard's own formatter, not the host's bare `mix format`: it works while the host's deps do not
    # resolve or its mix.exs does not parse, and never formats without a plugin the host uses
    errors =
      for file <- files, {:error, message} <- [Menard.format(file)], do: %{file: file, error: message}

    changed = Enum.filter(files, &(File.read!(&1) != before[&1]))
    %{ok: errors == [], changed: changed, errors: errors}
  end

  def result(dir, "compile", _args) do
    # no --force: the Elixir mix.exs requires reports, and fails on, warnings an earlier compile stored
    {out, status, fetched} = mix_fetching(dir, ["compile", "--warnings-as-errors"])

    diagnostics =
      ~r/(warning|error): (.+)\n(?:.*\n)*?\s*└─ ([^\s:]+):(\d+)/
      |> Regex.scan(out)
      |> Enum.map(fn [_, sev, msg, file, line] ->
        %{severity: sev, message: msg, file: file, line: String.to_integer(line)}
      end)

    %{ok: status == 0, exit: status, diagnostics: diagnostics, tail: tail(out), fetched: fetched}
  end

  # A host with no `precommit` alias: the three steps `run check` stands for, each its own mix, so
  # `test` picks its own env. The first that fails is the answer.
  defp check_steps(dir) do
    steps = [["format", "--check-formatted"], ["compile", "--warnings-as-errors"], ["test"]]

    {out, status, fetched} =
      Enum.reduce_while(steps, {"", 0, []}, fn step, {_out, _status, fetched} ->
        {out, status, more} = mix_fetching(dir, step)
        next = {out, status, fetched ++ more}
        if status == 0, do: {:cont, next}, else: {:halt, next}
      end)

    %{
      ok: status == 0,
      exit: status,
      tail: tail(out),
      fetched: fetched,
      ran: "format --check-formatted, compile --warnings-as-errors, test (no precommit alias)"
    }
  end

  # A pull that moved mix.lock leaves deps/ behind it, and every run failed on "dependency not
  # available" until someone ran deps.get. mix's own message is the signal: fetch, run once more,
  # and name what came.
  defp mix_fetching(dir, args) do
    {out, status} = mix(dir, args)

    if status != 0 and out =~ ~s(run "mix deps.get") do
      {got, _status} = mix(dir, ["deps.get"])
      fetched = ~r/\* Getting (\S+)/ |> Regex.scan(got) |> Enum.map(&List.last/1)
      {out, status} = mix(dir, args)
      {out, status, fetched}
    else
      {out, status, []}
    end
  end

  defp formatter_inputs(dir) do
    dot = Path.join(dir, ".formatter.exs")
    inputs = if File.regular?(dot), do: elem(Code.eval_file(dot), 0)[:inputs] || [], else: []

    inputs
    |> List.wrap()
    |> Enum.flat_map(&Path.wildcard(Path.join(dir, &1), match_dot: true))
    |> Enum.uniq()
  end

  # the TARGET project's mix, in its own directory and env — never this project's
  # UNSET, not pinned. `mix test` picks :test itself and `mix precommit` picks per task inside the
  # alias; anything forced here overrides both, which is how elixirc_paths(:test) got dropped and
  # every test/support module read as "not loaded" — first under `run test`, then again under
  # `run check`. nil unsets, so menard's own MIX_ENV cannot leak into the target either, which is
  # what the pin was for.
  defp mix(dir, args), do: Menard.host_mix(dir, args, env: [{"MIX_ENV", nil}])

  defp tail(out), do: out |> String.split("\n") |> Enum.take(-12) |> Enum.join("\n")

  @doc "Parse `mix test` output (+ its exit status) into `%{ok, exit, tests, failed, failures, tail}`."
  def parse_test(out, status) do
    # `--repeat-until-failure N` prints one run after another, and only the LAST run says anything:
    # the one that failed, or the Nth that passed. Its counts, failures and tail are the answer; the
    # seed is how to reproduce it, and the run count is how long it hid.
    runs = out |> String.split(~r/Running ExUnit with seed: /)
    last = List.last(runs)
    {tests, failed} = counts(last)

    %{
      ok: status == 0,
      exit: status,
      tests: tests,
      failed: failed,
      failures: failures(last),
      tail: summary(last),
      runs: length(runs) - 1,
      seed: seed(last)
    }
  end

  defp seed(run) do
    case Integer.parse(run) do
      {seed, _rest} -> seed
      :error -> nil
    end
  end

  @doc """
  Attach each failure's `source`: the test's body as written, from `at`'s file (under `root`)
  starting at its line and ending at the matching `end` (the first line at the test's indent).
  """
  def with_sources(%{failures: failures} = result, root) do
    %{result | failures: Enum.map(failures, &Map.put(&1, :source, source_of(&1[:at], root)))}
  end

  defp source_of(nil, _root), do: nil

  defp source_of(at, root) do
    [file, line] = String.split(at, ":")
    path = Path.expand(file, root)

    with true <- File.exists?(path),
         lines <- File.read!(path) |> String.split("\n"),
         {start, _} <- Integer.parse(line),
         [head | rest] <- Enum.drop(lines, start - 1) do
      indent = String.length(head) - String.length(String.trim_leading(head))

      body =
        Enum.take_while(
          rest,
          &(String.trim(&1) != "end" or
              String.length(&1) - String.length(String.trim_leading(&1)) != indent)
        )

      closer = Enum.at(rest, length(body))
      Enum.join([head | body] ++ List.wrap(closer), "\n")
    else
      _ -> nil
    end
  end

  # ExUnit ≥ 1.20 prints `Result: 5 passed` / `Result: 3/5 passed`; older prints `5 tests, 2 failures`.
  defp counts(out) do
    cond do
      m = Regex.run(~r/Result: (\d+)\/(\d+) passed/, out) ->
        [_, passed, total] = m
        {String.to_integer(total), String.to_integer(total) - String.to_integer(passed)}

      m = Regex.run(~r/Result: (\d+) passed/, out) ->
        [_, passed] = m
        {String.to_integer(passed), 0}

      m = Regex.run(~r/(\d+) tests?, (\d+) failures?/, out) ->
        [_, tests, failed] = m
        {String.to_integer(tests), String.to_integer(failed)}

      true ->
        {nil, nil}
    end
  end

  # Each `N) test NAME (Module)` block up to the next block or the summary.
  defp failures(out) do
    ~r/^\s*\d+\) test (.+?) \((\S+)\)\n(.*?)(?=^\s*\d+\) test |\nFinished in|\z)/ms
    |> Regex.scan(out)
    |> Enum.map(fn [_, name, module, body] ->
      %{
        name: name,
        module: module,
        at: first(~r/^\s*(\S+_test\.exs:\d+)\s*$/m, body),
        code: first(~r/^\s*code:\s+(.+)$/m, body),
        left: first(~r/^\s*left:\s+(.+)$/m, body),
        right: first(~r/^\s*right:\s+(.+)$/m, body),
        error: error_of(body)
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()
    end)
  end

  # The `** (Error) message` line and what follows it up to `code:` or `stacktrace:`: a MatchError's
  # value is on the lines after, and cut at the first line it read "no match of right hand side
  # value:" and nothing else.
  defp error_of(body) do
    case body |> String.split("\n") |> Enum.drop_while(&(not String.starts_with?(String.trim(&1), "** "))) do
      [] ->
        nil

      [first | rest] ->
        more = Enum.take_while(rest, &(not Regex.match?(~r/^\s*(code|left|right|stacktrace|hint):/, &1)))

        [first | more]
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
        |> Enum.join("\n")
        |> String.replace_prefix("** ", "")
    end
  end

  defp first(re, text) do
    case Regex.run(re, text) do
      [_, v] -> String.trim(v)
      _ -> nil
    end
  end

  # From ExUnit's `Finished in` line to the end — the summary lines only.
  defp summary(out) do
    case Regex.run(~r/(Finished in .*)\z/s, out) do
      [_, tail] ->
        tail |> String.trim() |> String.split("\n") |> Enum.map_join("\n", &String.trim/1)

      # no run at all: a compile error in a test file — the errors are what matters, not the
      # last five lines (the stack trace under "cannot compile module")
      _ ->
        case Regex.scan(~r/^\s*error: .*(?:\n(?!\s*error:).*)*?\n\s*└─ .*$/m, out) do
          [] ->
            out |> String.split("\n") |> Enum.take(-5) |> Enum.join("\n")

          errors ->
            Enum.map_join(errors, "\n", fn [e] ->
              e |> String.split("\n") |> Enum.map_join("\n", &String.trim/1)
            end)
        end
    end
  end
end
