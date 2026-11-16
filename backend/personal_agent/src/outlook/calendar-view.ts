import type { CalendarDayView, CalendarEventView } from "../agent/types";
import type { MicrosoftGraphClient } from "./graph";

interface GraphCollection<T> {
  value: T[];
}

interface GraphEvent {
  id?: string;
  subject?: string;
  start?: { dateTime?: string; timeZone?: string };
  end?: { dateTime?: string; timeZone?: string };
  location?: { displayName?: string };
  isAllDay?: boolean;
  isCancelled?: boolean;
}

const TIME_ZONE = "Europe/Rome";

function safeText(value: unknown, max: number): string {
  return typeof value === "string"
    ? value.replace(/\s+/gu, " ").trim().slice(0, max)
    : "";
}

export function requireCalendarDate(value: string): string {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/u.exec(value);
  if (!match) throw new Error("Invalid calendar date");
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const date = new Date(Date.UTC(year, month - 1, day));
  if (
    date.getUTCFullYear() !== year ||
    date.getUTCMonth() + 1 !== month ||
    date.getUTCDate() !== day
  ) {
    throw new Error("Invalid calendar date");
  }
  return value;
}

function nextDate(value: string): string {
  const [year, month, day] = value.split("-").map(Number) as [number, number, number];
  const next = new Date(Date.UTC(year, month - 1, day + 1));
  return [
    String(next.getUTCFullYear()).padStart(4, "0"),
    String(next.getUTCMonth() + 1).padStart(2, "0"),
    String(next.getUTCDate()).padStart(2, "0"),
  ].join("-");
}

function wallClockParts(date: Date, timeZone: string): number[] {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hourCycle: "h23",
  }).formatToParts(date);
  const part = (type: Intl.DateTimeFormatPartTypes): number =>
    Number(parts.find((candidate) => candidate.type === type)?.value ?? "NaN");
  return [
    part("year"),
    part("month"),
    part("day"),
    part("hour"),
    part("minute"),
    part("second"),
  ];
}

export function zonedMidnightToUtc(
  value: string,
  timeZone = TIME_ZONE,
): string {
  requireCalendarDate(value);
  const [year, month, day] = value.split("-").map(Number) as [number, number, number];
  const desired = Date.UTC(year, month - 1, day, 0, 0, 0);
  let guess = desired;
  for (let attempt = 0; attempt < 3; attempt += 1) {
    const parts = wallClockParts(new Date(guess), timeZone);
    const represented = Date.UTC(
      parts[0]!,
      parts[1]! - 1,
      parts[2]!,
      parts[3]!,
      parts[4]!,
      parts[5]!,
    );
    guess += desired - represented;
  }
  return new Date(guess).toISOString();
}

function eventView(event: GraphEvent): CalendarEventView | null {
  const id = safeText(event.id, 1_000);
  const startDateTime = safeText(event.start?.dateTime, 100);
  const endDateTime = safeText(event.end?.dateTime, 100);
  if (!id || !startDateTime || !endDateTime) return null;
  return {
    id,
    subject: safeText(event.subject, 500) || "Senza titolo",
    start: {
      dateTime: startDateTime,
      timeZone: safeText(event.start?.timeZone, 100) || TIME_ZONE,
    },
    end: {
      dateTime: endDateTime,
      timeZone: safeText(event.end?.timeZone, 100) || TIME_ZONE,
    },
    location: safeText(event.location?.displayName, 500),
    isAllDay: event.isAllDay ?? false,
    isCancelled: event.isCancelled ?? false,
  };
}

export async function readCalendarDay(
  graph: MicrosoftGraphClient,
  rawDate: string,
): Promise<CalendarDayView> {
  const date = requireCalendarDate(rawDate);
  const response = await graph.get<GraphCollection<GraphEvent>>(
    "/me/calendar/calendarView",
    {
      startDateTime: zonedMidnightToUtc(date),
      endDateTime: zonedMidnightToUtc(nextDate(date)),
      "$top": "50",
      "$orderby": "start/dateTime",
      "$select": "id,subject,start,end,location,isAllDay,isCancelled",
    },
  );
  return {
    date,
    timeZone: TIME_ZONE,
    events: response.value
      .map(eventView)
      .filter((event): event is CalendarEventView => event !== null),
  };
}
