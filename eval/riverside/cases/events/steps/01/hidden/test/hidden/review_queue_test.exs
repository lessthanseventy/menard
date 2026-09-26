defmodule ExRiverside.Hidden.ReviewQueueTest do
  @moduledoc """
  The dashboard's review queue lists only what the reviewer may act on: the review page enforces
  the strict-above rule (Permissions), so a submission by a user at the reviewer's own level must
  not be offered to them. Through the context function the dashboard uses and the dashboard itself.
  """
  use ExRiversideWeb.ConnCase, async: false

  import ExRiverside.AccountsFixtures
  import Phoenix.LiveViewTest

  alias ExRiverside.Events

  setup do
    moderator = user_fixture_at_level(5)
    peer = user_fixture_at_level(5)
    participant = user_fixture_at_level(3)

    {:ok, from_peer} =
      Events.submit_event(peer, %{
        title: "Peer workshop",
        description: "x",
        starts_at: ~U[2031-03-01 10:00:00Z]
      })

    {:ok, from_participant} =
      Events.submit_event(participant, %{
        title: "Member walk",
        description: "x",
        starts_at: ~U[2031-03-02 10:00:00Z]
      })

    %{moderator: moderator, from_peer: from_peer, from_participant: from_participant}
  end

  test "the queue holds only submissions from below the reviewer's level", ctx do
    ids = ctx.moderator |> Events.list_pending_submissions_for() |> Enum.map(& &1.id)
    assert ctx.from_participant.id in ids
    refute ctx.from_peer.id in ids
    assert Events.count_pending_submissions_for(ctx.moderator) == length(ids)
  end

  test "a manager, above both submitters, is offered both", ctx do
    manager = user_fixture_at_level(6)
    ids = manager |> Events.list_pending_submissions_for() |> Enum.map(& &1.id)
    assert ctx.from_participant.id in ids
    assert ctx.from_peer.id in ids
  end

  test "the dashboard offers the moderator nothing the review page would refuse", %{conn: conn} = ctx do
    conn = log_in_user(conn, ctx.moderator)
    {:ok, _view, html} = live(conn, ~p"/admin")
    # the queue's rows link to the review page; a title alone may also be in the activity feed
    assert html =~ ~s|href="/admin/reviews/#{ctx.from_participant.id}"|
    refute html =~ ~s|href="/admin/reviews/#{ctx.from_peer.id}"|
  end
end
