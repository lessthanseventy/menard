defmodule Menard.Verbs.Noun do
  @moduledoc """
  A noun, declared once: every `Menard.Verbs.<Noun>` answers `noun/0`, and both doors are made
  from it. The MCP tool is its `doc` and `fields` (`lib/menard/mcp/tools.ex`); the mix task is its
  `cli` (`lib/mix/tasks/menard.ex`, `Menard.CLI.run/2`), where it has one. A field added to a
  noun is added here and nowhere else.

      %{
        name: "attr",
        doc: "what an agent reads before its first call",
        fields: [{:verb, :enum, values: ~w(get set), required: true}, {:file, :string, []}],
        deadline: 90_000,
        cli: %{
          shapes: [{"get", [:file, :name]}, {"set", [:file, :name, :value]}],
          flags: [tag: {:keep, :tag}],
          stdin: [:code]
        }
      }

  A field is `{name, type, opts}` as the MCP schema takes it. A shape is a verb (nil for a noun
  with none) and the arguments that follow it, in order: a field, `{:optional, field}` last, or
  `{:rest, field}` for every argument left. Every field is also a flag (`--name-arity`), its type
  the field's; `flags` names the ones that differ, `flag: {type, field}`. `stdin` lists the fields
  that read stdin when given as `-`.
  """

  alias Menard.Verbs

  @type field :: {atom(), atom() | tuple(), keyword()}
  @type shape :: {String.t() | nil, [atom() | {:optional, atom()} | {:rest, atom()}]}
  @type t :: %{
          required(:name) => String.t(),
          required(:doc) => String.t(),
          required(:fields) => [field()],
          optional(:deadline) => pos_integer(),
          optional(:cli) => %{
            required(:shapes) => [shape()],
            optional(:flags) => keyword(),
            optional(:stdin) => [atom()]
          }
        }

  # an edit takes seconds; `run` and `deps` wait on a host's test suite or a fetch
  @deadline 90_000

  # the nouns that write, as the format hook matches them (hooks/hooks.json), and what their `then`
  # runs after: a test added with `block add` was run by a second call, as an edit's need not be
  @writing ~w(write rename clause stmt directive attr block module)
  @thens ~w(test check compile)
  @then_doc "\n`then` runs `test` (the tests of what it wrote), `check` or `compile` after, its answer in `run`.\n"

  @doc "Every noun's verb module, in the order the MCP door lists its tools."
  @spec modules() :: [module()]
  def modules do
    [
      Verbs.Edit,
      Verbs.Write,
      Verbs.Rename,
      Verbs.Clause,
      Verbs.Stmt,
      Verbs.Directive,
      Verbs.Attr,
      Verbs.Block,
      Verbs.Module,
      Verbs.Deps,
      Verbs.Outline,
      Verbs.Find,
      Verbs.Run,
      Verbs.Hook
    ]
  end

  @doc """
  The noun `verbs` declares. The doors are made from it while menard compiles, in an order the
  compiler chooses: asked of a module not compiled yet, `noun/0` was undefined, and a fresh
  checkout built or did not by that order. So the module is waited for first.
  """
  @spec of(module()) :: t()
  def of(verbs) do
    Code.ensure_compiled!(verbs)
    noun = verbs.noun()

    if noun.name in @writing and not Enum.any?(noun.fields, &(elem(&1, 0) == :then)),
      do: %{noun | fields: noun.fields ++ [{:then, :enum, [values: @thens]}], doc: noun.doc <> @then_doc},
      else: noun
  end

  @doc "What a writing verb's `then` runs after it (`Menard.Verbs.call/2`)."
  @spec thens() :: [String.t()]
  def thens, do: @thens

  @doc "The ms a door waits for the noun's verbs."
  @spec deadline(t()) :: pos_integer()
  def deadline(noun), do: Map.get(noun, :deadline, @deadline)

  @doc "The noun's flags as `OptionParser` takes them, and the field each one fills."
  @spec flags(t()) :: [{atom(), {atom(), atom()}}]
  def flags(%{fields: fields} = noun) do
    named = get_in(noun, [:cli, :flags]) || []
    taken = for {_flag, {_type, field}} <- named, do: field

    typed =
      for {name, type, _opts} <- fields, name != :verb, name not in taken, do: {name, {flag_type(type), name}}

    typed ++ named
  end

  @doc "The usage line of each shape, and the flags every one takes."
  @spec usage(t()) :: String.t()
  def usage(%{name: name, cli: %{shapes: shapes}} = noun) do
    lines =
      for {verb, args} <- shapes do
        # a verb by the one name both doors give it: the CLI's `insert-after` was taken to MCP,
        # which refused it
        Enum.join(
          ["mix menard.#{name}"] ++ List.wrap(verb && to_string(verb)) ++ Enum.map(args, &label/1),
          " "
        )
      end

    flags = Enum.map_join(flags(noun), " ", fn {flag, _} -> "--" <> dashed(flag) end)
    Enum.join(lines, "\n       ") <> "\n       flags: " <> flags
  end

  defp label({:optional, field}), do: "[#{label(field)}]"
  defp label({:rest, field}), do: label(field) <> "..."
  defp label(:name_arity), do: "name/arity"
  defp label(field), do: field |> to_string() |> String.upcase()

  defp dashed(name), do: name |> to_string() |> String.replace("_", "-")

  defp flag_type(type) when type in [:boolean, :integer], do: type
  defp flag_type({:list, _of}), do: :keep
  defp flag_type(_text), do: :string
end
