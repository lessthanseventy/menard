defmodule Menard do
  @moduledoc """
  Menard — Pierre Menard, author of the Quixote: rewrite a text word for word and have it come
  out different. AST-aware edits and introspection for Elixir repos (Sourceror patches: only the
  bytes a verb names move), as a project of its own so `mix menard.*` runs even while the app
  being edited does not compile.

  The tasks run from THIS project (`bin/menard VERB …` from anywhere), so a path is resolved
  against the caller's directory (`MENARD_CWD`, else the cwd), and the run verbs act in
  `--in DIR` (default: the caller's directory).
  """

  @first ~w(ok did tests failed)

  @last ~w(file version log)

  @doc "The directory the caller stood in."
  def caller_dir, do: System.get_env("MENARD_CWD") || File.cwd!()

  @doc """
  This menard as a shell runs it, by its path. Whatever menard tells an agent to run, it names by
  this: a plugin's `bin/` is the LAST place the harness's shell looks, so a bare `menard` is
  whichever one the PATH holds before it (an older install of the user's; in the eval, a stub that
  says no such command). `bin/menard` runs every verb from menard's own root, whoever starts it.
  """
  @spec bin() :: String.t()
  def bin, do: Path.join(File.cwd!(), "bin/menard")

  @doc """
  `verb` as it is run: by `bin/0` where menard runs from its own checkout, and as the mix task
  (`mix menard.VERB`) where it is a project's dependency and has no `bin/` of its own.
  """
  @spec command(String.t()) :: String.t()
  def command(verb), do: if(File.regular?(bin()), do: "#{bin()} #{verb}", else: "mix menard.#{verb}")

  @doc "A path as the caller meant it: absolute stays, relative joins the caller's directory."
  def resolve(path), do: Path.expand(path, caller_dir())

  @doc """
  menard's cache: the versions it handed out, the host formatters' deps. The user's cache directory,
  or `config :menard, :cache_dir` where one is set (menard's own tests, so a run never writes into,
  or prunes, the cache a live session reads).
  """
  def cache_dir, do: Application.get_env(:menard, :cache_dir) || :filename.basedir(:user_cache, "menard")

  @doc "Format `file` in place with the host's own formatter: `Menard.Format.file/2`."
  defdelegate format(file, opts \\ []), to: Menard.Format, as: :file

  @doc "Format `content` for `file` without writing, formatter and plugins apart: `Menard.Format.staged/3`."
  defdelegate format_staged(file, content, opts \\ []), to: Menard.Format, as: :staged

  # Every version handed out is kept, so a stale edit can be answered with the diff since it. A
  # week is longer than any session holds a version; older copies go when the next one is kept.
  @doc """
  The version of `content` (`sha256:` + 12 hex), with a copy kept, so a stale edit made against it
  can be answered with the diff since. What every writing verb and `outline` hand out. Twelve: a
  version is one file's state, and the 64 of the whole hash were a quarter of a reply's characters
  for none (handed out 277 times in the eval's sessions, passed back 0; Fable's review).
  """
  def remember(content) do
    version = version_of(content)
    path = version_path(version)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, content)
    # once a VM: a stat of every kept copy on each write and read was 2,733 files a call
    unless :persistent_term.get({__MODULE__, :pruned}, false) do
      :persistent_term.put({__MODULE__, :pruned}, true)
      prune_versions()
    end

    version
  end

  @doc "The kept copies older than a week, gone: longer than any session holds a version."
  def prune_versions do
    week_ago = System.os_time(:second) - 7 * 24 * 3600

    # a copy another menard pruned between the listing and the stat is already gone, not an error
    for old <- Path.wildcard(Path.join([cache_dir(), "versions", "*"])),
        {:ok, %{mtime: mtime}} <- [File.stat(old, time: :posix)],
        mtime < week_ago,
        do: File.rm(old)

    :ok
  end

  @doc """
  Write `content` to `file` through the staged pipeline: parse-check, format in-memory, diff each
  stage, write the result. Returns `{:ok, reply}` where reply is `%{did, file, version, stages}` —
  the LiveView reply (docs/live.md). `stages` has `:patch` (what the verb changed) and `:formatter`
  (what `mix format` changed after it), each as a list of `%{start, removed, added}` hunks.

  `did` is a human-readable one-liner (`opts[:did]`), `version` is `sha256:` + the hex digest of the
  file after every stage. A format failure is NOT a write failure: the bytes are on disk and
  correct, just not reformatted — the reply says so in `unformatted`, and the `:formatter` stage
  carries the reason. Nothing is printed: that is a door's business.
  """
  @spec write(String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, String.t()}
  def write(file, content, opts \\ []) do
    did = opts[:did] || "edit #{Path.relative_to_cwd(file)}"
    original = if File.regular?(file), do: File.read!(file), else: ""
    # a private function it adds goes below the public ones, whoever wrote it where
    {content, moved} =
      if Path.extname(file) in [".ex", ".exs"],
        do: Menard.Layout.private_last(original, content),
        else: {content, []}

    with :ok <- fresh(file, original, opts),
         {:ok, patched} <- checked(file, content, original) do
      {formatted, split, format_error} =
        case format_staged(file, patched) do
          {:ok, f, split} -> {f, split, nil}
          {:error, reason} -> {patched, nil, reason}
        end

      File.write!(file, formatted)
      version = remember(formatted)
      # what Claude Code tells an agent after an Edit, and the reason B re-read files A did not
      reply = %{
        did: did,
        file: file,
        version: version,
        stages: stages(original, patched, formatted, split),
        # kept on every write: without it, bench1/bench2's B read files back after its last edit
        # 2.6x as often, and the CLI's caller never sees the MCP instructions; short, as it rides
        # every reply
        note: "the stages are every change: no Read needed"
      }

      reply =
        if moved == [],
          do: reply,
          else: Map.put(reply, :moved, moved)

      {:ok, unformatted(reply, format_error)}
    end
  end

  @doc """
  Write `content` to `file`, but only if it still parses as Elixir, then format it. The thin
  wrapper over `write/3` for callers that don't need the reply yet. Every edit verb goes through
  here: an AST patch that lands unparseable bytes locks the file out of every other verb.
  """
  @spec checked_write(String.t(), String.t()) :: :ok | {:error, String.t()}
  def checked_write(file, content) do
    case write(file, content) do
      {:ok, _reply} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  The HOST project's `mix`, run in `dir` on the host's own toolchain. menard's toolchain is first on
  its PATH, so a bare `mix` built the host with the wrong Elixir: every dep rebuilt, and nothing the
  host's toolchain built would load. With mise installed, `mise exec` picks the host's pins.
  `require:` names an .exs file the host's VM loads before mix starts (`elixir -r FILE -S mix`).
  """
  def host_mix(dir, args, opts \\ []) do
    {require, opts} = Keyword.pop(opts, :require)
    argv = if require, do: ["elixir", "-r", require, "-S", "mix" | args], else: ["mix" | args]
    host_cmd(dir, argv, Keyword.put(opts, :label, "mix #{hd(args)}"))
  end

  @doc """
  `[exe | args]` as the host's toolchain runs it in `dir`, and a note for the caller when that is
  not the toolchain the host pins: `mise exec` where the host pins one that is installed, else the
  one on PATH.
  """
  @spec host_argv(String.t(), [String.t()]) :: {[String.t()], String.t()}
  def host_argv(dir, argv) do
    case host_toolchain(dir) do
      {:mise, mise} -> {[mise, "exec", "-C", dir, "--" | argv], ""}
      {:path, nil} -> {argv, ""}
      {:path, why} -> {argv, "menard: #{why}\n"}
    end
  end

  @doc """
  `[exe | args]` run in `dir` on the host's toolchain, as `host_mix/3` runs its mix: `elixir` for
  the formatter, which must not evaluate the host's `mix.exs`. `timeout:` is its deadline in ms;
  past it the process is killed and the status is 124 (137 when it would not stop); `label:` names
  it in the line that says so.
  """
  def host_cmd(dir, [exe | args], opts \\ []) do
    {timeout, opts} = Keyword.pop(opts, :timeout)
    {label, opts} = Keyword.pop(opts, :label, exe)
    opts = Keyword.merge([cd: dir, stderr_to_stdout: true], opts)
    {[exe | argv], note} = host_argv(dir, [exe | args])

    # stdin is /dev/null: the port's own stays open and never says anything, so a prompt (`mix
    # deps.get` asking "Shall I install Hex? [Yn]") waited forever. System.cmd cannot redirect it;
    # `sh` can, and its `exec` leaves no shell between the deadline's kill and the mix.
    argv = ["-c", ~s(exec "$@" </dev/null), "sh", exe | argv]
    {out, status} = bounded_cmd("sh", argv, opts, timeout, label)
    {note <> out, status}
  end

  @doc """
  `term` as JSON can carry it. JSON has no tuple, and the library answers with them (`lines: {3, 9}`):
  encoding one crashed the MCP tool call and `outline --json` alike.

      iex> Menard.jsonable(%{module: "A", lines: {1, 3}, defs: [%{lines: {2, 2}}]})
      %{module: "A", lines: [1, 3], defs: [%{lines: [2, 2]}]}
  """
  def jsonable(%{__struct__: _} = struct), do: struct
  def jsonable(map) when is_map(map), do: Map.new(map, fn {k, v} -> {k, jsonable(v)} end)
  def jsonable(list) when is_list(list), do: Enum.map(list, &jsonable/1)
  def jsonable(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> jsonable()
  def jsonable(other), do: other

  @doc """
  A reply as the JSON both doors write: `jsonable/1`, what happened first (`ok`, `did`, the
  counts) and what is only passed back or opened later last (`file`, `version`, `log`), the rest by
  name. A map's own order was the VM's: `version`'s hash first, and a reader that kept the first 60
  characters (the transcripts: 53 of 64 `cut -c1-60` on clause) saw nothing else.
  """
  @spec encode(term()) :: String.t()
  def encode(reply), do: reply |> jsonable() |> ordered() |> IO.iodata_to_binary()

  @doc """
  Every `{file, version}` still current, or the stale refusal for the first that is not: for the
  verbs that write several files (`rename`, `clause move`), checked before any of them is written.
  """
  @spec check_versions([{String.t(), String.t()}]) :: :ok | {:error, String.t()}
  def check_versions(versions) do
    Enum.reduce_while(versions, :ok, fn {file, version}, :ok ->
      original = if File.regular?(file), do: File.read!(file), else: ""

      case fresh(file, original, version: version) do
        :ok -> {:cont, :ok}
        stale -> {:halt, stale}
      end
    end)
  end

  # :formatter is what `mix format` alone changed; :plugins, when the host has any, what they
  # (Styler) rewrote after it — so an agent can tell a rewrite it did not ask for from its own edit
  defp stages(original, patched, formatted, nil),
    do:
      told([
        %{stage: :patch, hunks: Menard.Diff.hunks(original, patched)},
        %{stage: :formatter, hunks: Menard.Diff.hunks(patched, formatted)}
      ])

  defp stages(original, patched, formatted, {plain, plugins}) do
    told([
      %{stage: :patch, hunks: Menard.Diff.hunks(original, patched)},
      %{stage: :formatter, hunks: Menard.Diff.hunks(patched, plain)},
      %{stage: :plugins, plugins: plugins, hunks: Menard.Diff.hunks(plain, formatted)}
    ])
  end

  # The stages as news. The caller's own code is not: a patch hunk past a few lines is where it
  # went, `added`/`removed` as counts (a block add of a test came back as 3 KB, its code twice). A
  # hunk that only re-indented is `reindented: n`. A stage after the patch that changed nothing is
  # left out.
  defp told(stages) do
    for %{stage: stage, hunks: hunks} = s <- stages, stage == :patch or hunks != [] do
      %{s | hunks: Enum.map(hunks, &told(stage, &1))}
    end
  end

  # the caller's own code, said back: where it went and how many lines, small hunks too (they echoed
  # every hunk of six lines or fewer, code and all; Fable's review)
  defp told(:patch, %{removed: removed, added: added} = h),
    do: %{h | removed: length(removed), added: length(added)}

  defp told(_stage, %{start: start, removed: removed, added: added} = h) do
    if removed != [] and Enum.map(removed, &String.trim/1) == Enum.map(added, &String.trim/1),
      do: %{start: start, reindented: length(added)},
      else: h
  end

  defp checked(file, content, original) do
    with {:ok, patched} <- Menard.Write.checked(file, content),
         :ok <- Menard.Write.together(file, original, patched) do
      {:ok, patched}
    else
      {:error, reason} -> {:error, "refusing to write #{Path.relative_to_cwd(file)} — #{reason}"}
    end
  end

  # An edit computed against a version the file no longer has would overwrite whatever changed it
  # since, so a version given is a version checked (docs/live.md, phase 3). The refusal carries
  # what changed, when menard still has the version it handed out, so the agent can re-sync.
  defp fresh(file, original, opts) do
    expected = opts[:version]
    current = version_of(original)

    if is_nil(expected) or opts[:force] == true or expected == current do
      :ok
    else
      since =
        case File.read(version_path(expected)) do
          {:ok, old} -> "changed since: " <> JSON.encode!(Menard.Diff.hunks(old, original))
          {:error, _} -> "menard has no copy of #{expected} to diff against"
        end

      {:error,
       "stale: #{Path.relative_to_cwd(file)} is no longer #{expected} but #{current}; #{since}. " <>
         "Re-read it and redo the edit, or pass force to write anyway"}
    end
  end

  defp version_of(content),
    do: "sha256:" <> binary_part(Base.encode16(:crypto.hash(:sha256, content), case: :lower), 0, 12)

  defp version_path(version) do
    hex = version |> String.replace_prefix("sha256:", "") |> Path.basename()
    Path.join([cache_dir(), "versions", hex])
  end

  # Written but not formatted is an answer the agent has to see: on stderr alone, the reply looked
  # clean and neither the agent nor its check noticed (a host plugin that would not load here).
  defp unformatted(reply, nil), do: reply

  defp unformatted(reply, reason) do
    # the formatter's stage carries why, there or not (a stage that changed nothing is left out)
    stages =
      if Enum.any?(reply.stages, &(&1.stage == :formatter)),
        do: Enum.map(reply.stages, &if(&1.stage == :formatter, do: Map.put(&1, :error, reason), else: &1)),
        else: reply.stages ++ [%{stage: :formatter, hunks: [], error: reason}]

    Map.merge(reply, %{unformatted: reason, stages: stages})
  end

  # Past its deadline the host's mix is KILLED, not abandoned: a caller that gave up while it kept
  # compiling left it racing the next mix in the same _build ("corrupt atom table"). coreutils
  # `timeout` signals the OS process, which a killed Elixir task never does; without it, no deadline.
  defp bounded_cmd(exe, argv, opts, nil, _label), do: System.cmd(exe, argv, opts)

  defp bounded_cmd(exe, argv, opts, ms, label) do
    # to the nearest second: rounded down, 10_000ms given and 9_999 left a millisecond later was 9s
    secs = max(div(ms + 500, 1000), 1)

    case System.find_executable("timeout") do
      nil ->
        System.cmd(exe, argv, opts)

      timeout ->
        case System.cmd(timeout, ["--kill-after=5", "#{secs}", exe | argv], opts) do
          {out, status} when status in [124, 137] ->
            {out <> "\nmenard: #{label} did not finish in #{secs}s, and was stopped", status}

          done ->
            done
        end
    end
  end

  # `mise exec` installs a pinned tool that is missing, and for Erlang that is a source build: minutes
  # of kerl, which fail on a machine without its build deps, before the verb answered ok:false with no
  # reason. MISE_EXEC_AUTO_INSTALL=false did not stop it (mise 2026.8). So ask first: a host that pins
  # a toolchain that is not installed gets the mix on PATH, and is told why.
  defp host_toolchain(dir) do
    case System.find_executable("mise") do
      nil -> {:path, nil}
      mise -> mise_toolchain(mise, dir)
    end
  end

  defp mise_toolchain(mise, dir) do
    with {out, 0} <- System.cmd(mise, ["ls", "--current", "--json", "-C", dir]),
         {:ok, %{} = tools} <- JSON.decode(out) do
      # pinned by the host: a config in its dir or above it. mise's global default is not the host's,
      # and the mix on PATH is the one the agent's own `mix` runs: two toolchains in one _build
      # rebuild every dep the other built, each time either runs.
      pinned =
        for tool <- ["erlang", "elixir"],
            %{"source" => %{"path" => path}} = v <- tools[tool] || [],
            String.starts_with?(Path.expand(dir) <> "/", Path.dirname(path) <> "/"),
            do: {tool, v}

      missing = for {tool, %{"installed" => false} = v} <- pinned, do: "#{tool} #{v["version"]}"

      cond do
        pinned == [] ->
          {:path, nil}

        missing == [] ->
          {:mise, mise}

        true ->
          {:path, "#{Enum.join(missing, ", ")} pinned here is not installed, so this ran the mix on PATH"}
      end
    else
      # mise could not say: let `exec` decide, as before
      _ -> {:mise, mise}
    end
  end

  defp ordered(%{__struct__: _} = struct), do: JSON.encode!(struct)

  defp ordered(map) when is_map(map) do
    pairs =
      map
      |> Enum.map(fn {k, v} -> {to_string(k), v} end)
      |> Enum.sort_by(fn {k, _} -> rank(k) end)
      |> Enum.map(fn {k, v} -> [JSON.encode!(k), ?:, ordered(v)] end)

    [?{, Enum.intersperse(pairs, ?,), ?}]
  end

  defp ordered(list) when is_list(list), do: [?[, list |> Enum.map(&ordered/1) |> Enum.intersperse(?,), ?]]
  defp ordered(other), do: JSON.encode!(other)

  defp rank(key) do
    cond do
      i = Enum.find_index(@first, &(&1 == key)) -> {0, i, ""}
      i = Enum.find_index(@last, &(&1 == key)) -> {2, i, ""}
      true -> {1, 0, key}
    end
  end
end
