defmodule Menard.Run do
  @moduledoc """
  The run verbs: each runs mix in the project and answers `failures` in one shape for every verb
  (`kind`, `message`, `at`; a test failure adds its name, module, source and the assertion's
  code/left/right), the counts, and a tail that is the summary, not the logs a suite prints on its
  way. `Menard.Run.Output` reads what mix printed; `mix menard.run` prints what these return, as
  one JSON line.
  """

  alias Menard.Run.Lint
  alias Menard.Run.Lock
  alias Menard.Run.Output

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
        verb in ["check", "test"] -> Lock.one_at_a_time(run, fn -> verb(run, verb, args) end)
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
          |> Output.parse_check(status, fetched, dir)
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

    %{
      ok: status == 0,
      exit: status,
      failures: Output.diagnostics(out, run.dir),
      tail: Output.tail(out),
      fetched: fetched
    }
  end

  defp verb(run, "credo", args) do
    if Lint.credo?(run.dir),
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

  # A precommit that failed in credo printed its report as text: the same report as data puts each
  # issue in `failures`, at the alias's own strictness. `--strict` asked of an alias that lints at
  # credo's default level runs credo --strict as well: dropped, it passed a gate it was asked to fail.
  defp credo_named(reply, out, run, strict?) do
    alias_strict? = Lint.credo_strict?(run.dir)

    cond do
      not Lint.credo?(run.dir) ->
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
    # as strict as the project gates, asked or not: a clean answer its gate would not give is none
    {strict, args} = {"--strict" in args or Lint.credo_strict?(run.dir), args -- ["--strict"]}
    {changed, files} = {"--changed" in args, args -- ["--changed"]}
    # the report is read as JSON: a caller's `--format oneline` came after it, won, and nothing parsed
    files = drop_format(files)

    {out, status, fetched} =
      mix_fetching(run, ["credo", "--format", "json"] ++ if(strict, do: ["--strict"], else: []) ++ files)

    case Lint.credo_issues(out) do
      {:ok, issues} ->
        issues = if changed, do: Lint.only_changed(issues, run.dir), else: issues
        %{ok: issues == [], failures: issues, fetched: fetched}

      :error ->
        %{
          ok: false,
          exit: status,
          failures: [%{kind: "error", message: "credo gave no report"}],
          tail: Output.tail(out),
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
        {out, status, fetched} -> Output.parse_check(out, status, fetched, dir)
      end

    lint =
      if Lint.credo?(dir),
        do: credo(run, Enum.filter(args, &(&1 == "--strict"))),
        else: %{ok: true, failures: []}

    %{reply | ok: reply.ok and lint.ok, failures: reply.failures ++ lint.failures}
    |> Map.put(
      :ran,
      "format --check-formatted, compile --warnings-as-errors, test#{if Lint.credo?(dir), do: ", credo"} (no precommit alias)"
    )
  end

  defp drop_format(["--format", _ | rest]), do: drop_format(rest)
  defp drop_format(["--format=" <> _ | rest]), do: drop_format(rest)
  defp drop_format([arg | rest]), do: [arg | drop_format(rest)]
  defp drop_format([]), do: []

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

    held = Output.read_held(held)

    out
    |> Output.parse_test(status, held, run.dir)
    |> Output.with_sources(run.dir)
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
    changed = Output.changed_tests(dir)

    length(failures) <= 10 and Enum.all?(failures, &(&1[:kind] == "test" and &1[:at] != nil)) and
      Enum.any?(failures, &(not Output.changed?(&1.at, changed))) and
      not Enum.any?(args, &(&1 in ["--failed", "--repeat-until-failure"]))
  end

  defp rerun?(_first, _args, _dir), do: false

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
      %{ok: status == 0, exit: status, failures: [], ran: "mise run #{verb}", tail: Output.tail(out)}
    else
      nil ->
        %{ok: false, failures: [], tail: none}

      {out, _status} ->
        %{ok: false, failures: [], tail: if(out =~ "Task not found", do: none, else: Output.tail(out))}
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

  # The first few failures whole; past them, where and what, the message's first line: the log has all
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
