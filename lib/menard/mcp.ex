# anubis_mcp is optional: a host that takes menard as a library has no MCP door, and none of its
# deps (finch, mint, …) either. Without it these modules are not defined at all.
if Code.ensure_loaded?(Anubis.Server) do
  defmodule Menard.MCP do
    @moduledoc """
    The standalone door: a stdio MCP server exposing the SAME `Menard.*` functions to any harness —
    Claude Code, an editor, an agent of your own. No identity: every path is scoped to the ROOT the
    server was launched for (`MENARD_ROOT`, else the cwd); a path outside it is refused.

        claude mcp add menard -- /path/to/menard/bin/menard mcp
    """
    use Anubis.Server,
      name: "menard",
      version: Mix.Project.config()[:version],
      capabilities: [:tools],
      # an agent reads this before its first call: in the eval, 4 of 6 learned it from the guard instead
      instructions: """
      Use these only where grep, sed and Edit guess: a rename across files (rename), who calls a
      function (find), a function moved with its docs (clause move), one function out of a file too
      big to read (outline, then clause get). Any other edit is cheaper as a plain Edit or Write, and
      every Elixir file written is formatted after: don't reach for these for it. A clause is addressed
      by its head, a test or describe by its label. A write's reply is every change it made: no need
      to Read the file back. Finish on run {verb: "check"}: format, warnings-as-errors and the tests
      in one JSON line.
      """

    component(Menard.MCP.Write, name: "write")
    component(Menard.MCP.Rename, name: "rename")
    component(Menard.MCP.Clause, name: "clause")
    component(Menard.MCP.Stmt, name: "stmt")
    component(Menard.MCP.Directive, name: "directive")
    component(Menard.MCP.Attr, name: "attr")
    component(Menard.MCP.Block, name: "block")
    component(Menard.MCP.Module, name: "module")
    component(Menard.MCP.Deps, name: "deps")
    component(Menard.MCP.Outline, name: "outline")
    component(Menard.MCP.Find, name: "find")
    component(Menard.MCP.Run, name: "run")

    # A call the schema refuses was a protocol error, "Invalid params", its why in the error's data,
    # which Claude Code does not show: the eval's agent asked clause for verb "get" and learned nothing.
    # The same refusal as a tool error puts the why where the agent reads.
    @impl Anubis.Server
    def handle_request(%{"method" => "tools/call"} = request, frame) do
      case Anubis.Server.Handlers.handle(request, __MODULE__, frame) do
        {:error, %Anubis.MCP.Error{reason: :invalid_params, data: %{message: why}}, frame} ->
          tool = get_in(request, ["params", "name"])

          {:reply, %{"content" => [%{"type" => "text", "text" => "#{tool}: #{why}"}], "isError" => true},
           frame}

        other ->
          other
      end
    end

    def handle_request(request, frame), do: Anubis.Server.Handlers.handle(request, __MODULE__, frame)

    @doc "The directory every path resolves under."
    def root, do: System.get_env("MENARD_ROOT") || Menard.caller_dir()

    @doc "A path under the root, or a refusal — no edit escapes the launch directory."
    def resolve(path) do
      root = Path.expand(root())
      abs = Path.expand(path, root)

      if String.starts_with?(abs, root <> "/") or abs == root,
        do: {:ok, abs},
        else: {:error, "refused: #{path} is outside #{root}"}
    end

    @doc "Every path resolved, or the first refusal — no partial edits."
    def resolve_all(paths) do
      # a glob (`lib/**/*.ex`) is expanded under the root: agents pass them, and no shell is there to expand them
      root = Path.expand(root())
      globs = Enum.filter(paths, &String.contains?(&1, ["*", "?", "[", "{"]))

      expanded =
        Enum.flat_map(paths, fn p ->
          if p in globs, do: Path.wildcard(Path.expand(p, root)), else: [p]
        end)

      # a glob that matches nothing beside others that do is dropped; only an empty whole is refused
      case expanded do
        [] -> {:error, "no file matches #{Enum.join(globs, ", ")}"}
        _ -> resolve_all_plain(expanded)
      end
    end

    defp resolve_all_plain(paths) do
      Enum.reduce_while(paths, {:ok, []}, fn p, {:ok, acc} ->
        case resolve(p) do
          {:ok, abs} -> {:cont, {:ok, acc ++ [abs]}}
          {:error, _} = e -> {:halt, e}
        end
      end)
    end
  end
end
