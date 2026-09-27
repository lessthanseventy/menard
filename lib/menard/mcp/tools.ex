# only with the optional anubis_mcp, like Menard.MCP
if Code.ensure_loaded?(Anubis.Server) do
  defmodule Menard.MCP.Reply do
    @moduledoc false
    alias Anubis.Server.Response

    def ok(frame, payload), do: {:reply, Response.json(Response.tool(), Menard.jsonable(payload)), frame}
    def fail(frame, message), do: {:reply, Response.error(Response.tool(), message), frame}

    @doc "A verb's result (`Menard.Verbs`) as the tool's answer: the reply as is, the reason as a tool error."
    def answer(frame, {:ok, reply}), do: ok(frame, reply)
    def answer(frame, {:error, reason}), do: fail(frame, reason)

    @doc "The tool's params as the verb takes them: every path resolves under the launch root."
    def params(params), do: Map.put(params, :root, Menard.MCP.root())

    # Every tool's body is its call/2, and execute/2 only puts a deadline on it: over stdio a call
    # that never returns is a server gone silent, and one went past Claude Code's 120s. An edit
    # takes seconds; `run` and `deps` wait on a host's test suite or a fetch, so they get longer.
    def deadline(tool) when tool in [Menard.MCP.Run, Menard.MCP.Deps], do: 600_000
    def deadline(_tool), do: 90_000

    def bounded(tool, params, frame, ms \\ nil) do
      ms = ms || deadline(tool)
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
  end

  defmodule Menard.MCP.Rename do
    @moduledoc """
    Rename an identifier across files, AST-aware: every def head, call (local or remote), capture and
    variable named `old` becomes `new`; strings stay, except the docs: in `@doc`/`@moduledoc` a mention
    that reads as code (`old/1`, `A.old(x)` in a doctest, `` `old` ``) is renamed too, unless `docs`
    is false. `only` narrows it to `functions` or `variables`;
    `atoms` also renames `:old`/`old:`, `comments` the whole-word mentions in `#` comments. Only the
    identifier's bytes move. `files` are paths or globs (`lib/**/*.ex`) under the launch root. The
    reply lists the files `changed` (each with its version and stages), `unchanged`, and `skipped`
    (not parseable or not written, with why).
    """
    use Anubis.Server.Component, type: :tool
    import Menard.MCP.Reply
    alias Menard.Verbs

    @impl true
    def execute(params, frame), do: bounded(__MODULE__, params, frame)

    schema do
      field(:old, :string, required: true)
      field(:new, :string, required: true)
      field(:files, {:list, :string}, required: true)
      # `FILE=SHA` per file, from each one's last reply; all checked before any file is written
      field(:versions, {:list, :string})
      field(:force, :boolean)
      field(:only, :enum, values: ["functions", "variables"])
      field(:atoms, :boolean)
      field(:comments, :boolean)
      field(:docs, :boolean)
    end

    def call(params, frame), do: answer(frame, Verbs.Rename.run(params(params)))
  end

  defmodule Menard.MCP.Clause do
    @moduledoc """
    Edit ONE clause. `verb` is `replace` (its body := `code`), `rewrite` (the WHOLE clause, head
    included — the verb for changing args or adding a guard), `delete`, `insert_after` or
    `insert_before` (`code` is the new clause). Address it by `name_arity` ("go/1", or "Mod.go/1" in
    a file with several modules — an unqualified name that several modules define is refused) and
    `head`: the clause's CURRENT head as `outline` prints it (args as written, guard optional, parens
    optional), or "" for a zero-arity clause or a function's only one. What it becomes goes in `code`:
    a `rewrite` from `total(cart)` to `total(cart, rate)` is `name_arity: "total/1"`, `head: "cart"`.
    A miss lists the heads that exist. Only the clause's bytes change. An ExUnit `test` is a macro,
    not a clause: `block` reaches it.

    `visibility` flips a function public/private — EVERY clause of it, since a half-flipped
    function does not compile; going private also drops an attached `@doc`, which Elixir discards
    with a warning. Give it `name_arity` and `visibility`.

    With no `head`, `get` answers with the whole function as written (every clause, with the
    `@doc`/`@spec`/comments above it) and `delete` deletes it, answering with `left`: each call to it
    still to fix. With a `head`, each takes that one clause.

    `spec` sets the function's `@spec` (`code` is the signature; no `code` deletes it).

    Two clauses CAN share a head (an insert beside its twin). That is refused with both line
    numbers rather than guessed at; `nth` says which one.

    `insert_at` is the one verb that takes no clause: it adds a function that has NO sibling to
    anchor to. Give it `module` ("Mod.Name", or omit it in a single-module file) and `code`;
    placement follows the code — a `defp` lands with the other private functions, a `def` with the
    public ones — unless `at` ("top"/"bottom") overrides it.

    `move` takes functions to the file `to`: `name_arity` is one or several (a list, or "a/1,b/2"),
    so splitting a big module is ONE call per new module. Each goes with every clause, its `@doc`,
    `@spec` and comment. What the moved code needs comes along: the private helpers only it calls,
    the attributes it reads, the alias/import/require lines it uses; a call back to a public
    function that stays, and `__MODULE__`, now name the source. A private helper that a function
    staying behind also calls is refused, naming both (move that caller too, or make the helper
    public first). `delegate: true` leaves a `defdelegate` (defaults kept) for each public function
    moved, so the source's API and every caller keep working; without it, `left` names each call
    now pointing at nothing. A missing file is created, its module named from the path or by `as`,
    with `moduledoc` as its @moduledoc; `module` picks the destination module in a file with
    several. It answers `{did, created, moved, carried, attributes, directives, unresolved,
    qualified, delegated, left, to, from}`: `to` and `from` are each file's reply, version and
    stages; `unresolved` each call a `use` or an import without `only:` may answer, not copied.
    """
    use Anubis.Server.Component, type: :tool
    import Menard.MCP.Reply
    alias Menard.Verbs

    @impl true
    def execute(params, frame), do: bounded(__MODULE__, params, frame)

    schema do
      field(:version, :string)
      field(:force, :boolean)

      field(:verb, :enum,
        values: [
          "replace",
          "rewrite",
          "delete",
          "insert_after",
          "insert_before",
          "insert_at",
          "move",
          "visibility",
          "spec",
          "get"
        ],
        required: true
      )

      field(:file, :string, required: true)
      # `move` takes several: a list, or "a/1,b/2"
      field(:name_arity, {:either, {:string, {:list, :string}}})
      field(:head, :string)
      field(:code, :string)
      field(:module, :string)
      field(:at, :enum, values: ["top", "bottom"])
      field(:visibility, :enum, values: ["public", "private"])
      field(:nth, :integer)
      field(:to, :string)
      field(:as, :string)
      field(:moduledoc, :string)
      field(:delegate, :boolean)
    end

    def call(params, frame), do: answer(frame, Verbs.Clause.run(params(params)))
  end

  defmodule Menard.MCP.Stmt do
    @moduledoc """
    ONE statement inside a clause body — a line in a `do` block, a step in a `with`, a `case` arm.
    Name the clause (`name_arity` + `head`), then the statement by what is WRITTEN (`match`),
    whitespace-insensitive. `verb` is `insert_after`, `insert_before`, `replace`, `delete` or
    `list`; `code` is the new statement.

    A miss lists the statements that are there. An ambiguous match is refused with line numbers
    rather than guessed at; `nth` says which one.
    """
    use Anubis.Server.Component, type: :tool
    import Menard.MCP.Reply
    alias Menard.Verbs

    @impl true
    def execute(params, frame), do: bounded(__MODULE__, params, frame)

    schema do
      field(:version, :string)
      field(:force, :boolean)

      field(:verb, :enum,
        values: ["insert_after", "insert_before", "replace", "delete", "list"],
        required: true
      )

      field(:file, :string, required: true)
      field(:name_arity, :string, required: true)
      field(:head, :string, required: true)
      field(:match, :string)
      field(:code, :string)
      field(:nth, :integer)
    end

    def call(params, frame), do: answer(frame, Verbs.Stmt.run(params(params)))
  end

  defmodule Menard.MCP.Outline do
    @moduledoc """
    A file as an outline (`file`): modules, defs with arity/kind/head/spec/doc, line spans. Read
    before editing: each def's `head` is the address `clause` and `stmt` take. `verb: "map"`: every
    module under a `lib/` of the project, its file and public functions (a dozen each unless `all`),
    the map an agent starts with. `verb: "where"`: for each `FILE:LINE` in `at`, the module and
    function whose lines hold it — what a grep hit sits in.
    """
    use Anubis.Server.Component, type: :tool
    import Menard.MCP.Reply
    alias Menard.Verbs

    @impl true
    def execute(params, frame), do: bounded(__MODULE__, params, frame)

    schema do
      field(:verb, :enum, values: ["file", "map", "where"])
      field(:file, :string)
      field(:at, {:list, :string})
      field(:all, :boolean)
    end

    def call(params, frame), do: answer(frame, Verbs.Outline.run(params(params)))
  end

  defmodule Menard.MCP.Find do
    @moduledoc """
    grep that knows the code: `kind` is `calls` (target: "fun" or "Mod.fun", alias-aware), `defs`
    (target: "name" or "name/arity") or `aliases` (target: "Mod.Sub"). Strings and comments never
    match. `files` may be globs, under the launch root.
    """
    use Anubis.Server.Component, type: :tool
    import Menard.MCP.Reply
    alias Menard.Verbs

    @impl true
    def execute(params, frame), do: bounded(__MODULE__, params, frame)

    schema do
      field(:kind, :enum, values: ["calls", "defs", "aliases"], required: true)
      field(:target, :string, required: true)
      field(:files, {:list, :string}, required: true)
    end

    def call(params, frame), do: answer(frame, Verbs.Find.run(params(params)))
  end

  defmodule Menard.MCP.Run do
    @moduledoc """
    Run a verb in a mix project under the root and get ONE structured answer: `check` (the
    project's `mix precommit`: format, warnings-as-errors, tests), `test` (args: files, file:line,
    and any `mix test` flag), `format` (args: files), `compile`, `credo` (args: files, `--strict`,
    `--changed` for the lines changed since the last commit). `dir` defaults to the root.

    Every verb answers `failures` in one shape: `{kind, message, at}` — `kind` is `test`, `error`,
    `warning`, `format` or `credo`, `message` says why, `at` is `file:line`. A test failure adds `name`,
    `module`, `source` (the test as written) and, for an assertion, `code`, `left`, `right`.
    """
    use Anubis.Server.Component, type: :tool
    import Menard.MCP.Reply
    alias Menard.Verbs

    @impl true
    def execute(params, frame), do: bounded(__MODULE__, params, frame)

    schema do
      field(:verb, :enum, values: ["check", "test", "format", "compile", "credo"], required: true)
      field(:args, {:list, :string})
      field(:dir, :string)
    end

    # the host's mix is killed short of the tool's own deadline, so the reply says what it was doing
    # instead of the call going silent while mix keeps running
    def call(params, frame),
      do:
        answer(
          frame,
          Verbs.Run.run(params |> params() |> Map.put(:timeout, deadline(__MODULE__) - 20_000))
        )
  end

  defmodule Menard.MCP.Write do
    @moduledoc """
    Write a WHOLE file: `code` becomes the entire content of `file`. The verb for what the clause
    verbs structurally cannot do — a NEW module has no clause to address and no file to patch — and
    for a rewrite so total that patching is the wrong tool (a fixture, a generated table). Elixir
    that does not parse is refused before it reaches disk; the file is then formatted with the
    target project's own formatter.
    """
    use Anubis.Server.Component, type: :tool
    import Menard.MCP.Reply
    alias Menard.Verbs

    @impl true
    def execute(params, frame), do: bounded(__MODULE__, params, frame)

    schema do
      field(:version, :string)
      field(:force, :boolean)
      field(:file, :string, required: true)
      field(:code, :string, required: true)
    end

    def call(params, frame), do: answer(frame, Verbs.Write.run(params(params)))
  end

  defmodule Menard.MCP.Directive do
    @moduledoc """
    `alias` / `import` / `require` / `use`, placed where they belong. `verb` is `add` (in sorted
    position inside its own block, opening the block in Elixir's conventional order — use, import,
    alias, require — when there isn't one), `replace` (new `args` for one that is there, in
    place, in one step), `remove`, or `list` (what the module already pulls in).
    `kind` is which directive; `target` the module; `args` the rest as written ("only: [pad: 3]",
    "as: Thing"). Adding one that is already there is a no-op, never a duplicate line. `module` names
    which module in a file that has several.
    """
    use Anubis.Server.Component, type: :tool
    import Menard.MCP.Reply
    alias Menard.Verbs

    @impl true
    def execute(params, frame), do: bounded(__MODULE__, params, frame)

    schema do
      field(:version, :string)
      field(:force, :boolean)
      field(:verb, :enum, values: ["add", "replace", "remove", "list"], required: true)
      field(:file, :string, required: true)
      field(:kind, :enum, values: ["alias", "import", "require", "use", "doctest"])
      field(:target, :string)
      field(:args, :string)
      field(:module, :string)
    end

    def call(params, frame), do: answer(frame, Verbs.Directive.run(params(params)))
  end

  defmodule Menard.MCP.Attr do
    @moduledoc """
    Module attributes — the tables a module keeps at the top (`@hints`, `@colors`, `@panes`), which
    no clause verb reaches because an attribute is not a clause. `verb` is `get`, `set` (replaces the
    value, or adds the attribute above the first definition when missing), `delete` or `list`.
    Addressed by `name`; a name several attributes share (`@doc`/`@impl`/`@spec` repeat per clause)
    is refused with their lines — those belong to the clause verbs.
    """
    use Anubis.Server.Component, type: :tool
    import Menard.MCP.Reply
    alias Menard.Verbs

    @impl true
    def execute(params, frame), do: bounded(__MODULE__, params, frame)

    schema do
      field(:version, :string)
      field(:force, :boolean)
      field(:verb, :enum, values: ["get", "set", "delete", "list"], required: true)
      field(:file, :string, required: true)
      field(:name, :string)
      field(:value, :string)
      field(:module, :string)
    end

    def call(params, frame), do: answer(frame, Verbs.Attr.run(params(params)))
  end

  defmodule Menard.MCP.Block do
    @moduledoc """
    The body of a macro's `do` block — `schema do`, `describe "…" do`, `test "…" do`. Not a clause,
    so no clause verb reaches one. `verb` is `get`, `replace` (body := `code`), `list`, or `relabel`
    (`label` becomes `new_label`). `label` is the macro's first string argument, which is what makes
    `describe`/`test` addressable; several blocks of one name with no label is refused, listing them.
    `add` writes a NEW block — at the end of the block named by `in` (a describe, by its label), else
    after the last sibling of that name, else at the end of the module.
    """
    use Anubis.Server.Component, type: :tool
    import Menard.MCP.Reply
    alias Menard.Verbs

    @impl true
    def execute(params, frame), do: bounded(__MODULE__, params, frame)

    schema do
      field(:version, :string)
      field(:force, :boolean)
      field(:verb, :enum, values: ["get", "replace", "add", "delete", "list", "relabel"], required: true)
      field(:file, :string, required: true)
      field(:name, :string)
      field(:code, :string)
      field(:label, :string)
      field(:new_label, :string)
      field(:args, :string)
      field(:in, :string)
      field(:module, :string)
      field(:tag, :string)
    end

    def call(params, frame), do: answer(frame, Verbs.Block.run(params(params)))
  end

  defmodule Menard.MCP.Deps do
    @moduledoc """
    Dependencies, both kinds. `verb` is:

    - `refs` (the default): what one function references — the read before a move. Give `file` and
      `name_arity`. Returns the local calls it makes (each with `shared_with`: the OTHER functions
      here that also call it, so a helper with an empty list can travel and one with entries cannot),
      the remote calls, the modules whose aliases must travel, and the attributes it reads.
    - `add`: a project dependency, `spec` as written in mix.exs (`{:req, "~> 0.5"}`) or a bare name
      looked up on Hex. Written into the deps list, fetched and compiled; the answer carries the lock
      diff and the compile, `ok` false when either failed. A fetch that fails puts mix.exs back.
    - `upgrade`: `apps` updated (all when none are named), through the host's own
      `mix igniter.upgrade` when it has Igniter. `to` rewrites one app's requirement first.

    `dir` is the mix project, under the root (default: the root).
    """
    use Anubis.Server.Component, type: :tool
    import Menard.MCP.Reply
    alias Menard.Verbs

    @impl true
    def execute(params, frame), do: bounded(__MODULE__, params, frame)

    schema do
      field(:verb, :enum, values: ["refs", "add", "upgrade"])
      field(:file, :string)
      field(:name_arity, :string)
      field(:module, :string)
      field(:spec, :string)
      field(:apps, {:list, :string})
      field(:to, :string)
      field(:dir, :string)
    end

    def call(params, frame), do: answer(frame, Verbs.Deps.run(params(params)))
  end

  defmodule Menard.MCP.Module do
    @moduledoc """
    Whole modules inside a file. `verb` is `add` (a complete `defmodule` appended after the last
    one; a name the file already defines is refused), `replace` (the module named `module` swapped
    for `code`, a complete `defmodule` of that name; its neighbours untouched) or `list`. `clause
    insert_at` puts a function INTO a module, and `write` replaces the whole file.
    """
    use Anubis.Server.Component, type: :tool
    import Menard.MCP.Reply
    alias Menard.Verbs

    @impl true
    def execute(params, frame), do: bounded(__MODULE__, params, frame)

    schema do
      field(:version, :string)
      field(:force, :boolean)
      field(:verb, :enum, values: ["add", "replace", "list"], required: true)
      field(:file, :string, required: true)
      field(:code, :string)
      field(:module, :string)
    end

    def call(params, frame), do: answer(frame, Verbs.Module.run(params(params)))
  end
end
