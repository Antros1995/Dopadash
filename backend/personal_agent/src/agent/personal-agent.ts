import { Agent } from "agents";
import { persistStatisticsDay } from '../fitbit/statistics-storage';
import { ExpenseDownloadError } from "../expenses/onedrive-download.mjs";

import {
  appendPendingAction,
  createPendingAction,
  expireActions,
  pendingCount,
  resolveApproval,
} from "../approvals/service";
import type {
  ApprovalDecision,
  ApprovalResult,
} from "../approvals/types";
import { SAFE_MODE } from "../config/constants";
import { getRuntimeConfig } from "../config/runtime";
import {
  createEmailFollowUpTools,
  resolveEmailFollowUp,
  type EmailFollowUpPayload,
} from "../email/follow-up-tools";
import {
  createImportantEmailTools,
  readImportantEmailsSince,
} from "../email/important-email-tools";
import { emptyImportantEmailMonitorState } from "../email/types";
import { fetchFitbitDay, fetchFitbitDevice } from "../fitbit/api";
import { savedFitbitHistory } from "../fitbit/history";
import {
  beginFitbitAuthorization,
  completeFitbitAuthorization,
  emptyFitbitConnection,
  getValidFitbitAccessToken,
} from "../fitbit/auth";
import type { FitbitConnectionState, FitbitView } from "../fitbit/types";
import {
  addLongTermMemory,
  appendConversation,
  emptyMemoryState,
  normalizeMemoryState,
} from "../memory/service";
import type { MemoryView } from "../memory/types";
import { createAiProvider } from "../model/factory";
import {
  beginMicrosoftAuthorization,
  completeMicrosoftAuthorization,
  emptyMicrosoftConnection,
  getValidMicrosoftAccessToken,
  readMicrosoftProfile,
} from "../outlook/auth";
import {
  MicrosoftGraphClient,
  microsoftErrorUserHint,
} from "../outlook/graph";
import { readCalendarDay as fetchCalendarDay } from "../outlook/calendar-view";
import { createOutlookTools } from "../outlook/tools";
import { createCalendarWriteTools } from "../outlook/calendar-write-tools";
import { createSharedTaskTools } from "../tasks/tools";
import { createReminderTools } from "../reminders/tools";
import {
  createOutlookEventReminderTools,
  resolveOutlookEventReminderDelivery,
  type OutlookEventReminderPayload,
} from "../reminders/outlook-event-tools";
import { decideToolPolicy } from "../security/risk";
import { fitTelegramMessage } from "../security/input";
import { log, serializeError } from "../storage/logger";
import { combineTools, getModelTools, getTool } from "../tools/registry";
import { BotApiTelegramClient } from "../telegram/client";
import type { ToolDefinition } from "../tools/types";
import type {
  AgentStatus,
  CalendarDayView,
  CancelReminderResult,
  ChatResult,
  PersonalAgentState,
  ReminderView,
} from "./types";

interface TelegramReminderPayload {
  text: string;
  scheduledFor?: string;
}

interface CalendarBriefingPayload {
  startDateTime: string;
  endDateTime: string;
  scheduledFor?: string;
}

interface RecurringCalendarBriefingPayload {
  hour: number;
  minute: number;
  timeZone: "Europe/Rome";
}

interface ImportantEmailMonitorPayload {
  monitorVersion: 1;
}

interface CalendarBriefingEvent {
  subject?: string;
  start?: { dateTime?: string; timeZone?: string };
  end?: { dateTime?: string; timeZone?: string };
  location?: { displayName?: string };
  isCancelled?: boolean;
}

interface GraphCollection<T> {
  value: T[];
}

function safeReminderText(value: unknown, max = 500): string {
  return typeof value === "string"
    ? value.replace(/\s+/gu, " ").trim().slice(0, max)
    : "";
}

function formatRomeDateTime(value: string | undefined): string {
  if (!value) return "orario non disponibile";
  // Graph returns a local wall-clock value when the Prefer timezone header is
  // used. Do not reinterpret that value as UTC, otherwise Rome gets shifted.
  const local = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})/u.exec(value);
  const hasExplicitZone = /(?:Z|[+-]\d{2}:\d{2})$/u.test(value);
  if (local && !hasExplicitZone) {
    return `${local[3]}/${local[2]}, ${local[4]}:${local[5]}`;
  }
  const date = new Date(value);
  if (!Number.isFinite(date.getTime())) return safeReminderText(value, 100);
  return new Intl.DateTimeFormat("it-IT", {
    timeZone: "Europe/Rome",
    day: "2-digit",
    month: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
  }).format(date);
}

function romeDateParts(date: Date): {
  year: number;
  month: number;
  day: number;
  hour: number;
  minute: number;
} {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Europe/Rome",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
  }).formatToParts(date);
  const value = (type: Intl.DateTimeFormatPartTypes): number =>
    Number(parts.find((part) => part.type === type)?.value ?? "NaN");
  return {
    year: value("year"),
    month: value("month"),
    day: value("day"),
    hour: value("hour"),
    minute: value("minute"),
  };
}

function romeDateKey(date: Date): string {
  const parts = romeDateParts(date);
  return `${String(parts.year).padStart(4, "0")}-${String(parts.month).padStart(2, "0")}-${String(parts.day).padStart(2, "0")}`;
}

function timeZoneOffsetMs(date: Date, timeZone: string): number {
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
  const value = (type: Intl.DateTimeFormatPartTypes): number =>
    Number(parts.find((part) => part.type === type)?.value ?? "NaN");
  return (
    Date.UTC(
      value("year"),
      value("month") - 1,
      value("day"),
      value("hour"),
      value("minute"),
      value("second"),
    ) - date.getTime()
  );
}

function romeMidnightUtc(year: number, month: number, day: number): Date {
  const localAsUtc = Date.UTC(year, month - 1, day, 0, 0, 0);
  let guess = new Date(localAsUtc);
  for (let attempt = 0; attempt < 2; attempt += 1) {
    guess = new Date(localAsUtc - timeZoneOffsetMs(guess, "Europe/Rome"));
  }
  return guess;
}

function romeDayInterval(now: Date): CalendarBriefingPayload {
  const local = romeDateParts(now);
  const nextLocalDate = new Date(Date.UTC(local.year, local.month - 1, local.day + 1));
  return {
    startDateTime: romeMidnightUtc(local.year, local.month, local.day).toISOString(),
    endDateTime: romeMidnightUtc(
      nextLocalDate.getUTCFullYear(),
      nextLocalDate.getUTCMonth() + 1,
      nextLocalDate.getUTCDate(),
    ).toISOString(),
  };
}

async function privacyPreservingIdentifier(value: string): Promise<string> {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest), (byte) =>
    byte.toString(16).padStart(2, "0"),
  ).join("");
}

export class PersonalAgent extends Agent<Env, PersonalAgentState> {
  initialState: PersonalAgentState = {
    schemaVersion: 5,
    mode: "ACTIVE",
    updatedAt: new Date(0).toISOString(),
    stoppedAt: null,
    memory: emptyMemoryState(),
    pendingActions: [],
    microsoft: emptyMicrosoftConnection(),
    importantEmailMonitor: emptyImportantEmailMonitorState(),
    fitbit: emptyFitbitConnection(),
  };

  async getStatus(): Promise<AgentStatus> {
    const state = this.currentState();
    const actions = expireActions(state.pendingActions);
    if (JSON.stringify(actions) !== JSON.stringify(state.pendingActions)) {
      this.saveState({ ...state, pendingActions: actions });
    }
    const schedules = await this.listSchedules();
    return {
      mode: state.mode,
      safeMode: SAFE_MODE,
      aiConnected: Boolean(this.env.OPENAI_API_KEY),
      telegramWhitelist: "OK",
      outlook: !getRuntimeConfig(this.env).microsoft.configured
        ? "NOT CONFIGURED"
        : state.microsoft.status === "DISCONNECTED"
          ? "NOT CONNECTED"
          : state.microsoft.status,
      importantEmailMonitor: state.importantEmailMonitor.enabled ? "ON" : "OFF",
      followUps: schedules.filter(
        (schedule) => schedule.callback === "checkEmailFollowUp",
      ).length,
      habit: "NOT CONNECTED",
      fitbit: !getRuntimeConfig(this.env).fitbit.configured
        ? "NOT CONFIGURED"
        : state.fitbit.status === "DISCONNECTED"
          ? "NOT CONNECTED"
          : state.fitbit.status,
      sharedTasks: getRuntimeConfig(this.env).sharedTasks.configured
        ? "CONFIGURED"
        : "NOT CONFIGURED",
      pendingApprovals: pendingCount(actions),
      memoryEnabled: state.memory.enabled,
      updatedAt: state.updatedAt,
    };
  }

  async stop(): Promise<AgentStatus> {
    const state = this.currentState();
    if (state.mode !== "STOPPED") {
      const now = new Date().toISOString();
      this.saveState({ ...state, mode: "STOPPED", stoppedAt: now, updatedAt: now });
    }
    return this.getStatus();
  }

  async start(): Promise<AgentStatus> {
    const state = this.currentState();
    if (state.mode !== "ACTIVE") {
      this.saveState({
        ...state,
        mode: "ACTIVE",
        stoppedAt: null,
        updatedAt: new Date().toISOString(),
      });
    }
    return this.getStatus();
  }

  async chat(
    message: string,
    requestId: string,
    telegramUserId: string,
  ): Promise<ChatResult> {
    let state = this.currentState();
    if (state.mode === "STOPPED") {
      return {
        kind: "blocked",
        text: "L'agente è fermo. Usa /start per riattivarlo.",
      };
    }

    const config = getRuntimeConfig(this.env);
    const provider = createAiProvider(this.env, config);
    const memory = normalizeMemoryState(state.memory);
    const availableTools = this.availableTools(state);
    const toolMap = new Map(availableTools.map((tool) => [tool.name, tool]));
    const result = await provider.generateText({
      message,
      conversation: memory.enabled ? memory.conversation : [],
      longTermMemories: memory.enabled
        ? memory.longTerm.map((item) => item.content)
        : [],
      tools: availableTools.filter((tool) => tool.exposedToModel),
      handleToolCall: async (call) => {
        const tool = toolMap.get(call.name);
        if (!tool) {
          return { kind: "blocked", text: "Il tool richiesto non è autorizzato." };
        }

        const parameters = tool.validate(call.arguments);
        const policy = decideToolPolicy(tool.risk, state.mode);
        log("info", {
          event: "tool_call_evaluated",
          requestId,
          tool: tool.name,
          riskLevel: tool.risk,
          parameterNames: Object.keys(parameters),
          decision: policy,
        });

        if (policy === "BLOCK") {
          return { kind: "blocked", text: "Questa operazione non è consentita." };
        }
        if (policy === "REQUIRE_APPROVAL") {
          const prepared = tool.prepareApproval
            ? await tool.prepareApproval(parameters)
            : { parameters, preview: undefined, noActionResult: undefined };
          if (prepared.noActionResult) {
            return {
              kind: "output",
              output: JSON.stringify(prepared.noActionResult),
            };
          }
          const action = createPendingAction(
            tool,
            prepared.parameters,
            new Date(),
            crypto.randomUUID(),
            prepared.preview,
          );
          state = {
            ...state,
            pendingActions: appendPendingAction(state.pendingActions, action),
            updatedAt: new Date().toISOString(),
          };
          this.saveState(state);
          return {
            kind: "approval_required",
            actionId: action.id,
            text: `${action.preview}\n\n${tool.name.endsWith("_mock") ? "Questa è soltanto una simulazione." : "Usa i pulsanti qui sotto per confermare o annullare."}`,
          };
        }

        const execution = await tool.execute(parameters);
        log("info", {
          event: "tool_executed",
          requestId,
          tool: tool.name,
          riskLevel: tool.risk,
          simulated: execution.simulated,
        });
        return { kind: "output", output: JSON.stringify(execution) };
      },
      requestId,
      safetyIdentifier: await privacyPreservingIdentifier(telegramUserId),
    });

    state = {
      ...state,
      memory: appendConversation(
        appendConversation(state.memory, "user", message),
        "assistant",
        result.text,
      ),
      updatedAt: new Date().toISOString(),
    };
    this.saveState(state);

    log("info", {
      event: "ai_response_completed",
      requestId,
      model: config.ai.model,
      inputTokens: result.usage.inputTokens,
      outputTokens: result.usage.outputTokens,
      estimatedCostUsd: result.usage.estimatedCostUsd,
    });

    const text = fitTelegramMessage(result.text);
    return result.approvalRequest
      ? {
          kind: "approval_required",
          text,
          actionId: result.approvalRequest.actionId,
        }
      : { kind: "reply", text };
  }

  async decideAction(
    actionId: string,
    decision: ApprovalDecision,
    requestId: string,
  ): Promise<ApprovalResult> {
    const state = this.currentState();
    const now = new Date();
    const toolMap = new Map(
      this.availableTools(state).map((tool) => [tool.name, tool]),
    );
    const resolved = await resolveApproval({
      actions: state.pendingActions,
      actionId,
      decision,
      agentMode: state.mode,
      getTool: (name) => toolMap.get(name) ?? getTool(name),
      now,
      onApproved: (actions) => {
        this.saveState({
          ...state,
          pendingActions: actions,
          updatedAt: now.toISOString(),
        });
      },
    });
    this.saveState({
      ...state,
      pendingActions: resolved.actions,
      updatedAt: new Date().toISOString(),
    });
    log(resolved.result.outcome === "failed" ? "error" : "info", {
      event: `pending_action_${resolved.result.outcome}`,
      requestId,
      actionId,
      tool: resolved.toolName,
      simulated: resolved.toolName?.endsWith("_mock") ?? false,
      ...(resolved.error
        ? {
            error: serializeError(resolved.error, [
              this.env.OPENAI_API_KEY,
              this.env.TELEGRAM_BOT_TOKEN,
              this.env.MICROSOFT_CLIENT_SECRET,
              this.env.MICROSOFT_TOKEN_ENCRYPTION_KEY,
            ]),
          }
        : {}),
    });
    if (resolved.result.outcome !== "failed") return resolved.result;
    const hint = microsoftErrorUserHint(resolved.error);
    return {
      ...resolved.result,
      text: `Operazione non riuscita.${hint ? `\n${hint}` : ""}\nID errore: ${requestId}`,
    };
  }

  async listReminders(): Promise<ReminderView[]> {
    const schedules = await this.listSchedules();
    return schedules
      .filter(
        (schedule) =>
          schedule.callback === "deliverTelegramReminder" ||
          schedule.callback === "deliverCalendarBriefing" ||
          schedule.callback === "deliverRecurringCalendarBriefing" ||
          schedule.callback === "deliverOutlookEventReminder" ||
          schedule.callback === "checkEmailFollowUp" ||
          schedule.callback === "scanImportantEmails",
      )
      .map((schedule): ReminderView => {
        const payload = schedule.payload as Partial<
          TelegramReminderPayload &
            CalendarBriefingPayload &
            RecurringCalendarBriefingPayload &
            OutlookEventReminderPayload &
            EmailFollowUpPayload &
            ImportantEmailMonitorPayload
        >;
        const isBriefing = schedule.callback === "deliverCalendarBriefing";
        const isRecurringBriefing =
          schedule.callback === "deliverRecurringCalendarBriefing";
        const isOutlookEvent =
          schedule.callback === "deliverOutlookEventReminder";
        const isFollowUp = schedule.callback === "checkEmailFollowUp";
        const isEmailMonitor = schedule.callback === "scanImportantEmails";
        return {
          id: schedule.id,
          kind: isEmailMonitor
            ? "IMPORTANT_EMAIL_MONITOR"
            : isFollowUp
              ? "EMAIL_FOLLOW_UP"
              : isRecurringBriefing
                ? "RECURRING_CALENDAR_BRIEFING"
                : isBriefing
                  ? "CALENDAR_BRIEFING"
                  : isOutlookEvent
                    ? "OUTLOOK_EVENT"
                    : "MESSAGE",
          scheduledAt: new Date(schedule.time * 1_000).toISOString(),
          description: isEmailMonitor
            ? "Email Agent: notifica email IMPORTANT/ACTION_REQUIRED"
            : isFollowUp
              ? `Follow-up: ${safeReminderText(payload.contactName, 160)} — ${safeReminderText(payload.subject, 160)}`
              : isRecurringBriefing
                ? `Agenda Outlook giornaliera alle ${String(payload.hour ?? 8).padStart(2, "0")}:${String(payload.minute ?? 0).padStart(2, "0")}`
                : isBriefing
                  ? "Riepilogo degli impegni Outlook"
                  : isOutlookEvent
                    ? `${safeReminderText(payload.eventTitle, 160) || "Evento Outlook"} (${payload.minutesBefore ?? 15} min prima)`
                    : safeReminderText(payload.text, 200) || "Promemoria Telegram",
          recurring: isEmailMonitor
            ? "ogni 15 minuti"
            : isRecurringBriefing
              ? `ogni giorno alle ${String(payload.hour ?? 8).padStart(2, "0")}:${String(payload.minute ?? 0).padStart(2, "0")} Europe/Rome`
              : null,
        };
      })
      .sort((left, right) => left.scheduledAt.localeCompare(right.scheduledAt));
  }

  async cancelReminder(idOrPrefix: string): Promise<CancelReminderResult> {
    const normalized = idOrPrefix.trim();
    if (!/^[A-Za-z0-9_-]{8,128}$/u.test(normalized)) {
      return { outcome: "not_found" };
    }
    const reminders = await this.listReminders();
    const matches = reminders.filter(
      (reminder) => reminder.id === normalized || reminder.id.startsWith(normalized),
    );
    if (matches.length === 0) return { outcome: "not_found" };
    if (matches.length > 1) return { outcome: "ambiguous" };
    const reminder = matches[0]!;
    if (!(await this.cancelSchedule(reminder.id))) return { outcome: "not_found" };
    if (reminder.kind === "IMPORTANT_EMAIL_MONITOR") {
      const state = this.currentState();
      this.saveState({
        ...state,
        importantEmailMonitor: emptyImportantEmailMonitorState(),
        updatedAt: new Date().toISOString(),
      });
    }
    return { outcome: "cancelled", reminder };
  }

  async deliverTelegramReminder(payload: TelegramReminderPayload): Promise<void> {
    if (this.currentState().mode !== "ACTIVE") return;
    const text = safeReminderText(payload?.text, 2_000);
    if (!text) throw new Error("Invalid scheduled Telegram reminder");
    const config = getRuntimeConfig(this.env);
    await new BotApiTelegramClient(this.env.TELEGRAM_BOT_TOKEN).sendMessage(
      Number(config.telegram.allowedChatId),
      text,
    );
  }

  async deliverCalendarBriefing(payload: CalendarBriefingPayload): Promise<void> {
    const state = this.currentState();
    if (state.mode !== "ACTIVE") return;
    if (
      typeof payload?.startDateTime !== "string" ||
      typeof payload?.endDateTime !== "string"
    ) {
      throw new Error("Invalid scheduled calendar briefing");
    }
    const graph = this.microsoftGraphClient();
    const response = await graph.get<GraphCollection<CalendarBriefingEvent>>(
      "/me/calendar/calendarView",
      {
        startDateTime: payload.startDateTime,
        endDateTime: payload.endDateTime,
        "$top": "50",
        "$orderby": "start/dateTime",
        "$select": "subject,start,end,location,isCancelled",
      },
    );
    const events = response.value.filter((event) => !event.isCancelled);
    const lines = events.slice(0, 20).map((event) => {
      const title = safeReminderText(event.subject, 300) || "Senza titolo";
      const location = safeReminderText(event.location?.displayName, 200);
      return `- ${formatRomeDateTime(event.start?.dateTime)} — ${title}${location ? ` (${location})` : ""}`;
    });
    const message =
      lines.length === 0
        ? "Agenda Outlook: non risultano impegni nell'intervallo programmato."
        : `Agenda Outlook aggiornata:\n\n${lines.join("\n")}`;
    const config = getRuntimeConfig(this.env);
    await new BotApiTelegramClient(this.env.TELEGRAM_BOT_TOKEN).sendMessage(
      Number(config.telegram.allowedChatId),
      message,
    );
  }

  async deliverRecurringCalendarBriefing(
    payload: RecurringCalendarBriefingPayload,
  ): Promise<void> {
    if (
      !payload ||
      payload.timeZone !== "Europe/Rome" ||
      !Number.isInteger(payload.hour) ||
      payload.hour < 0 ||
      payload.hour > 23 ||
      !Number.isInteger(payload.minute) ||
      payload.minute < 0 ||
      payload.minute > 59
    ) {
      throw new Error("Invalid recurring calendar briefing");
    }
    const now = new Date();
    const local = romeDateParts(now);
    if (local.hour !== payload.hour || local.minute !== payload.minute) return;
    await this.deliverCalendarBriefing(romeDayInterval(now));
  }

  async scanImportantEmails(
    payload: ImportantEmailMonitorPayload,
  ): Promise<void> {
    const state = this.currentState();
    if (
      state.mode !== "ACTIVE" ||
      !state.importantEmailMonitor.enabled ||
      payload?.monitorVersion !== 1
    ) {
      return;
    }
    const scanStartedAt = new Date();
    const since = new Date(
      state.importantEmailMonitor.lastScanAt ?? scanStartedAt.toISOString(),
    );
    const emails = await readImportantEmailsSince(
      this.microsoftGraphClient(),
      since,
    );
    const alreadyNotified = new Set(
      state.importantEmailMonitor.notifiedMessageIds,
    );
    const newEmails = emails.filter(
      (email) => email.id && !alreadyNotified.has(email.id),
    );
    if (newEmails.length > 0) {
      const lines = newEmails.slice(0, 10).map((email) => {
        const sender = email.senderName || email.senderAddress || "mittente sconosciuto";
        return `[${email.classification}] ${email.subject}\nDa: ${sender}`;
      });
      const remainder =
        newEmails.length > 10
          ? `\n\nAltre ${newEmails.length - 10} email importanti non mostrate.`
          : "";
      const config = getRuntimeConfig(this.env);
      await new BotApiTelegramClient(this.env.TELEGRAM_BOT_TOKEN).sendMessage(
        Number(config.telegram.allowedChatId),
        fitTelegramMessage(
          `EMAIL IMPORTANTI\n\n${lines.join("\n\n")}${remainder}\n\nClassificazione automatica in sola lettura. Nessuna email è stata inviata o modificata.`,
        ),
      );
    }
    const latestState = this.currentState();
    if (!latestState.importantEmailMonitor.enabled) return;
    const notifiedMessageIds = [
      ...latestState.importantEmailMonitor.notifiedMessageIds,
      ...newEmails.map((email) => email.id),
    ].slice(-500);
    this.saveState({
      ...latestState,
      importantEmailMonitor: {
        ...latestState.importantEmailMonitor,
        // Keep a small overlap so a message committed during the scan is not lost.
        lastScanAt: new Date(scanStartedAt.getTime() - 60_000).toISOString(),
        notifiedMessageIds,
      },
      updatedAt: new Date().toISOString(),
    });
  }

  async checkEmailFollowUp(payload: EmailFollowUpPayload): Promise<void> {
    if (this.currentState().mode !== "ACTIVE") return;
    const config = getRuntimeConfig(this.env);
    const telegram = new BotApiTelegramClient(this.env.TELEGRAM_BOT_TOKEN);
    try {
      const result = await resolveEmailFollowUp(
        this.microsoftGraphClient(),
        payload,
      );
      if (result.kind === "notify") {
        await telegram.sendMessage(
          Number(config.telegram.allowedChatId),
          result.text,
        );
      }
    } catch {
      await telegram.sendMessage(
        Number(config.telegram.allowedChatId),
        `FOLLOW-UP EMAIL\n\nNon ho potuto verificare se ${safeReminderText(payload?.contactName, 160) || "il contatto"} ha risposto. Controlla Outlook e, se necessario, ricollegalo con /outlook_connect.\n\nNessuna email è stata inviata.`,
      );
    }
  }

  async deliverOutlookEventReminder(
    payload: OutlookEventReminderPayload,
  ): Promise<void> {
    if (this.currentState().mode !== "ACTIVE") return;
    const delivery = await resolveOutlookEventReminderDelivery(
      this.microsoftGraphClient(),
      payload,
    );
    if (delivery.kind === "skip") return;
    if (delivery.kind === "reschedule") {
      await this.schedule(
        delivery.at,
        "deliverOutlookEventReminder",
        delivery.payload,
        { idempotent: true },
      );
      return;
    }
    const config = getRuntimeConfig(this.env);
    await new BotApiTelegramClient(this.env.TELEGRAM_BOT_TOKEN).sendMessage(
      Number(config.telegram.allowedChatId),
      delivery.text,
    );
  }

  async getMemory(): Promise<MemoryView> {
    return this.memoryView(this.currentState());
  }

  async remember(content: string): Promise<MemoryView> {
    const state = this.currentState();
    if (!state.memory.enabled) return this.memoryView(state);
    const next = {
      ...state,
      memory: addLongTermMemory(state.memory, content),
      updatedAt: new Date().toISOString(),
    };
    this.saveState(next);
    return this.memoryView(next);
  }

  async clearMemory(): Promise<MemoryView> {
    const state = this.currentState();
    const next = {
      ...state,
      memory: { ...emptyMemoryState(), enabled: state.memory.enabled },
      updatedAt: new Date().toISOString(),
    };
    this.saveState(next);
    return this.memoryView(next);
  }

  async clearConversation(): Promise<MemoryView> {
    const state = this.currentState();
    const next = {
      ...state,
      memory: { ...state.memory, conversation: [] },
      updatedAt: new Date().toISOString(),
    };
    this.saveState(next);
    return this.memoryView(next);
  }

  async setMemoryEnabled(enabled: boolean): Promise<MemoryView> {
    const state = this.currentState();
    const next = {
      ...state,
      memory: { ...state.memory, enabled },
      updatedAt: new Date().toISOString(),
    };
    this.saveState(next);
    return this.memoryView(next);
  }

  async beginMicrosoftConnect(fileAccess = false): Promise<{ url: string }> {
    const config = getRuntimeConfig(this.env);
    if (!config.microsoft.configured) {
      throw new Error("Microsoft integration is not configured");
    }
    const state = this.currentState();
    const authorization = await beginMicrosoftAuthorization(config.microsoft, new Date(), fileAccess || state.microsoft.fileAccess === true);
    this.saveState({
      ...state,
      microsoft: authorization.state,
      updatedAt: new Date().toISOString(),
    });
    return { url: authorization.url };
  }

  async completeMicrosoftConnect(
    code: string,
    returnedState: string,
  ): Promise<{ connected: true; accountLabel: string | null }> {
    const config = getRuntimeConfig(this.env);
    if (!config.microsoft.configured) {
      throw new Error("Microsoft integration is not configured");
    }
    const state = this.currentState();
    const completed = await completeMicrosoftAuthorization(
      state.microsoft,
      config.microsoft,
      code,
      returnedState,
    );
    const profile = await readMicrosoftProfile(completed.accessToken);
    const accountLabel =
      profile.mail ?? profile.userPrincipalName ?? profile.displayName ?? null;
    this.saveState({
      ...state,
      microsoft: { ...completed.state, accountLabel },
      updatedAt: new Date().toISOString(),
    });
    log("info", {
      event: "microsoft_connected",
      requestId: "microsoft-oauth-callback",
      accountLabelPresent: Boolean(accountLabel),
    });
    return { connected: true, accountLabel };
  }

  async disconnectMicrosoft(): Promise<{ connected: false }> {
    const state = this.currentState();
    this.saveState({
      ...state,
      microsoft: emptyMicrosoftConnection(),
      updatedAt: new Date().toISOString(),
    });
    log("info", {
      event: "microsoft_disconnected",
      requestId: "telegram-command",
    });
    return { connected: false };
  }

  async readCalendarDay(date: string): Promise<CalendarDayView> {
    const state = this.currentState();
    if (state.microsoft.status !== "CONNECTED") {
      throw new Error("Microsoft account is not connected");
    }
    return fetchCalendarDay(this.microsoftGraphClient(), date);
  }

  async readExpenseWorkbook(link: string): Promise<{ bytes: Uint8Array | null; error?: string; status?: number }> {
    const state = this.currentState();
    if (state.microsoft.status !== "CONNECTED" || !state.microsoft.fileAccess) {
      return { bytes: null, status: 409, error: "Apri Fonte Excel e premi Collega OneDrive per autorizzare la lettura del file aggiornato." };
    }
    try {
      return { bytes: await this.microsoftGraphClient().downloadExpenseWorkbook(link) };
    } catch (error) {
      return { bytes: null, status: error instanceof ExpenseDownloadError ? error.status : 503,
        error: error instanceof ExpenseDownloadError ? error.message : "Collegamento Microsoft scaduto. Ricollega OneDrive da Fonte Excel." };
    }
  }

  async beginFitbitConnect(): Promise<{ url: string }> {
    const config = getRuntimeConfig(this.env);
    if (!config.fitbit.configured) throw new Error("Fitbit integration is not configured");
    const state = this.currentState();
    const authorization = await beginFitbitAuthorization(
      config.fitbit,
      state.fitbit.days,
    );
    this.saveState({
      ...state,
      fitbit: authorization.state,
      updatedAt: new Date().toISOString(),
    });
    return { url: authorization.url };
  }

  async completeFitbitConnect(
    code: string,
    returnedState: string,
  ): Promise<{ connected: true; deviceName: string | null }> {
    const config = getRuntimeConfig(this.env);
    if (!config.fitbit.configured) throw new Error("Fitbit integration is not configured");
    const state = this.currentState();
    const completed = await completeFitbitAuthorization(
      state.fitbit,
      config.fitbit,
      code,
      returnedState,
    );

    // Persist the OAuth tokens before making optional Google Health API calls.
    // A newly connected account may need a few moments before paired devices
    // and health data become available; that must not invalidate authorization.
    this.saveState({
      ...state,
      fitbit: completed.state,
      updatedAt: new Date().toISOString(),
    });

    let deviceName: string | null = null;
    try {
      deviceName = await fetchFitbitDevice(completed.accessToken);
    } catch (error) {
      console.warn("Google Health paired device lookup deferred", {
        message: error instanceof Error ? error.message.slice(0, 200) : "unknown",
      });
    }

    let syncScheduleId: string | null = null;
    try {
      const schedule = await this.schedule(
        "*/15 * * * *",
        "syncFitbitCurrentDay",
        {},
        { idempotent: true },
      );
      syncScheduleId = schedule.id;
    } catch (error) {
      console.warn("Google Health sync schedule creation deferred", {
        message: error instanceof Error ? error.message.slice(0, 200) : "unknown",
      });
    }

    const connectedState = this.currentState();
    this.saveState({
      ...connectedState,
      fitbit: {
        ...connectedState.fitbit,
        deviceName,
        syncScheduleId,
      },
      updatedAt: new Date().toISOString(),
    });

    try {
      await this.syncFitbitCurrentDay();
    } catch (error) {
      console.warn("Initial Google Health data sync deferred", {
        message: error instanceof Error ? error.message.slice(0, 200) : "unknown",
      });
    }
    return { connected: true, deviceName };
  }

  async readFitbitHistory(): Promise<{ days: NonNullable<FitbitView["day"]>[] }> {
    // Read saved snapshots only: viewing statistics never starts a Fitbit sync.
    return savedFitbitHistory(this.currentState().fitbit.days);
  }

  async readFitbitDay(date: string): Promise<FitbitView> {
    if (!/^\d{4}-\d{2}-\d{2}$/u.test(date)) throw new Error("Invalid Fitbit date");
    const config = getRuntimeConfig(this.env);
    let state = this.currentState();
    if (!config.fitbit.configured || state.fitbit.status !== "CONNECTED") {
      return {
        configured: config.fitbit.configured,
        connection: state.fitbit.status,
        deviceName: state.fitbit.deviceName,
        day: state.fitbit.days[date] ?? null,
      };
    }
    const today = romeDateKey(new Date());
    const cached = state.fitbit.days[date];
    const needsSchemaUpgrade = cached != null && cached.schemaVersion !== 7;
    const recentlySynced = cached && Date.now() - Date.parse(cached.syncedAt) < 4 * 60_000;
    if (
      (needsSchemaUpgrade || !cached?.finalized) &&
      (!recentlySynced || needsSchemaUpgrade) &&
      date <= today
    ) {
      try {
        await this.syncFitbitDate(date, date < today);
        state = this.currentState();
      } catch (error) {
        if (!cached) throw error;
        console.warn("Google Health sync failed; serving cached day", {
          date,
          status: error instanceof Error ? /status (\d{3})\b/u.exec(error.message)?.[1] : undefined,
        });
      }
    }
    return {
      configured: true,
      connection: state.fitbit.status,
      deviceName: state.fitbit.deviceName,
      day: state.fitbit.days[date] ?? null,
    };
  }

  async syncFitbitCurrentDay(): Promise<void> {
    const state = this.currentState();
    if (state.fitbit.status !== "CONNECTED") return;
    const today = romeDateKey(new Date());
    const unfinished = Object.values(state.fitbit.days)
      .filter((day) => !day.finalized && day.date < today)
      .sort((left, right) => left.date.localeCompare(right.date));
    for (const day of unfinished) await this.syncFitbitDate(day.date, true);
    await this.syncFitbitDate(today, false);
  }

  async setFitbitMindfulness(
    date: string,
    minutes: number | null,
  ): Promise<FitbitView> {
    if (!/^\d{4}-\d{2}-\d{2}$/u.test(date)) throw new Error("Invalid Fitbit date");
    if (
      minutes !== null &&
      (!Number.isInteger(minutes) || minutes < 0 || minutes > 1_440)
    ) {
      throw new Error("Invalid mindfulness minutes");
    }
    let state = this.currentState();
    if (!state.fitbit.days[date] && state.fitbit.status === "CONNECTED") {
      const today = romeDateKey(new Date());
      if (date <= today) await this.syncFitbitDate(date, date < today);
      state = this.currentState();
    }
    const day = state.fitbit.days[date];
    if (!day) throw new Error("Fitbit day is not available");
    const fitbit: FitbitConnectionState = {
      ...state.fitbit,
      days: {
        ...state.fitbit.days,
        [date]: { ...day, mindfulnessMinutes: minutes },
      },
    };
    this.saveState({ ...state, fitbit, updatedAt: new Date().toISOString() });
    return {
      configured: true,
      connection: fitbit.status,
      deviceName: fitbit.deviceName,
      day: fitbit.days[date] ?? null,
    };
  }

  private async syncFitbitDate(date: string, finalized: boolean): Promise<void> {
    const config = getRuntimeConfig(this.env);
    const state = this.currentState();
    if (!config.fitbit.configured || state.fitbit.status !== "CONNECTED") return;
    let token = await getValidFitbitAccessToken(state.fitbit, config.fitbit);
    if (token.state !== state.fitbit) {
      this.saveState({ ...state, fitbit: token.state, updatedAt: new Date().toISOString() });
    }
    let fetchedDay: Awaited<ReturnType<typeof fetchFitbitDay>>;
    try {
      fetchedDay = await fetchFitbitDay(date, token.accessToken, finalized);
    } catch (error) {
      if (!(error instanceof Error) || !/Google Health API request failed with status 401/u.test(error.message)) {
        throw error;
      }
      const current = this.currentState();
      token = await getValidFitbitAccessToken(current.fitbit, config.fitbit, new Date(), true);
      this.saveState({ ...current, fitbit: token.state, updatedAt: new Date().toISOString() });
      fetchedDay = await fetchFitbitDay(date, token.accessToken, finalized);
    }
    const day = {
      ...fetchedDay,
      mindfulnessMinutes: state.fitbit.days[date]?.mindfulnessMinutes ?? null,
    };
    const latest = this.currentState();
    const fitbit: FitbitConnectionState = {
      ...token.state,
      days: { ...latest.fitbit.days, [date]: day },
      deviceName: latest.fitbit.deviceName,
      syncScheduleId: latest.fitbit.syncScheduleId,
    };
    this.saveState({
      ...latest,
      fitbit,
      updatedAt: new Date().toISOString(),
    });
    try {
      await persistStatisticsDay(this.env, day);
    } catch (error) {
      // Retain the Worker snapshot for retry/import without breaking Fitbit sync.
      console.error('Statistics Supabase persistence pending', {
        date, message: error instanceof Error ? error.message : 'unavailable',
      });
    }
  }

  private currentState(): PersonalAgentState {
    const stored = this.state as Partial<PersonalAgentState>;
    const storedMonitor = stored.importantEmailMonitor;
    const importantEmailMonitor =
      storedMonitor &&
      typeof storedMonitor.enabled === "boolean" &&
      (storedMonitor.scheduleId === null ||
        typeof storedMonitor.scheduleId === "string") &&
      (storedMonitor.lastScanAt === null ||
        typeof storedMonitor.lastScanAt === "string") &&
      Array.isArray(storedMonitor.notifiedMessageIds)
        ? {
            enabled: storedMonitor.enabled,
            scheduleId: storedMonitor.scheduleId,
            lastScanAt: storedMonitor.lastScanAt,
            notifiedMessageIds: storedMonitor.notifiedMessageIds
              .filter((id): id is string => typeof id === "string")
              .slice(-500),
          }
        : emptyImportantEmailMonitorState();
    return {
      schemaVersion: 5,
      mode: stored.mode === "STOPPED" ? "STOPPED" : "ACTIVE",
      updatedAt: stored.updatedAt ?? new Date(0).toISOString(),
      stoppedAt: stored.stoppedAt ?? null,
      memory: normalizeMemoryState(stored.memory),
      pendingActions: Array.isArray(stored.pendingActions)
        ? stored.pendingActions
        : [],
      microsoft: stored.microsoft ?? emptyMicrosoftConnection(),
      importantEmailMonitor,
      fitbit: stored.fitbit ?? emptyFitbitConnection(),
    };
  }

  private saveState(state: PersonalAgentState): void {
    this.setState(state);
  }

  private memoryView(state: PersonalAgentState): MemoryView {
    return {
      enabled: state.memory.enabled,
      conversationItems: state.memory.conversation.length,
      longTerm: state.memory.longTerm,
    };
  }

  private availableTools(state: PersonalAgentState): ToolDefinition[] {
    const mockTools = getModelTools();
    const config = getRuntimeConfig(this.env);
    const sharedTaskTools = config.sharedTasks.configured
      ? createSharedTaskTools(this.env)
      : [];
    if (!config.microsoft.configured || state.microsoft.status !== "CONNECTED") {
      return combineTools(mockTools, sharedTaskTools);
    }

    const graph = this.microsoftGraphClient();
    const reminderTools = createReminderTools(graph, {
      scheduleMessage: async (at, text) => {
        const schedule = await this.schedule(
          at,
          "deliverTelegramReminder",
          { text, scheduledFor: at.toISOString() },
          { idempotent: true },
        );
        return schedule.id;
      },
      scheduleCalendarBriefing: async (at, startDateTime, endDateTime) => {
        const schedule = await this.schedule(
          at,
          "deliverCalendarBriefing",
          {
            startDateTime,
            endDateTime,
            scheduledFor: at.toISOString(),
          },
          { idempotent: true },
        );
        return schedule.id;
      },
      scheduleRecurringCalendarBriefing: async (hour, minute) => {
        const schedule = await this.schedule(
          `${minute} * * * *`,
          "deliverRecurringCalendarBriefing",
          { hour, minute, timeZone: "Europe/Rome" },
          { idempotent: true },
        );
        return schedule.id;
      },
      cancel: async (id) => {
        await this.cancelSchedule(id);
      },
    });
    const importantEmailTools = createImportantEmailTools(graph, {
      enable: async (startedAt) => {
        const schedule = await this.schedule(
          "*/15 * * * *",
          "scanImportantEmails",
          { monitorVersion: 1 },
          { idempotent: true },
        );
        const latest = this.currentState();
        this.saveState({
          ...latest,
          importantEmailMonitor: {
            enabled: true,
            scheduleId: schedule.id,
            lastScanAt: startedAt.toISOString(),
            notifiedMessageIds: latest.importantEmailMonitor.notifiedMessageIds,
          },
          updatedAt: new Date().toISOString(),
        });
        return schedule.id;
      },
      disable: async () => {
        const latest = this.currentState();
        const wasEnabled = latest.importantEmailMonitor.enabled;
        if (latest.importantEmailMonitor.scheduleId) {
          await this.cancelSchedule(latest.importantEmailMonitor.scheduleId);
        }
        this.saveState({
          ...latest,
          importantEmailMonitor: emptyImportantEmailMonitorState(),
          updatedAt: new Date().toISOString(),
        });
        return wasEnabled;
      },
    });
    const emailFollowUpTools = createEmailFollowUpTools(graph, {
      scheduleFollowUp: async (at, payload) => {
        const schedule = await this.schedule(at, "checkEmailFollowUp", payload, {
          idempotent: true,
        });
        return schedule.id;
      },
    });
    const outlookEventReminderTools = createOutlookEventReminderTools(graph, {
      scheduleEventReminder: async (at, payload) => {
        const schedule = await this.schedule(
          at,
          "deliverOutlookEventReminder",
          payload,
          { idempotent: true },
        );
        return schedule.id;
      },
      cancel: async (id) => {
        await this.cancelSchedule(id);
      },
    });
    const writeMocksOnly = mockTools.filter(
      (tool) =>
        ![
          "search_email_mock",
          "read_calendar_mock",
          "create_event_mock",
          "send_email_mock",
          "delete_email_mock",
        ].includes(tool.name),
    );
    return combineTools(
      writeMocksOnly,
      createOutlookTools(graph),
      createCalendarWriteTools(graph),
      reminderTools,
      outlookEventReminderTools,
      sharedTaskTools,
      importantEmailTools,
      emailFollowUpTools,
    );
  }

  private microsoftGraphClient(): MicrosoftGraphClient {
    const config = getRuntimeConfig(this.env);
    if (!config.microsoft.configured) {
      throw new Error("Microsoft integration is not configured");
    }
    return new MicrosoftGraphClient(async (forceRefresh) => {
      const latest = this.currentState();
      const token = await getValidMicrosoftAccessToken(
        latest.microsoft,
        config.microsoft,
        new Date(),
        forceRefresh,
      );
      if (JSON.stringify(token.state) !== JSON.stringify(latest.microsoft)) {
        this.saveState({
          ...latest,
          microsoft: token.state,
          updatedAt: new Date().toISOString(),
        });
      }
      return token.accessToken;
    });
  }
}
