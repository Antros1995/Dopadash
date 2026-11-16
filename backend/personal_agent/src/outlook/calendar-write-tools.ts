import { requireApprovedExecutionContext } from "../approvals/execution-context";
import { ToolRisk } from "../security/risk";
import type {
  ToolDefinition,
  ToolExecutionResult,
  ToolParameters,
} from "../tools/types";
import type { MicrosoftGraphClient } from "./graph";

interface GraphEventCreated {
  id: string;
  webLink?: string;
}

const MAX_TITLE_CHARS = 300;
const MAX_EVENT_DURATION_MS = 24 * 60 * 60 * 1_000;
const ISO_WITH_TIMEZONE =
  /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2}(?:\.\d{1,3})?)?(?:Z|[+-]\d{2}:\d{2})$/u;

function hasControlCharacters(value: string): boolean {
  return [...value].some((character) => {
    const codePoint = character.codePointAt(0) ?? 0;
    return codePoint <= 31 || codePoint === 127;
  });
}

function validateParameters(input: unknown): ToolParameters {
  if (!input || typeof input !== "object" || Array.isArray(input)) {
    throw new Error("Invalid calendar event parameters");
  }
  const candidate = input as Record<string, unknown>;
  const fields = ["title", "startDateTime", "endDateTime"] as const;
  const keys = Object.keys(candidate);
  if (keys.length !== fields.length || keys.some((key) => !fields.includes(key as typeof fields[number]))) {
    throw new Error("Unexpected calendar event parameters");
  }

  const title = candidate.title;
  const startDateTime = candidate.startDateTime;
  const endDateTime = candidate.endDateTime;
  if (
    typeof title !== "string" ||
    title.trim().length === 0 ||
    title.trim().length > MAX_TITLE_CHARS ||
    hasControlCharacters(title)
  ) {
    throw new Error("Invalid event title");
  }
  if (
    typeof startDateTime !== "string" ||
    !ISO_WITH_TIMEZONE.test(startDateTime) ||
    !Number.isFinite(Date.parse(startDateTime))
  ) {
    throw new Error("startDateTime must be ISO 8601 with an explicit timezone");
  }
  if (
    typeof endDateTime !== "string" ||
    !ISO_WITH_TIMEZONE.test(endDateTime) ||
    !Number.isFinite(Date.parse(endDateTime))
  ) {
    throw new Error("endDateTime must be ISO 8601 with an explicit timezone");
  }

  const duration = Date.parse(endDateTime) - Date.parse(startDateTime);
  if (duration <= 0 || duration > MAX_EVENT_DURATION_MS) {
    throw new Error("Event duration must be positive and no longer than 24 hours");
  }
  return { title: title.trim(), startDateTime, endDateTime };
}

function required(parameters: ToolParameters, name: string): string {
  const value = parameters[name];
  if (!value) throw new Error(`Missing ${name}`);
  return value;
}

function graphDateTime(value: string): { dateTime: string; timeZone: string } {
  return {
    dateTime: new Date(value).toISOString().replace(/Z$/u, ""),
    timeZone: "UTC",
  };
}

function formatRomeDateTime(value: string): string {
  return `${new Intl.DateTimeFormat("it-IT", {
    timeZone: "Europe/Rome",
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
  }).format(new Date(value))} (Europe/Rome)`;
}

export function createCalendarWriteTools(
  graph: MicrosoftGraphClient,
): ToolDefinition[] {
  return [
    {
      name: "create_outlook_calendar_event",
      description:
        "Propone la creazione di un singolo evento reale nel calendario Outlook. Usalo anche per richieste come 'ricordami domani di andare dal dentista alle 20': crea l'evento alle 20 e, se manca una durata, usa 30 minuti. Non esegue mai senza approvazione Telegram del backend. Non modifica e non cancella eventi.",
      risk: ToolRisk.WRITE_LOW_RISK,
      exposedToModel: true,
      parameters: {
        type: "object",
        properties: {
          title: { type: "string", description: "Titolo breve dell'evento" },
          startDateTime: {
            type: "string",
            description:
              "Inizio ISO 8601 con offset Europe/Rome, per esempio 2026-08-22T20:00:00+02:00",
          },
          endDateTime: {
            type: "string",
            description:
              "Fine ISO 8601 con offset Europe/Rome; usa 30 minuti dopo l'inizio se la durata non è specificata",
          },
        },
        required: ["title", "startDateTime", "endDateTime"],
        additionalProperties: false,
      },
      validate: validateParameters,
      preview: (parameters) =>
        `PROPOSTA CREAZIONE EVENTO OUTLOOK\n\nTitolo: ${parameters.title}\nInizio: ${formatRomeDateTime(parameters.startDateTime!)}\nFine: ${formatRomeDateTime(parameters.endDateTime!)}\nPromemoria Outlook: all'orario di inizio\n\nOperazione consentita: CREA UN SOLO EVENTO\nModifica/cancellazione: NON DISPONIBILI`,
      execute: async (parameters, executionContext): Promise<ToolExecutionResult> => {
        const approval = requireApprovedExecutionContext(executionContext);
        const validated = validateParameters(parameters);
        const startDateTime = required(validated, "startDateTime");
        if (Date.parse(startDateTime) <= Date.now()) {
          throw new Error("Event start must be in the future");
        }
        const event = await graph.post<GraphEventCreated>("/me/events", {
          subject: required(validated, "title"),
          start: graphDateTime(startDateTime),
          end: graphDateTime(required(validated, "endDateTime")),
          isReminderOn: true,
          reminderMinutesBeforeStart: 0,
          transactionId: approval.actionId,
          body: {
            contentType: "text",
            content: "Creato dal Personal Agent dopo approvazione esplicita su Telegram.",
          },
        });
        return {
          simulated: false,
          message: `Evento Outlook creato: ${required(validated, "title")}.`,
          data: { eventId: event.id, webLink: event.webLink ?? null },
        };
      },
    },
  ];
}
