defmodule Hidden.DigestTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Server.Channel
  alias Server.Dossier
  alias Server.Repo
  alias Server.Tickets
  alias Server.Workspaces

  setup do
    Server.TestDB.clean!()
    {:ok, ws} = Workspaces.register(%{name: "Digest"})
    {:ok, other} = Workspaces.register(%{name: "Elsewhere"})
    %{ws: ws, other: other}
  end

  # ten days old, outside a week's window
  defp age!(schema, id) do
    old = DateTime.utc_now() |> DateTime.add(-10 * 86_400) |> DateTime.truncate(:second)
    Repo.update_all(from(r in schema, where: r.id == ^id), set: [created_at: old])
  end

  defp post!(thread, body), do: elem(Channel.post(%{thread_id: thread.id, author: "andrew", body: body}), 1)

  defp fact!(thread, text),
    do:
      elem(Dossier.bank_fact(%{kind: "learned", text: text, provenance: "derived", thread_id: thread.id}), 1)

  test "counts a workspace's last days: busiest threads first, facts and tickets, nothing older or elsewhere",
       %{ws: ws, other: other} do
    {:ok, busy} = Channel.open_thread(%{title: "busy", workspace_id: ws.id})
    {:ok, quiet} = Channel.open_thread(%{title: "quiet", workspace_id: ws.id})
    {:ok, stale} = Channel.open_thread(%{title: "stale", workspace_id: ws.id})
    {:ok, away} = Channel.open_thread(%{title: "away", workspace_id: other.id})

    for n <- 1..3, do: post!(busy, "busy #{n}")
    post!(quiet, "recent")
    age!(Server.Message, post!(quiet, "old").id)
    age!(Server.Message, post!(stale, "old").id)
    post!(away, "not ours")

    fact!(busy, "recent fact")
    age!(Server.Fact, fact!(quiet, "old fact").id)
    fact!(away, "not ours")
    {:ok, _} = Dossier.forget_fact(fact!(busy, "forgotten"))

    {:ok, _} = Tickets.file(%{workspace_id: ws.id, title: "recent"})
    {:ok, old} = Tickets.file(%{workspace_id: ws.id, title: "old"})
    age!(Server.Ticket, old.id)
    {:ok, _} = Tickets.file(%{workspace_id: other.id, title: "not ours"})

    digest = Server.Digest.for_workspace(ws.id, DateTime.add(DateTime.utc_now(), -7 * 86_400))

    assert digest.threads == [
             %{thread_id: busy.id, title: "busy", messages: 3},
             %{thread_id: quiet.id, title: "quiet", messages: 1}
           ]

    assert digest.facts == 1
    assert digest.tickets_filed == 1
  end

  test "a tie in messages goes to the lower thread id", %{ws: ws} do
    {:ok, first} = Channel.open_thread(%{title: "first", workspace_id: ws.id})
    {:ok, second} = Channel.open_thread(%{title: "second", workspace_id: ws.id})
    post!(second, "one")
    post!(first, "one")

    since = DateTime.add(DateTime.utc_now(), -86_400)

    assert Enum.map(Server.Digest.for_workspace(ws.id, since).threads, & &1.thread_id) == [
             first.id,
             second.id
           ]
  end
end
