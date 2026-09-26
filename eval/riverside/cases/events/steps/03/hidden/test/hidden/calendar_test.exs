defmodule ExRiversideWeb.Hidden.CalendarTest do
  @moduledoc """
  The calendar file through its route: a live event answers an attachment whose VEVENT carries the
  event's fields, escaped and in UTC; every other status and a missing id answer 404; the public
  event page links to it. Lines are unfolded first, so a renderer that folds long lines passes too.
  """
  use ExRiversideWeb.ConnCase, async: false

  import ExRiverside.EventsFixtures
  import Phoenix.LiveViewTest

  alias ExRiverside.Events.Calendar

  defp lines(body) do
    body
    |> String.replace(~r/\r\n[ \t]/, "")
    |> String.split("\r\n")
  end

  # the response's status, whether it was sent or raised (Ecto.NoResultsError is a 404 to Plug)
  defp status_of(conn, path) do
    get(conn, path).status
  rescue
    e -> Plug.Exception.status(e)
  end

  test "a published event answers an iCalendar attachment", %{conn: conn} do
    event =
      event_fixture(%{
        title: "Bake sale; cookies, cakes",
        description: "Bring a plate.\nStay for tea",
        starts_at: ~U[2031-04-05 14:30:00Z],
        ends_at: ~U[2031-04-05 16:00:00Z],
        location: "Main Hall"
      })

    conn = get(conn, "/events/#{event.id}/calendar.ics")
    assert conn.status == 200
    assert [type] = get_resp_header(conn, "content-type")
    assert type =~ ~r"^text/calendar"
    assert [disposition] = get_resp_header(conn, "content-disposition")
    assert disposition =~ "attachment"
    assert disposition =~ "event-#{event.id}.ics"

    body = conn.resp_body
    assert String.starts_with?(body, "BEGIN:VCALENDAR\r\n")
    assert String.ends_with?(body, "END:VCALENDAR\r\n")
    refute body =~ ~r/(?<!\r)\n/, "every line ends with CRLF"

    lines = lines(body)
    assert "VERSION:2.0" in lines
    assert Enum.any?(lines, &String.starts_with?(&1, "PRODID:"))
    assert Enum.count(lines, &(&1 == "BEGIN:VEVENT")) == 1
    assert "UID:event-#{event.id}@riverside" in lines
    assert "DTSTART:20310405T143000Z" in lines
    assert "DTEND:20310405T160000Z" in lines
    assert "SUMMARY:Bake sale\\; cookies\\, cakes" in lines
    assert "DESCRIPTION:Bring a plate.\\nStay for tea" in lines
    assert "LOCATION:Main Hall" in lines

    assert Enum.any?(
             lines,
             &(String.starts_with?(&1, "URL:") and String.ends_with?(&1, "/events/#{event.id}"))
           )
  end

  test "a backslash in a text value is escaped and an ongoing event answers too", %{conn: conn} do
    event =
      event_fixture(%{
        title: ~S"Slash \ dance",
        status: :ongoing,
        starts_at: ~U[2020-01-01 10:00:00Z],
        ends_at: ~U[2099-01-01 10:00:00Z]
      })

    conn = get(conn, "/events/#{event.id}/calendar.ics")
    assert conn.status == 200
    assert ~S"SUMMARY:Slash \\ dance" in lines(conn.resp_body)
  end

  test "no end and no location leave DTEND and LOCATION out", %{conn: conn} do
    event = event_fixture(%{ends_at: nil, starts_at: ~U[2031-06-01 09:00:00Z]})
    conn = get(conn, "/events/#{event.id}/calendar.ics")
    assert conn.status == 200
    lines = lines(conn.resp_body)
    assert "DTSTART:20310601T090000Z" in lines
    refute Enum.any?(lines, &String.starts_with?(&1, "DTEND"))
    refute Enum.any?(lines, &String.starts_with?(&1, "LOCATION"))
  end

  test "events that are not live, and ids that are no event, answer 404", %{conn: conn} do
    for status <- [:draft, :submitted, :rejected, :canceled, :archived] do
      event = event_fixture(%{status: status})
      assert status_of(conn, "/events/#{event.id}/calendar.ics") == 404, "#{status} answered"
    end

    assert status_of(conn, "/events/999999999/calendar.ics") == 404
    assert status_of(conn, "/events/not-an-id/calendar.ics") == 404
  end

  test "Calendar.ics/1 renders the body the route sends", %{conn: conn} do
    event = event_fixture(%{title: "Same body", location: "Annex"})
    conn = get(conn, "/events/#{event.id}/calendar.ics")
    # a DTSTAMP (the render's own time) may differ between the two renders
    sans_stamp = fn body -> body |> lines() |> Enum.reject(&String.starts_with?(&1, "DTSTAMP")) end
    rendered = Calendar.ics(ExRiverside.Events.get_event!(event.id))
    assert sans_stamp.(rendered) == sans_stamp.(conn.resp_body)
    assert "SUMMARY:Same body" in lines(rendered)
  end

  test "the public event page links to the file for a live event only", %{conn: conn} do
    live_event = event_fixture(%{title: "Linked"})
    {:ok, _view, html} = live(conn, ~p"/events/#{live_event}")
    assert html =~ ~s|href="/events/#{live_event.id}/calendar.ics"|

    draft = event_fixture(%{title: "Not linked", published: false})
    {:ok, _view, html} = live(conn, ~p"/events/#{draft}")
    refute html =~ "calendar.ics"
  end
end
