defmodule Menard.Run do
  @moduledoc """
  The run verbs' parsers: mix's output → `failures` in one shape for every verb (`kind`, `message`,
  `at`; a test failure adds its name, module, source and the assertion's code/left/right), the
  counts, and a tail that is the summary, not the logs a suite prints on its way.
  `mix menard.run` prints what these return, as one JSON line.
  """

  @keep 40

  @doc """
  `result/3` under a deadline: `timeout:` in ms for the whole verb, however many mix calls it
  makes. Past it the host's mix is killed and the reply says so; the MCP door passes one under its
  client's timeout, the CLI none.
  """
  def result(dir, verb, args, opts) do
    # the run's context, handed to every mix it makes: its deadline, and its one log (the MCP server
    # lives across calls, and each call's output is its own)
    log = log_path(dir, [verb | args])

    run = %{
      dir: dir,
      log: log,
      deadline: if(ms = opts[:timeout], do: System.monotonic_time(:millisecond) + ms)
    }

    reply = verb(run, verb, args)
    if File.exists?(run.log), do: Map.put(reply, :log, run.log), else: reply
  end

  @doc """
  A run verb in the mix project at `dir` — `"check"` (its `mix precommit`), `"test"` (args: files,
  file:line), `"format"` (args: files; reports what changed), `"compile"` (warnings as
  diagnostics) — as one map with `ok`, and `log` when it ran mix. Both doors (`mix menard.run`, the
  MCP `run` tool) call this, and `deps` for its compile after an update.
  """
  def result(dir, verb, args), do: result(dir, verb, args, [])

  defp verb(%{dir: dir} = run, "check", args) do
    # the files as checked, taken before the gate runs: one written meanwhile is not what went green
    tree = tree(dir)
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

    if reply.ok and tree, do: File.write(green_stamp(dir), tree)
    reply
  end

  defp verb(run, "test", args) do
    # ExUnit's failures as data, from a formatter required into the host's VM beside its CLI one: read
    # from the prose, a `left:` that did not fit one line came back as its first line. The prose
    # still says what no formatter sees (a test file that does not compile, mix refusing an option).
    held = run.log <> ".exunit"
    formatters = ["--formatter", "Menard.ExUnitFormatter", "--formatter", "ExUnit.CLIFormatter"]

    host = [
      require: Application.app_dir(:menard, "priv/ex_unit_formatter.exs"),
      env: [{"MENARD_EXUNIT_OUT", held}]
    ]

    {out, status, fetched} = mix_fetching(run, ["test" | formatters ++ args], host)

    out
    |> parse_test(status, read_held(held))
    |> with_sources(run.dir)
    |> Map.put(:fetched, fetched)
  end

  defp verb(%{dir: dir}, "format", files) do
    # no files named: what the project's own `mix format` would take, its formatter inputs. Given
    # none, this formatted nothing and answered ok, while the project's check failed.
    files = if files == [], do: formatter_inputs(dir), else: Enum.map(files, &Path.expand(&1, dir))
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
          do: %{kind: "format", message: message, at: Path.relative_to(file, Path.expand(dir))}

    changed = Enum.filter(files, &(File.read!(&1) != before[&1]))
    %{ok: failures == [], changed: changed, failures: failures}
  end

  defp verb(run, "compile", _args) do
    # no --force: the Elixir mix.exs requires reports, and fails on, warnings an earlier compile stored
    {out, status, fetched} = mix_fetching(run, ["compile", "--warnings-as-errors"])

    %{ok: status == 0, exit: status, failures: diagnostics(out), tail: tail(out), fetched: fetched}
  end

  defp verb(run, "credo", args) do
    if credo?(run.dir),
      do: credo(run, args),
      else: %{ok: true, failures: [], skipped: "no credo in this project"}
  end

  # what the formatter wrote at the suite's end; nil when no suite ran
  defp read_held(path) do
    case File.read(path) do
      {:ok, bin} ->
        File.rm(path)
        :erlang.binary_to_term(bin, [:safe])

      _ ->
        nil
    end
  end

  # A precommit that failed in credo printed its report as text: the same report as data puts each
  # issue in `failures`, at the alias's own strictness. `--strict` asked of an alias that lints at
  # credo's default level runs credo --strict as well: dropped, it passed a gate it was asked to fail.
  defp credo_named(reply, out, run, strict?) do
    alias_strict? = File.read!(Path.join(run.dir, "mix.exs")) =~ "credo --strict"

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

  @doc """
  The project's files as a commit would take them now, untracked ones too and ignored ones not: a
  git tree id, the same for the same files whatever HEAD is. A green `check` stamps it in the repo's
  git dir (`green_stamp/1`), and the commit hook (hooks/commit-gate.sh, which computes it the same
  way) skips a gate over files it already passed. nil outside a git repo.

  `git add` into the scratch index writes each file's blob into the repo's `.git/objects`, as any
  `git add` does: unreferenced, they stay loose objects until `git gc` prunes them.
  """
  def tree(dir) do
    # a scratch index in the git dir: one under a TMPDIR inside the project would be one of its files.
    # Named by the OS pid, like the hook's (`$$`), so no other live process's is the same file:
    # `System.unique_integer` is unique in one VM only, and fresh VMs draw near the same numbers. The
    # integer after the pid keeps two calls in one VM (the MCP server's) apart.
    case System.cmd("git", ["-C", dir, "rev-parse", "--absolute-git-dir"], stderr_to_stdout: true) do
      {git_dir, 0} ->
        index = "menard-index-#{System.pid()}-#{System.unique_integer([:positive])}"
        tree(dir, Path.join(String.trim(git_dir), index))

      _ ->
        nil
    end
  end

  defp tree(dir, index) do
    env = [{"GIT_INDEX_FILE", index}]

    try do
      with {_, 0} <- System.cmd("git", ["-C", dir, "add", "-A", "."], env: env, stderr_to_stdout: true),
           {tree, 0} <- System.cmd("git", ["-C", dir, "write-tree"], env: env, stderr_to_stdout: true),
           do: String.trim(tree),
           else: (_ -> nil)
    after
      File.rm(index)
    end
  end

  # in the git dir, which the agent and the hooks share whatever TMPDIR each has; one per project of
  # the repo (Tlön's server/ and console/), named by its path in it
  defp green_stamp(dir) do
    {git_dir, 0} = System.cmd("git", ["-C", dir, "rev-parse", "--absolute-git-dir"])
    {prefix, 0} = System.cmd("git", ["-C", dir, "rev-parse", "--show-prefix"])
    name = prefix |> String.trim() |> String.replace(~r/[^A-Za-z0-9]/, "-") |> String.trim_trailing("-")
    Path.join(String.trim(git_dir), "menard-green-" <> if(name == "", do: "root", else: name))
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
  defp check_steps(%{dir: dir} = run, args) do
    steps = [["format", "--check-formatted"], ["compile", "--warnings-as-errors"], ["test"]]

    {out, status, fetched} =
      Enum.reduce_while(steps, {"", 0, []}, fn step, {_out, _status, fetched} ->
        {out, status, more} = mix_fetching(run, step)
        next = {out, status, fetched ++ more}
        if status == 0, do: {:cont, next}, else: {:halt, next}
      end)

    reply = gate(out, status, fetched, dir)

    lint =
      if credo?(dir), do: credo(run, Enum.filter(args, &(&1 == "--strict"))), else: %{ok: true, failures: []}

    %{reply | ok: reply.ok and lint.ok, failures: reply.failures ++ lint.failures}
    |> Map.put(
      :ran,
      "format --check-formatted, compile --warnings-as-errors, test#{if credo?(dir), do: ", credo"} (no precommit alias)"
    )
  end

  # The project lints with credo when it has it: its lock names it, or its deps hold it
  defp credo?(dir) do
    File.dir?(Path.join(dir, "deps/credo")) or
      case File.read(Path.join(dir, "mix.lock")) do
        {:ok, lock} -> lock =~ ~s("credo":)
        _ -> false
      end
  end

  # `--format json` prints the report after whatever compiling said first: the object from a line
  # that opens a brace to the end, however it is laid out
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

  defp credo_issue(i) do
    %{
      kind: "credo",
      message: "#{i["message"]} (#{i["check"] |> String.split(".") |> List.last()})",
      at: "#{i["filename"]}:#{i["line_no"]}"
    }
  end

  # Only what an edit brought: issues on the lines changed since the last commit, every line of a file
  # git does not track yet. Old debt in the file is not the edit's to answer for.
  # Two git calls for every file at once, not two per file: which are tracked, and one diff.
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
  defp problems(out, dir), do: unformatted(out, dir) ++ diagnostics(out) ++ failures(out)

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

  # what `mix format` takes: the inputs, and each `subdirectories:` match's own .formatter.exs inputs
  # (Phoenix's priv/*/migrations), relative to it
  defp formatter_inputs(dir) do
    dot = Path.join(dir, ".formatter.exs")
    opts = if File.regular?(dot), do: elem(Code.eval_file(dot), 0), else: []
    glob = &Path.wildcard(Path.join(dir, &1), match_dot: true)
    subdirs = for sub <- List.wrap(opts[:subdirectories]), path <- glob.(sub), File.dir?(path), do: path

    (Enum.flat_map(List.wrap(opts[:inputs]), glob) ++ Enum.flat_map(subdirs, &formatter_inputs/1))
    |> Enum.uniq()
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

  # Every mix a verb runs, its whole output kept in one log, the last #{@keep} per project: a red
  # reply names it, so what the failures leave out is a grep away, not a second run (Tlön's cap.sh
  # rule: run once, read the log; 40% of the operator's test runs were run again to see more)
  defp log_path(dir, words) do
    logs = Path.join([System.tmp_dir!(), "menard-run", slug(Path.expand(dir))])
    File.mkdir_p!(logs)
    # room for this run's: all but one of the last @keep stay
    logs |> File.ls!() |> Enum.sort(:desc) |> Enum.drop(@keep - 1) |> Enum.each(&File.rm(Path.join(logs, &1)))
    stamp = Calendar.strftime(DateTime.utc_now(), "%Y%m%dT%H%M%S%f")
    Path.join(logs, "#{stamp}-#{slug(Enum.join(words, " "))}.log")
  end

  defp slug(text),
    do: text |> String.replace(~r/[^A-Za-z0-9]+/, "-") |> String.trim("-") |> String.slice(0, 60)

  defp tail(out), do: out |> String.split("\n") |> Enum.take(-12) |> Enum.join("\n")

  @doc """
  Parse `mix test` output (+ its exit status) into `%{ok, exit, tests, failed, skipped, failures, tail}`.
  `held`, what priv/ex_unit_formatter.exs wrote, gives the counts and the test failures when the
  run had it; output menard does not run itself (a precommit alias) is read from its prose.
  """
  def parse_test(out, status, held \\ nil) do
    # `--repeat-until-failure N` prints one run after another, and only the LAST run says anything:
    # the one that failed, or the Nth that passed. Its counts, failures and tail are the answer; the
    # seed is how to reproduce it, and the run count is how long it hid.
    runs = out |> String.split(~r/Running ExUnit with seed: /)
    last = List.last(runs)
    # the formatter's counts and failures when it wrote them, else what the prose says
    {tests, failed, skipped} = if held, do: {held.tests, held.failed, held[:skipped]}, else: counts(last)
    # the compile before the first run: its warnings, which a green run went on to hide, or, with no
    # run at all, a test file's errors
    compile = diagnostics(hd(runs))
    failures = if(held, do: held.failures, else: failures(last)) ++ compile

    %{
      ok: status == 0,
      exit: status,
      tests: tests,
      failed: failed,
      skipped: skipped,
      failures: if(failures == [] and status != 0, do: refusal(out), else: failures),
      tail: summary(last),
      runs: length(runs) - 1,
      seed: seed(last)
    }
  end

  # mix refusing to run at all (an unknown option, a task it cannot find): its `** (Mix)` line and
  # what follows up to the first blank line, before the usage it lists after
  defp refusal(out) do
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

  @doc """
  The reply as both doors print it: what a reader looks for, nothing it has to filter out. Green,
  `ok` and the counts; red, the failures and the seed that reproduces them. `ok` and `failures`
  are always there, so every reply is the same shape. A tail stays only where it is the answer: a
  verb with no counts (`check`, `compile`), or a failure nothing parsed.
  """
  def lean(result) do
    ok = result[:ok]

    result
    |> Enum.reject(fn
      {_key, nil} -> true
      {:fetched, []} -> true
      {:tail, ""} -> true
      {:skipped, 0} -> true
      {:exit, _} -> ok
      {:log, _} -> ok
      {:seed, _} -> ok
      {:runs, runs} -> runs <= 1
      {:tail, _} -> (ok and result[:tests] != nil) or result[:failures] not in [nil, []]
      _ -> false
    end)
    |> Map.new()
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
    # `at` relative to the project, however mix printed it: under a precommit alias ExUnit prints
    # absolute paths, and the same failure must not look different by which verb found it
    prefix = Path.expand(root) <> "/"

    sourced = fn f ->
      f = if is_binary(f[:at]), do: %{f | at: String.replace_prefix(f.at, prefix, "")}, else: f
      if f[:kind] == "test", do: Map.put(f, :source, source_of(f[:at], root)), else: f
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
         # down to the next `end` at its indent, it was the rest of the module
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

  # Compiler warnings and errors, each the same shape as a test failure: kind, message, at
  defp diagnostics(out) do
    ~r/(warning|error): (.+)\n(?:.*\n)*?\s*└─ ([^\s:]+):(\d+)/
    |> Regex.scan(out)
    |> Enum.map(fn [_, kind, message, file, line] ->
      %{kind: kind, message: message, at: "#{file}:#{line}"}
    end)
    |> Kernel.++(raised(out))
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
end
