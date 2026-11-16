import { requireApprovedExecutionContext } from "../approvals/execution-context";
import type { MicrosoftGraphClient } from "../outlook/graph";
import { ToolRisk } from "../security/risk";
import type {
  ApprovalPreparation,
  ToolDefinition,
  ToolExecutionResult,
  ToolParameters,
} from "../tools/types";

interface GraphCollection<T> {
  value: T[];
  "@odata.nextLink"?: string;
}

interface GraphEvent {
  id: string;
  subject?: string;
  start?: { dateTime?: string; timeZone?: string };
  end?: { dateTime?: string; timeZone?: string };
  location?: { displayName?: string };
  isCancelled?: boolean;
  isAllDay?: boolean;
  showAs?: string;
}

interface EventSnapshot {
  id: string;
  title: string;
  startDateTime: string;
  endDateTime: string;
  location: string;
}

export interface OutlookEventReminderPayload {
  eventId: string;
  eventTitle: string;
  minutesBefore: number;
}

export type OutlookEventReminderDelivery =
  | { kind: "skip" }
  | { kind: "reschedule"; at: Date; payload: OutlookEventReminderPayload }
  | { kind: "send"; text: string };

export interface OutlookEventReminderScheduler {
  scheduleEventReminder(
    at: Date,
    payload: OutlookEventReminderPayload,
  ): Promise<string>;
  cancel(id: string): Promise<void>;
}

const MAX_BATCH_EVENTS = 20;
const MAX_EVENT_ID_CHARS = 512;
const MAX_TEXT_CHARS = 300;
const MAX_MINUTES_BEFORE = 24 * 60;
const MIN_SCHEDULE_DELAY_MS = 5_000;
const ISO_WITH_TIMEZONE =
  /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2}(?:\.\d{1,3})?)?(?:Z|[+-]\d{2}:\d{2})$/u;
const EVENT_SELECT =
  "id,subject,start,end,location,isCancelled,isAllDay,showAs";

function safeSingleLine(value: unknown, max = MAX_TEXT_CHARS): string {
  return typeof value === "string"
    ? value.replace(/\s+/gu, " ").trim().slice(0, max)
    : "";
}

function exactStringInput(
  input: unknown,
  fields: readonly string[],
): ToolParameters {
  if (!input || typeof input !== "object" || Array.isArray(input)) {
    throw new Error("Invalid Outlook reminder parameters");
  }
  const candidate = input as Record<string, unknown>;
  const keys = Object.keys(candidate);
  if (keys.length !== fields.length || keys.some((key) => !fields.includes(key))) {
    throw new Error("Unexpected Outlook reminder parameters");
  }
  return Object.fromEntries(
    fields.map((field) => {
      const value = candidate[field];
      if (typeof value !== "string" || value.trim().length === 0) {
        throw new Error(`Invalid ${field}`);
      }
      return [field, value.trim()];
    }),
  );
}

function parseMinutes(value: string): number {
  if (!/^\d{1,4}$/u.test(value)) throw new Error("Invalid minutesBefore");
  const minutes = Number(value);
  if (
    !Number.isInteger(minutes) ||
    minutes < 0 ||
    minutes > MAX_MINUTES_BEFORE ||
    String(minutes) !== value
  ) {
    throw new Error("minutesBefore must be between 0 and 1440");
  }
  return minutes;
}

function requireIsoWithTimezone(value: string, field: string): string {
  if (!ISO_WITH_TIMEZONE.test(value) || !Number.isFinite(Date.parse(value))) {
    throw new Error(`${field} must be ISO 8601 with an explicit timezone`);
  }
  return value;
}

function utcInstant(value: string | undefined, timeZone: string | undefined): Date {
  if (!value) throw new Error("Outlook event has no date-time");
  const normalized = /(?:Z|[+-]\d{2}:\d{2})$/u.test(value)
    ? value
    : timeZone === "UTC"
      ? `${value}Z`
      : "";
  const date = new Date(normalized);
  if (!normalized || !Number.isFinite(date.getTime())) {
    throw new Error("Outlook event date-time is ambiguous");
  }
  return date;
}

function snapshotEvent(event: GraphEvent): EventSnapshot | null {
  if (
    event.isCancelled ||
    event.isAllDay ||
    event.showAs?.toLowerCase() === "free" ||
    typeof event.id !== "string" ||
    event.id.length === 0 ||
    event.id.length > MAX_EVENT_ID_CHARS
  ) {
    return null;
  }
  const start = utcInstant(event.start?.dateTime, event.start?.timeZone);
  const end = utcInstant(event.end?.dateTime, event.end?.timeZone);
  if (end <= start) return null;
  return {
    id: event.id,
    title: safeSingleLine(event.subject) || "Evento senza titolo",
    startDateTime: start.toISOString(),
    endDateTime: end.toISOString(),
    location: safeSingleLine(event.location?.displayName),
  };
}

function parseSnapshots(value: string): EventSnapshot[] {
  let parsed: unknown;
  try {
    parsed = JSON.parse(value) as unknown;
  } catch {
    throw new Error("Invalid event snapshot");
  }
  if (!Array.isArray(parsed) || parsed.length > MAX_BATCH_EVENTS) {
    throw new Error("Invalid event snapshot count");
  }
  return parsed.map((item) => {
    if (!item || typeof item !== "object" || Array.isArray(item)) {
      throw new Error("Invalid event snapshot item");
    }
    const candidate = item as Record<string, unknown>;
    const fields = ["id", "title", "startDateTime", "endDateTime", "location"];
    if (
      Object.keys(candidate).length !== fields.length ||
      Object.keys(candidate).some((key) => !fields.includes(key)) ||
      typeof candidate.id !== "string" ||
      candidate.id.length === 0 ||
      candidate.id.length > MAX_EVENT_ID_CHARS ||
      typeof candidate.title !== "string" ||
      candidate.title.length === 0 ||
      candidate.title.length > MAX_TEXT_CHARS ||
      typeof candidate.location !== "string" ||
      candidate.location.length > MAX_TEXT_CHARS ||
      typeof candidate.startDateTime !== "string" ||
      typeof candidate.endDateTime !== "string"
    ) {
      throw new Error("Invalid event snapshot fields");
    }
    requireIsoWithTimezone(candidate.startDateTime, "startDateTime");
    requireIsoWithTimezone(candidate.endDateTime, "endDateTime");
    if (Date.parse(candidate.endDateTime) <= Date.parse(candidate.startDateTime)) {
      throw new Error("Invalid event snapshot duration");
    }
    return candidate as unknown as EventSnapshot;
  });
}

function validatePrepared(input: unknown): ToolParameters {
  const result = exactStringInput(input, [
    "selection",
    "minutesBefore",
    "eventsJson",
  ]);
  if (result.selection !== "single" && result.selection !== "day") {
    throw new Error("Invalid reminder selection");
  }
  parseMinutes(result.minutesBefore!);
  parseSnapshots(result.eventsJson!);
  return result;
}

function formatRome(iso: string): string {
  return new Intl.DateTimeFormat("it-IT", {
    timeZone: "Europe/Rome",
    dateStyle: "short",
    timeStyle: "short",
  }).format(new Date(iso));
}

function approvalPreview(events: EventSnapshot[], minutesBefore: number): string {
  const lines = events.map(
    (event) =>
      `- ${formatRome(event.startDateTime)} | ${event.title}${event.location ? ` | ${event.location}` : ""}`,
  );
  const preview = `PROGRAMMA PROMEMORIA TELEGRAM DA OUTLOOK\n\nAnticipo: ${minutesBefore} minuti\nEventi (${events.length}):\n${lines.join("\n")}\n\nPrima di inviare, il bot ricontrollerà su Outlook che ogni evento esista ancora e non sia stato annullato. Nessun evento verrà creato, modificato o cancellato.`;
  if (preview.length > 3_500) {
    throw new Error("The exact approval recap is too long for Telegram");
  }
  return preview;
}

function prepared(
  selection: "single" | "day",
  events: EventSnapshot[],
  minutesBefore: number,
): ApprovalPreparation {
  const parameters = {
    selection,
    minutesBefore: String(minutesBefore),
    eventsJson: JSON.stringify(events),
  };
  if (events.length === 0) {
    return {
      parameters,
      preview: "Nessun evento idoneo trovato.",
      noActionResult: {
        simulated: false,
        message:
          "Non ci sono eventi attivi con un orario preciso da ricordare nell'intervallo richiesto.",
      },
    };
  }
  return { parameters, preview: approvalPreview(events, minutesBefore) };
}

async function currentSnapshot(
  graph: MicrosoftGraphClient,
  eventId: string,
): Promise<EventSnapshot | null> {
  const event = await graph.getUtc<GraphEvent>(
    `/me/events/${encodeURIComponent(eventId)}`,
    { "$select": EVENT_SELECT },
  );
  return snapshotEvent(event);
}

export async function resolveOutlookEventReminderDelivery(
  graph: MicrosoftGraphClient,
  payload: OutlookEventReminderPayload,
  now = new Date(),
): Promise<OutlookEventReminderDelivery> {
  if (
    !payload ||
    typeof payload.eventId !== "string" ||
    payload.eventId.length === 0 ||
    payload.eventId.length > MAX_EVENT_ID_CHARS ||
    !Number.isInteger(payload.minutesBefore) ||
    payload.minutesBefore < 0 ||
    payload.minutesBefore > MAX_MINUTES_BEFORE
  ) {
    throw new Error("Invalid scheduled Outlook event reminder");
  }

  let event: EventSnapshot | null;
  try {
    event = await currentSnapshot(graph, payload.eventId);
  } catch (error) {
    if (error instanceof Error && error.message.includes("status 404")) {
      return { kind: "skip" };
    }
    throw error;
  }
  if (!event) return { kind: "skip" };

  const start = Date.parse(event.startDateTime);
  if (start <= now.getTime()) return { kind: "skip" };
  const desiredDelivery = start - payload.minutesBefore * 60_000;
  if (desiredDelivery > now.getTime() + 30_000) {
    return {
      kind: "reschedule",
      at: new Date(desiredDelivery),
      payload: {
        eventId: event.id,
        eventTitle: event.title,
        minutesBefore: payload.minutesBefore,
      },
    };
  }

  const minutesUntilStart = Math.max(
    1,
    Math.ceil((start - now.getTime()) / 60_000),
  );
  return {
    kind: "send",
    text: `PROMEMORIA OUTLOOK\n\nTra ${minutesUntilStart} minuti: ${event.title}\nOrario: ${formatRome(event.startDateTime)}${event.location ? `\nLuogo: ${event.location}` : ""}`,
  };
}

function sameApprovedEvent(
  approved: EventSnapshot,
  current: EventSnapshot | null,
): current is EventSnapshot {
  return Boolean(
    current &&
      current.id === approved.id &&
      current.title === approved.title &&
      current.startDateTime === approved.startDateTime &&
      current.endDateTime === approved.endDateTime &&
      current.location === approved.location,
  );
}

function executionTime(startDateTime: string, minutesBefore: number): Date | null {
  const now = Date.now();
  const start = Date.parse(startDateTime);
  if (start <= now) return null;
  return new Date(Math.max(start - minutesBefore * 60_000, now + MIN_SCHEDULE_DELAY_MS));
}

function inputSchema(properties: Record<string, string>): Record<string, unknown> {
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

export function createOutlookEventReminderTools(
  graph: MicrosoftGraphClient,
  scheduler: OutlookEventReminderScheduler,
): ToolDefinition[] {
  const execute = async (
    parameters: ToolParameters,
    executionContext: Parameters<ToolDefinition["execute"]>[1],
  ): Promise<ToolExecutionResult> => {
    requireApprovedExecutionContext(executionContext);
    const validated = validatePrepared(parameters);
    const minutesBefore = parseMinutes(validated.minutesBefore!);
    const approvedEvents = parseSnapshots(validated.eventsJson!);

    const currentEvents: EventSnapshot[] = [];
    for (const approvedEvent of approvedEvents) {
      const current = await currentSnapshot(graph, approvedEvent.id);
      if (!sameApprovedEvent(approvedEvent, current)) {
        throw new Error("An Outlook event changed after the approval recap");
      }
      currentEvents.push(current);
    }

    const scheduleIds: string[] = [];
    try {
      for (const event of currentEvents) {
        const at = executionTime(event.startDateTime, minutesBefore);
        if (!at) continue;
        scheduleIds.push(
          await scheduler.scheduleEventReminder(at, {
            eventId: event.id,
            eventTitle: event.title,
            minutesBefore,
          }),
        );
      }
    } catch (error) {
      await Promise.allSettled(scheduleIds.map((id) => scheduler.cancel(id)));
      throw error;
    }
    return {
      simulated: false,
      message:
        scheduleIds.length === 0
          ? "Nessun promemoria programmato: gli eventi risultano già iniziati."
          : `${scheduleIds.length} promemoria Telegram programmati con ${minutesBefore} minuti di anticipo.`,
      data: { scheduleIds },
    };
  };

  return [
    {
      name: "schedule_specific_outlook_event_reminder",
      description:
        "Programma un promemoria Telegram per uno specifico evento Outlook già trovato. Usa 15 minuti se l'utente non indica l'anticipo; converti un'ora in 60 minuti. Richiede sempre approvazione.",
      risk: ToolRisk.WRITE_LOW_RISK,
      exposedToModel: true,
      parameters: inputSchema({
        eventId: "ID esatto ottenuto da find_calendar_events o read_calendar",
        minutesBefore:
          "Minuti interi di anticipo; usa 15 se l'utente non specifica altro",
      }),
      validate: (input) => {
        const result = exactStringInput(input, ["eventId", "minutesBefore"]);
        if (result.eventId!.length > MAX_EVENT_ID_CHARS) {
          throw new Error("Invalid eventId");
        }
        parseMinutes(result.minutesBefore!);
        return result;
      },
      validateApproved: validatePrepared,
      prepareApproval: async (parameters) => {
        const event = await currentSnapshot(graph, parameters.eventId!);
        return prepared(
          "single",
          event && Date.parse(event.startDateTime) > Date.now() ? [event] : [],
          parseMinutes(parameters.minutesBefore!),
        );
      },
      preview: () => "Promemoria Outlook in attesa di preparazione.",
      execute,
    },
    {
      name: "schedule_outlook_day_event_reminders",
      description:
        "Programma promemoria Telegram per tutti gli eventi Outlook attivi con orario preciso nell'intervallo richiesto. Esclude eventi annullati, giornalieri e segnati come libero. Usa 15 minuti di anticipo se l'utente non specifica altro. Richiede sempre approvazione.",
      risk: ToolRisk.WRITE_LOW_RISK,
      exposedToModel: true,
      parameters: inputSchema({
        calendarStartDateTime:
          "Inizio del giorno/intervallo ISO 8601 con offset Europe/Rome",
        calendarEndDateTime:
          "Fine esclusiva del giorno/intervallo ISO 8601 con offset Europe/Rome",
        minutesBefore:
          "Minuti interi di anticipo; usa 15 se l'utente non specifica altro",
      }),
      validate: (input) => {
        const result = exactStringInput(input, [
          "calendarStartDateTime",
          "calendarEndDateTime",
          "minutesBefore",
        ]);
        const start = requireIsoWithTimezone(
          result.calendarStartDateTime!,
          "calendarStartDateTime",
        );
        const end = requireIsoWithTimezone(
          result.calendarEndDateTime!,
          "calendarEndDateTime",
        );
        const duration = Date.parse(end) - Date.parse(start);
        if (duration <= 0 || duration > 26 * 60 * 60 * 1_000) {
          throw new Error("Reminder interval must be one day or less");
        }
        parseMinutes(result.minutesBefore!);
        return result;
      },
      validateApproved: validatePrepared,
      prepareApproval: async (parameters) => {
        const response = await graph.getUtc<GraphCollection<GraphEvent>>(
          "/me/calendar/calendarView",
          {
            startDateTime: parameters.calendarStartDateTime!,
            endDateTime: parameters.calendarEndDateTime!,
            "$top": "50",
            "$orderby": "start/dateTime",
            "$select": EVENT_SELECT,
          },
        );
        const events = response.value
          .map(snapshotEvent)
          .filter((event): event is EventSnapshot => Boolean(event))
          .filter((event) => Date.parse(event.startDateTime) > Date.now())
          .sort((left, right) =>
            left.startDateTime.localeCompare(right.startDateTime),
          );
        if (response["@odata.nextLink"] || events.length > MAX_BATCH_EVENTS) {
          throw new Error("Too many events for one approved reminder batch");
        }
        return prepared(
          "day",
          events,
          parseMinutes(parameters.minutesBefore!),
        );
      },
      preview: () => "Promemoria giornalieri in attesa di preparazione.",
      execute,
    },
  ];
}
