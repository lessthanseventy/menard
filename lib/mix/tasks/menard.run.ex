defmodule Mix.Tasks.Menard.Run do
  @shortdoc "A run verb with structured output: mix menard.run (check|test|format|compile) [ARGS]"
  @moduledoc """
  The run-and-update verbs an agent calls instead of a shell chain with greps on the end:

      mix menard.run check                # this app's gate (mix precommit): {ok, exit, tail}
      mix menard.run test [FILE[:LINE]]   # one file / one test, or the suite: {ok, tests, failed, failures: [{name, module, at, code, left, right | error, source}], tail}
      mix menard.run format [FILES]       # format; reports the files it changed
      mix menard.run compile              # compile --warnings-as-errors: {ok, diagnostics}

  Always prints ONE JSON object on the last line, and exits 1 when `ok` is false, so a caller
  reads one line and gates on the status. Human output above it is the underlying task's.
  """
  use Mix.Task

  @impl true
  def run(argv) do
    # Only `--in` is menard's; every other flag belongs to the mix task behind the verb
    # (`--repeat-until-failure 50`, `--seed 0`, `--only integration`) and passes through untouched.
    {dir, args} = split_in(argv, ".", [])

    case args do
      [verb | rest] when verb in ~w(check test format compile) ->
        finish(Menard.Run.result(Menard.resolve(dir), verb, rest))

      _ ->
        Mix.raise(
          "usage: mix menard.run [--in DIR] (check|test [FILE[:LINE]] [MIX TEST FLAGS]|format [FILES]|compile)"
        )
    end
  end

  defp split_in(["--in", dir | rest], _dir, acc), do: split_in(rest, dir, acc)
  defp split_in(["--in=" <> dir | rest], _dir, acc), do: split_in(rest, dir, acc)
  defp split_in([arg | rest], dir, acc), do: split_in(rest, dir, [arg | acc])
  defp split_in([], dir, acc), do: {dir, Enum.reverse(acc)}

  defp finish(%{ok: ok} = result) do
    Mix.shell().info(JSON.encode!(result))
    if not ok, do: exit({:shutdown, 1})
  end
end
