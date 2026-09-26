Next, a feature: an "Add to calendar" file for events, so a member can put one in their own
calendar.

`GET /events/:id/calendar.ics` answers a live event (status `:published` or `:ongoing`) as an
iCalendar file: content type `text/calendar`, sent as an attachment named `event-<id>.ics`. The
body is one VCALENDAR (`VERSION:2.0`, a `PRODID`) holding one VEVENT with:

- `UID`: `event-<id>@riverside`;
- `DTSTART`, and `DTEND` when the event has an end, in UTC as `YYYYMMDDTHHMMSSZ`;
- `SUMMARY`: the title; `DESCRIPTION`: the description; `LOCATION`: the location's name, when
  the event has one; `URL`: the event's page, `/events/<id>` on the endpoint's URL;
- text values escaped as RFC 5545 wants: `\`, `;` and `,` backslash-escaped, a newline as `\n`.

Lines end with CRLF. Any other status, or an id that is no event, answers 404. Put the rendering
in `ExRiverside.Events.Calendar.ics/1` (an event in, the body out) so it can be tested on its own,
and add an "Add to calendar" link to the file on the public event page of every live event. Test
it.
