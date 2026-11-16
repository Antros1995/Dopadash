import { beforeEach, describe, expect, it } from "vitest";

import { processTelegramUpdate } from "../src/telegram/processor";
import {
  AUTHORIZED_CHAT_ID,
  AUTHORIZED_USER_ID,
  FakeAgent,
  FakeTelegram,
  callbackUpdate,
  update,
} from "./fixtures";

describe("Telegram update processor", () => {
  let agent: FakeAgent;
  let telegram: FakeTelegram;

  beforeEach(() => {
    agent = new FakeAgent();
    telegram = new FakeTelegram();
  });

  async function process(text: string, userId?: number) {
    return processTelegramUpdate(
      update(text, userId),
      {
        agent,
        telegram,
        rateLimit: async () => true,
      },
      {
        allowedUserId: AUTHORIZED_USER_ID,
        allowedChatId: AUTHORIZED_CHAT_ID,
      },
      "request-123",
    );
  }

  it("responds to an authorized chat message", async () => {
    await expect(process("Ciao")).resolves.toBe("processed");
    expect(agent.chatCalls).toBe(1);
    expect(telegram.messages.at(-1)?.text).toBe("Risposta AI");
  });

  it("returns the exact Microsoft permission-management link without calling AI", async () => {
    await process("Come si chiama il sito per togliere le autorizzazioni?");
    expect(agent.chatCalls).toBe(0);
    expect(telegram.messages.at(-1)?.text).toContain(
      "https://account.live.com/consent/Manage",
    );
  });

  it("does nothing for an unauthorized user", async () => {
    await expect(process("Ciao", 999)).resolves.toBe("unauthorized");
    expect(agent.chatCalls).toBe(0);
    expect(telegram.messages).toHaveLength(0);
  });

  it("supports help and status without calling AI", async () => {
    await process("/help");
    await process("/status");
    expect(agent.chatCalls).toBe(0);
    expect(telegram.messages[0]?.text).toContain("SAFE MODE ON");
    expect(telegram.messages[1]?.text).toContain("Status: ACTIVE");
    expect(telegram.messages[1]?.text).toContain("Version: 0.7.0");
  });

  it("supports explicit memory commands without calling AI", async () => {
    await process("/remember Preferisco risposte concise");
    await process("/memory");
    expect(agent.chatCalls).toBe(0);
    expect(telegram.messages[1]?.text).toContain("Preferisco risposte concise");
  });

  it("returns the Microsoft login URL on outlook_connect", async () => {
    await process("/outlook_connect");
    expect(telegram.messages.at(-1)?.text).toContain(
      "https://login.microsoftonline.com/test",
    );
    expect(agent.chatCalls).toBe(0);
  });

  it("recognizes reminders without calling AI", async () => {
    await process("/reminders");
    expect(agent.chatCalls).toBe(0);
    expect(telegram.messages.at(-1)?.text).toContain(
      "Nessun promemoria programmato",
    );
  });

  it("cancels a Telegram reminder by its displayed ID without calling AI", async () => {
    agent.reminders = [
      {
        id: "a1b2c3d4-full-id",
        kind: "MESSAGE",
        scheduledAt: "2099-01-01T08:00:00.000Z",
        description: "Test",
        recurring: null,
      },
    ];
    await process("/reminder_cancel a1b2c3d4");
    expect(agent.chatCalls).toBe(0);
    expect(agent.reminders).toHaveLength(0);
    expect(telegram.messages.at(-1)?.text).toContain("cancellato");
    expect(telegram.messages.at(-1)?.text).toContain(
      "Nessun evento Outlook",
    );
  });

  it("shows follow-ups and Email Agent status without calling AI", async () => {
    agent.reminders = [
      {
        id: "followup1-full-id",
        kind: "EMAIL_FOLLOW_UP",
        scheduledAt: "2099-01-02T08:00:00.000Z",
        description: "Follow-up: Marco — Budget",
        recurring: null,
      },
    ];
    await process("/followups");
    await process("/email_status");
    expect(agent.chatCalls).toBe(0);
    expect(telegram.messages.at(-2)?.text).toContain("Marco");
    expect(telegram.messages.at(-1)?.text).toContain("ACTION_REQUIRED");
    expect(telegram.messages.at(-1)?.text).toContain("NON DISPONIBILE");
  });

  it("adds approval buttons for simulated write actions", async () => {
    agent.nextChatResult = {
      kind: "approval_required",
      text: "Anteprima",
      actionId: "00000000-0000-4000-8000-000000000001",
    };
    await process("Invia una email simulata");
    expect(telegram.messages.at(-1)?.approvalActionId).toBe(
      "00000000-0000-4000-8000-000000000001",
    );
  });

  it("processes an authorized approval callback", async () => {
    const actionId = "00000000-0000-4000-8000-000000000001";
    const result = await processTelegramUpdate(
      callbackUpdate(actionId, "approve"),
      { agent, telegram, rateLimit: async () => true },
      {
        allowedUserId: AUTHORIZED_USER_ID,
        allowedChatId: AUTHORIZED_CHAT_ID,
      },
      "request-123",
    );
    expect(result).toBe("processed");
    expect(agent.decisions).toEqual([{ actionId, decision: "approve" }]);
    expect(telegram.callbackAnswers.at(-1)?.text).toContain("eseguita");
    expect(telegram.edits.at(-1)?.text).toContain("Simulazione eseguita");
  });

  it("rejects approval callbacks from another user", async () => {
    const result = await processTelegramUpdate(
      callbackUpdate(
        "00000000-0000-4000-8000-000000000001",
        "approve",
        999,
      ),
      { agent, telegram, rateLimit: async () => true },
      {
        allowedUserId: AUTHORIZED_USER_ID,
        allowedChatId: AUTHORIZED_CHAT_ID,
      },
      "request-123",
    );
    expect(result).toBe("unauthorized");
    expect(agent.decisions).toHaveLength(0);
  });

  it("prevents AI calls after the kill switch", async () => {
    await process("/stop");
    await process("Questa richiesta non deve raggiungere il modello");
    expect(agent.mode).toBe("STOPPED");
    expect(agent.chatCalls).toBe(0);
    expect(telegram.messages.at(-1)?.text).toContain("fermo");
  });

  it("allows only the owner command to reactivate processing", async () => {
    await process("/stop");
    await process("/start");
    await process("Ciao di nuovo");
    expect(agent.mode).toBe("ACTIVE");
    expect(agent.chatCalls).toBe(1);
  });

  it("enforces the rate limiter before calling AI", async () => {
    const result = await processTelegramUpdate(
      update("Ciao"),
      {
        agent,
        telegram,
        rateLimit: async () => false,
      },
      {
        allowedUserId: AUTHORIZED_USER_ID,
        allowedChatId: AUTHORIZED_CHAT_ID,
      },
      "request-123",
    );

    expect(result).toBe("rate_limited");
    expect(agent.chatCalls).toBe(0);
    expect(telegram.messages.at(-1)?.text).toContain("Troppe richieste");
  });
});
