import { afterEach, describe, expect, it, vi } from "vitest";

import { createPendingAction, resolveApproval } from "../src/approvals/service";
import { MicrosoftGraphClient } from "../src/outlook/graph";
import {
  createOutlookEventReminderTools,
  resolveOutlookEventReminderDelivery,
  type OutlookEventReminderScheduler,
} from "../src/reminders/outlook-event-tools";

afterEach(() => vi.restoreAllMocks());

function event(
  overrides: Record<string, unknown> = {},
): Record<string, unknown> {
  return {
    id: "event-1",
    subject: "Dentista",
    start: { dateTime: "2099-08-22T18:00:00.000", timeZone: "UTC" },
    end: { dateTime: "2099-08-22T18:30:00.000", timeZone: "UTC" },
    location: { displayName: "Studio medico" },
    isCancelled: false,
    isAllDay: false,
    showAs: "busy",
    ...overrides,
  };
}

function response(body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status: 200,
    headers: { "content-type": "application/json" },
  });
}

function scheduler(): OutlookEventReminderScheduler & {
  scheduleEventReminder: ReturnType<typeof vi.fn>;
  cancel: ReturnType<typeof vi.fn>;
} {
  return {
    scheduleEventReminder: vi.fn(async () => "schedule-1"),
    cancel: vi.fn(async () => undefined),
  };
}

describe("Outlook-backed Telegram event reminders", () => {
  it("prepares today's exact recap with the default 15-minute lead without scheduling", async () => {
    const fetchSpy = vi
      .spyOn(globalThis, "fetch")
      .mockResolvedValue(response({ value: [event()] }));
    const reminderScheduler = scheduler();
    const tool = createOutlookEventReminderTools(
      new MicrosoftGraphClient(async () => "token"),
      reminderScheduler,
    ).find((candidate) => candidate.name === "schedule_outlook_day_event_reminders")!;

    const input = tool.validate({
      calendarStartDateTime: "2099-08-22T00:00:00+02:00",
      calendarEndDateTime: "2099-08-23T00:00:00+02:00",
      minutesBefore: "15",
    });
    const prepared = await tool.prepareApproval!(input);

    expect(prepared.preview).toContain("Anticipo: 15 minuti");
    expect(prepared.preview).toContain("Dentista");
    expect(prepared.preview).toContain("Studio medico");
    expect(reminderScheduler.scheduleEventReminder).not.toHaveBeenCalled();
    expect(fetchSpy).toHaveBeenCalledOnce();
    expect(fetchSpy.mock.calls[0]?.[1]?.method).toBe("GET");
    expect(fetchSpy.mock.calls[0]?.[1]?.headers).toMatchObject({
      prefer: expect.stringContaining('outlook.timezone="UTC"'),
    });
  });

  it("schedules the approved snapshot once and persists APPROVED first", async () => {
    const fetchSpy = vi
      .spyOn(globalThis, "fetch")
      .mockResolvedValueOnce(response({ value: [event()] }))
      .mockResolvedValueOnce(response(event()));
    const reminderScheduler = scheduler();
    const tool = createOutlookEventReminderTools(
      new MicrosoftGraphClient(async () => "token"),
      reminderScheduler,
    ).find((candidate) => candidate.name === "schedule_outlook_day_event_reminders")!;
    const prepared = await tool.prepareApproval!(
      tool.validate({
        calendarStartDateTime: "2099-08-22T00:00:00+02:00",
        calendarEndDateTime: "2099-08-23T00:00:00+02:00",
        minutesBefore: "15",
      }),
    );
    const action = createPendingAction(
      tool,
      prepared.parameters,
      new Date(0),
      "00000000-0000-4000-8000-000000000001",
      prepared.preview,
    );
    const persisted: string[][] = [];

    const approved = await resolveApproval({
      actions: [action],
      actionId: action.id,
      decision: "approve",
      agentMode: "ACTIVE",
      getTool: () => tool,
      now: new Date(1),
      onApproved: (actions) =>
        persisted.push(actions.map((candidate) => candidate.status)),
    });

    expect(approved.result.outcome).toBe("executed");
    expect(persisted).toEqual([["APPROVED"]]);
    expect(reminderScheduler.scheduleEventReminder).toHaveBeenCalledWith(
      new Date("2099-08-22T17:45:00.000Z"),
      { eventId: "event-1", eventTitle: "Dentista", minutesBefore: 15 },
    );
    expect(fetchSpy).toHaveBeenCalledTimes(2);

    const duplicate = await resolveApproval({
      actions: approved.actions,
      actionId: action.id,
      decision: "approve",
      agentMode: "ACTIVE",
      getTool: () => tool,
      now: new Date(2),
      onApproved: () => undefined,
    });
    expect(duplicate.result.outcome).toBe("already_handled");
    expect(reminderScheduler.scheduleEventReminder).toHaveBeenCalledOnce();
  });

  it("supports a custom one-hour reminder for one exact event", async () => {
    vi.spyOn(globalThis, "fetch")
      .mockResolvedValueOnce(response(event()))
      .mockResolvedValueOnce(response(event()));
    const reminderScheduler = scheduler();
    const tool = createOutlookEventReminderTools(
      new MicrosoftGraphClient(async () => "token"),
      reminderScheduler,
    ).find(
      (candidate) =>
        candidate.name === "schedule_specific_outlook_event_reminder",
    )!;
    const prepared = await tool.prepareApproval!(
      tool.validate({ eventId: "event-1", minutesBefore: "60" }),
    );
    expect(prepared.preview).toContain("Anticipo: 60 minuti");
    const action = createPendingAction(
      tool,
      prepared.parameters,
      new Date(0),
      "00000000-0000-4000-8000-000000000002",
      prepared.preview,
    );
    const approved = await resolveApproval({
      actions: [action],
      actionId: action.id,
      decision: "approve",
      agentMode: "ACTIVE",
      getTool: () => tool,
      now: new Date(1),
      onApproved: () => undefined,
    });
    expect(approved.result.outcome).toBe("executed");
    expect(reminderScheduler.scheduleEventReminder).toHaveBeenCalledWith(
      new Date("2099-08-22T17:00:00.000Z"),
      { eventId: "event-1", eventTitle: "Dentista", minutesBefore: 60 },
    );
  });

  it("blocks direct scheduling without approval and detects a changed event", async () => {
    const reminderScheduler = scheduler();
    const tool = createOutlookEventReminderTools(
      new MicrosoftGraphClient(async () => "token"),
      reminderScheduler,
    ).find(
      (candidate) =>
        candidate.name === "schedule_specific_outlook_event_reminder",
    )!;
    const preparedParameters = {
      selection: "single",
      minutesBefore: "15",
      eventsJson: JSON.stringify([
        {
          id: "event-1",
          title: "Dentista",
          startDateTime: "2099-08-22T18:00:00.000Z",
          endDateTime: "2099-08-22T18:30:00.000Z",
          location: "Studio medico",
        },
      ]),
    };
    const fetchSpy = vi.spyOn(globalThis, "fetch");
    await expect(tool.execute(preparedParameters)).rejects.toThrow(
      "Approved execution context required",
    );
    expect(fetchSpy).not.toHaveBeenCalled();

    fetchSpy.mockResolvedValue(
      response(event({ subject: "Dentista - nuovo titolo" })),
    );
    const action = createPendingAction(
      tool,
      preparedParameters,
      new Date(0),
      "00000000-0000-4000-8000-000000000003",
      "Preview originale",
    );
    const result = await resolveApproval({
      actions: [action],
      actionId: action.id,
      decision: "approve",
      agentMode: "ACTIVE",
      getTool: () => tool,
      now: new Date(1),
      onApproved: () => undefined,
    });
    expect(result.result.outcome).toBe("failed");
    expect(reminderScheduler.scheduleEventReminder).not.toHaveBeenCalled();
  });

  it("returns no approval action when today has only cancelled, all-day or free events", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(
      response({
        value: [
          event({ id: "cancelled", isCancelled: true }),
          event({ id: "all-day", isAllDay: true }),
          event({ id: "free", showAs: "free" }),
        ],
      }),
    );
    const reminderScheduler = scheduler();
    const tool = createOutlookEventReminderTools(
      new MicrosoftGraphClient(async () => "token"),
      reminderScheduler,
    ).find((candidate) => candidate.name === "schedule_outlook_day_event_reminders")!;
    const prepared = await tool.prepareApproval!(
      tool.validate({
        calendarStartDateTime: "2099-08-22T00:00:00+02:00",
        calendarEndDateTime: "2099-08-23T00:00:00+02:00",
        minutesBefore: "15",
      }),
    );
    expect(prepared.noActionResult?.message).toContain("Non ci sono eventi");
    expect(reminderScheduler.scheduleEventReminder).not.toHaveBeenCalled();
  });

  it("rechecks Outlook at delivery, reschedules moved events, and skips cancellations", async () => {
    const graph = new MicrosoftGraphClient(async () => "token");
    const fetchSpy = vi.spyOn(globalThis, "fetch");

    fetchSpy.mockResolvedValueOnce(
      response(
        event({
          start: { dateTime: "2099-08-22T20:00:00.000", timeZone: "UTC" },
          end: { dateTime: "2099-08-22T20:30:00.000", timeZone: "UTC" },
        }),
      ),
    );
    const moved = await resolveOutlookEventReminderDelivery(
      graph,
      { eventId: "event-1", eventTitle: "Dentista", minutesBefore: 60 },
      new Date("2099-08-22T18:00:00.000Z"),
    );
    expect(moved).toMatchObject({
      kind: "reschedule",
      at: new Date("2099-08-22T19:00:00.000Z"),
    });

    fetchSpy.mockResolvedValueOnce(response(event({ isCancelled: true })));
    await expect(
      resolveOutlookEventReminderDelivery(
        graph,
        { eventId: "event-1", eventTitle: "Dentista", minutesBefore: 60 },
        new Date("2099-08-22T17:00:00.000Z"),
      ),
    ).resolves.toEqual({ kind: "skip" });
  });

  it("builds the Telegram message when the approved reminder is due", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(response(event()));
    const delivery = await resolveOutlookEventReminderDelivery(
      new MicrosoftGraphClient(async () => "token"),
      { eventId: "event-1", eventTitle: "Dentista", minutesBefore: 60 },
      new Date("2099-08-22T17:00:00.000Z"),
    );
    expect(delivery).toMatchObject({ kind: "send" });
    if (delivery.kind === "send") {
      expect(delivery.text).toContain("Tra 60 minuti: Dentista");
      expect(delivery.text).toContain("Studio medico");
    }
  });
});
