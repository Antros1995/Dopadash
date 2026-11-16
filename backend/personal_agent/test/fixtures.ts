import type {
  AgentGateway,
  AgentStatus,
  CalendarDayView,
  ChatResult,
  ReminderView,
} from "../src/agent/types";
import type { FitbitView } from "../src/fitbit/types";
import type { ApprovalDecision, ApprovalResult } from "../src/approvals/types";
import type { MemoryView } from "../src/memory/types";
import type { TelegramClient, TelegramUpdate } from "../src/telegram/types";

export const AUTHORIZED_USER_ID = "123456789";
export const AUTHORIZED_CHAT_ID = "123456789";

export function update(
  text: string,
  userId = Number(AUTHORIZED_USER_ID),
  chatId = Number(AUTHORIZED_CHAT_ID),
): TelegramUpdate {
  return {
    update_id: 42,
    message: {
      message_id: 7,
      from: { id: userId, is_bot: false },
      chat: { id: chatId, type: "private" },
      date: 1_700_000_000,
      text,
    },
  };
}

export function callbackUpdate(
  actionId: string,
  decision: ApprovalDecision,
  userId = Number(AUTHORIZED_USER_ID),
  chatId = Number(AUTHORIZED_CHAT_ID),
): TelegramUpdate {
  return {
    update_id: 43,
    callback_query: {
      id: "callback-1",
      from: { id: userId, is_bot: false },
      data: `pa:${decision}:${actionId}`,
      message: {
        message_id: 8,
        chat: { id: chatId, type: "private" },
        date: 1_700_000_001,
        text: "Anteprima simulazione",
      },
    },
  };
}

export class FakeAgent implements AgentGateway {
  mode: AgentStatus["mode"] = "ACTIVE";
  chatCalls = 0;
  decisions: Array<{ actionId: string; decision: ApprovalDecision }> = [];
  memory: MemoryView = {
    enabled: true,
    conversationItems: 0,
    longTerm: [],
  };
  nextChatResult: ChatResult = { kind: "reply", text: "Risposta AI" };
  reminders: ReminderView[] = [];

  async getStatus(): Promise<AgentStatus> {
    return {
      mode: this.mode,
      safeMode: true,
      aiConnected: true,
      telegramWhitelist: "OK",
      outlook: "NOT CONNECTED",
      importantEmailMonitor: "OFF",
      followUps: 0,
      habit: "NOT CONNECTED",
      fitbit: "NOT CONNECTED",
      sharedTasks: "CONFIGURED",
      pendingApprovals: 0,
      memoryEnabled: this.memory.enabled,
      updatedAt: new Date(0).toISOString(),
    };
  }

  async stop(): Promise<AgentStatus> {
    this.mode = "STOPPED";
    return this.getStatus();
  }

  async start(): Promise<AgentStatus> {
    this.mode = "ACTIVE";
    return this.getStatus();
  }

  async chat(): Promise<ChatResult> {
    this.chatCalls += 1;
    return this.nextChatResult;
  }

  async decideAction(
    actionId: string,
    decision: ApprovalDecision,
  ): Promise<ApprovalResult> {
    this.decisions.push({ actionId, decision });
    return decision === "approve"
      ? { outcome: "executed", text: "Simulazione eseguita" }
      : { outcome: "rejected", text: "Azione rifiutata" };
  }

  async getMemory(): Promise<MemoryView> {
    return this.memory;
  }

  async remember(content: string): Promise<MemoryView> {
    if (this.memory.enabled) {
      this.memory = {
        ...this.memory,
        longTerm: [
          ...this.memory.longTerm,
          { id: "memory-1", content, createdAt: new Date(0).toISOString() },
        ],
      };
    }
    return this.memory;
  }

  async clearMemory(): Promise<MemoryView> {
    this.memory = { ...this.memory, conversationItems: 0, longTerm: [] };
    return this.memory;
  }

  async clearConversation(): Promise<MemoryView> {
    this.memory = { ...this.memory, conversationItems: 0 };
    return this.memory;
  }

  async setMemoryEnabled(enabled: boolean): Promise<MemoryView> {
    this.memory = { ...this.memory, enabled };
    return this.memory;
  }

  async beginMicrosoftConnect(): Promise<{ url: string }> {
    return { url: "https://login.microsoftonline.com/test" };
  }

  async readExpenseWorkbook(_link: string): Promise<{ bytes: Uint8Array | null; error?: string; status?: number }> {
    return { bytes: null, status: 409, error: "OneDrive not connected" };
  }

  async completeMicrosoftConnect(): Promise<{
    connected: true;
    accountLabel: string | null;
  }> {
    return { connected: true, accountLabel: "test@example.com" };
  }

  async disconnectMicrosoft(): Promise<{ connected: false }> {
    return { connected: false };
  }

  async readCalendarDay(date: string): Promise<CalendarDayView> {
    return { date, timeZone: "Europe/Rome", events: [] };
  }

  async beginFitbitConnect(): Promise<{ url: string }> {
    return { url: "https://www.fitbit.com/oauth2/authorize" };
  }

  async completeFitbitConnect(): Promise<{
    connected: true;
    deviceName: string | null;
  }> {
    return { connected: true, deviceName: "Charge 6" };
  }

  async readFitbitDay(): Promise<FitbitView> {
    return {
      configured: true,
      connection: "CONNECTED",
      deviceName: "Charge 6",
      day: null,
    };
  }

  async readFitbitHistory(): Promise<{ days: NonNullable<FitbitView["day"]>[] }> {
    return { days: [] };
  }

  async setFitbitMindfulness(): Promise<FitbitView> {
    return this.readFitbitDay();
  }

  async syncFitbitCurrentDay(): Promise<void> {}

  async listReminders(): Promise<ReminderView[]> {
    return this.reminders;
  }

  async cancelReminder(idOrPrefix: string) {
    const reminder = this.reminders.find((candidate) =>
      candidate.id.startsWith(idOrPrefix),
    );
    if (!reminder) return { outcome: "not_found" as const };
    this.reminders = this.reminders.filter(
      (candidate) => candidate.id !== reminder.id,
    );
    return { outcome: "cancelled" as const, reminder };
  }
}

export class FakeTelegram implements TelegramClient {
  messages: Array<{
    chatId: number;
    text: string;
    approvalActionId?: string;
  }> = [];
  callbackAnswers: Array<{ callbackQueryId: string; text: string }> = [];
  edits: Array<{ chatId: number; messageId: number; text: string }> = [];

  async sendMessage(
    chatId: number,
    text: string,
    options?: { approvalActionId?: string },
  ): Promise<void> {
    this.messages.push({ chatId, text, ...options });
  }

  async answerCallbackQuery(callbackQueryId: string, text: string): Promise<void> {
    this.callbackAnswers.push({ callbackQueryId, text });
  }

  async editMessageText(
    chatId: number,
    messageId: number,
    text: string,
  ): Promise<void> {
    this.edits.push({ chatId, messageId, text });
  }
}
