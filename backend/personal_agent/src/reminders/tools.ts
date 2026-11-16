import { ToolRisk } from "../security/risk";
import type { ToolDefinition, ToolParameters } from "../tools/types";
import type { MicrosoftGraphClient } from "../outlook/graph";
import { requireApprovedExecutionContext } from "../approvals/execution-context";

export interface ReminderScheduler {
  scheduleMessage(at: Date, text: string): Promise<string>;
  scheduleCalendarBriefing(
    at: Date,
    startDateTime: string,
    endDateTime: string,
  ): Promise<string>;
  scheduleRecurringCalendarBriefing(
    hour: number,
    minute: number,
  ): Promise<string>;
  cancel(id: string): Promise<void>;
}

interface GraphEventCreated {
  id: string;
  webLink?: string;
}

const MAX_PARAMETER_CHARS = 2_000;

function exactStrings(input: unknown, fields: readonly string[]): ToolParameters {
  if (!input || typeof input !== "object" || Array.isArray(input)) {
    throw new Error("Invalid reminder parameters");
  }
  const candidate = input as Record<string, unknown>;
  const keys = Object.keys(candidate);
  if (keys.length !== fields.length || keys.some((key) => !fields.includes(key))) {
    throw new Error("Unexpected reminder parameters");
  }
  return Object.fromEntries(
    fields.map((field) => {
      const value = candidate[field];
      if (
        typeof value !== "string" ||
        value.trim().length === 0 ||
        value.length > MAX_PARAMETER_CHARS
      ) {
        throw new Error(`Invalid ${field}`);
      }
      return [field, value.trim()];
    }),
  );
}

function schema(properties: Record<string, string>): Record<string, unknown> {
  return {
    type: "object",
    properties: Object.fromEntries(
      Object.entries(properties).map(([name, description]) => [
        name,
        { type: "string", description },
      ]),
    ),
    required: Object.keys(properties),
    additionalProperties: false,
  };
}

function required(parameters: ToolParameters, name: string): string {
  const value = parameters[name];
  if (!value) throw new Error(`Missing ${name}`);
  return value;
}

function validateSingleLineTitle(value: string): void {
  const hasControlCharacters = [...value].some((character) => {
    const codePoint = character.codePointAt(0) ?? 0;
    return codePoint <= 31 || codePoint === 127;
  });
  if (hasControlCharacters || value.length > 300) {
    throw new Error("Invalid title");
  }
}

function isoDate(value: string, name: string): Date {
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/u.test(value)) {
    throw new Error(`${name} must be an ISO date-time`);
  }
  const parsed = new Date(value);
  if (!Number.isFinite(parsed.getTime())) {
    throw new Error(`${name} must be an ISO date-time`);
  }
  return parsed;
}

function graphDateTime(value: Date): { dateTime: string; timeZone: string } {
  return {
    dateTime: value.toISOString().replace(/Z$/u, ""),
    timeZone: "UTC",
  };
}

function dailyTime(value: string): { hour: number; minute: number } {
  const match = /^(\d{2}):(\d{2})$/u.exec(value);
  if (!match) throw new Error("deliveryTime must use HH:mm");
  const hour = Number(match[1]);
  const minute = Number(match[2]);
  if (hour > 23 || minute > 59) {
    throw new Error("deliveryTime must be a valid Europe/Rome time");
  }
  return { hour, minute };
}

export function createReminderTools(
  graph: MicrosoftGraphClient,
  scheduler: ReminderScheduler,
): ToolDefinition[] {
  return [
    {
      name: "create_outlook_event_with_telegram_reminder",
      description:
        "Crea un evento reale Outlook e programma un messaggio Telegram. Usalo soltanto quando l'utente chiede esplicitamente entrambe le cose. Richiede approvazione. Se manca una durata, usa 30 minuti.",
      risk: ToolRisk.WRITE_LOW_RISK,
      exposedToModel: true,
      parameters: schema({
        title: "Titolo breve dell'evento e del promemoria",
        startDateTime: "Inizio evento ISO 8601 con offset Europe/Rome",
        endDateTime: "Fine evento ISO 8601 con offset Europe/Rome",
        telegramReminderDateTime:
          "Istante ISO 8601 con offset Europe/Rome in cui inviare il messaggio Telegram",
      }),
      validate: (input) => {
        const result = exactStrings(input, [
          "title",
          "startDateTime",
          "endDateTime",
          "telegramReminderDateTime",
        ]);
        validateSingleLineTitle(required(result, "title"));
        const start = isoDate(required(result, "startDateTime"), "startDateTime");
        const end = isoDate(required(result, "endDateTime"), "endDateTime");
        isoDate(
          required(result, "telegramReminderDateTime"),
          "telegramReminderDateTime",
        );
        if (end <= start) throw new Error("Event end must be after start");
        return result;
      },
      preview: (parameters) =>
        `CREA EVENTO OUTLOOK + PROMEMORIA TELEGRAM\n\nTitolo: ${parameters.title}\nInizio: ${parameters.startDateTime}\nFine: ${parameters.endDateTime}\nMessaggio Telegram: ${parameters.telegramReminderDateTime}`,
      execute: async (parameters, executionContext) => {
        const approval = requireApprovedExecutionContext(executionContext);
        const title = required(parameters, "title");
        const start = isoDate(required(parameters, "startDateTime"), "startDateTime");
        const end = isoDate(required(parameters, "endDateTime"), "endDateTime");
        const reminderAt = isoDate(
          required(parameters, "telegramReminderDateTime"),
          "telegramReminderDateTime",
        );
        if (reminderAt.getTime() <= Date.now()) {
          throw new Error("Telegram reminder time must be in the future");
        }

        const scheduleId = await scheduler.scheduleMessage(
          reminderAt,
          `Promemoria: ${title}`,
        );
        let event: GraphEventCreated;
        try {
          event = await graph.post<GraphEventCreated>("/me/events", {
            subject: title,
            transactionId: approval.actionId,
            start: graphDateTime(start),
            end: graphDateTime(end),
            isReminderOn: false,
            body: {
              contentType: "text",
              content: "Creato dal Personal Agent dopo approvazione Telegram.",
            },
          });
        } catch (error) {
          await scheduler.cancel(scheduleId);
          throw error;
        }
        return {
          simulated: false,
          message: `Evento Outlook creato e promemoria Telegram programmato. ID promemoria: ${scheduleId.slice(0, 8)}`,
          data: { eventId: event.id, scheduleId },
        };
      },
    },
    {
      name: "schedule_calendar_briefing",
      description:
        "Programma un messaggio Telegram futuro che, al momento dell'invio, legge il calendario Outlook per l'intervallo richiesto e invia l'elenco aggiornato degli impegni. Richiede approvazione.",
      risk: ToolRisk.WRITE_LOW_RISK,
      exposedToModel: true,
      parameters: schema({
        deliveryDateTime: "Istante futuro ISO 8601 con offset Europe/Rome",
        calendarStartDateTime: "Inizio dell'intervallo calendario ISO 8601",
        calendarEndDateTime: "Fine dell'intervallo calendario ISO 8601",
      }),
      validate: (input) => {
        const result = exactStrings(input, [
          "deliveryDateTime",
          "calendarStartDateTime",
          "calendarEndDateTime",
        ]);
        isoDate(required(result, "deliveryDateTime"), "deliveryDateTime");
        const start = isoDate(
          required(result, "calendarStartDateTime"),
          "calendarStartDateTime",
        );
        const end = isoDate(
          required(result, "calendarEndDateTime"),
          "calendarEndDateTime",
        );
        if (end <= start) throw new Error("Calendar end must be after start");
        return result;
      },
      preview: (parameters) =>
        `PROGRAMMA RIEPILOGO CALENDARIO\n\nInvio Telegram: ${parameters.deliveryDateTime}\nIntervallo: ${parameters.calendarStartDateTime} — ${parameters.calendarEndDateTime}`,
      execute: async (parameters, executionContext) => {
        requireApprovedExecutionContext(executionContext);
        const at = isoDate(required(parameters, "deliveryDateTime"), "deliveryDateTime");
        if (at.getTime() <= Date.now()) {
          throw new Error("Briefing time must be in the future");
        }
        const scheduleId = await scheduler.scheduleCalendarBriefing(
          at,
          required(parameters, "calendarStartDateTime"),
          required(parameters, "calendarEndDateTime"),
        );
        return {
          simulated: false,
          message: `Riepilogo calendario programmato su Telegram. ID promemoria: ${scheduleId.slice(0, 8)}`,
          data: { scheduleId },
        };
      },
    },
    {
      name: "schedule_recurring_daily_calendar_briefing",
      description:
        "Programma un riepilogo Telegram ricorrente degli eventi Outlook del giorno, per richieste come 'ogni mattina ricordami gli eventi di oggi'. Usa 08:00 Europe/Rome quando l'utente non indica un orario. Richiede approvazione e non modifica il calendario.",
      risk: ToolRisk.WRITE_LOW_RISK,
      exposedToModel: true,
      parameters: schema({
        deliveryTime:
          "Ora locale Europe/Rome in formato HH:mm; usa 08:00 se l'utente dice soltanto ogni mattina",
      }),
      validate: (input) => {
        const result = exactStrings(input, ["deliveryTime"]);
        dailyTime(required(result, "deliveryTime"));
        return result;
      },
      preview: (parameters) =>
        `PROGRAMMA PROMEMORIA RICORRENTE\n\nQuando: ogni giorno alle ${parameters.deliveryTime} (Europe/Rome)\nContenuto: eventi Outlook aggiornati del giorno\nCalendario: SOLA LETTURA\nCancellazione eventi: NON DISPONIBILE`,
      execute: async (parameters, executionContext) => {
        requireApprovedExecutionContext(executionContext);
        const time = dailyTime(required(parameters, "deliveryTime"));
        const scheduleId = await scheduler.scheduleRecurringCalendarBriefing(
          time.hour,
          time.minute,
        );
        return {
          simulated: false,
          message: `Promemoria ricorrente programmato. ID: ${scheduleId.slice(0, 8)}.`,
          data: { scheduleId },
        };
      },
    },
  ];
}
