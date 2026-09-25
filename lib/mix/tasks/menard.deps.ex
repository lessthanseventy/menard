defmodule Mix.Tasks.Menard.Deps do
  @shortdoc "A function's references, or a project's dependencies: mix menard.deps FILE name/arity | add SPEC | upgrade [APPS]"
  @moduledoc """
  `mix menard.deps lib/a.ex go/1` — the local calls it makes (and which OTHER functions here share
  them), the remote calls, the modules its body names, and the attributes it reads. The read that
  answers "can this move, and what comes with it?".

  `mix menard.deps add [--in DIR] SPEC|NAME` — a dependency (`'{:req, "~> 0.5"}'`, or a bare name
  looked up with `mix hex.info`) written into the deps list, fetched and compiled. One JSON line:
  the lock diff and the compile. A fetch that fails puts mix.exs back.

  `mix menard.deps upgrade [--in DIR] [APPS] [--to REQ]` — updated (every app when none are
  named), through the host's own `mix igniter.upgrade` when it has Igniter, so each package's
  upgraders run. `--to` rewrites one app's requirement first, to cross a major version.
  """
  use Mix.Task

  @impl true
  def run(argv) do
    {opts, args, _} = OptionParser.parse(argv, strict: [module: :string, in: :string, to: :string])

    case args do
      ["add", spec] ->
        finish(Menard.MixDeps.add_in(Menard.resolve(opts[:in] || "."), spec))

      ["upgrade" | apps] ->
        finish(Menard.MixDeps.upgrade_in(Menard.resolve(opts[:in] || "."), apps, opts[:to]))

      [file, name_arity] ->
        case Menard.Deps.of(File.read!(Menard.resolve(file)), name_arity, module: opts[:module]) do
          {:error, message} -> Mix.raise(message)
          report -> Mix.shell().info(render(report))
        end

      _ ->
        Mix.raise(
          "usage: mix menard.deps FILE name/arity [--module Mod]        what a function references\n" <>
            "       mix menard.deps add [--in DIR] SPEC|NAME              a dependency, fetched and compiled\n" <>
            "       mix menard.deps upgrade [--in DIR] [APPS] [--to REQ]  updated, with its upgraders"
        )
    end
  end

  # one JSON line, and a failing exit when it did not work — the way `run` answers
  defp finish(%{ok: ok} = result) do
    Mix.shell().info(JSON.encode!(result))
    if not ok, do: exit({:shutdown, 1})
  end

  defp render(report) do
    [
      section("locals", Enum.map(report.locals, &local/1)),
      section("remotes", report.remotes),
      section("modules", report.modules),
      section("attributes", Enum.map(report.attributes, &"@#{&1}"))
    ]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  defp local(%{call: call, shared_with: []}), do: "#{call} (free to move)"
  defp local(%{call: call, shared_with: others}), do: "#{call} (also used by #{Enum.join(others, ", ")})"

  defp section(_title, []), do: ""
  defp section(title, lines), do: "#{title}:\n" <> Enum.map_join(lines, "\n", &("  " <> &1))
end
