defmodule Menard.Run.Lint do
  @moduledoc "Credo for the run verbs: whether a project has it and how strictly it gates, its JSON report as failures, and the issues on the lines changed since the last commit."

  alias Menard.Run

  @doc """
  Credo's findings on the lines changed in `rels` (paths from `dir`), as strict as the project's
  gate, or none where the project has no credo. `run` is `result/3`, or a test's stand-in.
  """
  @spec credo_changed(String.t(), [String.t()], (String.t(), String.t(), [String.t()] -> map())) :: [map()]
  def credo_changed(dir, rels, run \\ &Run.result/3)
  def credo_changed(_dir, [], _run), do: []

  def credo_changed(dir, rels, run) do
    # as strict as the project's gate: at credo's default a strict-only check (AliasUsage) passed
    # every write, and failed the gate
    strict = if credo_strict?(dir), do: ["--strict"], else: []
    if credo?(dir), do: run.(dir, "credo", ["--changed" | rels] ++ strict)[:failures] || [], else: []
  end

  @doc "Whether `dir`'s project gates with `credo --strict`: what a lint of it must match."
  @spec credo_strict?(String.t()) :: boolean()
  def credo_strict?(dir) do
    case File.read(Path.join(dir, "mix.exs")) do
      {:ok, mix} -> mix =~ "credo --strict"
      _ -> false
    end
  end

  # The project lints with credo when it has it: its lock names it, or its deps hold it
  @doc "Whether the project at `dir` has credo: its lock names it, or its deps hold it."
  @spec credo?(String.t()) :: boolean()
  def credo?(dir) do
    File.dir?(Path.join(dir, "deps/credo")) or
      case File.read(Path.join(dir, "mix.lock")) do
        {:ok, lock} -> lock =~ ~s("credo":)
        _ -> false
      end
  end

  # `--format json` prints the report after whatever compiling said first: the object from a line
  # that opens a brace to the end, however it is laid out
  @doc "The issues in `credo --format json` output, as failures, or `:error` where it holds no report."
  @spec credo_issues(String.t()) :: {:ok, [Run.issue()]} | :error
  def credo_issues(out) do
    ~r/^\{/m
    |> Regex.scan(out, return: :index)
    |> Enum.find_value(:error, fn [{at, _}] ->
      case JSON.decode(binary_part(out, at, byte_size(out) - at)) do
        {:ok, %{"issues" => issues}} -> {:ok, Enum.map(issues, &credo_issue/1)}
        _ -> nil
      end
    end)
  end

  # Only what an edit brought: issues on the lines changed since the last commit, every line of a file
  # git does not track yet. Old debt in the file is not the edit's to answer for. Credo anchors a
  # function's complexity or arity on its def line, so a finding there counts a change anywhere in it.
  # Two git calls for every file at once, not two per file: which are tracked, and one diff.
  @doc """
  The `issues` on lines changed since the last commit in the repo at `dir`, every one of an
  untracked file, and those on a def line whose function holds a changed line.
  """
  @spec only_changed([Run.issue()], String.t()) :: [Run.issue()]
  def only_changed(issues, dir) do
    files = issues |> Enum.map(&(&1.at |> String.split(":") |> hd())) |> Enum.uniq()
    # paths as the project names them, whatever its place in the repo, and unquoted
    git = &System.cmd("git", ["-C", dir, "-c", "core.quotePath=false" | &1], stderr_to_stdout: true)
    {tracked, _} = git.(["ls-files", "-z", "--" | files])
    tracked = tracked |> String.split(<<0>>, trim: true) |> MapSet.new()
    {diff, _} = git.(["diff", "-U0", "--relative", "HEAD", "--" | files])
    hunks = hunks(diff)
    lines = Map.new(files, &{&1, if(&1 in tracked, do: Map.get(hunks, &1, MapSet.new()), else: :all)})
    defs = Map.new(Map.keys(hunks), &{&1, def_spans(Path.join(dir, &1))})

    Enum.filter(issues, fn %{at: at} ->
      [file, line] = String.split(at, ":")
      line = String.to_integer(line)
      changed = lines[file]

      changed == :all or line in changed or
        Enum.any?(get_in(defs, [file, line]) || [], &(&1 in changed))
    end)
  end

  defp credo_issue(i) do
    %{
      kind: "credo",
      message: "#{i["message"]} (#{i["check"] |> String.split(".") |> List.last()})",
      at: "#{i["filename"]}:#{i["line_no"]}"
    }
  end

  # each def's first line and the lines it spans; none where the file does not parse
  defp def_spans(path) do
    with {:ok, source} <- File.read(path),
         {:ok, ast} <- Code.string_to_quoted(source, token_metadata: true) do
      {_, spans} =
        Macro.prewalk(ast, %{}, fn
          {kind, meta, [_ | _]} = node, acc when kind in [:def, :defp, :defmacro, :defmacrop] ->
            {node, Map.put(acc, meta[:line], meta[:line]..last_line(node))}

          node, acc ->
            {node, acc}
        end)

      spans
    else
      _ -> %{}
    end
  end

  defp last_line(node) do
    {_, last} =
      Macro.prewalk(node, 0, fn
        {_, meta, _} = n, acc when is_list(meta) ->
          {n,
           Enum.max([
             acc,
             meta[:line] || 0,
             get_in(meta, [:end, :line]) || 0,
             get_in(meta, [:closing, :line]) || 0
           ])}

        n, acc ->
          {n, acc}
      end)

    last
  end

  # each file's changed lines, from one diff of them all
  defp hunks(diff) do
    for [_, file, body] <- Regex.scan(~r/^\+\+\+ b\/(.+)\n((?:(?!diff --git ).*\n?)*)/m, diff),
        into: %{},
        do: {file, hunk_lines(body)}
  end

  defp hunk_lines(body) do
    # the count's group always matches, empty when a hunk has none (`@@ -2 +2 @@`): an optional group
    # that did not match drops out of scan's list, and the pattern skipped every one-line hunk
    for [_, start, count] <- Regex.scan(~r/^@@ -\S+ \+(\d+),?(\d*) @@/m, body),
        n = if(count == "", do: 1, else: String.to_integer(count)),
        n > 0,
        line <- String.to_integer(start)..(String.to_integer(start) + n - 1),
        into: MapSet.new(),
        do: line
  end
end
