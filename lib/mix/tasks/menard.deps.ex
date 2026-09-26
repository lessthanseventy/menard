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

  alias Menard.Verbs

  import Menard.CLI

  @impl true
  def run(argv) do
    {opts, args} = OptionParser.parse!(argv, strict: [module: :string, in: :string, to: :string])

    case args do
      ["add", spec] ->
        finish(Verbs.Deps.run(%{verb: "add", dir: opts[:in], spec: spec}))

      ["upgrade" | apps] ->
        finish(Verbs.Deps.run(%{verb: "upgrade", dir: opts[:in], apps: apps, to: opts[:to]}))

      [file, name_arity] ->
        answer(Verbs.Deps.run(%{verb: "refs", file: file, name_arity: name_arity, module: opts[:module]}))

      _ ->
        usage(
          "mix menard.deps FILE name/arity [--module Mod]        what a function references\n" <>
            "       mix menard.deps add [--in DIR] SPEC|NAME              a dependency, fetched and compiled\n" <>
            "       mix menard.deps upgrade [--in DIR] [APPS] [--to REQ]  updated, with its upgraders"
        )
    end
  end
end
