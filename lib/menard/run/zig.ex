defmodule Menard.Run.Zig do
  @moduledoc """
  The run verbs in a Zig project (a `build.zig`, no `mix.exs`): `zig build`, and what it printed
  read into the reply every run verb gives. A compile error is its file, line and message, once
  however many steps hit it; a failed test its name, the line in the test, and what it expected.
  The `failed command:` line, every flag and path of it, is in the log only.
  """

  alias Menard.Run.Output

  @steps %{"test" => ~w(test), "compile" => [], "check" => ~w(install test)}

  @stuck_ms 10_000

  @doc """
  Kills the processes a zig run left behind, which nothing wants: a build runner whose working
  directory was a `menard-zigc-*` scratch dir that is now deleted spins forever, and a compiler
  (`--listen=-`) whose build runner was killed is left to init holding its cache locks, every
  later build that needs them waiting behind it. Answers the OS pids it killed.
  """
  @spec reap() :: [non_neg_integer()]
  def reap do
    for entry <- proc_entries(),
        pid = parse_pid(entry),
        left_behind?(entry),
        {_, 0} <- [System.cmd("kill", ["-KILL", entry], stderr_to_stdout: true)] do
      pid
    end
  end

  @doc """
  Runs `fun`, a zig build in `dir`, as every zig run goes: what earlier runs left behind reaped
  first, and a wait on a lock that would never end, ended (`watch_locks/3`).
  """
  @spec watched(String.t(), (-> result)) :: {result, [map()]} when result: term()
  def watched(dir, fun) do
    reap()
    watch_locks(dir, fun, @stuck_ms)
  end

  @doc """
  Runs `fun` while watching the processes working in `dir` for a wait on a file lock (zig's cache
  takes one per entry) whose holder, with what it runs and what it waits on in turn, used no CPU
  for `stuck_ms`: that wait would never end, so the waiter is killed and the run ends. Answers
  `fun`'s answer and a `lock` failure for each wait it ended.
  """
  @spec watch_locks(String.t(), (-> result), pos_integer()) :: {result, [map()]} when result: term()
  def watch_locks(dir, fun, stuck_ms) do
    watcher = Task.async(fn -> watch(Path.expand(dir), stuck_ms, %{}, []) end)
    answer = fun.()
    send(watcher.pid, :stop)
    {answer, Task.await(watcher)}
  end

  @doc "`verb` (`test`, `compile`, `check`) as `zig build` steps in `run.dir`, `args` passed on."
  @spec result(map(), String.t(), [String.t()]) :: map()
  def result(%{dir: dir} = run, verb, args) do
    steps = Map.fetch!(@steps, verb)
    ran = Enum.join(["zig", "build" | steps], " ")
    left = if at = run.deadline, do: max(at - System.monotonic_time(:millisecond), 1_000)

    {{out, status}, stuck} =
      watched(
        dir,
        fn ->
          Menard.host_cmd(dir, ["zig", "build"] ++ steps ++ ["--summary", "all" | args],
            timeout: left,
            label: ran
          )
        end
      )

    File.write!(run.log, "$ #{ran}\n#{out}\n", [:append])
    reply = out |> parse(status, dir) |> Map.put(:ran, ran)
    if stuck == [], do: reply, else: %{reply | ok: false, failures: stuck ++ reply.failures}
  end

  @doc """
  `test` on named `.zig` files: `zig test FILE` for each (a `:LINE` suffix dropped), the rest of
  `args` passed on, and the counts and failures summed into one reply. A file that imports a
  module the build defines can't be run alone, and the reply says so.
  """
  @spec test_files(map(), [String.t()], [String.t()]) :: map()
  def test_files(run, files, args) do
    files = Enum.map(files, &String.replace(&1, ~r/:\d+$/, ""))
    ran = Enum.map_join(files, ", ", &"zig test #{&1}")

    {replies, stuck} =
      Enum.map_reduce(files, [], fn file, stuck ->
        {reply, more} = test_file(run, file, args)
        {reply, stuck ++ more}
      end)

    failures = stuck ++ Enum.flat_map(replies, & &1.failures)

    counts =
      for key <- [:tests, :failed],
          into: %{},
          do: {key, replies |> Enum.map(&Map.get(&1, key, 0)) |> Enum.sum()}

    Map.merge(counts, %{
      ok: Enum.all?(replies, & &1.ok) and stuck == [],
      exit: replies |> Enum.map(& &1.exit) |> Enum.max(fn -> 0 end),
      failures: failures,
      ran: ran
    })
  end

  @doc """
  What `zig test FILE` printed, exiting `status`, as a run reply: `ok`, the `failures` (a failed
  test's name, place and message, a compile error's place and message), `tests` and `failed`.
  """
  @spec parse_test(String.t(), non_neg_integer(), String.t(), String.t()) :: map()
  def parse_test(out, status, dir, file) do
    out = String.replace(out, ~r/\e\[[0-9;]*m/, "")
    {tests, failed} = test_counts(out)

    failures =
      case compile_errors(out, dir) do
        [] -> test_failures(String.split(out, "\n"), dir)
        errors -> Enum.map(errors, &needs_build(&1, file))
      end

    failures = if failures == [] and status != 0, do: build_errors(out), else: failures
    %{ok: status == 0, exit: status, failures: failures, tests: tests, failed: failed}
  end

  @doc """
  `compile` in a Zig project: a fast check, not a build. `zig ast-check` on `args` (the `.zig`
  files changed; every `.zig` file of the project when none), then `zig build check` where
  `build.zig` defines that step. The full build is `run build`'s.
  """
  @spec compile(map(), [String.t()]) :: map()
  def compile(%{dir: dir} = run, args) do
    reap()
    files = if args == [], do: project_files(dir), else: Enum.filter(args, &String.ends_with?(&1, ".zig"))

    {out, status} =
      Enum.reduce(files, {"", 0}, fn file, {out, status} ->
        {more, code} = zig(run, ["ast-check", "--color", "off", file], "zig ast-check")
        {out <> more, max(status, code)}
      end)

    {out, status, ran} =
      if status == 0 and quick_step?(dir) do
        {more, code} = zig(run, ["build", "check"], "zig build check")
        {out <> more, code, "zig ast-check, zig build check"}
      else
        {out, status, "zig ast-check"}
      end

    File.write!(run.log, "$ #{ran}\n#{out}\n", [:append])
    %{ok: status == 0, exit: status, failures: compile_errors(out, dir), ran: ran}
  end

  @doc """
  What `zig build --summary all` printed, exiting `status` in `dir`, as a run reply: `ok`, the
  `failures`, `tests` and `failed` where tests ran (with `cached`, the test steps zig skipped as
  unchanged, when there were any), and a `tail` where neither says it (tests
  cached and not run, or a failure of no shape known here).
  """
  @spec parse(String.t(), non_neg_integer(), String.t()) :: map()
  def parse(out, status, dir) do
    out = String.replace(out, ~r/\e\[[0-9;]*m/, "")
    failures = compile_errors(out, dir) ++ failed_tests(out, dir)
    failures = if failures == [] and status != 0, do: build_errors(out), else: failures
    reply = %{ok: status == 0, exit: status, failures: failures}

    case Regex.run(~r/^Build Summary: (.+?)(?:; (\d+)\/(\d+) tests passed(.*))?$/m, out) do
      [_, _steps, _passed, total, rest] ->
        failed =
          case Regex.run(~r/(\d+) failed/, rest) do
            [_, n] -> String.to_integer(n)
            nil -> 0
          end

        reply
        |> Map.merge(%{tests: String.to_integer(total), failed: failed})
        |> put_cached(out)

      [_, steps] when status == 0 ->
        Map.put(reply, :tail, steps <> cached(out))

      _ when failures == [] ->
        Map.put(
          reply,
          :tail,
          out |> String.replace(~r/^failed command: .*\n?/m, "") |> String.trim() |> Output.tail()
        )

      _ ->
        reply
    end
  end

  defp put_cached(reply, out) do
    case length(Regex.scan(~r/^[| +-]*run test.* cached$/m, out)) do
      0 -> reply
      n -> Map.put(reply, :cached, n)
    end
  end

  defp cached(out) do
    if out =~ ~r/^[| +-]*run test.* cached$/m,
      do: "; tests cached: none ran, as nothing they read has changed",
      else: ""
  end

  defp compile_errors(out, dir) do
    for [_, file, line, message] <- Regex.scan(~r/^(\S[^:\n]*):(\d+):\d+: error: (.+)$/m, out), uniq: true do
      %{kind: "compile", at: "#{relative(file, dir)}:#{line}", message: message}
    end
  end

  # `error: no such step: x`, `error: unable to ...`: zig's own, outside any file or test
  defp build_errors(out) do
    for [_, message] <- Regex.scan(~r/^error: (?!'.*' failed:)(.+)$/m, out), uniq: true do
      %{kind: "build", message: message}
    end
  end

  defp failed_tests(out, dir), do: silent_tests(out, dir) ++ said_tests(out, dir)

  defp silent_tests(out, dir) do
    for [_, name] <- Regex.scan(~r/^error: '(.+)' failed without output$/m, out) do
      %{kind: "test", name: name, message: "failed without output"}
      |> Map.merge(declaration(name, dir))
    end
  end

  # a test that printed nothing has no trace, so its place is where its `test "name"` is declared
  defp declaration(name, dir) do
    short = name |> String.split(".test.", parts: 2) |> List.last()
    decls = [~s(test "#{short}"), "test #{short} "]

    place =
      for file <- project_files(dir),
          {line, n} <- file |> then(&Path.join(dir, &1)) |> File.stream!() |> Stream.with_index(1),
          String.trim_leading(line) |> String.starts_with?(decls),
          do: "#{file}:#{n}"

    case place do
      [at | _] -> %{at: at}
      [] -> %{}
    end
  end

  defp said_tests(out, dir) do
    for [_, name, inline, body] <- Regex.scan(~r/^error: '(.+)' failed:[ \t]*(.*)\n((?:[ \t]+.*\n?)*)/m, out) do
      lines = body |> String.split("\n", trim: true) |> Enum.map(&String.trim/1)
      {said, trace} = Enum.split_while(lines, &(frame(&1) == nil))
      said = Enum.reject([inline | said], &(&1 == ""))

      {at, code} = place(trace, dir)

      failure =
        if said == [],
          do: %{message: code || "failed"},
          else: %{message: Enum.join(said, "\n"), code: code}

      failure
      |> Map.merge(%{kind: "test", name: name, at: at})
      |> Map.reject(fn {_key, value} -> value == nil end)
    end
  end

  # the last frame is the test's own line, and the line under it its code
  defp place(trace, dir) do
    case trace |> Enum.with_index() |> Enum.filter(fn {line, _i} -> frame(line) end) |> List.last() do
      {line, i} ->
        {file, n} = frame(line)
        {"#{relative(file, dir)}:#{n}", Enum.at(trace, i + 1)}

      nil ->
        {nil, nil}
    end
  end

  defp frame(line) do
    case Regex.run(~r/^(.+?):(\d+):\d+: 0x[0-9a-f]+ in /, line) do
      [_, file, n] -> {file, n}
      nil -> nil
    end
  end

  defp relative(file, dir), do: Path.relative_to(file, Path.expand(dir))

  defp zig(%{dir: dir} = run, args, label) do
    left = if at = run.deadline, do: max(at - System.monotonic_time(:millisecond), 1_000)
    Menard.host_cmd(dir, ["zig" | args], timeout: left, label: label)
  end

  defp left_behind?(entry) do
    case File.read_link("/proc/#{entry}/cwd") do
      {:ok, cwd} -> cwd =~ ~r{/menard-zigc-[^/]* \(deleted\)$} or orphan_compiler?(entry)
      {:error, _} -> false
    end
  end

  defp orphan_compiler?(entry) do
    with {:ok, cmdline} <- File.read("/proc/#{entry}/cmdline"),
         [exe | args] <- String.split(cmdline, <<0>>, trim: true),
         true <- Path.basename(exe) == "zig" and "--listen=-" in args do
      parent(entry) == 1
    else
      _ -> false
    end
  end

  defp parent(pid) do
    case stat(pid) do
      [_state, ppid | _] -> String.to_integer(ppid)
      nil -> nil
    end
  end

  # the fields after `(comm)`, which may itself hold spaces
  defp stat(pid) do
    case File.read("/proc/#{pid}/stat") do
      {:ok, text} -> text |> String.split(") ") |> List.last() |> String.split(" ")
      {:error, _} -> nil
    end
  end

  defp watch(dir, stuck_ms, seen, ended) do
    receive do
      :stop -> ended
    after
      250 ->
        now = System.monotonic_time(:millisecond)
        waits = lock_waits()

        seen =
          for {waiter, holder} = wait <- waits, cwd(waiter) == dir, into: %{} do
            ticks = work(holder, waits, MapSet.new())

            case seen do
              %{^wait => {^ticks, since}} -> {wait, {ticks, since}}
              _ -> {wait, {ticks, now}}
            end
          end

        {stuck, seen} = Map.split_with(seen, fn {_wait, {_ticks, since}} -> now - since >= stuck_ms end)

        ended =
          ended ++
            Enum.map(stuck, fn {{waiter, holder}, {_, since}} -> end_wait(waiter, holder, now - since) end)

        watch(dir, stuck_ms, seen, ended)
    end
  end

  # waiter => holder, from /proc/locks: a waiter's line is its holder's number with `->`
  defp lock_waits do
    locks =
      case File.read("/proc/locks") do
        {:ok, text} -> Regex.scan(~r/^(\d+): (-> )?\S+\s+\S+\s+\S+\s+(\d+) /m, text)
        {:error, _} -> []
      end

    holders = for [_, id, "", pid] <- locks, into: %{}, do: {id, String.to_integer(pid)}

    for [_, id, "-> ", pid] <- locks,
        %{^id => holder} <- [holders],
        into: %{},
        do: {String.to_integer(pid), holder}
  end

  # CPU ticks of `pid`, what it runs, and the holder of any lock it waits on: unchanged, none of
  # them moved
  defp work(pid, waits, seen) do
    if pid in seen do
      0
    else
      seen = MapSet.put(seen, pid)
      own = Enum.sum(for p <- [pid | descendants(pid)], do: ticks(p))

      case waits do
        %{^pid => holder} -> own + work(holder, waits, seen)
        _ -> own
      end
    end
  end

  defp ticks(pid) do
    case stat(pid) do
      [_ | _] = fields -> String.to_integer(Enum.at(fields, 11)) + String.to_integer(Enum.at(fields, 12))
      nil -> 0
    end
  end

  defp descendants(pid) do
    children =
      for task <- Path.wildcard("/proc/#{pid}/task/*/children"),
          {:ok, text} <- [File.read(task)],
          child <- String.split(text, " ", trim: true),
          do: String.to_integer(child)

    children ++ Enum.flat_map(children, &descendants/1)
  end

  defp cwd(pid) do
    case File.read_link("/proc/#{pid}/cwd") do
      {:ok, cwd} -> cwd
      {:error, _} -> nil
    end
  end

  defp end_wait(waiter, holder, ms) do
    System.cmd("kill", ["-KILL", "#{waiter}"], stderr_to_stdout: true)

    %{
      kind: "lock",
      message:
        "waited #{div(ms, 1000)}s on a lock held by pid #{holder} (#{command(holder)}), which did no work in that time: " <>
          "stopped, as that wait would never end"
    }
  end

  defp command(pid) do
    case File.read("/proc/#{pid}/cmdline") do
      {:ok, cmdline} ->
        cmdline |> String.split(<<0>>, trim: true) |> Enum.take(2) |> Enum.map_join(" ", &Path.basename/1)

      {:error, _} ->
        "gone"
    end
  end

  defp quick_step?(dir), do: File.read!(Path.join(dir, "build.zig")) =~ ~s|b.step("check"|

  defp project_files(dir) do
    for file <- Path.wildcard(Path.join(dir, "{src,test}/**/*.zig")), do: Path.relative_to(file, dir)
  end

  defp proc_entries do
    case File.ls("/proc") do
      {:ok, entries} -> entries
      {:error, _} -> []
    end
  end

  defp parse_pid(entry) do
    case Integer.parse(entry) do
      {pid, ""} -> pid
      _ -> nil
    end
  end

  defp needs_build(%{message: "no module named" <> _ = message} = error, file),
    do: %{
      error
      | message:
          "#{message}: #{file} needs the build's modules, run the whole suite or pass --test-filter NAME"
    }

  defp needs_build(error, _file), do: error

  defp test_counts(out) do
    case {Regex.run(~r/^(\d+) passed; (\d+) skipped; (\d+) failed\./m, out),
          Regex.run(~r/^All (\d+) tests passed\./m, out)} do
      {[_, passed, skipped, failed], _} ->
        {String.to_integer(passed) + String.to_integer(skipped) + String.to_integer(failed),
         String.to_integer(failed)}

      {nil, [_, passed]} ->
        {String.to_integer(passed), 0}

      _ ->
        {0, 0}
    end
  end

  defp test_failures([line | rest], dir) do
    case Regex.run(~r/^\d+\/\d+ (.+?)\.\.\.(.*)$/, line) do
      [_, _name, said] when said in ["OK", "SKIP"] ->
        test_failures(rest, dir)

      [_, name, said] ->
        {body, rest} = Enum.split_while(rest, &(not Regex.match?(~r/^(\d+\/\d+ |\d+ passed; |error: )/, &1)))
        [test_failure(name, said, body, dir) | test_failures(rest, dir)]

      nil ->
        test_failures(rest, dir)
    end
  end

  defp test_failures([], _dir), do: []

  defp test_failure(name, said, body, dir) do
    {said, body} = if said =~ ~r/^FAIL \(/, do: {"", [said | body]}, else: {said, body}
    {head, trace} = Enum.split_while(body, &(frame(String.trim(&1)) == nil))

    kind =
      head
      |> Enum.find_value(&Regex.run(~r/^FAIL \((.+)\)$/, &1, capture: :all_but_first))
      |> List.wrap()
      |> List.first()

    {at, code} = place(Enum.map(trace, &String.trim/1), dir)
    message = if said == "", do: kind || "failed", else: said

    Map.reject(%{kind: "test", name: name, at: at, message: message, code: code}, fn {_key, value} ->
      value == nil
    end)
  end

  defp test_file(%{dir: dir} = run, file, args) do
    {{out, status}, stuck} =
      watched(dir, fn ->
        zig(run, ["test", file | args], "zig test #{file}")
      end)

    File.write!(run.log, "$ zig test #{file}\n#{out}\n", [:append])
    {parse_test(out, status, dir, file), stuck}
  end
end
