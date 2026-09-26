defmodule Mix.Tasks.Menard.Guard do
  @shortdoc "Should a text edit of FILE be refused? Exit 2 with the reason for an Elixir module, 0 otherwise"
  @moduledoc """
  `mix menard.guard FILE [--mcp PREFIX] [--edit JSON]` — the enforcement every harness adapter
  calls from its pre-edit hook (docs/adapters.md, `Verbs.Guard`). A text edit of an existing
  `.ex`/`.exs` holding a `defmodule` exits 2 with the reason and the verbs to use on stderr;
  everything else exits 0, as does an edit (`--edit`, the harness's tool input) that only changes
  text inside a string or sigil or a `#` comment. `--mcp` names the harness's MCP tools in the
  refusal instead of CLI lines.
  """
  use Mix.Task

  alias Menard.Verbs

  import Menard.CLI

  @impl true
  def run(argv) do
    case OptionParser.parse(argv, strict: [mcp: :string, edit: :string]) do
      {opts, [file], []} -> check(Verbs.Guard.run(%{file: file, mcp: opts[:mcp], edit: opts[:edit]}))
      _ -> usage("mix menard.guard FILE [--mcp TOOL_PREFIX] [--edit TOOL_INPUT_JSON]")
    end
  end

  # the hook's protocol: exit 2 with the reason on stderr blocks, exit 0 allows
  defp check({:ok, %{allowed: false, reason: reason}}) do
    IO.puts(:stderr, reason)
    exit({:shutdown, 2})
  end

  defp check({:ok, %{allowed: true}}), do: :ok
  defp check({:error, reason}), do: Mix.raise(reason)
end
