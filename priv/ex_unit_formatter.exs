# Required into the HOST's `mix test` (`elixir -r THIS -S mix test --formatter
# Menard.ExUnitFormatter --formatter ExUnit.CLIFormatter`): ExUnit's own events, written as data,
# so `run test` reads each failure as ExUnit holds it instead of regexes over the prose the CLI
# formatter prints (a multi-line `left:` came back as its first line). It runs on the host's
# Elixir, whatever version that is: no JSON module, only what ExUnit has had for years.
#
# At each suite's end it writes `:erlang.term_to_binary(%{tests, failed, skipped, excluded,
# excluded_by, failures, times})` to the path
# in MENARD_EXUNIT_OUT; each failure is the reply's shape (kind, message, at, name, module, and an
# assertion's code/left/right). A `--repeat-until-failure` run writes once per suite, so the file
# holds the last, the run the reply is about.
defmodule Menard.ExUnitFormatter do
  @moduledoc false
  use GenServer

  @impl true
  def init(_opts) do
    snapshot_later()
    {:ok, fresh()}
  end

  # A run stopped at its deadline is killed with this VM, before its suite ends: what it had so far
  # is written every second, the tests still running with it (up2 Oban: a run that hung on MySQL
  # answered nothing of what it had)
  @impl true
  def handle_info(:snapshot, acc) do
    write(acc)
    snapshot_later()
    {:noreply, acc}
  end

  def handle_cast({:test_started, %ExUnit.Test{} = test}, acc),
    do:
      {:noreply,
       %{acc | running: Map.put(acc.running, {test.module, test.name}, %{name: name(test), at: at(test)})}}

  @impl true
  def handle_cast({:test_finished, %ExUnit.Test{state: state} = test}, acc) do
    acc = %{acc | running: Map.delete(acc.running, {test.module, test.name})}

    acc =
      case state do
        nil ->
          %{acc | tests: acc.tests + 1, times: [time(test) | acc.times]}

        {:failed, failures} ->
          failed(%{acc | times: [time(test) | acc.times]}, [test_failure(test, failures)])

        {:invalid, _module} ->
          failed(acc, [])

        {:skipped, _reason} ->
          %{acc | skipped: acc.skipped + 1}

        # "due to slow filter": the tag a reply can say to --include
        {:excluded, reason} ->
          %{
            acc
            | excluded: acc.excluded + 1,
              excluded_by: Map.update(acc.excluded_by, filter(reason), 1, &(&1 + 1))
          }

        _ ->
          acc
      end

    {:noreply, acc}
  end

  # setup_all raised: the module's tests come as :invalid, and this is the why
  def handle_cast({:module_finished, %ExUnit.TestModule{state: {:failed, failures}} = module}, acc),
    do: {:noreply, %{acc | failures: [setup_all_failure(module, failures) | acc.failures]}}

  def handle_cast({:suite_finished, _times}, acc), do: finish(acc)
  def handle_cast({:suite_finished, _run_us, _load_us}, acc), do: finish(acc)
  def handle_cast(_event, acc), do: {:noreply, acc}

  defp fresh,
    do: %{
      tests: 0,
      failed: 0,
      skipped: 0,
      excluded: 0,
      excluded_by: %{},
      failures: [],
      times: [],
      running: %{}
    }

  defp snapshot_later, do: Process.send_after(self(), :snapshot, 1_000)

  defp write(acc) do
    if path = System.get_env("MENARD_EXUNIT_OUT") do
      acc = %{acc | failures: Enum.reverse(acc.failures), running: Map.values(acc.running)}
      File.write!(path, :erlang.term_to_binary(acc))
    end
  end

  # every test that ran, for `--slowest N`: which N is the reply's to pick
  defp time(test), do: %{name: name(test), at: at(test), ms: div(test.time, 1000)}

  defp name(test) do
    type = to_string(test.tags[:test_type] || :test)
    test.name |> to_string() |> String.replace_prefix(type <> " ", "")
  end

  defp at(test), do: "#{Path.relative_to_cwd(test.tags.file)}:#{test.tags.line}"

  defp filter(reason) do
    case Regex.run(~r/^due to (.+) filter$/, reason) do
      [_, tag] -> tag
      nil -> reason
    end
  end

  defp failed(acc, failures),
    do: %{acc | tests: acc.tests + 1, failed: acc.failed + 1, failures: failures ++ acc.failures}

  defp finish(acc) do
    write(acc)
    {:noreply, fresh()}
  end

  defp test_failure(test, [{kind, reason, stack} | _]) do
    compact(%{
      kind: "test",
      name: name(test),
      module: inspect(test.module),
      at: at(test),
      message: message(kind, reason, stack),
      stack: frames(reason, stack),
      code: code(reason),
      left: side(reason, :left),
      right: side(reason, :right)
    })
  end

  defp setup_all_failure(module, [{kind, reason, stack} | _]) do
    at =
      Enum.find_value(stack, fn {_m, _f, _a, location} ->
        file = to_string(location[:file])
        if String.ends_with?(file, "_test.exs"), do: "#{file}:#{location[:line]}"
      end)

    compact(%{
      kind: "test",
      name: "setup_all",
      module: inspect(module.name),
      at: at,
      message: "setup_all failed, so none of the module's tests ran: " <> message(kind, reason, stack)
    })
  end

  # Where a raise came from: up to three frames in the project (lib/, test/). A KeyError raised in
  # lib/shop/cart.ex:25 answered its banner and the test's line alone (Fable's review, 2026-10-01).
  # An assertion's own line is the test's, said by `at`.
  defp frames(%ExUnit.AssertionError{}, _stack), do: nil

  defp frames(_reason, stack) do
    frames =
      for {_m, _f, _a, location} = entry <- stack,
          file = location[:file],
          String.starts_with?(Path.relative_to_cwd(to_string(file)), ["lib/", "test/"]),
          do: Exception.format_stacktrace_entry(entry)

    if frames == [], do: nil, else: Enum.take(frames, 3)
  end

  defp message(:error, %ExUnit.AssertionError{message: message}, _stack), do: message

  defp message(kind, reason, stack),
    do: kind |> Exception.format_banner(reason, stack) |> String.replace_prefix("** ", "")

  defp code(%ExUnit.AssertionError{expr: expr}) when is_binary(expr), do: expr

  defp code(%ExUnit.AssertionError{expr: expr}) do
    if expr == ExUnit.AssertionError.no_value(), do: nil, else: Macro.to_string(expr)
  end

  defp code(_reason), do: nil

  defp side(%ExUnit.AssertionError{} = error, key) do
    value = Map.fetch!(error, key)

    cond do
      value == ExUnit.AssertionError.no_value() -> nil
      # a match's left is its pattern, quoted (`{:match, pins}`, not an atom); written back as code,
      # the way the CLI formatter shows it
      key == :left and not is_atom(error.context) -> value |> Macro.prewalk(&original/1) |> Macro.to_string()
      # a struct of thirty fields was a page of every reply it failed in: its first ones, then `...`
      true -> inspect(value, pretty: true, width: 80, limit: 25, printable_limit: 500)
    end
  end

  defp side(_reason, _key), do: nil

  defp original({_, [original: original], _}), do: original
  defp original(node), do: node

  defp compact(map), do: for({k, v} <- map, v != nil, into: %{}, do: {k, v})
end
