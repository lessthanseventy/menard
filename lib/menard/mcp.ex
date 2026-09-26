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
    alias Anubis.MCP.Error
    alias Anubis.Server.Handlers

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
      case Handlers.handle(request, __MODULE__, frame) do
        {:error, %Error{reason: :invalid_params, data: %{message: why}}, frame} ->
          tool = get_in(request, ["params", "name"])

          {:reply, %{"content" => [%{"type" => "text", "text" => "#{tool}: #{why}"}], "isError" => true},
           frame}

        other ->
          other
      end
    end

    def handle_request(request, frame), do: Handlers.handle(request, __MODULE__, frame)

    @doc "The directory every path resolves under."
    def root, do: System.get_env("MENARD_ROOT") || Menard.caller_dir()

    @doc "A path under the root, or a refusal — no edit escapes the launch directory."
    def resolve(path) do
      root = Path.expand(root())
      resolve(path, root, real(root))
    end

    # Under the root as written, and as the OS will follow it: a symlink under the root that points
    # outside it passed the first test alone.
    defp resolve(path, root, real_root) do
      abs = Path.expand(path, root)

      if under?(abs, root) and under?(real_below(abs, root, real_root), real_root),
        do: {:ok, abs},
        else: {:error, "refused: #{path} is outside #{root}"}
    end

    # only the part below the root is walked, from the root's own real path: each link looked up is a
    # call to the file server, and resolve_all makes these for every file it is given
    defp real_below(abs, root, real_root) do
      abs |> Path.relative_to(root) |> Path.split() |> Enum.reduce(real_root, &follow(Path.join(&2, &1), 0))
    end

    defp under?(path, dir), do: path == dir or String.starts_with?(path, dir <> "/")

    # `path` with each symlink in it followed, as far as it exists: a file about to be created is
    # taken as written. A link loop stops following after 40 links, as the OS does.
    defp real(path, hops \\ 0) do
      path |> Path.split() |> Enum.reduce(&follow(Path.join(&2, &1), hops))
    end

    defp follow(path, hops) when hops > 40, do: path

    defp follow(path, hops) do
      case :file.read_link(path) do
        {:ok, target} -> real(Path.expand(to_string(target), Path.dirname(path)), hops + 1)
        {:error, _} -> path
      end
    end

    @doc "Every path resolved, or the first refusal — no partial edits."
    def resolve_all(paths) do
      # a glob (`lib/**/*.ex`) is expanded under the root: agents pass them, and no shell is there to expand them
      root = Path.expand(root())
      glob? = &String.contains?(&1, ["*", "?", "[", "{"])

      expanded =
        Enum.flat_map(paths, fn p ->
          if glob?.(p), do: Path.wildcard(Path.expand(p, root)), else: [p]
        end)

      # a glob that matches nothing beside others that do is dropped; only an empty whole is refused
      case expanded do
        [] -> {:error, "no file matches #{paths |> Enum.filter(glob?) |> Enum.join(", ")}"}
        _ -> resolve_all_plain(expanded, root, real(root))
      end
    end

    defp resolve_all_plain(paths, root, real_root) do
      resolved =
        Enum.reduce_while(paths, {:ok, []}, fn p, {:ok, acc} ->
          case resolve(p, root, real_root) do
            {:ok, abs} -> {:cont, {:ok, [abs | acc]}}
            {:error, _} = e -> {:halt, e}
          end
        end)

      with {:ok, reversed} <- resolved, do: {:ok, Enum.reverse(reversed)}
    end
  end
end
