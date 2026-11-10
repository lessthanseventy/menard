defmodule Menard.Run.Output do
  @moduledoc "What mix printed, read: a test run's counts and failures, the compiler's diagnostics, the files not formatted, and the tail worth showing."

  @doc """
  Parse `mix test` output (+ its exit status) into `%{ok, exit, tests, failed, skipped, excluded,
  failures, tail}`. A run that excluded every test it had is not `ok`, whatever mix's exit.
  `held`, what priv/ex_unit_formatter.exs wrote, gives the counts and the test failures when the
  run had it; output menard does not run itself (a precommit alias) is read from its prose.
  """
  @spec parse_test(String.t(), non_neg_integer(), map() | nil, String.t() | nil) :: map()
  def parse_test(out, status, held \\ nil, dir \\ nil) do
    # `--repeat-until-failure N` prints one run after another, and only the LAST run says anything:
    # the one that failed, or the Nth that passed. Its counts, failures and tail are the answer; the
    # seed is how to reproduce it, and the run count is how long it hid.
    runs = out |> String.split(~r/Running ExUnit with seed: /)
    last = List.last(runs)
    # the formatter's counts and failures when it wrote them, else what the prose says
    {tests, failed, skipped, excluded, excluded_by, failures} = read_run(held, last)
    # the compile before the first run: its warnings, which a green run went on to hide, or a test
    # file's errors, which 1.19 on prints after the seed line, in the first run
    # an umbrella's apps each print a run, and each may hold a test file's errors
    suites = suites(held)
    compile = runs |> Enum.take(max(2, suites + 1)) |> Enum.join() |> diagnostics(dir)
    failures = failures ++ compile
    # every test filtered out is no green, whatever mix's exit: `ok, tests: 0` read as "it passes"
    # (up3-oban 03: a new test under a tag the test_helper excludes, and ~30 calls to find out why)
    none_ran? = tests == 0 and (excluded || 0) > 0
    failures = if none_ran? and failures == [], do: [none_ran(excluded, excluded_by)], else: failures

    %{
      ok: status == 0 and not none_ran?,
      excluded: excluded,
      exit: status,
      tests: tests,
      failed: failed,
      skipped: skipped,
      failures: if(failures == [] and status != 0, do: refusal(out), else: failures),
      tail: summary(last),
      runs: length(runs) - suites,
      seed: seed(last)
    }
  end

  @doc """
  Attach each failure's `source`: the test's body as written, from `at`'s file (under `root`)
  starting at its line and ending at the matching `end` (the first line at the test's indent).
  """
  @spec with_sources(%{required(:failures) => [map()], optional(atom()) => term()}, String.t()) :: map()
  def with_sources(%{failures: failures} = result, root) do
    # `at` relative to the project, however mix printed it: under a precommit alias ExUnit prints
    # absolute paths, and the same failure must not look different by which verb found it
    prefix = Path.expand(root) <> "/"
    # a test file changed since HEAD is the agent's own, its test written a call ago: its body said
    # back is noise in a red reply
    changed = changed_tests(root)

    sourced = fn f ->
      f = if is_binary(f[:at]), do: %{f | at: String.replace_prefix(f.at, prefix, "")}, else: f

      if f[:kind] == "test" and not changed?(f[:at], changed),
        do: Map.put(f, :source, source_of(f[:at], root)),
        else: f
    end

    %{result | failures: Enum.map(failures, sourced)}
  end

  @doc """
  Compiler warnings and errors, each the same shape as a test failure: kind, message, at. A
  dependency's print relative to its own root (`lib/styler/…`, under `==> styler`): no file of
  the project's, and not its failures (`ok: true` over a non-empty list).
  """
  @spec diagnostics(String.t(), String.t() | nil) :: [map()]
  def diagnostics(out, dir) do
    # its `└─` is the first below it: one with none (a deprecation mix prints bare) is not given
    # the next diagnostic's place. In an umbrella the path may follow `(app 0.1.0) `
    ~r/^([ \t]*)(warning|error): (.+\n(?:(?!\s*(?:warning|error): ).*\n)*?)\s*└─ (?:\([^)]*\) )?([^\s:]+):(\d+)/m
    |> Regex.scan(out)
    |> Enum.flat_map(fn [_, indent, kind, block, file, line] ->
      case placed(file, dir) do
        nil -> []
        file -> [%{kind: kind, message: said(block, indent), at: "#{file}:#{line}"}]
      end
    end)
    |> Kernel.++(raised(out))
  end

  @doc "`check`'s reply, whichever way it ran: `test`'s counts and summary, and every kind of failure."
  @spec parse_check(String.t(), non_neg_integer(), [String.t()], String.t()) :: map()
  def parse_check(out, status, fetched, dir) do
    {tests, failed, skipped} = counts(out)

    with_sources(
      %{
        ok: status == 0,
        exit: status,
        tests: tests,
        failed: failed,
        skipped: skipped,
        failures: problems(out, dir),
        tail: summary(out),
        fetched: fetched
      },
      dir
    )
  end

  @doc "The last lines of `out`: what a verb with nothing parsed has to show."
  @spec tail(String.t()) :: String.t()
  def tail(out), do: out |> String.split("\n") |> Enum.take(-12) |> Enum.join("\n")

  @doc "The files changed since HEAD, tracked and untracked, from `dir`; `:unknown` outside git."
  @spec changed_tests(String.t()) :: MapSet.t(String.t()) | :unknown
  def changed_tests(dir) do
    git = &System.cmd("git", ["-C", dir | &1], stderr_to_stdout: true)

    with {diff, 0} <- git.(["diff", "--name-only", "--relative", "HEAD"]),
         {new, 0} <- git.(["ls-files", "--others", "--exclude-standard"]) do
      MapSet.new(String.split(diff <> "\n" <> new, "\n", trim: true))
    else
      _ -> :unknown
    end
  end

  @doc "Whether the file of `at` (`FILE:LINE`) is among `changed`, what `changed_tests/1` answered."
  @spec changed?(String.t() | nil, MapSet.t(String.t()) | :unknown) :: boolean()
  def changed?(_at, :unknown), do: false
  def changed?(at, changed) when is_binary(at), do: MapSet.member?(changed, at |> String.split(":") |> hd())
  def changed?(_at, _changed), do: false

  @doc """
  What the formatter wrote at the suite's end, the file removed; nil when no suite ran. Read here,
  in the module that names its keys: `:safe` takes only atoms a loaded module has.
  """
  @spec read_held(String.t()) :: map() | nil
  def read_held(path) do
    case File.read(path) do
      {:ok, bin} ->
        File.rm(path)
        # an umbrella's suites, one per app, added up by the formatter (`suites`)
        bin |> :erlang.binary_to_term([:safe]) |> Map.drop([:prior, :app, :out])

      _ ->
        nil
    end
  end

  # mix refusing to run at all (an unknown option, a task it cannot find): its `** (Mix)` line and
  # what follows up to the first blank line, before the usage it lists after
  defp suites(%{suites: suites}), do: suites
  defp suites(_held), do: 1

  defp refusal(out) do
    case Regex.run(~r/^menard: (.+ did not finish in \d+s, and was stopped)$/m, out) do
      [_, stopped] -> [%{kind: "timeout", message: stopped}]
      nil -> refused(out)
    end
  end

  defp refused(out) do
    case out |> String.split("\n") |> Enum.drop_while(&(not String.starts_with?(&1, "** ("))) do
      [] ->
        []

      lines ->
        message =
          lines
          |> Enum.take_while(&(String.trim(&1) != ""))
          |> Enum.join("\n")
          |> String.replace_prefix("** ", "")

        [%{kind: "error", message: message}]
    end
  end

  defp seed(run) do
    case Integer.parse(run) do
      {seed, _rest} -> seed
      :error -> nil
    end
  end

  defp source_of(nil, _root), do: nil

  defp source_of(at, root) do
    [file, line] = String.split(at, ":")
    path = Path.expand(file, root)

    with true <- File.exists?(path),
         lines <- File.read!(path) |> String.split("\n"),
         {start, _} <- Integer.parse(line),
         [head | rest] <- Enum.drop(lines, start - 1),
         # a line that opens no block (`doctest Mod`, a one-line test) is the whole source: read
         # down to the next `end` at its indent would be the rest of the module
         true <- String.ends_with?(String.trim_trailing(head), " do") || head do
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
      head when is_binary(head) -> head
      _ -> nil
    end
  end

  # ExUnit ≥ 1.20 prints `Result: 5 passed` / `Result: 3/5 passed`; older prints `5 tests, 2 failures`.
  defp counts(out) do
    cond do
      m = Regex.run(~r/Result: (\d+)\/(\d+) passed.*/, out) ->
        [line, passed, total] = m
        {String.to_integer(total), String.to_integer(total) - String.to_integer(passed), skipped(line)}

      m = Regex.run(~r/Result: (\d+) passed.*/, out) ->
        [line, passed] = m
        {String.to_integer(passed), 0, skipped(line)}

      # `1 doctest, 1 property, 2 tests, 3 failures, 1 invalid`: every kind of test counts, and a test
      # a failed setup_all invalidated did not pass. `N tests` counts the skipped too: out, as 1.20
      # and the formatter leave them.
      line =
          ~r/^\d+ [a-z]+(?:, \d+ [a-z]+)*/m
          |> Regex.scan(out)
          |> List.flatten()
          |> Enum.filter(&(&1 =~ "failure"))
          |> List.last() ->
        counted = for [_, n, word] <- Regex.scan(~r/(\d+) ([a-z]+)/, line), do: {word, String.to_integer(n)}
        failed = for {word, n} <- counted, word in ~w(failure failures invalid), do: n
        tests = for {word, n} <- counted, word not in ~w(failure failures invalid excluded skipped), do: n
        {Enum.sum(tests) - skipped(line), Enum.sum(failed), skipped(line)}

      true ->
        {nil, nil, nil}
    end
  end

  # a run's counts and failures: as the formatter held them, else as the prose says
  defp read_run(nil, out) do
    {tests, failed, skipped} = counts(out)
    {tests, failed, skipped, excluded(out), nil, failures(out)}
  end

  # `excluded` is the project's filters' (its test_helper); the run's own (a file:line, --only, as
  # the `test` filter) left out what was not asked for, and is no news. All of them, when nothing ran.
  defp read_run(held, _out) do
    by = held[:excluded_by] || %{}
    project = by |> Map.delete("test") |> Map.values() |> Enum.sum()
    excluded = if held.tests == 0, do: held[:excluded], else: project
    {held.tests, held.failed, held[:skipped], excluded, Map.keys(by), held.failures ++ running(held)}
  end

  # `(N excluded)` in a summary line: the tests the project's filters (or the run's --only) left out
  defp excluded(out) do
    case Regex.run(~r/^\d+ [a-z]+.*\((\d+) excluded\)/m, out) do
      [_, n] -> String.to_integer(n)
      nil -> nil
    end
  end

  defp none_ran(n, tags) do
    include = (tags || []) |> List.delete("test") |> Enum.map_join(" ", &"--include #{&1}")

    how =
      cond do
        tags == nil -> "the project's filters (its test_helper's exclude); `--include TAG` runs them"
        include == "" -> "the run's own filter (--only, a file:line)"
        true -> "the project's filters; `#{include}` runs them"
      end

    %{kind: "excluded", message: "no test ran: #{n} excluded by #{how}"}
  end

  # `N skipped` in a summary line. An excluded test is the project's own filter and no count, as in
  # the formatter: a skip is a test that did not run when it was asked to.
  defp skipped(line) do
    case Regex.run(~r/(\d+) skipped/, line) do
      [_, n] -> String.to_integer(n)
      nil -> 0
    end
  end

  # Each `N) TYPE NAME (Module)` block (a test, a doctest, a property) up to the next block or the
  # summary, and each `N) Module: failure on setup_all callback` block.
  defp failures(out) do
    ~r/^\s*\d+\) (?:\w+ (.+?) \(([\w.]+)\)|([\w.]+): failure on setup_all callback[^\n]*)\n(.*?)(?=^\s*\d+\) |\nFinished in|\z)/ms
    |> Regex.scan(out)
    |> Enum.map(fn
      [_, "", "", module, body] ->
        %{
          kind: "test",
          name: "setup_all",
          module: module,
          message:
            "setup_all failed, so none of the module's tests ran: " <> (error_of(body) || headline(body)),
          at: first(~r/^\s*(\S+_test\.exs:\d+):/m, body)
        }

      [_, name, module, _, body] ->
        %{
          kind: "test",
          message: error_of(body) || headline(body),
          at: first(~r/^\s*(\S+_test\.exs:\d+)\s*$/m, body),
          name: name,
          module: module,
          code: first(~r/^\s*code:\s+(.+)$/m, body),
          left: first(~r/^\s*left:\s+(.+)$/m, body),
          right: first(~r/^\s*right:\s+(.+)$/m, body)
        }
    end)
    |> Enum.map(fn failure -> failure |> Enum.reject(fn {_k, v} -> is_nil(v) end) |> Map.new() end)
  end

  # An assertion's reason: ExUnit's lines under the location up to its code, "Assertion with ==
  # failed", or a property's generated values with the assertion under them
  defp headline(body) do
    body
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.drop_while(&(&1 == "" or &1 =~ ~r/^\S+_test\.exs:\d+$/))
    |> Enum.take_while(&(not Regex.match?(~r/^(code|left|right|stacktrace|doctest):/, &1)))
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  # a diagnostic's message: its lines down to the gutter (`│`) that frames the code, at their own
  # indent. A type warning's first line is "comparison between distinct types found:" and no more
  defp said(block, indent) do
    block
    |> String.split("\n")
    |> Enum.take_while(&(not String.starts_with?(String.trim_leading(&1), "│")))
    |> Enum.map_join("\n", &String.replace_prefix(&1, indent, ""))
    |> String.trim_trailing()
  end

  # the file as the project names it, or nil for one that is not the project's. An umbrella's app
  # prints its paths from its own root
  defp placed(file, nil), do: file

  defp placed(file, dir) do
    if File.exists?(Path.expand(file, dir)) do
      file
    else
      case Path.wildcard(Path.join([dir, "apps", "*", file])) do
        [one] -> Path.relative_to(one, dir)
        _ -> nil
      end
    end
  end

  # A compile error raised as an exception (`cannot set attribute @doc inside function/macro`) comes
  # as `== Compilation error in file F ==` and `** (Error) message` over a stack: no `error:` line
  # for the pattern above, so it was no failure at all. `at` is the first frame in the project. The
  # CompileError that says "errors have been logged" only sums up `error:` lines already parsed.
  defp raised(out) do
    for [_, file, error, message, stack] <-
          Regex.scan(
            ~r/== Compilation error in file (\S+) ==\n\*\* \(([\w.]+)\) (.+)\n((?:[ \t]+.*\n?)*)/,
            out
          ),
        not String.contains?(message, "errors have been logged") do
      at =
        case Regex.run(~r/^\s+((?:lib|test|config)\/\S+?\.exs?):(\d+):/m, stack) do
          [_, path, line] -> "#{path}:#{line}"
          nil -> file
        end

      %{kind: "error", message: "(#{error}) #{message}", at: at}
    end
  end

  # `mix format --check-formatted`'s list of files, each with its diff after
  defp unformatted(out, dir) do
    case String.split(out, "The following files are not formatted:", parts: 2) do
      [_, rest] ->
        root = Path.expand(dir) <> "/"

        for line <- String.split(rest, "\n"),
            path = String.trim(line),
            path =~ ~r/\.(ex|exs|heex)$/,
            do: %{kind: "format", message: "not formatted", at: String.replace_prefix(path, root, "")}

      _ ->
        []
    end
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
        compile_errors(out)
    end
  end

  defp compile_errors(out) do
    case Regex.scan(~r/^\s*error: .*(?:\n(?!\s*error:).*)*?\n\s*└─ .*$/m, out) do
      [] ->
        # the last lines that say anything: a run stopped at its deadline ends in blank lines and the
        # VM's shutdown notice, and what it was doing is just above them
        out
        |> String.split("\n")
        |> Enum.reject(&(String.trim(&1) == ""))
        |> Enum.take(-5)
        |> Enum.join("\n")

      errors ->
        Enum.map_join(errors, "\n", fn [e] ->
          e |> String.split("\n") |> Enum.map_join("\n", &String.trim/1)
        end)
    end
  end

  # Everything `check` can fail on, one shape: the files not formatted, the compiler's warnings and
  # errors, the failing tests
  defp problems(out, dir), do: unformatted(out, dir) ++ diagnostics(out, dir) ++ failures(out)

  # a run stopped at its deadline: the tests it was still running are failures too, by name
  defp running(held) do
    for test <- held[:running] || [],
        do:
          Map.merge(test, %{
            kind: "timeout",
            message: "still running when the run was stopped at its deadline"
          })
  end
end
