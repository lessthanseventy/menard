defmodule Menard.CLI do
  @moduledoc """
  What every `mix menard.*` task shares once it has turned its argv into a verb's params
  (`Menard.Verbs`): the reply printed as one JSON line on stdout, the reason raised as the task's
  error, so a caller reads one line and gates on the exit status. Only a door prints or raises.
  """

  alias Menard.Verbs.Noun

  @doc """
  A verb's result as the CLI's answer: `{:ok, reply}` is one JSON line; `{:error, reason}` is the
  `Mix.raise`. A write that could not be formatted says so on stderr too — the reply carries it,
  and a reader of the exit status alone would take it for clean.
  """
  @spec answer(Menard.Verbs.result()) :: map()
  def answer({:ok, reply}) do
    Mix.shell().info(JSON.encode!(Menard.jsonable(reply)))
    if reason = reply[:unformatted], do: Mix.shell().error("menard: " <> reason)
    reply
  end

  def answer({:error, reason}), do: Mix.raise(reason)

  @doc "`answer/1`, and a failing exit when the reply's `ok` is false — the way `run` and `deps` gate."
  @spec finish(Menard.Verbs.result()) :: map()
  def finish(result) do
    reply = answer(result)
    if reply[:ok] == false, do: exit({:shutdown, 1})
    reply
  end

  @doc """
  A noun's mix task (`Menard.Verbs.Noun`): `argv` read by the noun's `cli`, its verb run, the
  result answered. An argv no shape takes raises the usage, made from the same shapes.
  """
  @spec run(module(), [String.t()]) :: map()
  def run(verbs, argv) do
    noun = Noun.of(verbs)
    flags = Noun.flags(noun)
    {given, args} = options(argv, for({flag, {type, _field}} <- flags, do: {flag, type}))

    case shaped(noun.cli.shapes, args) do
      nil -> usage(Noun.usage(noun))
      params -> answer(verbs.run(given |> flagged(flags) |> Map.merge(from_stdin(params, noun))))
    end
  end

  # a flag fills its field; one that repeats (`--tag a --tag b`) fills it with every value, none with []
  defp flagged(given, flags) do
    Map.new(flags, fn
      {flag, {:keep, field}} -> {field, Keyword.get_values(given, flag)}
      {flag, {_type, field}} -> {field, given[flag]}
    end)
    |> Map.reject(fn {_field, value} -> is_nil(value) end)
  end

  # the first shape of the verb that takes the arguments, as the params they fill
  defp shaped(shapes, args) do
    Enum.find_value(shapes, fn
      {nil, fields} -> fill(fields, args, %{})
      {verb, fields} -> if verb == verb(List.first(args) || ""), do: fill(fields, tl(args), %{verb: verb})
    end)
  end

  defp fill([], [], params), do: params
  defp fill([{:optional, _field}], [], params), do: params
  defp fill([{:optional, field}], [arg], params), do: Map.put(params, field, arg)
  defp fill([{:rest, field}], [_ | _] = args, params), do: Map.put(params, field, args)

  defp fill([field | fields], [arg | args], params) when is_atom(field),
    do: fill(fields, args, Map.put(params, field, arg))

  defp fill(_fields, _args, _params), do: nil

  defp from_stdin(params, noun) do
    for field <- get_in(noun, [:cli, :stdin]) || [], is_map_key(params, field), reduce: params do
      params -> Map.update!(params, field, &stdin(&1, "menard.#{noun.name}"))
    end
  end

  @doc "The usage line, raised: a call the verbs do not take."
  @spec usage(String.t()) :: no_return()
  def usage(text), do: Mix.raise("usage: " <> as_run(text))

  @doc "Each `mix menard.VERB` of `text` as the verb is run here (`Menard.command/1`)."
  @spec as_run(String.t()) :: String.t()
  def as_run(text), do: Regex.replace(~r/mix menard\.(\w+)/, text, fn _all, verb -> Menard.command(verb) end)

  @doc """
  The flags and arguments of `argv`, or the usage raised for any flag the verb cannot read: an unknown
  one, or one whose value is missing or starts with `-` (`--flag=VALUE`, or CODE after `--`). Dropped
  silently, `--label "--x"` wrote a test with no name and answered as a success.
  """
  @spec options([String.t()], keyword()) :: {keyword(), [String.t()]}
  def options(argv, strict) do
    case OptionParser.parse(argv, strict: strict) do
      {flags, args, []} ->
        {flags, args}

      {_flags, _args, invalid} ->
        named = Enum.map_join(invalid, ", ", fn {flag, _value} -> flag end)

        known =
          Enum.map_join(strict, " ", fn {name, _type} -> "--" <> String.replace(to_string(name), "_", "-") end)

        usage(
          "cannot read #{named}: a flag this verb does not take, or its value is missing or starts with -. " <>
            "A flag's value that starts with - goes as --flag=VALUE; CODE or an argument that does goes " <>
            "after --. This verb takes: #{known}"
        )
    end
  end

  @doc "The two doors spelled verbs differently, the CLI with dashes: both spellings work everywhere."
  @spec verb(String.t()) :: String.t()
  def verb(verb), do: String.replace(verb, "-", "_")

  @doc "CODE from stdin (`-`), for a module no shell quoting carries intact; an empty stdin is a pipe that lost its input, not code."
  @spec stdin(String.t(), String.t()) :: String.t()
  def stdin("-", what) do
    case IO.read(:stdio, :eof) do
      text when is_binary(text) and text != "" -> text
      _empty -> Mix.raise("#{what}: stdin was empty — nothing written")
    end
  end

  def stdin(code, _what), do: code
end
