# only with the optional anubis_mcp, like Menard.MCP
if Code.ensure_loaded?(Anubis.Server) do
  defmodule Menard.MCP.Reply do
    @moduledoc false
    alias Anubis.Server.Response

    def ok(frame, payload), do: {:reply, Response.json(Response.tool(), Menard.jsonable(payload)), frame}
    def fail(frame, message), do: {:reply, Response.error(Response.tool(), message), frame}

    # Every tool's body is its call/2, and execute/2 only puts a deadline on it: over stdio a call
    # that never returns is a server gone silent, and one went past Claude Code's 120s. An edit
    # takes seconds; `run` and `deps` wait on a host's test suite or a fetch, so they get longer.
    def deadline(tool) when tool in [Menard.MCP.Run, Menard.MCP.Deps], do: 600_000
    def deadline(_tool), do: 90_000

    def bounded(tool, params, frame, ms \\ nil) do
      ms = ms || deadline(tool)

      # a raise is an answer too, not a crash of the server's process
      task =
        Task.async(fn ->
          try do
            tool.call(params, frame)
          rescue
            e -> fail(frame, Exception.message(e))
          end
        end)

      case Task.yield(task, ms) || Task.shutdown(task, :brutal_kill) do
        {:ok, reply} ->
          reply

        _timeout ->
          fail(
            frame,
            "#{inspect(tool)} did not finish in #{ms / 1000}s. It may have written its file: read it before retrying"
          )
      end
    end

    # `version` (from the last reply) is checked before the edit, and `force` writes over a stale
    # one: docs/live.md, phase 3
    def staged_write(file, content, params, opts),
      do: Menard.write(file, content, opts ++ [version: params[:version], force: params[:force] == true])
  end

  defmodule Menard.MCP.Rename do
    @moduledoc """
    Rename an identifier across files, AST-aware: every def head, call (local or remote), capture and
    variable named `old` becomes `new`; strings stay, except the docs: in `@doc`/`@moduledoc` a mention
    that reads as code (`old/1`, `A.old(x)` in a doctest, `` `old` ``) is renamed too, unless `docs`
    is false. `only` narrows it to `functions` or `variables`;
    `atoms` also renames `:old`/`old:`, `comments` the whole-word mentions in `#` comments. Only the
    identifier's bytes move. `files` are paths or globs (`lib/**/*.ex`) under the launch root.
    """
    use Anubis.Server.Component, type: :tool
    import Menard.MCP.Reply

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

    def call(params, frame) do
      with {:ok, files} <- Menard.MCP.resolve_all(params.files),
           :ok <- versions(params) do
        opts = [
          atoms: params[:atoms] == true,
          comments: params[:comments] == true,
          docs: params[:docs] != false,
          only: params[:only] && String.to_existing_atom(params[:only])
        ]

        {changed, unchanged} = Enum.split_with(files, &renamed?(&1, params, opts))
        ok(frame, %{"changed" => changed, "unchanged" => unchanged})
      else
        {:error, message} -> fail(frame, message)
      end
    end

    defp versions(%{force: true}), do: :ok

    defp versions(params) do
      pairs =
        for spec <- params[:versions] || [] do
          [file, version] = String.split(spec, "=", parts: 2)
          {:ok, abs} = Menard.MCP.resolve(file)
          {abs, version}
        end

      Menard.check_versions(pairs)
    rescue
      MatchError -> {:error, "versions are FILE=SHA, each FILE under the root"}
    end

    defp renamed?(file, params, opts) do
      source = File.read!(file)

      case Menard.Rename.run(source, params.old, params.new, opts) do
        out when is_binary(out) and out != source ->
          match?(
            {:ok, _reply},
            Menard.write(file, out, did: "rename #{params.old} → #{params.new} in #{Path.basename(file)}")
          )

        _ ->
          false
      end
    end
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

    `doc` and `comment` set the `@doc` or the `#` comment above a clause — prose in `text`, no
    `text` deletes it. They are the only door to either: both are string literals, so the clause
    verbs cannot reach them.

    Two clauses CAN share a head (an insert beside its twin). That is refused with both line
    numbers rather than guessed at; `nth` says which one.

    `insert_at` is the one verb that takes no clause: it adds a function that has NO sibling to
    anchor to. Give it `module` ("Mod.Name", or omit it in a single-module file) and `code`;
    placement follows the code — a `defp` lands with the other private functions, a `def` with the
    public ones — unless `at` ("top"/"bottom") overrides it.

    `move` carries EVERY clause of `name_arity`, with its `@doc`, `@spec` and comment, to the file
    `to`. A missing file is created, its module named from the path or by `as`; `module` picks the
    destination module in a file with several. Aliases and call sites are not touched — `deps` first.
    """
    use Anubis.Server.Component, type: :tool
    import Menard.MCP.Reply

    @impl true
    def execute(params, frame), do: bounded(__MODULE__, params, frame)
    alias Menard.Clause

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
          "doc",
          "comment",
          "get"
        ],
        required: true
      )

      field(:file, :string, required: true)
      field(:name_arity, :string)
      field(:head, :string)
      field(:code, :string)
      field(:module, :string)
      field(:at, :enum, values: ["top", "bottom"])
      field(:visibility, :enum, values: ["public", "private"])
      field(:text, :string)
      field(:nth, :integer)
      field(:to, :string)
      field(:as, :string)
    end

    def call(%{verb: "move"} = params, frame) do
      with {:ok, file} <- Menard.MCP.resolve(params.file),
           {:ok, dest} <- Menard.MCP.resolve(params[:to] || ""),
           # `version` is the source file's: the one the agent's edit came from
           :ok <-
             if(params[:version] && params[:force] != true,
               do: Menard.check_versions([{file, params.version}]),
               else: :ok
             ),
           {:ok, created} <-
             Menard.Move.run(file, dest, params.name_arity, as: params[:as], module: params[:module]) do
        ok(frame, %{
          "did" => "move #{params.name_arity} to #{Path.basename(dest)}",
          "file" => dest,
          "created" => created
        })
      else
        {:error, message} -> fail(frame, message)
      end
    end

    # reads, never writes: the function as written, and the file's version for the edit that follows
    def call(%{verb: "get"} = params, frame) do
      with {:ok, file} <- Menard.MCP.resolve(params.file),
           name_arity when is_binary(name_arity) <-
             params[:name_arity] || {:error, "clause get needs name_arity: the function's name/arity"},
           source = File.read!(file),
           {:ok, got} <-
             Clause.get(source, name_arity, params[:head], if(n = params[:nth], do: [nth: n], else: [])) do
        ok(frame, Map.merge(got, %{file: file, version: Menard.remember(source)}))
      else
        {:error, message} -> fail(frame, message)
      end
    end

    # no head: the whole function, every clause. The reply names each call still left, lib and test,
    # so the agent fixes or deletes those on purpose; tests are never deleted for it.
    def call(%{verb: "delete"} = params, frame) when not is_map_key(params, :head) do
      with {:ok, file} <- Menard.MCP.resolve(params.file),
           name_arity when is_binary(name_arity) <-
             params[:name_arity] || {:error, "clause delete needs name_arity: the function's name/arity"},
           source = File.read!(file),
           out when is_binary(out) <- Clause.delete_function(source, name_arity),
           {:ok, reply} <-
             staged_write(file, out, params,
               did: "delete #{name_arity}, every clause, in #{Path.basename(file)}"
             ) do
        ok(frame, Map.put(reply, :left, Menard.Find.left(Menard.MCP.root(), file, source, name_arity)))
      else
        {:error, message} -> fail(frame, message)
      end
    end

    def call(params, frame) do
      with {:ok, file} <- Menard.MCP.resolve(params.file),
           source <- File.read!(file),
           out when is_binary(out) <- edit(params, source),
           {:ok, reply} <-
             staged_write(file, out, params,
               did:
                 "#{params.verb} #{params[:name_arity] || params[:module] || "-"} `#{params[:head] || params[:at]}` in #{Path.basename(file)}"
             ) do
        ok(frame, reply)
      else
        {:error, message} -> fail(frame, message)
      end
    end

    defp want("public"), do: :public
    defp want(_private), do: :private

    defp edit(%{verb: verb} = p, source) do
      if verb != "insert_at" and is_nil(p[:name_arity]) do
        {:error, "clause #{verb} needs name_arity: the function's name/arity, as outline lists it"}
      else
        # `nth` disambiguates a head two clauses share; without it that is refused, not guessed.
        opts = if n = p[:nth], do: [nth: n], else: []
        # no head is a function's only clause, as `head: ""` is; among several, that is refused with theirs
        edit_clause(verb, Map.put(p, :head, p[:head] || ""), source, p[:code] || "", opts)
      end
    end

    defp edit_clause("replace", p, source, code, opts),
      do: Clause.replace_body(source, p.name_arity, p.head, code, opts)

    defp edit_clause("rewrite", p, source, code, opts),
      do: Clause.rewrite(source, p.name_arity, p.head, code, opts)

    defp edit_clause("delete", p, source, _code, opts), do: Clause.delete(source, p.name_arity, p.head, opts)

    defp edit_clause("insert_after", p, source, code, opts),
      do: Clause.insert_after(source, p.name_arity, p.head, code, opts)

    defp edit_clause("insert_before", p, source, code, opts),
      do: Clause.insert_before(source, p.name_arity, p.head, code, opts)

    defp edit_clause("insert_at", p, source, code, _opts),
      do: Clause.insert_at(source, p[:module], p[:at], code)

    # `text` absent means DELETE for both — the prose is the whole payload, so nothing to give
    # is the only way to say "remove it".
    defp edit_clause("doc", p, source, _code, opts),
      do: Clause.doc(source, p.name_arity, p.head, p[:text], opts)

    defp edit_clause("comment", p, source, _code, opts),
      do: Clause.comment(source, p.name_arity, p.head, p[:text], opts)

    # every clause of the function at once — a half-flipped one does not compile
    defp edit_clause("visibility", p, source, _code, _opts),
      do: Clause.visibility(source, p.name_arity, want(p[:visibility]))

    # the function's, not a clause's: no head. `code` is the signature, absent deletes it
    defp edit_clause("spec", p, source, _code, _opts), do: Clause.spec(source, p.name_arity, p[:code])
  end

  defmodule Menard.MCP.Stmt do
    @moduledoc """
    ONE statement inside a clause body — a line in a `do` block, a step in a `with`, a `case` arm.
    Name the clause (`name_arity` + `head`), then the statement by what is WRITTEN (`match`),
    whitespace-insensitive. `verb` is `insert_after`, `insert_before`, `replace`, `delete` or
    `list`; `code` is the new statement. `comment` sets the `#` comment above it — prose in
    `text`, no `text` removes it.

    A miss lists the statements that are there. An ambiguous match is refused with line numbers
    rather than guessed at; `nth` says which one.
    """
    use Anubis.Server.Component, type: :tool
    import Menard.MCP.Reply

    @impl true
    def execute(params, frame), do: bounded(__MODULE__, params, frame)
    alias Menard.Stmt

    schema do
      field(:version, :string)
      field(:force, :boolean)

      field(:verb, :enum,
        values: ["insert_after", "insert_before", "replace", "delete", "comment", "list"],
        required: true
      )

      field(:file, :string, required: true)
      field(:name_arity, :string, required: true)
      field(:head, :string, required: true)
      field(:match, :string)
      field(:code, :string)
      field(:text, :string)
      field(:nth, :integer)
    end

    def call(%{verb: "list"} = params, frame) do
      with {:ok, file} <- Menard.MCP.resolve(params.file),
           statements when is_list(statements) <- Stmt.list(File.read!(file), params.name_arity, params.head) do
        ok(frame, %{"statements" => statements, "file" => file})
      else
        {:error, message} -> fail(frame, message)
      end
    end

    def call(params, frame) do
      with {:ok, file} <- Menard.MCP.resolve(params.file),
           out when is_binary(out) <- edit(params, File.read!(file)),
           {:ok, reply} <-
             staged_write(file, out, params,
               did: "#{params.verb} `#{params[:match]}` in #{params.name_arity} of #{Path.basename(file)}"
             ) do
        ok(frame, reply)
      else
        {:error, message} -> fail(frame, message)
      end
    end

    defp edit(%{verb: verb} = p, source) do
      opts = if n = p[:nth], do: [nth: n], else: []
      code = p[:code] || ""
      args = [source, p.name_arity, p.head, p[:match] || ""]

      case verb do
        "insert_after" -> apply(Stmt, :insert_after, args ++ [code, opts])
        "insert_before" -> apply(Stmt, :insert_before, args ++ [code, opts])
        "replace" -> apply(Stmt, :replace, args ++ [code, opts])
        "delete" -> apply(Stmt, :delete, args ++ [opts])
        "comment" -> apply(Stmt, :comment, args ++ [p[:text], opts])
      end
    end
  end

  defmodule Menard.MCP.Outline do
    @moduledoc "A file as an outline: modules, defs with arity/kind/head/spec/doc, line spans. Read before editing: each def's `head` is the address `clause` and `stmt` take."
    use Anubis.Server.Component, type: :tool
    import Menard.MCP.Reply

    @impl true
    def execute(params, frame), do: bounded(__MODULE__, params, frame)

    schema do
      field(:file, :string, required: true)
    end

    def call(%{file: file}, frame) do
      with {:ok, abs} <- Menard.MCP.resolve(file),
           content = File.read!(abs),
           {:ok, modules} <- Menard.Outline.run(content) do
        ok(frame, %{"file" => abs, "version" => Menard.remember(content), "modules" => modules})
      else
        {:error, message} when is_binary(message) -> fail(frame, message)
        {:error, reason} -> fail(frame, "not parseable — #{inspect(reason)}")
      end
    end
  end

  defmodule Menard.MCP.Find do
    @moduledoc """
    grep that knows the code: `kind` is `calls` (target: "fun" or "Mod.fun", alias-aware), `defs`
    (target: "name" or "name/arity") or `aliases` (target: "Mod.Sub"). Strings and comments never
    match. `files` may be globs, under the launch root.
    """
    use Anubis.Server.Component, type: :tool
    import Menard.MCP.Reply

    @impl true
    def execute(params, frame), do: bounded(__MODULE__, params, frame)

    schema do
      field(:kind, :enum, values: ["calls", "defs", "aliases"], required: true)
      field(:target, :string, required: true)
      field(:files, {:list, :string}, required: true)
    end

    def call(params, frame) do
      with {:ok, patterns} <- Menard.MCP.resolve_all(params.files),
           {:ok, files} <- Menard.Find.files(patterns) do
        finder =
          case params.kind do
            "calls" -> &Menard.Find.calls(&1, params.target)
            "defs" -> &Menard.Find.defs(&1, params.target)
            "aliases" -> &Menard.Find.aliases(&1, params.target)
          end

        hits =
          Enum.flat_map(files, fn file ->
            file |> File.read!() |> finder.() |> Enum.map(&Map.put(&1, :file, file))
          end)

        ok(frame, %{"hits" => hits})
      else
        {:error, message} -> fail(frame, message)
      end
    end
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

    @impl true
    def execute(params, frame), do: bounded(__MODULE__, params, frame)

    schema do
      field(:verb, :enum, values: ["check", "test", "format", "compile", "credo"], required: true)
      field(:args, {:list, :string})
      field(:dir, :string)
    end

    def call(params, frame) do
      case Menard.MCP.resolve(params[:dir] || ".") do
        {:ok, dir} ->
          # the host's mix is killed short of the tool's own deadline, so the reply says what it was doing
          # instead of the call going silent while mix keeps running
          timeout = deadline(__MODULE__) - 20_000

          ok(
            frame,
            Menard.Run.lean(Menard.Run.result(dir, params.verb, params[:args] || [], timeout: timeout))
          )

        {:error, message} ->
          fail(frame, message)
      end
    end
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

    @impl true
    def execute(params, frame), do: bounded(__MODULE__, params, frame)

    schema do
      field(:version, :string)
      field(:force, :boolean)
      field(:file, :string, required: true)
      field(:code, :string, required: true)
    end

    def call(%{file: file, code: code} = params, frame) do
      case Menard.MCP.resolve(file) do
        {:ok, abs} -> write_file(abs, code, params, frame)
        {:error, message} -> fail(frame, message)
      end
    end

    defp write_file(abs, code, params, frame) do
      if File.exists?(abs) and File.read!(abs) == String.trim_trailing(code, "\n") <> "\n" do
        ok(frame, %{did: "write #{Path.basename(abs)}", file: abs, unchanged: true})
      else
        File.mkdir_p!(Path.dirname(abs))

        case staged_write(abs, code, params, did: "write #{Path.basename(abs)}") do
          {:ok, reply} -> ok(frame, reply)
          {:error, message} -> fail(frame, message)
        end
      end
    end
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

    @impl true
    def execute(params, frame), do: bounded(__MODULE__, params, frame)

    alias Menard.Directive

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

    def call(%{verb: "list"} = params, frame) do
      with {:ok, file} <- Menard.MCP.resolve(params.file),
           found when is_list(found) <- Directive.list(File.read!(file), module: params[:module]) do
        ok(frame, %{"directives" => Enum.map(found, fn {kind, target} -> "#{kind} #{target}" end)})
      else
        {:error, message} -> fail(frame, message)
      end
    end

    def call(params, frame) do
      with {:ok, file} <- Menard.MCP.resolve(params.file),
           {:ok, kind} <- kind(params[:kind]),
           {:ok, target} <- target(params[:target]),
           out when is_binary(out) <- edit(params.verb, File.read!(file), kind, target, params),
           {:ok, reply} <-
             staged_write(file, out, params,
               did: "#{params.verb} #{kind} #{target} in #{Path.basename(file)}"
             ) do
        ok(frame, reply)
      else
        {:error, message} -> fail(frame, message)
      end
    end

    defp edit("add", source, kind, target, params),
      do: Directive.add(source, kind, target, module: params[:module], args: params[:args])

    defp edit("replace", source, kind, target, params),
      do: Directive.replace(source, kind, target, module: params[:module], args: params[:args])

    defp edit("remove", source, kind, target, params),
      do: Directive.remove(source, kind, target, module: params[:module])

    defp kind(k) when k in ["alias", "import", "require", "use", "doctest"],
      do: {:ok, String.to_existing_atom(k)}

    defp kind(_k), do: {:error, "kind is required: alias, import, require or use"}

    defp target(t) when is_binary(t) and t != "", do: {:ok, t}
    defp target(_t), do: {:error, "target is required — the module the directive names"}
  end

  defmodule Menard.MCP.Attr do
    @moduledoc """
    Module attributes — the tables a module keeps at the top (`@hints`, `@colors`, `@panes`), which
    no clause verb reaches because an attribute is not a clause. `verb` is `get`, `set` (replaces the
    value, or adds the attribute above the first definition when missing), `delete`, `list`, or
    `comment` (the `#` comment above it — prose in `text`, no `text` deletes it). Addressed by
    `name`; a name several attributes share (`@doc`/`@impl`/`@spec` repeat per clause) is refused
    with their lines — those belong to the clause verbs.
    """
    use Anubis.Server.Component, type: :tool
    import Menard.MCP.Reply

    @impl true
    def execute(params, frame), do: bounded(__MODULE__, params, frame)

    alias Menard.Attr

    schema do
      field(:version, :string)
      field(:force, :boolean)
      field(:verb, :enum, values: ["get", "set", "replace", "delete", "list", "comment"], required: true)
      field(:file, :string, required: true)
      field(:name, :string)
      field(:value, :string)
      field(:text, :string)
      field(:module, :string)
    end

    def call(%{verb: verb} = params, frame) when verb in ["get", "list"] do
      with {:ok, file} <- Menard.MCP.resolve(params.file),
           source <- File.read!(file),
           result <- read(verb, source, params) do
        case result do
          {:error, :missing} ->
            fail(frame, missing(params))

          {:error, message} ->
            fail(frame, message)

          found when is_list(found) ->
            ok(frame, %{"attributes" => Enum.map(found, fn {n, l} -> "@#{n} (line #{l})" end)})

          text ->
            ok(frame, %{"value" => text})
        end
      else
        {:error, message} -> fail(frame, message)
      end
    end

    def call(params, frame) do
      # the name may come with its `@` or without; the reply names it once either way
      at = "@" <> String.trim_leading(params[:name] || "", "@")

      with {:ok, file} <- Menard.MCP.resolve(params.file),
           out when is_binary(out) <- write(params.verb, File.read!(file), params),
           {:ok, reply} <-
             staged_write(file, out, params, did: "#{params.verb} #{at} in #{Path.basename(file)}") do
        ok(frame, reply)
      else
        {:error, :missing} -> fail(frame, missing(params))
        {:error, message} -> fail(frame, message)
      end
    end

    # `attr :product, …` in a component is Phoenix's declaration, not a module attribute: bench4
    # new-component.B.haiku tried to delete one here and was told only that there was no @product
    defp missing(params) do
      name = String.trim_leading(params[:name] || "", "@")

      declared? =
        with {:ok, file} <- Menard.MCP.resolve(params.file),
             {:ok, source} <- File.read(file),
             do: source =~ ~r/^\s*(attr|slot)\s+:#{Regex.escape(name)}\b/m,
             else: (_ -> false)

      if declared?,
        do:
          "no @#{name} in this module; `attr :#{name}` here is a Phoenix component declaration, which goes " <>
            "with the def below it (clause get/delete/move carry it), and stmt reaches it as a statement of the module",
        else: "no @#{name} in this module"
    end

    defp read("get", source, p), do: Attr.get(source, p[:name] || "", module: p[:module])
    defp read("list", source, p), do: Attr.list(source, module: p[:module])

    defp write("set", source, p), do: Attr.set(source, p[:name] || "", p[:value] || "", module: p[:module])
    # every other tool calls it replace, and agents do too
    defp write("replace", source, p), do: write("set", source, p)
    defp write("delete", source, p), do: Attr.delete(source, p[:name] || "", module: p[:module])
    defp write("comment", source, p), do: Attr.comment(source, p[:name] || "", p[:text], module: p[:module])
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

    @impl true
    def execute(params, frame), do: bounded(__MODULE__, params, frame)

    alias Menard.Block

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

    def call(%{verb: "list"} = params, frame) do
      with {:ok, file} <- Menard.MCP.resolve(params.file),
           found when is_list(found) <- Block.list(File.read!(file), module: params[:module]) do
        ok(frame, %{"blocks" => Enum.map(found, fn {n, l, line} -> "#{n} #{inspect(l)} (line #{line})" end)})
      else
        {:error, message} -> fail(frame, message)
      end
    end

    def call(%{verb: "get"} = params, frame) do
      case Menard.MCP.resolve(params.file) do
        {:ok, file} -> get(File.read!(file), params[:name] || "", params, frame)
        {:error, message} -> fail(frame, message)
      end
    end

    def call(params, frame) do
      # in a test file, a block added with no name is a test: what an agent leaving `name` out means
      params =
        if params.verb == "add" and params[:name] in [nil, ""] and String.ends_with?(params.file, "_test.exs"),
          do: Map.put(params, :name, "test"),
          else: params

      with {:ok, file} <- Menard.MCP.resolve(params.file),
           out when is_binary(out) <- edit(params, File.read!(file)),
           {:ok, reply} <-
             staged_write(file, out, params, did: "#{params.verb} #{params[:name]} in #{Path.basename(file)}") do
        ok(frame, reply)
      else
        {:error, message} -> fail(frame, message)
      end
    end

    defp edit(%{verb: "add"} = p, source),
      do:
        Block.add(source, p[:name] || "", p[:label], p[:code] || "",
          in: p[:in],
          module: p[:module],
          args: p[:args],
          tag: p[:tag]
        )

    defp edit(%{verb: "relabel"} = p, source),
      do: Block.relabel(source, p[:name] || "", p[:label] || "", p[:new_label] || "", module: p[:module])

    defp edit(%{verb: "replace"} = p, source),
      do: Block.replace(source, p[:name] || "", p[:code] || "", where(p))

    defp edit(%{verb: "delete"} = p, source), do: Block.delete(source, p[:name] || "", where(p))
    defp edit(%{verb: verb}, _source), do: {:error, "block has no verb #{inspect(verb)}"}

    defp where(params), do: [module: params[:module], label: params[:label]]

    # no label among several: every one, not a refusal to pick (bench3 new-component.B.haiku)
    defp get(source, name, params, frame) do
      case params[:label] || Block.get_all(source, name, where(params)) do
        [_, _ | _] = all ->
          ok(frame, %{"blocks" => all})

        _ ->
          case Block.get(source, name, where(params)) do
            text when is_binary(text) -> ok(frame, %{"body" => text})
            {:error, message} -> fail(frame, message)
          end
      end
    end
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
      diff and the compile. A fetch that fails puts mix.exs back.
    - `upgrade`: `apps` updated (all when none are named), through the host's own
      `mix igniter.upgrade` when it has Igniter. `to` rewrites one app's requirement first.

    `dir` is the mix project, under the root (default: the root).
    """
    use Anubis.Server.Component, type: :tool
    import Menard.MCP.Reply

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

    def call(%{verb: "add"} = params, frame) do
      case Menard.MCP.resolve(params[:dir] || ".") do
        {:ok, dir} -> answer(frame, Menard.MixDeps.add_in(dir, params[:spec] || ""))
        {:error, message} -> fail(frame, message)
      end
    end

    def call(%{verb: "upgrade"} = params, frame) do
      case Menard.MCP.resolve(params[:dir] || ".") do
        {:ok, dir} -> answer(frame, Menard.MixDeps.upgrade_in(dir, params[:apps] || [], params[:to]))
        {:error, message} -> fail(frame, message)
      end
    end

    def call(params, frame) do
      with {:ok, file} <- Menard.MCP.resolve(params[:file] || ""),
           %{} = report <-
             Menard.Deps.of(File.read!(file), params[:name_arity] || "", module: params[:module]) do
        ok(frame, report)
      else
        {:error, message} -> fail(frame, message)
      end
    end

    defp answer(frame, %{ok: true} = result), do: ok(frame, result)
    defp answer(frame, result), do: fail(frame, JSON.encode!(result))
  end

  defmodule Menard.MCP.Module do
    @moduledoc """
    Whole modules inside a file. `verb` is `add` (a complete `defmodule` appended after the last
    one; a name the file already defines is refused), `replace` (the module named `module` swapped
    for `code`, a complete `defmodule` of that name; its neighbours untouched), `list`, or `comment`
    (the `#` comment at the top of a module's body, or with `above` the one over its `defmodule`;
    `module`, or the file's one). `clause insert_at`
    puts a function INTO a module, and `write` replaces the whole file.
    """
    use Anubis.Server.Component, type: :tool
    import Menard.MCP.Reply

    @impl true
    def execute(params, frame), do: bounded(__MODULE__, params, frame)

    schema do
      field(:version, :string)
      field(:force, :boolean)
      field(:verb, :enum, values: ["add", "replace", "list", "comment"], required: true)
      field(:file, :string, required: true)
      field(:code, :string)
      field(:module, :string)
      field(:text, :string)
      field(:above, :boolean)
    end

    def call(%{verb: "list"} = params, frame) do
      with {:ok, file} <- Menard.MCP.resolve(params.file),
           names when is_list(names) <- Menard.Module.list(File.read!(file)) do
        ok(frame, %{"modules" => names})
      else
        {:error, message} -> fail(frame, message)
      end
    end

    def call(%{verb: verb} = params, frame) when verb in ["add", "replace", "comment"] do
      with {:ok, file} <- Menard.MCP.resolve(params.file),
           out when is_binary(out) <- edit(verb, File.read!(file), params),
           {:ok, reply} <-
             staged_write(file, out, params,
               did: "#{verb} #{params[:module] || "a module"} in #{Path.basename(file)}"
             ) do
        ok(frame, reply)
      else
        {:error, message} -> fail(frame, message)
      end
    end

    def call(%{verb: verb}, frame), do: fail(frame, "module has no verb #{inspect(verb)}")

    defp edit("add", source, p), do: Menard.Module.add(source, p[:code] || "")
    defp edit("replace", source, p), do: Menard.Module.replace(source, p[:module] || "", p[:code] || "")

    defp edit("comment", source, p),
      do: Menard.Module.comment(source, p[:module], p[:text], above: p[:above] == true)
  end
end
