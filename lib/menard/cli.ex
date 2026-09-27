defmodule Menard.CLI do
  @moduledoc """
  What every `mix menard.*` task shares once it has turned its argv into a verb's params
  (`Menard.Verbs`): the reply printed as one JSON line on stdout, the reason raised as the task's
  error, so a caller reads one line and gates on the exit status. Only a door prints or raises.
  """

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

  @doc "The usage line, raised: a call the verbs do not take."
  @spec usage(String.t()) :: no_return()
  def usage(text), do: Mix.raise("usage: " <> text)

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
