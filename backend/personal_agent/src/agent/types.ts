import type { ApprovalDecision, ApprovalResult, PendingAction } from "../approvals/types";
import type { MemoryState, MemoryView } from "../memory/types";
import type { MicrosoftConnectionState } from "../outlook/types";
import type { ImportantEmailMonitorState } from "../email/types";
import type { FitbitConnectionState, FitbitView } from "../fitbit/types";

export type AgentMode = "ACTIVE" | "STOPPED";

export interface PersonalAgentState {
  schemaVersion: 5;
  mode: AgentMode;
  updatedAt: string;
  stoppedAt: string | null;
  memory: MemoryState;
  pendingActions: PendingAction[];
  microsoft: MicrosoftConnectionState;
  importantEmailMonitor: ImportantEmailMonitorState;
  fitbit: FitbitConnectionState;
}

export interface AgentStatus {
  mode: AgentMode;
  safeMode: true;
  aiConnected: boolean;
  telegramWhitelist: "OK";
  outlook: "NOT CONFIGURED" | "NOT CONNECTED" | "PENDING" | "CONNECTED";
  importantEmailMonitor: "ON" | "OFF";
  followUps: number;
  habit: "NOT CONNECTED";
  fitbit: "NOT CONFIGURED" | "NOT CONNECTED" | "PENDING" | "CONNECTED";
  sharedTasks: "CONFIGURED" | "NOT CONFIGURED";
  pendingApprovals: number;
  memoryEnabled: boolean;
  updatedAt: string;
}

export interface ReminderView {
  id: string;
  kind:
    | "MESSAGE"
    | "CALENDAR_BRIEFING"
    | "RECURRING_CALENDAR_BRIEFING"
    | "OUTLOOK_EVENT"
    | "EMAIL_FOLLOW_UP"
    | "IMPORTANT_EMAIL_MONITOR";
  scheduledAt: string;
  description: string;
  recurring: string | null;
}

export type CancelReminderResult =
  | { outcome: "cancelled"; reminder: ReminderView }
  | { outcome: "not_found" }
  | { outcome: "ambiguous" };

export interface CalendarEventView {
  id: string;
  subject: string;
  start: { dateTime: string; timeZone: string };
  end: { dateTime: string; timeZone: string };
  location: string;
  isAllDay: boolean;
  isCancelled: boolean;
}

export interface CalendarDayView {
  date: string;
  timeZone: "Europe/Rome";
  events: CalendarEventView[];
}

export type ChatResult =
  | { kind: "reply"; text: string }
  | { kind: "blocked"; text: string }
  | { kind: "approval_required"; text: string; actionId: string };

export interface AgentGateway {
  getStatus(): Promise<AgentStatus>;
  stop(): Promise<AgentStatus>;
  start(): Promise<AgentStatus>;
  chat(
    message: string,
    requestId: string,
    telegramUserId: string,
  ): Promise<ChatResult>;
  decideAction(
    actionId: string,
    decision: ApprovalDecision,
    requestId: string,
  ): Promise<ApprovalResult>;
  getMemory(): Promise<MemoryView>;
  remember(content: string): Promise<MemoryView>;
  clearMemory(): Promise<MemoryView>;
  clearConversation(): Promise<MemoryView>;
  setMemoryEnabled(enabled: boolean): Promise<MemoryView>;
  beginMicrosoftConnect(fileAccess?: boolean): Promise<{ url: string }>;
  readExpenseWorkbook(link: string): Promise<{ bytes: Uint8Array | null; error?: string; status?: number }>;
  completeMicrosoftConnect(
    code: string,
    state: string,
  ): Promise<{ connected: true; accountLabel: string | null }>;
  disconnectMicrosoft(): Promise<{ connected: false }>;
  readCalendarDay(date: string): Promise<CalendarDayView>;
  beginFitbitConnect(): Promise<{ url: string }>;
  completeFitbitConnect(
    code: string,
    state: string,
  ): Promise<{ connected: true; deviceName: string | null }>;
  readFitbitDay(date: string): Promise<FitbitView>;
  readFitbitHistory(): Promise<{ days: NonNullable<FitbitView["day"]>[] }>;
  setFitbitMindfulness(date: string, minutes: number | null): Promise<FitbitView>;
  syncFitbitCurrentDay(): Promise<void>;
  listReminders(): Promise<ReminderView[]>;
  cancelReminder(idOrPrefix: string): Promise<CancelReminderResult>;
}
