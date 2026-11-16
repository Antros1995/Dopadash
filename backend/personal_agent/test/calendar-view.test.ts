import { describe, expect, it, vi } from "vitest";

import {
  readCalendarDay,
  requireCalendarDate,
  zonedMidnightToUtc,
} from "../src/outlook/calendar-view";
import type { MicrosoftGraphClient } from "../src/outlook/graph";

describe("desktop Outlook calendar view", () => {
  it("uses the correct Rome offset in winter and summer", () => {
    expect(zonedMidnightToUtc("2026-01-15")).toBe(
      "2026-01-14T23:00:00.000Z",
    );
    expect(zonedMidnightToUtc("2026-08-25")).toBe(
      "2026-08-24T22:00:00.000Z",
    );
  });

  it("rejects impossible dates", () => {
    expect(() => requireCalendarDate("2026-02-30")).toThrow(
      "Invalid calendar date",
    );
  });

  it("sanitizes the Graph response and keeps the calendar timezone", async () => {
    const get = vi.fn(async () => ({
      value: [
        {
          id: "event-1",
          subject: "  Riunione   progetto  ",
          start: { dateTime: "2026-08-25T09:00:00.0000000", timeZone: "Europe/Rome" },
          end: { dateTime: "2026-08-25T10:00:00.0000000", timeZone: "Europe/Rome" },
          location: { displayName: "Sala 1" },
        },
      ],
    }));
    const graph = { get } as unknown as MicrosoftGraphClient;
    const result = await readCalendarDay(graph, "2026-08-25");
    expect(result.events[0]?.subject).toBe("Riunione progetto");
    expect(result.timeZone).toBe("Europe/Rome");
    expect(get).toHaveBeenCalledWith(
      "/me/calendar/calendarView",
      expect.objectContaining({
        startDateTime: "2026-08-24T22:00:00.000Z",
        endDateTime: "2026-08-25T22:00:00.000Z",
      }),
    );
  });
});
