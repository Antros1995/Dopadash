import { afterEach, describe, expect, it, vi } from "vitest";

import { createPendingAction, resolveApproval } from "../src/approvals/service";
import { createCalendarWriteTools } from "../src/outlook/calendar-write-tools";
import { MicrosoftGraphClient } from "../src/outlook/graph";
import { ToolRisk } from "../src/security/risk";

afterEach(() => vi.restoreAllMocks());

function calendarTool() {
  return createCalendarWriteTools(
    new MicrosoftGraphClient(async () => "access-token"),
  )[0]!;
}

const parameters = {
  title: "Andare dal dentista",
  startDateTime: "2099-08-22T20:00:00+02:00",
  endDateTime: "2099-08-22T20:30:00+02:00",
};

function graphCreatedResponse(): Response {
  return new Response(
    JSON.stringify({
      id: "event-1",
      webLink: "https://outlook.office.com/calendar/item/event-1",
    }),
    { status: 201, headers: { "content-type": "application/json" } },
  );
}

describe("Approved Outlook calendar writes", () => {
  it("exposes creation as an approval-gated write and exposes no delete tool", () => {
    const tools = createCalendarWriteTools(
      new MicrosoftGraphClient(async () => "access-token"),
    );
    expect(tools).toHaveLength(1);
    expect(tools[0]).toMatchObject({
      name: "create_outlook_calendar_event",
      risk: ToolRisk.WRITE_LOW_RISK,
      exposedToModel: true,
    });
    expect(tools.some((tool) => tool.name.includes("delete"))).toBe(false);
  });

  it("refuses direct execution without an approval capability", async () => {
    const fetchSpy = vi.spyOn(globalThis, "fetch");
    await expect(calendarTool().execute(parameters)).rejects.toThrow(
      "Approved execution context required",
    );
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it("shows an exact recap without writing before approval", () => {
    const fetchSpy = vi.spyOn(globalThis, "fetch");
    const action = createPendingAction(
      calendarTool(),
      parameters,
      new Date(0),
      "00000000-0000-4000-8000-000000000001",
    );
    expect(action.preview).toContain("PROPOSTA CREAZIONE EVENTO OUTLOOK");
    expect(action.preview).toContain("Andare dal dentista");
    expect(action.preview).toContain("20:00 (Europe/Rome)");
    expect(action.preview).not.toContain("+02:00");
    expect(action.status).toBe("PENDING");
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it("does not write when the owner rejects the recap", async () => {
    const fetchSpy = vi.spyOn(globalThis, "fetch");
    const tool = calendarTool();
    const action = createPendingAction(
      tool,
      parameters,
      new Date(0),
      "00000000-0000-4000-8000-000000000001",
    );
    const rejected = await resolveApproval({
      actions: [action],
      actionId: action.id,
      decision: "reject",
      agentMode: "ACTIVE",
      getTool: () => tool,
      now: new Date(1),
      onApproved: () => undefined,
    });
    expect(rejected.result.outcome).toBe("rejected");
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it("does not write when approval is expired or the kill switch is active", async () => {
    const fetchSpy = vi.spyOn(globalThis, "fetch");
    const tool = calendarTool();
    const expiredAction = createPendingAction(
      tool,
      parameters,
      new Date(0),
      "00000000-0000-4000-8000-000000000001",
    );
    const expired = await resolveApproval({
      actions: [expiredAction],
      actionId: expiredAction.id,
      decision: "approve",
      agentMode: "ACTIVE",
      getTool: () => tool,
      now: new Date(11 * 60 * 1_000),
      onApproved: () => undefined,
    });
    expect(expired.result.outcome).toBe("expired");

    const stoppedAction = createPendingAction(
      tool,
      parameters,
      new Date(0),
      "00000000-0000-4000-8000-000000000002",
    );
    const stopped = await resolveApproval({
      actions: [stoppedAction],
      actionId: stoppedAction.id,
      decision: "approve",
      agentMode: "STOPPED",
      getTool: () => tool,
      now: new Date(1),
      onApproved: () => undefined,
    });
    expect(stopped.result.outcome).toBe("blocked");
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it("persists APPROVED before one exact idempotent Graph POST", async () => {
    const fetchSpy = vi
      .spyOn(globalThis, "fetch")
      .mockResolvedValue(graphCreatedResponse());
    const persistedStatuses: string[][] = [];
    const tool = calendarTool();
    const original = { ...parameters };
    const action = createPendingAction(
      tool,
      original,
      new Date(0),
      "00000000-0000-4000-8000-000000000001",
    );
    original.title = "Titolo alterato";

    const first = await resolveApproval({
      actions: [action],
      actionId: action.id,
      decision: "approve",
      agentMode: "ACTIVE",
      getTool: () => tool,
      now: new Date(1),
      onApproved: (actions) => {
        persistedStatuses.push(actions.map((candidate) => candidate.status));
      },
    });
    expect(first.result.outcome).toBe("executed");
    expect(persistedStatuses).toEqual([["APPROVED"]]);
    expect(fetchSpy).toHaveBeenCalledOnce();

    const [url, init] = fetchSpy.mock.calls[0]!;
    expect(String(url)).toBe("https://graph.microsoft.com/v1.0/me/events");
    expect(init?.method).toBe("POST");
    expect(JSON.parse(String(init?.body))).toMatchObject({
      subject: "Andare dal dentista",
      start: {
        dateTime: "2099-08-22T18:00:00.000",
        timeZone: "UTC",
      },
      end: {
        dateTime: "2099-08-22T18:30:00.000",
        timeZone: "UTC",
      },
      isReminderOn: true,
      reminderMinutesBeforeStart: 0,
      transactionId: action.id,
    });

    const second = await resolveApproval({
      actions: first.actions,
      actionId: action.id,
      decision: "approve",
      agentMode: "ACTIVE",
      getTool: () => tool,
      now: new Date(2),
      onApproved: () => undefined,
    });
    expect(second.result.outcome).toBe("already_handled");
    expect(fetchSpy).toHaveBeenCalledOnce();
  });
});
