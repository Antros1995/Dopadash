import { afterEach, describe, expect, it, vi } from "vitest";

import { createPendingAction, resolveApproval } from "../src/approvals/service";
import { MicrosoftGraphClient } from "../src/outlook/graph";
import { createReminderTools, type ReminderScheduler } from "../src/reminders/tools";

afterEach(() => vi.restoreAllMocks());

function scheduler(): ReminderScheduler {
  return {
    scheduleMessage: vi.fn(async () => "schedule-message-1234"),
    scheduleCalendarBriefing: vi.fn(async () => "schedule-briefing-1234"),
    scheduleRecurringCalendarBriefing: vi.fn(
      async () => "schedule-recurring-1234",
    ),
    cancel: vi.fn(async () => undefined),
  };
}

describe("Persistent Telegram reminders", () => {
  it("refuses every real reminder write without an approval capability", async () => {
    const fetchSpy = vi.spyOn(globalThis, "fetch");
    const reminderScheduler = scheduler();
    const tools = createReminderTools(
      new MicrosoftGraphClient(async () => "access-token"),
      reminderScheduler,
    );
    await expect(
      tools
        .find(
          (candidate) =>
            candidate.name === "create_outlook_event_with_telegram_reminder",
        )!
        .execute({
          title: "Fare la spesa",
          startDateTime: "2099-08-13T09:00:00+02:00",
          endDateTime: "2099-08-13T09:30:00+02:00",
          telegramReminderDateTime: "2099-08-13T09:00:00+02:00",
        }),
    ).rejects.toThrow("Approved execution context required");
    await expect(
      tools.find((candidate) => candidate.name === "schedule_calendar_briefing")!
        .execute({
          deliveryDateTime: "2099-08-13T08:00:00+02:00",
          calendarStartDateTime: "2099-08-13T00:00:00+02:00",
          calendarEndDateTime: "2099-08-14T00:00:00+02:00",
        }),
    ).rejects.toThrow("Approved execution context required");
    expect(fetchSpy).not.toHaveBeenCalled();
    expect(reminderScheduler.scheduleMessage).not.toHaveBeenCalled();
    expect(reminderScheduler.scheduleCalendarBriefing).not.toHaveBeenCalled();
    expect(
      reminderScheduler.scheduleRecurringCalendarBriefing,
    ).not.toHaveBeenCalled();
  });

  it("creates the Outlook event and Telegram reminder only after approval", async () => {
    const fetchSpy = vi.spyOn(globalThis, "fetch").mockResolvedValue(
      new Response(JSON.stringify({ id: "event-1" }), {
        status: 201,
        headers: { "content-type": "application/json" },
      }),
    );
    const reminderScheduler = scheduler();
    const tool = createReminderTools(
      new MicrosoftGraphClient(async () => "access-token"),
      reminderScheduler,
    ).find((candidate) => candidate.name === "create_outlook_event_with_telegram_reminder")!;
    const parameters = {
      title: "Fare la spesa",
      startDateTime: "2099-08-13T09:00:00+02:00",
      endDateTime: "2099-08-13T09:30:00+02:00",
      telegramReminderDateTime: "2099-08-13T09:00:00+02:00",
    };
    const action = createPendingAction(
      tool,
      parameters,
      new Date(0),
      "00000000-0000-4000-8000-000000000001",
    );

    expect(fetchSpy).not.toHaveBeenCalled();
    expect(reminderScheduler.scheduleMessage).not.toHaveBeenCalled();

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
    expect(reminderScheduler.scheduleMessage).toHaveBeenCalledOnce();
    expect(fetchSpy).toHaveBeenCalledOnce();
    const [url, init] = fetchSpy.mock.calls[0]!;
    expect(String(url)).toBe("https://graph.microsoft.com/v1.0/me/events");
    expect(init?.method).toBe("POST");
    expect(JSON.parse(String(init?.body))).toMatchObject({
      subject: "Fare la spesa",
      start: {
        dateTime: "2099-08-13T07:00:00.000",
        timeZone: "UTC",
      },
      end: {
        dateTime: "2099-08-13T07:30:00.000",
        timeZone: "UTC",
      },
      isReminderOn: false,
    });
  });

  it("programs a future briefing without reading the calendar immediately", async () => {
    const fetchSpy = vi.spyOn(globalThis, "fetch");
    const reminderScheduler = scheduler();
    const tool = createReminderTools(
      new MicrosoftGraphClient(async () => "access-token"),
      reminderScheduler,
    ).find((candidate) => candidate.name === "schedule_calendar_briefing")!;

    const parameters = {
      deliveryDateTime: "2099-08-13T08:00:00+02:00",
      calendarStartDateTime: "2099-08-13T00:00:00+02:00",
      calendarEndDateTime: "2099-08-14T00:00:00+02:00",
    };
    const action = createPendingAction(
      tool,
      parameters,
      new Date(0),
      "00000000-0000-4000-8000-000000000002",
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
    expect(reminderScheduler.scheduleCalendarBriefing).toHaveBeenCalledWith(
      new Date("2099-08-13T08:00:00+02:00"),
      "2099-08-13T00:00:00+02:00",
      "2099-08-14T00:00:00+02:00",
    );
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it("programs a deduplicable recurring daily briefing only after approval", async () => {
    const reminderScheduler = scheduler();
    const tool = createReminderTools(
      new MicrosoftGraphClient(async () => "access-token"),
      reminderScheduler,
    ).find(
      (candidate) =>
        candidate.name === "schedule_recurring_daily_calendar_briefing",
    )!;
    const parameters = { deliveryTime: "08:00" };

    await expect(tool.execute(parameters)).rejects.toThrow(
      "Approved execution context required",
    );
    const action = createPendingAction(
      tool,
      parameters,
      new Date(0),
      "00000000-0000-4000-8000-000000000003",
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
    expect(
      reminderScheduler.scheduleRecurringCalendarBriefing,
    ).toHaveBeenCalledWith(8, 0);
  });
});
