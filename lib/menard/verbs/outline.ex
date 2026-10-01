defmodule Menard.Verbs.Outline do
  @moduledoc """
  The `outline` verbs (`Menard.Verbs`). With `file` (the default, `verb` absent or `file`): the
  file's modules, defs and version. `map`: every module under a `lib/` of the project, its file and
  public functions, a dozen each unless `all`, the whole capped near 12,000 characters (what the
  cap cuts is counted in `cut`). `where`: for each `FILE:LINE` in `at`, the module and function
  whose lines hold it.
  """

  import Menard.Verbs
  alias Menard.Outline

  @verbs ~w(file map where)
  @cap 12_000

  @doc "The noun, as both doors are made from it (`Menard.Verbs.Noun`)."
  @spec noun() :: Menard.Verbs.Noun.t()
  def noun do
    %{
      name: "outline",
      doc: """
      A file as an outline (`file`): modules, defs with arity/kind/head/spec/doc and a component's
      attr/slot lines, line spans, and a
      test file's `tests` (setup, test, describe with its tests), each with its label and lines. Read
      before editing: each def's `head` is the address `clause` and `stmt` take. `verb: "map"`: every
      module under a `lib/` of the project, its file and public functions (a dozen each unless `all`),
      the map an agent starts with. `verb: "where"`: for each `FILE:LINE` in `at`, the module and
      function whose lines hold it — what a grep hit sits in.
      """,
      fields: [
        {:verb, :enum, [values: ["file", "map", "where"]]},
        {:file, :string, []},
        {:at, {:list, :string}, []},
        {:all, :boolean, []}
      ]
    }
  end

  @spec run(Menard.Verbs.params()) :: Menard.Verbs.result()
  def run(%{verb: "map"} = p) do
    root = p[:root] || Menard.caller_dir()
    all = p[:all] == true

    modules =
      root
      |> Path.join("**/lib/**/*.ex")
      |> Path.wildcard()
      |> Enum.reject(&(&1 =~ ~r{/(deps|_build|node_modules)/}))
      |> Enum.sort()
      |> Enum.flat_map(&modules(&1, Path.relative_to(&1, root), all))

    {shown, _size} =
      Enum.reduce_while(modules, {[], 0}, fn m, {acc, size} ->
        line = byte_size(line(m)) + 1

        if not all and size + line > @cap,
          do: {:halt, {acc, size}},
          else: {:cont, {[m | acc], size + line}}
      end)

    {:ok, %{modules: Enum.reverse(shown), cut: length(modules) - length(shown)}}
  end

  def run(%{verb: "where"} = p) do
    with {:ok, at} <- at(p[:at]) do
      found =
        at
        |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
        |> Enum.flat_map(fn {file, lines} -> where(file, lines, p) end)
        |> Enum.sort_by(&{&1.file, &1.line})

      {:ok, %{at: found}}
    end
  end

  def run(%{verb: verb} = p) when verb in [nil, "file"] do
    with :ok <- need(p, [:file], "outline"),
         {:ok, file} <- resolve(p.file, p),
         {:ok, source} <- read(file),
         {:ok, modules} <- outline(p.file, source) do
      {:ok, %{file: file, version: Menard.remember(source), modules: modules}}
    end
  end

  def run(%{verb: verb}),
    do: {:error, "outline has no verb #{inspect(verb)}: one of #{Enum.join(@verbs, ", ")}"}

  def run(p), do: run(Map.put(p, :verb, "file"))

  @doc "A module of the map as its line: `Shop.Cart  lib/shop/cart.ex  new/0 add/3 (+3 more)`."
  @spec line(map()) :: String.t()
  def line(%{module: module, file: file, functions: functions, more: more}) do
    more = if more == 0, do: "", else: " (+#{more} more)"
    String.trim_trailing("#{module}  #{file}  #{Enum.join(functions, " ")}#{more}")
  end

  defp modules(path, rel, all) do
    with {:ok, content} <- File.read(path), {:ok, modules} <- Outline.run(content) do
      flatten(modules, rel, all)
    else
      _ -> []
    end
  end

  defp flatten(modules, rel, all) do
    Enum.flat_map(modules, fn m ->
      public =
        m.defs
        |> Enum.filter(&(&1.kind in [:def, :defmacro, :defdelegate]))
        |> Enum.map(&"#{&1.name}/#{&1.arity}")
        |> Enum.uniq()

      # a module of 150 functions took a third of the map: the first dozen say what it is
      {first, rest} = if all, do: {public, []}, else: Enum.split(public, 12)

      [%{module: m.module, file: rel, functions: first, more: length(rest)}] ++ flatten(m.modules, rel, all)
    end)
  end

  defp at(nil), do: {:error, "where needs at: FILE:LINE, one or more"}
  defp at([]), do: {:error, "where needs at: FILE:LINE, one or more"}

  defp at(specs) when is_list(specs) do
    {:ok,
     Enum.flat_map(specs, fn spec ->
       case Regex.run(~r/\A(.+\.exs?):(\d+)/, spec) do
         [_, file, line] -> [{file, String.to_integer(line)}]
         nil -> []
       end
     end)}
  end

  defp where(file, lines, p) do
    with {:ok, abs} <- resolve(file, p),
         {:ok, content} <- File.read(abs),
         {:ok, modules} <- Outline.run(content) do
      for line <- lines, name = in_(modules, line), do: %{file: file, line: line, in: name}
    else
      _ -> []
    end
  end

  # the innermost module holding the line, then its def: a nested module's defs are its own
  defp in_(modules, line) do
    Enum.find_value(modules, fn m ->
      {a, b} = m.lines || {0, 0}
      if line in a..b//1, do: in_(m.modules, line) || def_at(m, line)
    end)
  end

  defp def_at(m, line) do
    case Enum.find(m.defs, &within?(&1, line)) do
      nil -> test_at(m.module, m.tests, line) || m.module
      d -> "#{m.module}.#{d.name}/#{d.arity}"
    end
  end

  # a line of a test file is in its test, inside its describe: `M describe "a" test "b"`
  defp test_at(prefix, tests, line) do
    case Enum.find(tests, &within?(&1, line)) do
      nil ->
        nil

      t ->
        here = "#{prefix} #{t.kind}#{if t.label, do: " " <> inspect(t.label)}"
        test_at(here, t[:tests] || [], line) || here
    end
  end

  defp within?(%{lines: lines}, line), do: line in elem(lines || {0, 0}, 0)..elem(lines || {0, 0}, 1)//1

  defp outline(name, source) do
    with {:error, reason} <- Outline.run(source), do: {:error, "#{name}: #{reason}"}
  end
end
