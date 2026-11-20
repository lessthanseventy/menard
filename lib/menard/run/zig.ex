defmodule Menard.Run.Zig do
  @moduledoc """
  The run verbs in a Zig project (a `build.zig`, no `mix.exs`): `zig build`, and what it printed
  read into the reply every run verb gives. A compile error is its file, line and message, once
  however many steps hit it; a failed test its name, the line in the test, and what it expected.
  The `failed command:` line, every flag and path of it, is in the log only.
  """

  alias Menard.Run.Output

  @steps %{"test" => ~w(test), "compile" => [], "check" => ~w(install test)}

  @doc "`verb` (`test`, `compile`, `check`) as `zig build` steps in `run.dir`, `args` passed on."
  @spec result(map(), String.t(), [String.t()]) :: map()
  def result(%{dir: dir} = run, verb, args) do
    steps = Map.fetch!(@steps, verb)
    ran = Enum.join(["zig", "build" | steps], " ")
    left = if at = run.deadline, do: max(at - System.monotonic_time(:millisecond), 1_000)

    {out, status} =
      Menard.host_cmd(dir, ["zig", "build"] ++ steps ++ ["--summary", "all" | args],
        timeout: left,
        label: ran
      )

    File.write!(run.log, "$ #{ran}\n#{out}\n", [:append])
    out |> parse(status, dir) |> Map.put(:ran, ran)
  end

  @doc """
  What `zig build --summary all` printed, exiting `status` in `dir`, as a run reply: `ok`, the
  `failures`, `tests` and `failed` where tests ran, and a `tail` where neither says it (tests
  cached and not run, or a failure of no shape known here).
  """
  @spec parse(String.t(), non_neg_integer(), String.t()) :: map()
  def parse(out, status, dir) do
    out = String.replace(out, ~r/\e\[[0-9;]*m/, "")
    failures = compile_errors(out, dir) ++ failed_tests(out, dir)
    reply = %{ok: status == 0, exit: status, failures: failures}

    case Regex.run(~r/^Build Summary: (.+?)(?:; (\d+)\/(\d+) tests passed(.*))?$/m, out) do
      [_, _steps, _passed, total, rest] ->
        failed =
          case Regex.run(~r/(\d+) failed/, rest) do
            [_, n] -> String.to_integer(n)
            nil -> 0
          end

        Map.merge(reply, %{tests: String.to_integer(total), failed: failed})

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

  defp failed_tests(out, dir) do
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
end
