defmodule Menard.MixDeps do
  @moduledoc """
  A project's dependencies in its `mix.exs`, edited the way every verb edits: the deps list is
  found in the tree (inline under `project/0`'s `deps:`, or the body of the function that key
  calls), and only its range is patched. Nothing re-renders the file, so its comments and layout
  stay as written.

  `lock_diff/2` compares two `mix.lock` texts by version, read as data and never evaluated.
  """

  import Menard.Source, only: [parse: 1]

  alias Menard.Clause

  @doc """
  Add `spec`, a dependency as written in mix.exs (`{:req, "~> 0.5", only: :test}`), after the
  list's last entry, on its own line and at its indent. A dependency already there is refused,
  quoted as written.
  """
  @spec add(String.t(), String.t()) :: String.t() | {:error, String.t()}
  def add(source, spec) do
    with {:ok, app} <- spec_app(spec),
         {:ok, list} <- deps_list(source) do
      case Enum.find(elements(list), &(dep_app(&1) == app)) do
        nil ->
          append(source, list, String.trim(spec))

        dep ->
          {:error, "#{app} is already a dependency: #{Menard.Source.slice(source, Sourceror.get_range(dep))}"}
      end
    end
  end

  @doc "Change the version requirement of `app`'s dependency — its bytes and nothing else."
  @spec set_requirement(String.t(), String.t(), String.t()) :: String.t() | {:error, String.t()}
  def set_requirement(source, app, requirement) do
    app = String.to_atom(app)

    with {:ok, list} <- deps_list(source),
         dep when not is_nil(dep) <- Enum.find(elements(list), &(dep_app(&1) == app)) do
      case requirement_node(dep) do
        {:__block__, _, [current]} = node when is_binary(current) ->
          range = Menard.Source.range(node, source)
          patch(source, [%{range: range, change: inspect(requirement)}])

        _ ->
          {:error, "#{app} has no version requirement to change (a path or git dependency)"}
      end
    else
      nil -> {:error, "#{app} is not a dependency in this mix.exs"}
      error -> error
    end
  end

  @doc """
  What changed between two mix.lock texts: `%{added, removed, changed}`, each entry naming the app
  and its version (a git dependency's is its commit, shortened).
  """
  @spec lock_diff(String.t() | nil, String.t() | nil) :: map()
  def lock_diff(before, after_) do
    old = lock_versions(before)
    new = lock_versions(after_)

    %{
      added: for({app, v} <- Enum.sort(new), not Map.has_key?(old, app), do: %{app: app, version: v}),
      removed: for({app, v} <- Enum.sort(old), not Map.has_key?(new, app), do: %{app: app, version: v}),
      changed:
        for(
          {app, v} <- Enum.sort(new),
          Map.has_key?(old, app) and old[app] != v,
          do: %{app: app, from: old[app], to: v}
        )
    }
  end

  # -- finding the list -----------------------------------------------------

  defp deps_list(source) do
    with {:ok, _ast} <- parse(source),
         {:ok, project} <- Clause.find(source, "project/0", "", []) do
      case keyword_value(body(project.node), :deps) do
        {:__block__, _, [list]} = node when is_list(list) ->
          {:ok, node}

        {name, _, args} when is_atom(name) and args in [[], nil] ->
          with {:ok, fun} <- Clause.find(source, "#{name}/0", "", []) do
            case body(fun.node) do
              {:__block__, _, [list]} = node when is_list(list) -> {:ok, node}
              _ -> {:error, "#{name}/0 does not return a literal list"}
            end
          end

        _ ->
          {:error, "no `deps:` list in project/0"}
      end
    end
  end

  defp body({_kind, _meta, [_head, [{_do, body}]]}), do: body
  defp body(_node), do: nil

  defp keyword_value({:__block__, _, [pairs]}, key) when is_list(pairs) do
    Enum.find_value(pairs, fn
      {{:__block__, _, [^key]}, value} -> value
      _ -> nil
    end)
  end

  defp keyword_value(_node, _key), do: nil

  defp elements({:__block__, _, [list]}), do: list

  defp dep_app({:__block__, _, [{app, _}]}), do: unwrap(app)
  defp dep_app({:{}, _, [app | _]}), do: unwrap(app)
  defp dep_app(_node), do: nil

  defp requirement_node({:__block__, _, [{_app, req}]}), do: req
  defp requirement_node({:{}, _, [_app, req | _]}), do: req

  defp unwrap({:__block__, _, [atom]}) when is_atom(atom), do: atom
  defp unwrap(_node), do: nil

  defp spec_app(spec) do
    with {:ok, node} <- parse(spec),
         app when is_atom(app) and not is_nil(app) <- dep_app(node) do
      {:ok, app}
    else
      _ -> {:error, "a dependency is written as a tuple, `{:app, \"~> 1.0\"}`, got: #{String.trim(spec)}"}
    end
  end

  # -- writing ---------------------------------------------------------------

  defp append(source, list, spec) do
    case elements(list) do
      [] ->
        range = Menard.Source.range(list, source)
        patch(source, [%{range: range, change: "[" <> spec <> "]"}])

      [first | _] = elems ->
        %{start: [line: _, column: col]} = Sourceror.get_range(first)

        %{end: [line: b, column: c]} =
          elems |> List.last() |> Menard.Source.range(source)

        line = source |> String.split("\n") |> Enum.at(b - 1)
        rest = line |> String.slice((c - 1)..-1//1) |> String.trim_leading()
        comma = if String.starts_with?(rest, ","), do: [], else: [insert(b, c, ",")]

        # the list closes on this line (`…}]`): the new entry goes straight after the last one;
        # otherwise at the end of its line, so a trailing `# why` stays with the entry it explains
        if String.contains?(rest |> String.split("#") |> hd(), "]") do
          patch(source, [insert(b, c, ", " <> spec)])
        else
          indent = String.duplicate(" ", col - 1)
          eol = String.length(line) + 1

          # at one position two insertions have no order: a comma owed at the line end is written first
          case comma do
            [_] when c == eol -> patch(source, [insert(b, eol, ",\n" <> indent <> spec)])
            _ -> patch(source, comma ++ [insert(b, eol, "\n" <> indent <> spec)])
          end
        end
    end
  end

  defp insert(line, column, text),
    do: %{range: %{start: [line: line, column: column], end: [line: line, column: column]}, change: text}

  defp patch(source, patches),
    do: Sourceror.patch_string(source, Enum.map(patches, &Map.put(&1, :preserve_indentation, false)))

  # -- mix.lock ---------------------------------------------------------------

  defp lock_versions(text) when text in [nil, ""], do: %{}

  defp lock_versions(text) do
    # mix.lock quotes every key, and the parser warns about each one that did not need it
    case Code.string_to_quoted(text, emit_warnings: false) do
      {:ok, {:%{}, _, pairs}} -> Map.new(pairs, fn {app, entry} -> {to_string(app), lock_version(entry)} end)
      _ -> %{}
    end
  end

  defp lock_version({:{}, _, [:hex, _name, version | _]}), do: version
  defp lock_version({:{}, _, [:git, _url, ref | _]}) when is_binary(ref), do: String.slice(ref, 0, 7)
  defp lock_version(_entry), do: "?"

  @doc """
  `add/2` in the project at `dir`: write mix.exs, `mix deps.get`, and answer
  `%{ok, dep, lock, compile}` — the lock diff and the compile result. A bare name (`req`) takes the
  spec `mix hex.info` prints. A fetch that fails puts mix.exs back as it was.
  """
  @spec add_in(String.t(), String.t()) :: map()
  def add_in(dir, spec_or_name) do
    source = File.read!(Path.join(dir, "mix.exs"))

    with {:ok, spec} <- resolve_spec(dir, String.trim(spec_or_name)),
         out when is_binary(out) <- add(source, spec) do
      update(dir, source, out, ["deps.get"], %{dep: spec})
    else
      {:error, message} -> %{ok: false, error: message}
    end
  end

  @doc """
  Update `apps` (every dependency when none are named) in the project at `dir`, answering like
  `add_in/2` plus `via`, the command that ran. Through the host's own `mix igniter.upgrade` when its
  lock has Igniter, so each package's upgrade tasks run too; else `mix deps.update`. `to` rewrites
  one app's requirement first — the way across a major version — and is put back if the update fails.
  """
  @spec upgrade_in(String.t(), [String.t()], String.t() | nil) :: map()
  def upgrade_in(dir, apps, to) do
    source = File.read!(Path.join(dir, "mix.exs"))

    edited =
      case {to, apps} do
        {nil, _} -> source
        {req, [app]} -> set_requirement(source, app, req)
        {_req, _} -> {:error, "--to changes ONE dependency's requirement: name exactly one app"}
      end

    case edited do
      {:error, message} ->
        %{ok: false, error: message}

      out ->
        command = upgrade_command(read_lock(dir), apps)
        update(dir, source, out, command, %{via: hd(command)})
    end
  end

  @doc "The command an upgrade runs: the host's own `igniter.upgrade` when its lock has Igniter."
  @spec upgrade_command(String.t() | nil, [String.t()]) :: [String.t()]
  def upgrade_command(lock_text, apps) do
    igniter? = Map.has_key?(lock_versions(lock_text), "igniter")

    case {igniter?, apps} do
      {true, []} -> ["igniter.upgrade", "--all", "--yes"]
      {true, apps} -> ["igniter.upgrade" | apps] ++ ["--yes"]
      {false, []} -> ["deps.update", "--all"]
      {false, apps} -> ["deps.update" | apps]
    end
  end

  @doc "The dependency tuple `mix hex.info NAME` prints on its `Config:` line."
  @spec spec_from_hex_info(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def spec_from_hex_info(output) do
    case Regex.run(~r/^Config: (\{.+\})\s*$/m, output) do
      [_, spec] -> {:ok, spec}
      nil -> {:error, "hex.info gave no Config line: " <> (output |> String.split("\n") |> hd())}
    end
  end

  defp resolve_spec(_dir, "{" <> _ = spec), do: {:ok, spec}

  defp resolve_spec(dir, name) do
    {output, _status} = Menard.host_mix(dir, ["hex.info", name])
    spec_from_hex_info(output)
  end

  # Write mix.exs, run `command`, check every dependency is really there, and answer with the lock
  # diff and the compile. Any step failing puts mix.exs and mix.lock back: a dependency that cannot
  # be fetched leaves the project unable to build at all. The check is its own step because
  # `deps.get` exits 0 on a path dependency that does not exist.
  defp update(dir, source, out, command, extra) do
    mix_exs = Path.join(dir, "mix.exs")
    lock_before = read_lock(dir)
    env = [env: [{"MIX_ENV", nil}]]

    with :ok <- if(out == source, do: :ok, else: Menard.checked_write(mix_exs, out)),
         {_output, 0} <- Menard.host_mix(dir, command, env),
         {_output, 0} <- Menard.host_mix(dir, ["deps.loadpaths", "--no-compile"], env) do
      compile = Menard.Run.result(dir, "compile", [])

      Map.merge(extra, %{
        ok: compile.ok,
        lock: lock_diff(lock_before, read_lock(dir)),
        compile: Map.take(compile, [:ok, :diagnostics, :tail])
      })
    else
      {:error, message} ->
        Map.merge(extra, %{ok: false, error: message})

      {output, _status} ->
        File.write!(mix_exs, source)
        if lock_before, do: File.write!(Path.join(dir, "mix.lock"), lock_before)
        tail = output |> String.split("\n") |> Enum.take(-8) |> Enum.join("\n")

        Map.merge(extra, %{ok: false, error: "#{Enum.join(command, " ")} failed; mix.exs put back:\n" <> tail})
    end
  end

  defp read_lock(dir) do
    case File.read(Path.join(dir, "mix.lock")) do
      {:ok, text} -> text
      _ -> nil
    end
  end
end
