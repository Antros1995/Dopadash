import { afterEach, describe, expect, it, vi } from "vitest";

import { createPendingAction, resolveApproval } from "../src/approvals/service";
import { classifyEmail } from "../src/email/classifier";
import {
  createEmailFollowUpTools,
  resolveEmailFollowUp,
  type EmailFollowUpScheduler,
} from "../src/email/follow-up-tools";
import {
  createImportantEmailTools,
  type ImportantEmailMonitorScheduler,
} from "../src/email/important-email-tools";
import { MicrosoftGraphClient } from "../src/outlook/graph";

afterEach(() => vi.restoreAllMocks());

function response(body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status: 200,
    headers: { "content-type": "application/json" },
  });
}

describe("Email importance classification", () => {
  it("uses the three requested stable classifications", () => {
    expect(classifyEmail({ subject: "Newsletter di agosto" }).classification).toBe(
      "INFORMATIONAL",
    );
    expect(
      classifyEmail({ subject: "Avviso di sicurezza importante" }).classification,
    ).toBe("IMPORTANT");
    expect(
      classifyEmail({ subject: "Action required: approve by Friday" })
        .classification,
    ).toBe("ACTION_REQUIRED");
  });

  it("notifies only IMPORTANT and ACTION_REQUIRED messages", async () => {
    const fetchSpy = vi.spyOn(globalThis, "fetch").mockResolvedValue(
      response({
        value: [
          {
            id: "info-1",
            subject: "Newsletter",
            receivedDateTime: "2099-08-21T08:00:00Z",
          },
          {
            id: "important-1",
            subject: "Servizio non disponibile",
            receivedDateTime: "2099-08-21T08:01:00Z",
          },
          {
            id: "action-1",
            subject: "Conferma richiesta entro domani",
            receivedDateTime: "2099-08-21T08:02:00Z",
          },
        ],
      }),
    );
    const scheduler: ImportantEmailMonitorScheduler = {
      enable: vi.fn(async () => "email-monitor-1"),
      disable: vi.fn(async () => true),
    };
    const tool = createImportantEmailTools(
      new MicrosoftGraphClient(async () => "token"),
      scheduler,
    ).find((candidate) => candidate.name === "list_important_emails")!;
    const result = await tool.execute({
      sinceDateTime: "2099-08-21T00:00:00Z",
    });
    const emails = (result.data as { emails: Array<{ id: string }> }).emails;

    expect(emails.map((email) => email.id)).toEqual([
      "important-1",
      "action-1",
    ]);
    expect(fetchSpy).toHaveBeenCalledOnce();
    expect(fetchSpy.mock.calls[0]?.[1]?.method).toBe("GET");
  });

  it("requires approval before enabling the persistent monitor", async () => {
    const scheduler: ImportantEmailMonitorScheduler = {
      enable: vi.fn(async () => "email-monitor-1"),
      disable: vi.fn(async () => true),
    };
    const tool = createImportantEmailTools(
      new MicrosoftGraphClient(async () => "token"),
      scheduler,
    ).find(
      (candidate) => candidate.name === "enable_important_email_monitor",
    )!;
    await expect(tool.execute({})).rejects.toThrow(
      "Approved execution context required",
    );

    const action = createPendingAction(
      tool,
      {},
      new Date(0),
      "00000000-0000-4000-8000-000000000010",
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
    expect(result.result.outcome).toBe("executed");
    expect(scheduler.enable).toHaveBeenCalledOnce();
  });
});

describe("Email follow-up agent", () => {
  function scheduler(): EmailFollowUpScheduler {
    return { scheduleFollowUp: vi.fn(async () => "follow-up-1") };
  }

  const sentMessage = {
    id: "sent-1",
    conversationId: "conversation-1",
    subject: "Budget 2027",
    sentDateTime: "2099-08-20T08:00:00Z",
    toRecipients: [
      { emailAddress: { name: "Marco", address: "marco@example.com" } },
    ],
  };

  it("resolves the sent message before approval and schedules no email send", async () => {
    const fetchSpy = vi
      .spyOn(globalThis, "fetch")
      .mockResolvedValue(response({ value: [sentMessage] }));
    const followUpScheduler = scheduler();
    const tool = createEmailFollowUpTools(
      new MicrosoftGraphClient(async () => "token"),
      followUpScheduler,
    )[0]!;
    const input = tool.validate({
      contactQuery: "Marco",
      deadlineDateTime: "2099-08-28T18:00:00+02:00",
    });
    const prepared = await tool.prepareApproval!(input);

    expect(prepared.preview).toContain("Marco <marco@example.com>");
    expect(prepared.preview).toContain("Non invierà email");
    expect(followUpScheduler.scheduleFollowUp).not.toHaveBeenCalled();

    const action = createPendingAction(
      tool,
      prepared.parameters,
      new Date(0),
      "00000000-0000-4000-8000-000000000011",
      prepared.preview,
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

    expect(result.result.outcome).toBe("executed");
    expect(followUpScheduler.scheduleFollowUp).toHaveBeenCalledOnce();
    expect(fetchSpy).toHaveBeenCalledOnce();
    expect(fetchSpy.mock.calls[0]?.[1]?.method).toBe("GET");
  });

  it("stays silent when the expected contact replied", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(
      response({
        value: [
          {
            id: "reply-1",
            conversationId: "conversation-1",
            receivedDateTime: "2099-08-21T08:00:00Z",
            from: { emailAddress: { address: "marco@example.com" } },
          },
        ],
      }),
    );
    await expect(
      resolveEmailFollowUp(
        new MicrosoftGraphClient(async () => "token"),
        {
          conversationId: "conversation-1",
          contactName: "Marco",
          contactAddress: "marco@example.com",
          subject: "Budget 2027",
          sentDateTime: "2099-08-20T08:00:00Z",
          deadlineDateTime: "2099-08-28T16:00:00Z",
        },
      ),
    ).resolves.toEqual({ kind: "replied" });
  });

  it("returns a Telegram warning when no reply arrived", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(response({ value: [] }));
    const result = await resolveEmailFollowUp(
      new MicrosoftGraphClient(async () => "token"),
      {
        conversationId: "conversation-1",
        contactName: "Marco",
        contactAddress: "marco@example.com",
        subject: "Budget 2027",
        sentDateTime: "2099-08-20T08:00:00Z",
        deadlineDateTime: "2099-08-28T16:00:00Z",
      },
    );
    expect(result.kind).toBe("notify");
    if (result.kind === "notify") {
      expect(result.text).toContain("Non risulta ancora una risposta");
      expect(result.text).toContain("Nessuna email è stata inviata");
    }
  });

  it("can perform the check after the scheduled deadline has passed", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(response({ value: [] }));
    await expect(
      resolveEmailFollowUp(
        new MicrosoftGraphClient(async () => "token"),
        {
          conversationId: "conversation-old",
          contactName: "Marco",
          contactAddress: "marco@example.com",
          subject: "Budget precedente",
          sentDateTime: "2020-08-20T08:00:00Z",
          deadlineDateTime: "2020-08-28T16:00:00Z",
        },
      ),
    ).resolves.toMatchObject({ kind: "notify" });
  });
});
