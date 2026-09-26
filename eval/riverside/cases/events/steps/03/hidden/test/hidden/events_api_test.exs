defmodule ExRiverside.Hidden.EventsApiTest do
  @moduledoc """
  Every public function ExRiverside.Events had before the split (its `__info__(:functions)` at the
  base, defaults expanded) is still there, on that module: a caller anywhere in the app or a
  console session keeps working. Behaviour is the suite's to check.
  """
  use ExUnit.Case, async: true

  @api [
    approve_event: 2,
    archive_event: 2,
    cancel_event: 3,
    cancel_series: 2,
    change_event: 1,
    change_event: 2,
    change_series: 1,
    change_series: 2,
    collapse_series: 1,
    collapse_series: 2,
    count_pending_submissions: 0,
    count_pending_submissions_for: 1,
    create_event: 1,
    create_event: 2,
    create_event: 3,
    create_series: 1,
    create_series: 2,
    create_series: 3,
    delete_event: 1,
    delete_event: 2,
    delete_series: 1,
    delete_series: 2,
    demote_series_to_event: 3,
    demote_series_to_event: 4,
    generate_occurrences: 1,
    get_event: 1,
    get_event!: 1,
    get_series!: 1,
    list_event_series: 0,
    list_event_series: 1,
    list_events: 0,
    list_events_by_tag: 1,
    list_events_by_tag_ids: 1,
    list_past_events: 0,
    list_pending_submissions: 0,
    list_pending_submissions_for: 1,
    list_published_events: 0,
    list_published_events: 1,
    list_series_occurrences: 1,
    list_submissions_by: 1,
    list_tags_in_sector: 1,
    owner_can_edit?: 2,
    promote_event_to_series: 3,
    promote_event_to_series: 4,
    publish_event: 2,
    publish_series: 1,
    reject_event: 3,
    search_events: 1,
    submit_event: 2,
    submit_event: 3,
    subscribe_admin_inbox: 0,
    subscribe_events: 0,
    transition_due_events: 0,
    transition_due_events: 1,
    update_event: 2,
    update_event: 3,
    update_event: 4,
    update_series: 2,
    update_series: 3,
    update_series: 4,
    update_submission: 3,
    update_submission: 4
  ]

  test "ExRiverside.Events still exports every public function it had" do
    Code.ensure_loaded!(ExRiverside.Events)

    missing =
      for {name, arity} <- @api,
          not function_exported?(ExRiverside.Events, name, arity),
          do: "#{name}/#{arity}"

    assert missing == [], "gone from ExRiverside.Events: #{Enum.join(missing, ", ")}"
  end
end
