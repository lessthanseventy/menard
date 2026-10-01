defmodule Menard.Piped do
  @moduledoc """
  A test run piped through `tail`, `head` or `grep`, run through `menard run` in its place.

  Across 288 of the operator's sessions, 90% of test and gate runs were piped to cut their output
  down, and 40% were run again with no edit between, to see a different slice of the same failure:
  the pipe keeps the summary and drops the failure, and the suite is run twice to read it once.
  `menard run` answers one JSON line: `ok`, the counts, and each failure with its file, line and
  message, so nothing is cut and nothing is run again.

  The command is rewritten before it runs, not refused: what was asked for is what is done, the
  tests run, and no call is lost to a refusal. Only a command that is one test run and its pipe
  is rewritten; the same run with anything else beside it (an edit before, another command after)
  is left as it was written, as is a run that is not piped at all.
  """

  # kept around the run: a cd before it (`&&` or `;`), `time`, and `mise exec … --` (the project's
  # toolchain); a subshell's parens are dropped, and only a pair is taken
  @pipe ~S"\s*\|\s*(?:tail|head|grep)\b[^|;&()]*"
  @piped Regex.compile!(
           ~S/^\s*(?<cd>cd\s+(?:"[^"]+"|'[^']+'|[^\s;&|]+)\s*(?:&&|;)\s*)?(?<time>time\s+)?(?<open>\(\s*)?/ <>
             ~S/(?:\w+=\S*\s+)*(?<mise>mise\s+(?:exec|x)\s+(?:[^\s;&|()]+\s+)*?--\s+)?(?:\w+=\S*\s+)*/ <>
             ~S/mix\s+(?<task>test|precommit)\b(?<args>[^|;&<>()]*?)(?:\s*2>&1)?(?:/ <>
             @pipe <> ~S")+(?(<open>)\s*\))\s*$"
         )

  @doc "The command `menard run` stands in for `command` with, or nil where it stands as written."
  @spec rewritten(String.t(), String.t()) :: String.t() | nil
  def rewritten(command, menard) do
    case Regex.named_captures(@piped, command) do
      %{"cd" => cd, "time" => time, "mise" => mise, "task" => task, "args" => args} ->
        cd <> time <> mise <> menard <> " run " <> verb(task, String.trim(args))

      nil ->
        nil
    end
  end

  defp verb("precommit", _args), do: "check"
  defp verb("test", ""), do: "test"
  defp verb("test", args), do: "test " <> args

  @doc "What is so in this session, said at its start."
  @spec upfront(String.t()) :: String.t()
  def upfront(menard) do
    "In this session a test run piped through tail, head or grep (`mix test … | tail -20`) is run " <>
      "as `#{menard} run test …` in its place, and `mix precommit | …` as `#{menard} run check`: " <>
      "the answer is one JSON line, `ok`, the counts, and every failure with its file, line and " <>
      "message, a failed assertion with its left and right. Nothing is cut, so no run is made " <>
      "again to read the rest."
  end
end
