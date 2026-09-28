defmodule Menard.Verbs.Hook do
  @moduledoc """
  The `hook` verb (`Menard.Verbs`): what the harness said of a tool call, answered by
  `Menard.Hook`. The payload is the harness's own (`payload`, Claude Code's hook JSON as a map), or
  its fields as a `mcp_tool` hook fills them: `event`, `tool`, `session`, `call`, `cwd`, and the
  tool's `input` and `response` as JSON text. The reply is `%{}` with nothing to say, `context`
  with what the formatter changed, or `problem` with the files that could not be formatted.
  """

  @doc "The noun, as both doors are made from it (`Menard.Verbs.Noun`)."
  @spec noun() :: Menard.Verbs.Noun.t()
  def noun do
    %{
      name: "hook",
      doc: """
      The harness calls this after a tool ran, not you: it formats the Elixir files the call wrote and
      answers with what the formatter changed.
      """,
      fields: [
        {:event, :string, []},
        {:tool, :string, []},
        {:session, :string, []},
        {:call, :string, []},
        {:cwd, :string, []},
        {:input, :string, []},
        {:response, :string, []}
      ]
    }
  end

  @spec run(Menard.Verbs.params()) :: Menard.Verbs.result()
  def run(%{payload: %{} = payload}), do: {:ok, reply(Menard.Hook.run(payload), payload["hook_event_name"])}

  def run(p) do
    run(%{
      payload: %{
        "hook_event_name" => p[:event],
        "tool_name" => p[:tool],
        "session_id" => p[:session],
        "tool_use_id" => p[:call],
        "cwd" => p[:cwd],
        "tool_input" => object(p[:input]),
        "tool_response" => object(p[:response])
      }
    })
  end

  defp reply(:quiet, _event), do: %{}
  defp reply({:context, text}, event), do: %{context: text, event: event || "PostToolUse"}
  defp reply({:problem, text}, _event), do: %{problem: text}

  # a placeholder the harness could not fill (no `tool_response` before the tool ran) is no object
  defp object(text) when is_binary(text) do
    case JSON.decode(text) do
      {:ok, %{} = map} -> map
      _ -> %{}
    end
  end

  defp object(_none), do: %{}
end
