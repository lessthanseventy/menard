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
    alias Menard.Verbs.Noun

    use Anubis.Server,
      name: "menard",
      version: Mix.Project.config()[:version],
      capabilities: [:tools],
      # an agent reads this before its first call, instead of learning it from the guard
      instructions: """
      Several replacements of text, in one file or many, are ONE call to edit, where you would
      write a script (python, sed): each text is found exactly once or the call is refused and
      says which, nothing is written unless all of it is, and `then: "test"` runs the tests of what it changed after.
      The other tools are for where grep, sed and Edit guess: a rename across files (rename), who
      calls a function (find), a function moved with its docs (clause move), a module split into
      several in one call (clause split), one function out of a file too big to read (outline,
      then clause get). Every Elixir file written, by any tool or command, is formatted after. A
      clause is addressed by its head, a test or describe by its label. A write's reply is every
      change it made: no need to Read the file back. Finish on run {verb: "check"}: format,
      warnings-as-errors and the tests in one JSON line.
      """

    component(Menard.MCP.Edit, name: "edit")
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
    component(Menard.MCP.Hook, name: "hook")

    # A call the schema refuses is a protocol error, "Invalid params", its why in the error's data,
    # which Claude Code does not show. The same refusal as a tool error puts the why where the agent
    # reads.
    @impl Anubis.Server
    def handle_request(%{"method" => "tools/call"} = request, frame) do
      case Handlers.handle(request, __MODULE__, frame) do
        {:error, %Error{reason: :invalid_params, data: %{message: why}}, frame} ->
          tool = get_in(request, ["params", "name"])
          # what the tool takes beside what came: the schema's word for a wrong key inside a list
          # (`edits: [{file, search, replace}]`) is nothing at all, and for a wrong key at the top
          # (`name` for `target`) only the field it left empty
          given = get_in(request, ["params", "arguments"]) || %{}
          text = "#{tool}: #{why}\n#{tool} takes: #{takes(tool)}; given: #{keys(given)}"

          {:reply, %{"content" => [%{"type" => "text", "text" => text}], "isError" => true}, frame}

        other ->
          other
      end
    end

    def handle_request(request, frame), do: Handlers.handle(request, __MODULE__, frame)

    @doc """
    The directory every path resolves under: where the session stands now (`Menard.Hook.session_dir/2`),
    else where it started.
    """
    @spec root() :: String.t()
    def root do
      session = System.get_env("CLAUDE_CODE_SESSION_ID")
      (session && Menard.Hook.session_dir(session)) || System.get_env("MENARD_ROOT") || Menard.caller_dir()
    end

    @doc "A path under the root or in a sibling checkout under the home, or a refusal (`Menard.Verbs.resolve/2`)."
    @spec resolve(String.t()) :: {:ok, String.t()} | {:error, String.t()}
    def resolve(path), do: Menard.Verbs.resolve(path, %{root: root()})

    @doc "Every path resolved, globs expanded, or the first refusal — no partial edits."
    @spec resolve_all([String.t()]) :: {:ok, [String.t()]} | {:error, String.t()}
    def resolve_all(paths), do: Menard.Verbs.resolve_all(paths, %{root: root()})

    defp takes(tool) do
      case Enum.find(Noun.modules(), &(Noun.of(&1).name == tool)) do
        nil -> "?"
        verbs -> keys(Map.new(Noun.of(verbs).fields, fn {name, type, _} -> {name, type} end))
      end
    end

    # the keys of `map`, in order, a list of maps among its values as the keys of its first
    defp keys(map) do
      map
      |> Enum.sort_by(fn {key, _} -> to_string(key) end)
      |> Enum.map_join(", ", fn
        {key, {:list, %{} = of}} -> "#{key} [{#{keys(of)}}]"
        {key, [%{} = of | _]} -> "#{key} [{#{keys(of)}}]"
        {key, _} -> to_string(key)
      end)
    end
  end

  defmodule Menard.MCP.Keeper do
    @moduledoc """
    Keeps a stdio server's session there. Anubis ends a session (idle past its timeout, or crashed)
    and starts no other, and a stdio client initializes once: every call after went unanswered,
    each hook to its timeout. When the session ends, the keeper starts it again from the spec the
    server's supervisor had for it, initialized without the client's handshake.
    """
    use GenServer

    require Logger

    alias Anubis.Server.Registry
    alias Anubis.Server.Session

    @doc "Started once `server` is up, under a supervisor: it reads the session's spec while the session lives."
    @spec start_link(module()) :: GenServer.on_start()
    def start_link(server), do: GenServer.start_link(__MODULE__, server)

    @impl true
    def init(server) do
      supervisor = Registry.supervisor_name(server)
      # a temporary child's spec goes with it: read now, while it is there
      {:ok, spec} = :supervisor.get_childspec(supervisor, Session)
      {:ok, watch(%{session: Registry.stdio_session_name(server), supervisor: supervisor, spec: spec})}
    end

    @impl true
    def handle_info({:DOWN, ref, :process, _pid, reason}, %{ref: ref} = state) do
      with {:ok, _pid} <- Supervisor.start_child(state.supervisor, state.spec),
           :ok <- Session.auto_initialize(state.session) do
        Logger.warning("menard: the MCP session ended (#{inspect(reason)}) and was started again")
        {:noreply, watch(state)}
      else
        # the server itself is stopping, its client gone: nothing to keep
        _ -> {:stop, :normal, state}
      end
    catch
      :exit, _ -> {:stop, :normal, state}
    end

    def handle_info(_other, state), do: {:noreply, state}

    defp watch(state), do: Map.put(state, :ref, Process.monitor(state.session))
  end

  defmodule Menard.MCP.Hooks do
    @moduledoc """
    The hooks' own server (`bin/menard mcp --hooks`), its one tool `hook`. A server takes one call
    at a time, and with the verbs' it would hold every hook behind a `run check`, to the hooks'
    timeout. Apart, a hook waits on no verb.
    """
    use Anubis.Server,
      name: "menard-hooks",
      version: Mix.Project.config()[:version],
      capabilities: [:tools],
      instructions: "menard's hooks, called by the harness, not by an agent."

    component(Menard.MCP.Hook, name: "hook")
  end
end
