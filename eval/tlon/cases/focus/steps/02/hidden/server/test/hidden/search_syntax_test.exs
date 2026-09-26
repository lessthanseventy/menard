defmodule Hidden.SearchSyntaxTest do
  use ExUnit.Case, async: false

  alias Server.Channel
  alias Server.Dossier
  alias Server.Search

  setup do
    Server.TestDB.clean!()
    {:ok, thread} = Channel.open_thread(%{title: "search syntax"})

    ids =
      for body <- [
            "the deploy failed on staging",
            "deploy of the failed build",
            "the deploy failed in production"
          ],
          into: %{} do
        {:ok, m} = Channel.post(%{thread_id: thread.id, author: "a", body: body})
        {body, m.id}
      end

    for text <- [
          "credo strict mode fails the build",
          "strict credo checks run in CI",
          "credo strict mode on staging"
        ] do
      {:ok, _} = Dossier.bank_fact(%{kind: "learned", text: text, provenance: "derived"})
    end

    %{ids: ids}
  end

  defp ids(%{shown: shown}), do: shown |> Enum.map(& &1.message_id) |> Enum.sort()

  test "a quoted phrase matches only as that phrase, and counts true beyond the cut", %{ids: ids} do
    want = Enum.sort([ids["the deploy failed on staging"], ids["the deploy failed in production"]])
    assert ids(Search.history(~s("deploy failed"))) == want
    assert %{shown: [_], more: 1} = Search.history(~s("deploy failed"), 1)
  end

  test "a word with a leading minus excludes", %{ids: ids} do
    want = Enum.sort([ids["deploy of the failed build"], ids["the deploy failed in production"]])
    assert ids(Search.history("deploy -staging")) == want
  end

  test "plain words still all have to match", %{ids: ids} do
    assert ids(Search.history("deploy production")) == [ids["the deploy failed in production"]]
  end

  test "fact search takes the same syntax" do
    texts = fn r -> r.shown |> Enum.map(& &1.text) |> Enum.sort() end

    assert texts.(Search.facts(~s("credo strict"))) == [
             "credo strict mode fails the build",
             "credo strict mode on staging"
           ]

    assert texts.(Search.facts(~s("credo strict" -staging))) == ["credo strict mode fails the build"]
  end
end
