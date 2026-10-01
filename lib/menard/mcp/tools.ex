# only with the optional anubis_mcp, like Menard.MCP
if Code.ensure_loaded?(Anubis.Server) do
  defmodule Menard.MCP.Reply do
    @moduledoc false
    alias Anubis.Server.Response
    alias Menard.Verbs

    def ok(frame, payload), do: {:reply, Response.text(Response.tool(), Menard.encode(payload)), frame}
    def fail(frame, message), do: {:reply, Response.error(Response.tool(), message), frame}

    @doc "A verb's result (`Menard.Verbs`) as the tool's answer: the reply as is, the reason as a tool error."
    def answer(frame, {:ok, reply}), do: ok(frame, reply)
    def answer(frame, {:error, reason}), do: fail(frame, reason)

    @doc "The tool's params as the verb takes them: every path resolves under the launch root."
    def params(params), do: Map.put(params, :root, Menard.MCP.root())

    @doc """
    Every tool's body: the noun's verb run on the params, its result the answer. `run` is told its
    deadline, so the host's mix is killed short of the tool's own and the reply says what it was
    doing, where the call would have gone silent while mix kept running. `hook` answers the
    harness, which reads the text as a command hook's stdout: a JSON object, or nothing to say; a
    file that could not be formatted blocks, which is how its reason reaches the agent.
    """
    def call(Verbs.Run = verbs, params, frame, ms),
      do: answer(frame, verbs.run(params |> params() |> Map.put(:timeout, ms - 20_000)))

    def call(Verbs.Hook = verbs, params, frame, _ms) do
      case verbs.run(params) do
        {:ok, %{context: text, event: event}} -> ok(frame, Menard.Hook.context(text, event))
        {:ok, %{problem: text}} -> ok(frame, %{decision: "block", reason: text})
        {:ok, %{deny: text}} -> ok(frame, Menard.Hook.denial(text))
        {:ok, %{rewrite: input}} -> ok(frame, Menard.Hook.rewrite(input))
        {:ok, %{}} -> ok(frame, %{})
      end
    end

    def call(verbs, params, frame, _ms), do: answer(frame, verbs.run(params(params)))

    @doc """
    Working on menard itself, its source changes under the server, and a server that kept the code
    it started with ran none of the fixes made since (hooks included: they are calls to it). So a
    call first compiles menard as it is now, in place; one that does not compile (an edit half
    applied) leaves the code it had. An installed menard's source does not change: this is a stat
    of each file. No mix project (`--frozen`): nothing to compile.
    """
    def fresh do
      stamp = newest_source()

      if stamp > loaded(), do: :global.trans({__MODULE__, :fresh}, fn -> compile(stamp) end)
      :ok
    end

    @doc "What the server runs, stamped as current: called once it has started."
    def loaded!, do: :persistent_term.put({__MODULE__, :loaded}, newest_source())

    # Every tool runs under a deadline: over stdio a call that never returns is a server gone
    # silent, and one went past Claude Code's 120s.
    def bounded(tool, params, frame, ms) do
      fresh()
      caller = self()
      tag = make_ref()

      # Monitored, not linked: in a linked Task, an exit the tool did not catch (or a process it had
      # linked dying) took the server's own process with it. A raise, a throw or an exit is an answer,
      # with the trace that says where in menard it came from.
      {pid, monitor} =
        spawn_monitor(fn ->
          reply =
            try do
              tool.call(params, frame)
            catch
              kind, reason -> fail(frame, Exception.format(kind, reason, __STACKTRACE__))
            end

          send(caller, {tag, reply})
        end)

      receive do
        {^tag, reply} ->
          Process.demonitor(monitor, [:flush])
          reply

        {:DOWN, ^monitor, :process, ^pid, reason} ->
          fail(frame, "#{inspect(tool)} died: #{Exception.format_exit(reason)}")
      after
        ms ->
          Process.exit(pid, :kill)
          Process.demonitor(monitor, [:flush])

          # an answer that came in as the clock ran out is not left in the server's mailbox
          receive do
            {^tag, _late} -> :ok
          after
            0 -> :ok
          end

          fail(
            frame,
            "#{inspect(tool)} did not finish in #{ms / 1000}s. It may have written its file: read it before retrying"
          )
      end
    end

    defp loaded, do: :persistent_term.get({__MODULE__, :loaded}, 0)

    # stdout is the protocol: mix's shell says nothing; a warning or an error goes to stderr. Again
    # under the lock: a call that waited on another's compile has nothing left to do.
    defp compile(stamp) do
      if stamp > loaded(), do: compiled(stamp)
    end

    defp compiled(stamp) do
      shell = Mix.shell()
      Mix.shell(Mix.Shell.Quiet)

      try do
        Mix.Task.rerun("compile")
      after
        Mix.shell(shell)
      end

      :persistent_term.put({__MODULE__, :loaded}, stamp)
    end

    defp newest_source do
      case Mix.Project.get() && Mix.Project.project_file() do
        nil ->
          0

        file ->
          dir = Path.dirname(file)

          [file | Path.wildcard(Path.join(dir, "lib/**/*.ex"))]
          |> Enum.map(&File.stat!(&1, time: :posix).mtime)
          |> Enum.max()
      end
    end
  end

  # Every tool, made from its noun (`Menard.Verbs.Noun`): the noun's `doc` is what an agent reads
  # before its first call, its `fields` the schema, and the tool's answer its verb's result.
  for verbs <- Menard.Verbs.Noun.modules() do
    noun = Menard.Verbs.Noun.of(verbs)

    fields =
      for {name, type, opts} <- noun.fields,
          do: quote(do: field(unquote(name), unquote(Macro.escape(type)), unquote(opts)))

    defmodule Module.concat(Menard.MCP, Macro.camelize(noun.name)) do
      @moduledoc noun.doc
      use Anubis.Server.Component, type: :tool

      alias Menard.MCP.Reply

      @verbs verbs
      @deadline Menard.Verbs.Noun.deadline(noun)

      schema do
        (unquote_splicing(fields))
      end

      @impl true
      def execute(params, frame), do: Reply.bounded(__MODULE__, params, frame, @deadline)

      def call(params, frame), do: Reply.call(@verbs, params, frame, @deadline)
    end
  end
end
