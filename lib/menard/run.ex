defmodule Menard.Run do
  @moduledoc """
  The run verbs' parsers: mix's output → `failures` in one shape for every verb (`kind`, `message`,
  `at`; a test failure adds its name, module, source and the assertion's code/left/right), the
  counts, and a tail that is the summary, not the logs a suite prints on its way.
  `mix menard.run` prints what these return, as one JSON line.
  """

  @keep 40
  # what a repo with no mix.exs answers through its mise task of that name
  @tasks ~w(check test compile)

  @type issue :: %{kind: String.t(), message: String.t(), at: String.t()}

  @doc """
  `result/3` under a deadline: `timeout:` in ms for the whole verb, however many mix calls it
  makes. Past it the host's mix is killed and the reply says so; the MCP door passes one under its
  client's timeout, the CLI none.
  """
  @spec result(String.t(), String.t(), [String.t()], keyword()) :: map()
  def result(dir, verb, args, opts) do
    # the run's context, handed to every mix it makes: its deadline, and its one log (the MCP server
    # lives across calls, and each call's output is its own)
    log = log_path(dir, [verb | args])

    run = %{
      dir: dir,
      log: log,
      deadline: if(ms = opts[:timeout], do: System.monotonic_time(:millisecond) + ms)
    }

    reply =
      cond do
        verb in @tasks and not File.regular?(Path.join(dir, "mix.exs")) -> task(run, verb, args)
        verb in ["check", "test"] -> one_at_a_time(run, fn -> verb(run, verb, args) end)
        true -> verb(run, verb, args)
      end

    if File.exists?(run.log), do: Map.put(reply, :log, run.log), else: reply
  end

  @doc """
  A run verb in the mix project at `dir` — `"check"` (its `mix precommit`), `"test"` (args: files,
  file:line), `"format"` (args: files; reports what changed), `"compile"` (warnings as
  diagnostics) — as one map with `ok`, and `log` when it ran mix. Both doors (`mix menard.run`, the
  MCP `run` tool) call this, and `deps` for its compile after an update.
  """
  @spec result(String.t(), String.t(), [String.t()]) :: map()
  def result(dir, verb, args), do: result(dir, verb, args, [])

  @doc """
  Credo's findings on the lines changed in `rels` (paths from `dir`), as strict as the project's
  gate, or none where the project has no credo. `run` is `result/3`, or a test's stand-in.
  """
  @spec credo_changed(String.t(), [String.t()], (String.t(), String.t(), [String.t()] -> map())) :: [map()]
  def credo_changed(dir, rels, run \\ &result/3)
  def credo_changed(_dir, [], _run), do: []

  def credo_changed(dir, rels, run) do
    # as strict as the project's gate: at credo's default a strict-only check (AliasUsage) passed
    # every write, and failed the gate
    strict = if credo_strict?(dir), do: ["--strict"], else: []
    if credo?(dir), do: run.(dir, "credo", ["--changed" | rels] ++ strict)[:failures] || [], else: []
  end

  @doc "Whether `dir`'s project gates with `credo --strict`: what a lint of it must match."
  @spec credo_strict?(String.t()) :: boolean()
  def credo_strict?(dir) do
    case File.read(Path.join(dir, "mix.exs")) do
      {:ok, mix} -> mix =~ "credo --strict"
      _ -> false
    end
  end

  # The project lints with credo when it has it: its lock names it, or its deps hold it
  @doc "Whether the project at `dir` has credo: its lock names it, or its deps hold it."
  @spec credo?(String.t()) :: boolean()
  def credo?(dir) do
    File.dir?(Path.join(dir, "deps/credo")) or
      case File.read(Path.join(dir, "mix.lock")) do
        {:ok, lock} -> lock =~ ~s("credo":)
        _ -> false
      end
  end

  # `--format json` prints the report after whatever compiling said first: the object from a line
  # that opens a brace to the end, however it is laid out
  @doc "The issues in `credo --format json` output, as failures, or `:error` where it holds no report."
  @spec credo_issues(String.t()) :: {:ok, [issue()]} | :error
  def credo_issues(out) do
    ~r/^\{/m
    |> Regex.scan(out, return: :index)
    |> Enum.find_value(:error, fn [{at, _}] ->
      case JSON.decode(binary_part(out, at, byte_size(out) - at)) do
        {:ok, %{"issues" => issues}} -> {:ok, Enum.map(issues, &credo_issue/1)}
        _ -> nil
      end
    end)
  end

  # Only what an edit brought: issues on the lines changed since the last commit, every line of a file
  # git does not track yet. Old debt in the file is not the edit's to answer for.
  # Two git calls for every file at once, not two per file: which are tracked, and one diff.
  @doc "The `issues` on lines changed since the last commit in the repo at `dir`, every one of an untracked file."
  @spec only_changed([issue()], String.t()) :: [issue()]
  def only_changed(issues, dir) do
    files = issues |> Enum.map(&(&1.at |> String.split(":") |> hd())) |> Enum.uniq()
    # paths as the project names them, whatever its place in the repo, and unquoted
    git = &System.cmd("git", ["-C", dir, "-c", "core.quotePath=false" | &1], stderr_to_stdout: true)
    {tracked, _} = git.(["ls-files", "-z", "--" | files])
    tracked = tracked |> String.split(<<0>>, trim: true) |> MapSet.new()
    {diff, _} = git.(["diff", "-U0", "--relative", "HEAD", "--" | files])
    hunks = hunks(diff)
    lines = Map.new(files, &{&1, if(&1 in tracked, do: Map.get(hunks, &1, MapSet.new()), else: :all)})

    Enum.filter(issues, fn %{at: at} ->
      [file, line] = String.split(at, ":")
      lines[file] == :all or String.to_integer(line) in lines[file]
    end)
  end

  @doc """
  What `mix format` takes in `dir`: the inputs, and each `subdirectories:` match's own
  .formatter.exs inputs (Phoenix's priv/*/migrations), relative to it.
  """
  @spec formatter_inputs(String.t()) :: [String.t()]
  def formatter_inputs(dir) do
    case formatter_opts(dir) do
      {:ok, opts} -> inputs(dir, opts)
      {:error, _why} -> []
    end
  end

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
    suites = (held && held[:suites]) || 1
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
  The reply as both doors print it: what a reader looks for, nothing it has to filter out. Green,
  `ok` and the counts; red, the failures and the seed that reproduces them. `ok` and `failures`
  are always there, so every reply is the same shape. A tail stays only where it is the answer: a
  verb with no counts (`check`, `compile`), or a failure nothing parsed.
  """
  @spec lean(map()) :: map()
  def lean(result) do
    ok = result[:ok]

    result
    |> Enum.reject(fn
      {_key, nil} -> true
      {:fetched, []} -> true
      {:tail, ""} -> true
      {:skipped, 0} -> true
      {:excluded, 0} -> true
      {:exit, _} -> ok
      {:log, _} -> ok
      {:seed, _} -> ok
      {:runs, runs} -> runs <= 1
      {:tail, _} -> (ok and result[:tests] != nil) or result[:failures] not in [nil, []]
      _ -> false
    end)
    |> Map.new()
    |> Map.update(:failures, [], &brief/1)
  end

  # The first few failures whole; past them, where and what, the message's first line: the log has all

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

  # Compiler warnings and errors, each the same shape as a test failure: kind, message, at. A
  # dependency's print relative to its own root (`lib/styler/…`, under `==> styler`): no file of
  # the project's, and not its failures (`ok: true` over a non-empty list).
  defp diagnostics(out, dir) do
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

  defp verb(%{dir: dir} = run, "check", args) do
    # Formatting is mechanical, as an editor does it on save: the project formatted first, so the gate
    # fails on nothing a formatter fixes, and the reply names what it formatted
    formatted = for file <- verb(run, "format", []).changed, do: Path.relative_to(file, Path.expand(dir))

    # mix's task trace on (priv/mix_debug.exs): it names each task it runs and each it finished, so
    # the alias step that failed is the one it never finished. Read here, out of every parser's way.
    {out, status, fetched} =
      mix_fetching(run, ["precommit"], require: Application.app_dir(:menard, "priv/mix_debug.exs"))

    {out, failed_step} = untrace(out)

    reply =
      if status != 0 and out =~ ~s(The task "precommit" could not be found),
        do: check_steps(run, args),
        else:
          out
          |> gate(status, fetched, dir)
          |> credo_named(out, run, "--strict" in args)
          |> step_named(failed_step)

    # its failed tests once more, as `run test` does: a flake is not the change's
    reply = check_flakes(run, reply, failed_step)
    if reply.ok, do: warm_stale(run)

    if formatted == [], do: reply, else: Map.put(reply, :formatted, formatted)
  end

  # Failed, a few test failures run once more (`--failed`): one that passes is the suite's flake,
  # named, not the change's
  defp verb(run, "test", args) do
    first = tested(run, args, run.log <> ".exunit")
    if first.ok and full?(args), do: warm_stale(run)

    if rerun?(first, args, run.dir),
      do:
        flakes(first, tested(run, List.delete(args, "--stale") ++ ["--failed"], run.log <> ".rerun.exunit")),
      else: first
  end

  defp verb(%{dir: dir}, "format", files) do
    # no files named: what the project's own `mix format` would take, its formatter inputs. Given
    # none, this formatted nothing and answered ok, while the project's check failed.
    rel = &Path.relative_to(&1, Path.expand(dir))

    {files, broken} =
      case {files, formatter_opts(dir)} do
        {[], {:ok, opts}} -> {inputs(dir, opts), []}
        {[], {:error, why}} -> {[], [%{kind: "format", message: why, at: ".formatter.exs"}]}
        {files, _opts} -> {Enum.map(files, &Path.expand(&1, dir)), []}
      end

    {files, missing} = Enum.split_with(files, &File.regular?/1)
    missing = for file <- missing, do: %{kind: "format", message: "no such file", at: rel.(file)}
    before = Map.new(files, &{&1, File.read!(&1)})

    # menard's own formatter, not the host's bare `mix format`: it works while the host's deps do not
    # resolve or its mix.exs does not parse, and never formats without a plugin the host uses. A file
    # it cannot format (a plugin the host never built) is checked instead: formatted already, the
    # plugins left out, is no failure (the format hook blocked on files as they were at HEAD).
    failed = for {file, {:error, message}} <- Menard.Format.files(files), do: {file, message}
    passing = Menard.Format.formatted_without_plugins(Enum.map(failed, &elem(&1, 0)))

    failures =
      for {file, message} <- failed,
          file not in passing,
          do: %{kind: "format", message: message, at: rel.(file)}

    failures = broken ++ missing ++ failures
    changed = Enum.filter(files, &(File.read!(&1) != before[&1]))
    %{ok: failures == [], changed: changed, failures: failures}
  end

  defp verb(run, "compile", _args) do
    # no --force: the Elixir mix.exs requires reports, and fails on, warnings an earlier compile stored
    {out, status, fetched} = mix_fetching(run, ["compile", "--warnings-as-errors"])

    %{ok: status == 0, exit: status, failures: diagnostics(out, run.dir), tail: tail(out), fetched: fetched}
  end

  defp verb(run, "credo", args) do
    if credo?(run.dir),
      do: credo(run, args),
      else: %{ok: true, failures: [], skipped: "no credo in this project"}
  end

  # A FILE:LINE runs the closest test at or before the line: which one, as a line that has drifted
  # runs another, and a green of counts alone says nothing of it. A describe's line runs them all.
  defp ran(args, %{times: times}) do
    if Enum.any?(args, &(&1 =~ ~r/:\d+$/)) do
      times |> Enum.reverse() |> Enum.take(10) |> Enum.map(&Map.take(&1, [:name, :at]))
    end
  end

  defp ran(_args, _held), do: nil

  # `--slowest N`: mix prints them, and a reply of the counts alone dropped them
  defp slowest(args, %{times: times}) do
    with [_, n | _] <- Enum.drop_while(args, &(&1 != "--slowest")),
         {n, ""} <- Integer.parse(n) do
      times |> Enum.sort_by(& &1.ms, :desc) |> Enum.take(n)
    else
      _ -> nil
    end
  end

  defp slowest(_args, _held), do: nil

  # what the formatter wrote at the suite's end; nil when no suite ran
  defp read_held(path) do
    case File.read(path) do
      {:ok, bin} ->
        File.rm(path)
        # an umbrella's suites, one per app, added up by the formatter (`suites`)
        bin |> :erlang.binary_to_term([:safe]) |> Map.drop([:prior, :app, :out])

      _ ->
        nil
    end
  end

  # A precommit that failed in credo printed its report as text: the same report as data puts each
  # issue in `failures`, at the alias's own strictness. `--strict` asked of an alias that lints at
  # credo's default level runs credo --strict as well: dropped, it passed a gate it was asked to fail.
  defp credo_named(reply, out, run, strict?) do
    alias_strict? = credo_strict?(run.dir)

    cond do
      not credo?(run.dir) ->
        reply

      strict? and not alias_strict? ->
        lint = credo(run, ["--strict"])
        %{reply | ok: reply.ok and lint.ok, failures: reply.failures ++ lint.failures}

      not reply.ok and out =~ "mix credo explain" ->
        %{
          reply
          | failures: reply.failures ++ credo(run, if(alias_strict?, do: ["--strict"], else: [])).failures
        }

      true ->
        reply
    end
  end

  defp credo(run, args) do
    {strict, args} = {"--strict" in args, args -- ["--strict"]}
    {changed, files} = {"--changed" in args, args -- ["--changed"]}
    # the report is read as JSON: a caller's `--format oneline` came after it, won, and nothing parsed
    files = drop_format(files)

    {out, status, fetched} =
      mix_fetching(run, ["credo", "--format", "json"] ++ if(strict, do: ["--strict"], else: []) ++ files)

    case credo_issues(out) do
      {:ok, issues} ->
        issues = if changed, do: only_changed(issues, run.dir), else: issues
        %{ok: issues == [], failures: issues, fetched: fetched}

      :error ->
        %{
          ok: false,
          exit: status,
          failures: [%{kind: "error", message: "credo gave no report"}],
          tail: tail(out),
          fetched: fetched
        }
    end
  end

  # mix's task trace out of the output, and the alias step it started and never finished with what
  # that step printed: `{output, nil | {task, printed}}`
  defp untrace(out) do
    lines = String.split(out, "\n")
    trace = ~r/^(->|<-) (?:Running|Ran) mix (\S.*?)(?: \(inside [\w.]+\)| in \d+ms)?$/

    {open, _depth} =
      lines
      |> Enum.with_index()
      |> Enum.reduce({[], 0}, fn {line, i}, {open, depth} ->
        case Regex.run(trace, line) do
          [_, "->", task] -> {[{task, i, depth} | open], depth + 1}
          [_, "<-", _task] -> {tl(open), depth - 1}
          nil -> {open, depth}
        end
      end)

    untraced = &(&1 |> Enum.reject(fn line -> Regex.match?(trace, line) end) |> Enum.join("\n"))

    # an alias's steps run at depth 0, the tasks they run under them
    step =
      case Enum.find(open, fn {_task, _i, depth} -> depth == 0 end) do
        {task, i, _depth} -> {task, untraced.(Enum.drop(lines, i + 1))}
        nil -> nil
      end

    {untraced.(lines), step}
  end

  # A red precommit whose output no parser read (a `cmd` step, a task menard knows nothing of): the
  # step that failed and the last lines it printed above its stack trace, as its failure
  defp step_named(%{ok: false, failures: []} = reply, {task, printed}) do
    {said, stack} = printed |> String.split("\n") |> Enum.split_while(&(not String.starts_with?(&1, "** (")))

    lines =
      said
      |> Enum.reject(&(String.trim(&1) == ""))
      |> Enum.take(-10)
      |> Kernel.++(Enum.take(stack, 1))

    %{
      reply
      | failures: [
          %{
            kind: "step",
            at: "mix.exs",
            step: task,
            message: Enum.join(["mix #{task} failed:" | lines], "\n")
          }
        ]
    }
  end

  defp step_named(reply, _step), do: reply

  # A host with no `precommit` alias: the steps `run check` stands for, each its own mix, so `test`
  # picks its own env. The first that fails is the answer. Credo too, when the project has it: at
  # its default level, `--strict` when the caller asks.
  # `test` through `tested/3`, as `run test` is: its failures the formatter's, not the prose's.
  defp check_steps(%{dir: dir} = run, args) do
    steps = [["format", "--check-formatted"], ["compile", "--warnings-as-errors"]]

    reply =
      steps
      |> Enum.reduce_while({"", 0, []}, fn step, {_out, _status, fetched} ->
        {out, status, more} = mix_fetching(run, step)
        next = {out, status, fetched ++ more}
        if status == 0, do: {:cont, next}, else: {:halt, next}
      end)
      |> case do
        {_out, 0, fetched} -> Map.update!(tested(run, [], run.log <> ".exunit"), :fetched, &(fetched ++ &1))
        {out, status, fetched} -> gate(out, status, fetched, dir)
      end

    lint =
      if credo?(dir), do: credo(run, Enum.filter(args, &(&1 == "--strict"))), else: %{ok: true, failures: []}

    %{reply | ok: reply.ok and lint.ok, failures: reply.failures ++ lint.failures}
    |> Map.put(
      :ran,
      "format --check-formatted, compile --warnings-as-errors, test#{if credo?(dir), do: ", credo"} (no precommit alias)"
    )
  end

  defp drop_format(["--format", _ | rest]), do: drop_format(rest)
  defp drop_format(["--format=" <> _ | rest]), do: drop_format(rest)
  defp drop_format([arg | rest]), do: [arg | drop_format(rest)]
  defp drop_format([]), do: []

  defp credo_issue(i) do
    %{
      kind: "credo",
      message: "#{i["message"]} (#{i["check"] |> String.split(".") |> List.last()})",
      at: "#{i["filename"]}:#{i["line_no"]}"
    }
  end

  # each file's changed lines, from one diff of them all
  defp hunks(diff) do
    for [_, file, body] <- Regex.scan(~r/^\+\+\+ b\/(.+)\n((?:(?!diff --git ).*\n?)*)/m, diff),
        into: %{},
        do: {file, hunk_lines(body)}
  end

  defp hunk_lines(body) do
    # the count's group always matches, empty when a hunk has none (`@@ -2 +2 @@`): an optional group
    # that did not match drops out of scan's list, and the pattern skipped every one-line hunk
    for [_, start, count] <- Regex.scan(~r/^@@ -\S+ \+(\d+),?(\d*) @@/m, body),
        n = if(count == "", do: 1, else: String.to_integer(count)),
        n > 0,
        line <- String.to_integer(start)..(String.to_integer(start) + n - 1),
        into: MapSet.new(),
        do: line
  end

  # Everything `check` can fail on, one shape: the files not formatted, the compiler's warnings and
  # errors, the failing tests
  defp problems(out, dir), do: unformatted(out, dir) ++ diagnostics(out, dir) ++ failures(out)

  # `check`'s reply, whichever way it ran: `test`'s counts and summary, and every kind of failure
  defp gate(out, status, fetched, dir) do
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

  # ExUnit's failures as data, from a formatter required into the host's VM beside its CLI one: read
  # from the prose, a `left:` that did not fit one line came back as its first line. The prose
  # still says what no formatter sees (a test file that does not compile, mix refusing an option).
  defp tested(run, args, held) do
    formatters = ["--formatter", "Menard.ExUnitFormatter", "--formatter", "ExUnit.CLIFormatter"]

    host = [
      require: Application.app_dir(:menard, "priv/ex_unit_formatter.exs"),
      env: [{"MENARD_EXUNIT_OUT", held}]
    ]

    {out, status, fetched} = mix_fetching(run, ["test" | formatters ++ args], host)

    held = read_held(held)

    out
    |> parse_test(status, held, run.dir)
    |> with_sources(run.dir)
    |> Map.put(:fetched, fetched)
    |> Map.put(:ran, ran(args, held))
    |> Map.put(:slowest, slowest(args, held))
    |> Map.put(:slowest_modules, slowest_modules(args, held))
  end

  # `--slowest-modules N`: the test files that took longest, each its tests' time summed and counted
  defp slowest_modules(args, %{times: times}) do
    with [_, n | _] <- Enum.drop_while(args, &(&1 != "--slowest-modules")),
         {n, ""} <- Integer.parse(n) do
      times
      |> Enum.group_by(&(&1.at |> String.split(":") |> hd()))
      |> Enum.map(fn {file, tests} ->
        %{file: file, ms: tests |> Enum.map(& &1.ms) |> Enum.sum(), tests: length(tests)}
      end)
      |> Enum.sort_by(& &1.ms, :desc)
      |> Enum.take(n)
    else
      _ -> nil
    end
  end

  defp slowest_modules(_args, _held), do: nil

  # A check's failures that pass again are flakes. Its own steps (no precommit alias) all ran, credo
  # after the tests too, so none left is green; an alias stops at the task that failed, and what came
  # after it never ran: red still, and the reply says why
  defp check_flakes(run, reply, failed_step) do
    if rerun?(reply, [], run.dir) do
      again = flakes(reply, tested(run, ["--failed"], run.log <> ".rerun.exunit"))

      cond do
        not Map.has_key?(again, :flaky) or again.flaky == nil -> reply
        reply[:ran] != nil or not again.ok -> again
        true -> after_flakes(run, again, failed_step)
      end
    else
      reply
    end
  end

  # Every failure a flake, under an alias. A failing `mix test` ends as finished and the alias goes
  # on, so the steps after it ran: one that failed is left open in the trace, and is the failure;
  # none open, every step passed. A test task that exits on failure (this repo's test_no_leaks)
  # stops the alias: its steps after it run here, each its own mix.
  defp after_flakes(_run, again, nil),
    do:
      Map.put(
        again,
        :note,
        "every test failure passed when run again (flaky); the precommit steps after the tests ran, and passed"
      )

  defp after_flakes(run, again, {task, _printed} = failed_step) do
    if String.starts_with?(task, "test") do
      steps = alias_steps(run)
      at = Enum.find_index(steps, &(hd(String.split(&1)) == hd(String.split(task))))

      if at == nil or "<fn>" in steps,
        do:
          Map.put(
            %{again | ok: false},
            :note,
            "every test failure passed when run again (flaky), and the precommit steps after the tests did not run: run check again"
          ),
        else: run_rest(run, again, Enum.drop(steps, at + 1))
    else
      step_named(
        Map.put(
          %{again | ok: false, failures: []},
          :note,
          "every test failure passed when run again (flaky); mix #{task} failed"
        ),
        failed_step
      )
    end
  end

  defp run_rest(run, again, rest) do
    green =
      Map.put(
        %{again | ok: true},
        :note,
        "every test failure passed when run again (flaky); the precommit steps after the tests ran green: #{Enum.join(rest, ", ")}"
      )

    Enum.reduce_while(rest, green, fn step, acc ->
      case mix(run, OptionParser.split(step), []) do
        {_out, 0} ->
          {:cont, acc}

        {out, _status} ->
          red =
            Map.put(
              %{again | ok: false, failures: []},
              :note,
              "every test failure passed when run again (flaky); then mix #{step} failed"
            )

          {:halt, step_named(red, {step, out})}
      end
    end)
  end

  # the precommit alias's steps, as strings; a step that is a function is `<fn>`
  defp alias_steps(run) do
    code =
      ~s|for s <- List.wrap(Mix.Project.config()[:aliases][:precommit]), do: IO.puts(if(is_binary(s), do: s, else: "<fn>"))|

    case mix(run, ["run", "--no-start", "--no-compile", "--no-deps-check", "-e", code], []) do
      {out, 0} ->
        out |> String.split("\n", trim: true) |> Enum.reject(&(&1 =~ ~r/^(Compiling|Generated|==>|warning:)/))

      _ ->
        []
    end
  end

  # `--stale` is the tests a change touches since the last `--stale` run, and nothing ran one: cold,
  # it was every test (1,084 here). A green full run warms it, running nothing (every test excluded),
  # so the next `--stale` (`then test` where no test file mirrors the change) is the change's tests
  defp warm_stale(run), do: mix(run, ["test", "--stale", "--exclude", "test"], [])

  # the whole suite: no file named, nor a selection of its own
  defp full?(args),
    do:
      Enum.all?(args, &String.starts_with?(&1, "-")) and
        not Enum.any?(args, &(&1 in ["--stale", "--failed", "--only"]))

  # red with test failures alone, few enough to run again, and not a run that is itself a rerun
  # and one at least in a test file unchanged since HEAD: a red of the agent's own new test is the
  # red it wrote, no flake to look for
  defp rerun?(%{ok: false, failures: [_ | _] = failures}, args, dir) do
    changed = changed_tests(dir)

    length(failures) <= 10 and Enum.all?(failures, &(&1[:kind] == "test" and &1[:at] != nil)) and
      Enum.any?(failures, &(not changed?(&1.at, changed))) and
      not Enum.any?(args, &(&1 in ["--failed", "--repeat-until-failure"]))
  end

  defp rerun?(_first, _args, _dir), do: false

  # the files changed since HEAD, tracked and untracked, from `dir`; :unknown outside git
  defp changed_tests(dir) do
    git = &System.cmd("git", ["-C", dir | &1], stderr_to_stdout: true)

    with {diff, 0} <- git.(["diff", "--name-only", "--relative", "HEAD"]),
         {new, 0} <- git.(["ls-files", "--others", "--exclude-standard"]) do
      MapSet.new(String.split(diff <> "\n" <> new, "\n", trim: true))
    else
      _ -> :unknown
    end
  end

  defp changed?(_at, :unknown), do: false
  defp changed?(at, changed) when is_binary(at), do: MapSet.member?(changed, at |> String.split(":") |> hd())
  defp changed?(_at, _changed), do: false

  # a failure that passed again is a flake; one that failed again stands. A rerun that ran nothing
  # (it did not compile, mix refused) says nothing, and the first run is the answer
  defp flakes(first, %{tests: tests} = again) when is_integer(tests) and tests > 0 do
    again_at = MapSet.new(again.failures, & &1[:at])
    {stood, flaked} = Enum.split_with(first.failures, &(&1.at in again_at))

    %{
      first
      | ok: stood == [],
        failed: length(stood),
        failures: stood,
        exit: if(stood == [], do: 0, else: first.exit)
    }
    |> Map.put(:flaky, if(flaked != [], do: Enum.map(flaked, &Map.take(&1, [:name, :at]))))
  end

  defp flakes(first, _again), do: first

  # a run stopped at its deadline: the tests it was still running are failures too, by name
  defp running(held) do
    for test <- held[:running] || [],
        do:
          Map.merge(test, %{
            kind: "timeout",
            message: "still running when the run was stopped at its deadline"
          })
  end

  # One check or test run at a time in a project: two in one checkout raced in its _build and its
  # tmp/. The next waits for the one running, up to its own deadline, and says how long; a lock
  # whose holder is dead is no wait.
  defp one_at_a_time(%{dir: dir} = run, check) do
    lock = Path.join(dir, "_build/.menard-check.lock")
    File.mkdir_p!(Path.dirname(lock))

    case take(lock, run.deadline, 0) do
      {:taken, waited} ->
        try do
          reply = check.()
          if waited > 0, do: Map.put(reply, :waited, waited), else: reply
        after
          :global.unregister_name({__MODULE__, :check, lock})
          File.rm(lock)
        end

      # the lock is its holder's: nothing is run beside it, and it is not this run's to remove
      {:busy, waited} ->
        message =
          "another run in this project (pid #{lock |> File.read() |> elem(1) |> to_string() |> String.trim()}) " <>
            "was still going after the #{waited}s this one could wait: nothing ran. Wait for it, or " <>
            "give this run longer"

        %{ok: false, exit: 124, waited: waited, failures: [%{kind: "error", message: message}]}
    end
  end

  defp take(lock, deadline, waited) do
    case File.open(lock, [:write, :exclusive]) do
      {:ok, io} ->
        # the holder in this VM, by name: a check the MCP server killed at its deadline never ran
        # its `after`, and its lock, the server's own (live) OS pid, would have stood for good.
        # Named before the pid is written, so no waiter of this VM reads the pid with no name
        :global.register_name({__MODULE__, :check, lock}, self())
        IO.write(io, System.pid())
        File.close(io)
        {:taken, waited}

      {:error, :eexist} ->
        cond do
          not held?(lock) ->
            unstale(lock)
            take(lock, deadline, waited)

          deadline && System.monotonic_time(:millisecond) > deadline ->
            {:busy, waited}

          true ->
            Process.sleep(1_000)
            take(lock, deadline, waited + 1)
        end
    end
  end

  # A dead holder's lock out of the way. Two waiters that both found it dead each removed "the"
  # lock, and the second's would be the first's new one: moved aside by a rename only one of them
  # wins, and given back when what it moved is a live holder's after all.
  defp unstale(lock) do
    aside = "#{lock}.#{System.pid()}-#{System.unique_integer([:positive])}"

    with :ok <- File.rename(lock, aside),
         true <- held?(lock, aside),
         do: File.ln(aside, lock)

    File.rm(aside)
    true
  end

  # by another VM that is alive, or by a check of this one that still runs (`file`: the lock's
  # contents, moved aside)
  defp held?(lock, file \\ nil) do
    case File.read(file || lock) do
      # made and not yet written: its holder is between the two
      {:ok, ""} ->
        case File.stat(file || lock, time: :posix) do
          {:ok, %{mtime: at}} -> System.os_time(:second) - at < 5
          _ -> false
        end

      {:ok, pid} ->
        if String.trim(pid) == System.pid(),
          do: :global.whereis_name({__MODULE__, :check, lock}) != :undefined,
          else: match?({_, 0}, System.cmd("kill", ["-0", String.trim(pid)], stderr_to_stdout: true))

      _ ->
        false
    end
  end

  # A pull that moved mix.lock leaves deps/ behind it, and every run failed on "dependency not
  # available" until someone ran deps.get. mix's own message is the signal: fetch, run once more,
  # and name what came.
  defp mix_fetching(run, args, host \\ []) do
    {out, status} = mix(run, args, host)

    if status != 0 and out =~ ~s(run "mix deps.get") do
      {got, _status} = mix(run, ["deps.get"])
      fetched = ~r/\* Getting (\S+)/ |> Regex.scan(got) |> Enum.map(&List.last/1)
      {out, status} = mix(run, args, host)
      {out, status, fetched}
    else
      {out, status, []}
    end
  end

  # the TARGET project's mix, in its own directory and env — never this project's
  # UNSET, not pinned. `mix test` picks :test itself and `mix precommit` picks per task inside the
  # alias; anything forced here overrides both, which is how elixirc_paths(:test) got dropped and
  # every test/support module read as "not loaded" — first under `run test`, then again under
  # `run check`. nil unsets, so menard's own MIX_ENV cannot leak into the target either, which is
  # what the pin was for.
  defp mix(run, args, host \\ []) do
    left = if at = run.deadline, do: max(at - System.monotonic_time(:millisecond), 1_000)
    {env, host} = Keyword.pop(host, :env, [])
    {out, status} = Menard.host_mix(run.dir, args, [env: [{"MIX_ENV", nil} | env], timeout: left] ++ host)
    File.write!(run.log, "$ mix #{Enum.join(args, " ")}\n#{out}\n", [:append])
    # uncoloured, once, for every parser: `config :elixir, :ansi_enabled, true` colours ExUnit's
    # report even into this pipe, and `mix format --check-formatted` colours its list anyway
    {String.replace(out, ~r/\e\[[0-9;]*m/, ""), status}
  end

  # A repo with no mix.exs, whose gate is its own: nothing to parse, so what it printed is the answer
  defp task(%{dir: dir} = run, verb, args) do
    none = "no mix.exs in #{dir}, and no mise task #{verb} to run instead"

    with mise when is_binary(mise) <- System.find_executable("mise"),
         {_info, 0} <- System.cmd(mise, ["tasks", "info", verb, "--json"], cd: dir, stderr_to_stdout: true) do
      left = if at = run.deadline, do: max(at - System.monotonic_time(:millisecond), 1_000)

      {out, status} =
        Menard.host_cmd(dir, [mise, "run", verb | args], timeout: left, label: "mise run #{verb}")

      File.write!(run.log, "$ mise run #{Enum.join([verb | args], " ")}\n#{out}\n", [:append])
      out = String.replace(out, ~r/\e\[[0-9;]*m/, "")
      %{ok: status == 0, exit: status, failures: [], ran: "mise run #{verb}", tail: tail(out)}
    else
      nil ->
        %{ok: false, failures: [], tail: none}

      {out, _status} ->
        %{ok: false, failures: [], tail: if(out =~ "Task not found", do: none, else: tail(out))}
    end
  end

  # Every mix a verb runs, its whole output kept in one log, the last #{@keep} per project: a red
  # reply names it, so what the failures leave out is a grep away, not a second run (Tlön's cap.sh
  # rule: run once, read the log; 40% of the operator's test runs were run again to see more)
  defp log_path(dir, words) do
    dir = Path.expand(dir)
    # the slug is cut short, and two projects under one long path shared it, each's rotation
    # deleting the other's logs
    hash = :md5 |> :crypto.hash(dir) |> Base.encode16(case: :lower) |> binary_part(0, 8)
    logs = Path.join(Menard.log_dir(), slug(dir) <> "-" <> hash)
    File.mkdir_p!(logs)
    # room for this run's: all but one of the last @keep stay
    logs |> File.ls!() |> Enum.sort(:desc) |> Enum.drop(@keep - 1) |> Enum.each(&File.rm(Path.join(logs, &1)))
    stamp = Calendar.strftime(DateTime.utc_now(), "%Y%m%dT%H%M%S%f")
    Path.join(logs, "#{stamp}-#{slug(Enum.join(words, " "))}.log")
  end

  defp slug(text),
    do: text |> String.replace(~r/[^A-Za-z0-9]+/, "-") |> String.trim("-") |> String.slice(0, 60)

  defp tail(out), do: out |> String.split("\n") |> Enum.take(-12) |> Enum.join("\n")

  # mix refusing to run at all (an unknown option, a task it cannot find): its `** (Mix)` line and
  # what follows up to the first blank line, before the usage it lists after
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

  defp brief(failures) do
    {whole, rest} = Enum.split(failures, 3)

    whole ++
      Enum.map(rest, fn f ->
        f
        |> Map.take([:kind, :name, :at, :message])
        |> Map.update(:message, nil, &(&1 |> String.split("\n", parts: 2) |> hd()))
        |> Map.reject(fn {_k, v} -> v == nil end)
      end)
  end

  # the project's .formatter.exs, or why it could not be read: it is code, and may raise
  defp formatter_opts(dir) do
    dot = Path.join(dir, ".formatter.exs")

    try do
      case File.read(dot) do
        {:ok, source} -> evaluated(dot, dir, source =~ ~r/\b(Path|File|System)\./)
        {:error, _} -> {:ok, []}
      end
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  # A .formatter.exs that asks the file system (`Path.wildcard("lib/*.ex")`) means its own
  # directory, and this VM's is menard's, or the session's first: evaluated in a VM of its own,
  # there. One that is a literal, as nearly all are, costs no VM.
  defp evaluated(dot, _dir, false), do: {:ok, elem(Code.eval_file(dot), 0)}

  defp evaluated(dot, dir, true) do
    code = "IO.write(Base.encode64(:erlang.term_to_binary(elem(Code.eval_file(hd(System.argv())), 0))))"

    case Menard.host_cmd(dir, ["elixir", "-e", code, dot], label: "elixir .formatter.exs", timeout: 30_000) do
      {out, 0} ->
        # not `:safe`: a plugin's module is an atom this VM has not met, and the file is the
        # project's own, evaluated here when it is a literal
        {:ok, out |> String.split("\n") |> List.last() |> Base.decode64!() |> :erlang.binary_to_term()}

      {out, _status} ->
        {:error, out |> String.trim() |> String.split("\n") |> hd()}
    end
  end

  defp inputs(dir, opts) do
    # the glob under dir, not dir joined into it: a dir with glob characters in its name (`p[x]`)
    # matched nothing
    glob = fn pattern ->
      for path <- :filelib.wildcard(to_charlist(pattern), to_charlist(dir)),
          do: Path.join(dir, to_string(path))
    end

    subdirs = for sub <- List.wrap(opts[:subdirectories]), path <- glob.(sub), File.dir?(path), do: path

    (Enum.flat_map(List.wrap(opts[:inputs]), glob) ++ Enum.flat_map(subdirs, &formatter_inputs/1))
    |> Enum.uniq()
  end
end
