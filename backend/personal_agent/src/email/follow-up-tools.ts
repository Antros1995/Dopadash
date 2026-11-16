import { requireApprovedExecutionContext } from "../approvals/execution-context";
import type { MicrosoftGraphClient } from "../outlook/graph";
import { ToolRisk } from "../security/risk";
import type {
  ApprovalPreparation,
  ToolDefinition,
  ToolExecutionResult,
  ToolParameters,
} from "../tools/types";
import type { GraphCollection, GraphMailMessage } from "./types";

export interface EmailFollowUpPayload {
  conversationId: string;
  contactName: string;
  contactAddress: string;
  subject: string;
  sentDateTime: string;
  deadlineDateTime: string;
}

export interface EmailFollowUpScheduler {
  scheduleFollowUp(at: Date, payload: EmailFollowUpPayload): Promise<string>;
}

export type EmailFollowUpResolution =
  | { kind: "replied" }
  | { kind: "notify"; text: string };

const MAX_ID_CHARS = 1_024;
const MAX_TEXT_CHARS = 300;
const ISO_WITH_TIMEZONE =
  /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2}(?:\.\d{1,3})?)?(?:Z|[+-]\d{2}:\d{2})$/u;

function safeSingleLine(value: unknown, max = MAX_TEXT_CHARS): string {
  return typeof value === "string"
    ? value.replace(/\s+/gu, " ").trim().slice(0, max)
    : "";
}

function normalizeSearch(value: string): string {
  return value
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/gu, "")
    .toLocaleLowerCase()
    .replace(/\s+/gu, " ")
    .trim();
}

function exactStrings(input: unknown, fields: readonly string[]): ToolParameters {
  if (!input || typeof input !== "object" || Array.isArray(input)) {
    throw new Error("Invalid follow-up parameters");
  }
  const candidate = input as Record<string, unknown>;
  const keys = Object.keys(candidate);
  if (keys.length !== fields.length || keys.some((key) => !fields.includes(key))) {
    throw new Error("Unexpected follow-up parameters");
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

function requireIso(value: string, field: string): string {
  if (!ISO_WITH_TIMEZONE.test(value) || !Number.isFinite(Date.parse(value))) {
    throw new Error(`${field} must be ISO 8601 with an explicit timezone`);
  }
  return value;
}

function requireValue(parameters: ToolParameters, field: string): string {
  const value = parameters[field];
  if (!value) throw new Error(`Missing ${field}`);
  return value;
}

function inputSchema(): Record<string, unknown> {
  return {
    type: "object",
    properties: {
      contactQuery: {
        type: "string",
        description:
          "Nome o indirizzo del destinatario, per esempio Marco o marco@example.com",
      },
      deadlineDateTime: {
        type: "string",
        description:
          "Scadenza futura ISO 8601 con offset Europe/Rome entro cui attendere la risposta",
      },
    },
    required: ["contactQuery", "deadlineDateTime"],
    additionalProperties: false,
  };
}

function validateInput(input: unknown): ToolParameters {
  const result = exactStrings(input, ["contactQuery", "deadlineDateTime"]);
  if (result.contactQuery!.length > 200) throw new Error("contactQuery is too long");
  requireIso(result.deadlineDateTime!, "deadlineDateTime");
  if (Date.parse(result.deadlineDateTime!) <= Date.now()) {
    throw new Error("Follow-up deadline must be in the future");
  }
  return result;
}

function validateFollowUpPayload(
  input: unknown,
  requireFutureDeadline: boolean,
): ToolParameters {
  const fields = [
    "conversationId",
    "contactName",
    "contactAddress",
    "subject",
    "sentDateTime",
    "deadlineDateTime",
  ] as const;
  const result = exactStrings(input, fields);
  if (result.conversationId!.length > MAX_ID_CHARS) {
    throw new Error("conversationId is too long");
  }
  for (const field of ["contactName", "contactAddress", "subject"] as const) {
    if (result[field]!.length > MAX_TEXT_CHARS) {
      throw new Error(`${field} is too long`);
    }
  }
  if (!/^\S+@\S+\.\S+$/u.test(result.contactAddress!)) {
    throw new Error("Invalid contactAddress");
  }
  requireIso(result.sentDateTime!, "sentDateTime");
  requireIso(result.deadlineDateTime!, "deadlineDateTime");
  if (
    requireFutureDeadline &&
    Date.parse(result.deadlineDateTime!) <= Date.now()
  ) {
    throw new Error("Follow-up deadline must be in the future");
  }
  return result;
}

function validatePrepared(input: unknown): ToolParameters {
  return validateFollowUpPayload(input, true);
}

function payloadFrom(parameters: ToolParameters): EmailFollowUpPayload {
  return {
    conversationId: requireValue(parameters, "conversationId"),
    contactName: requireValue(parameters, "contactName"),
    contactAddress: requireValue(parameters, "contactAddress"),
    subject: requireValue(parameters, "subject"),
    sentDateTime: requireValue(parameters, "sentDateTime"),
    deadlineDateTime: requireValue(parameters, "deadlineDateTime"),
  };
}

function preparedFollowUp(
  message: GraphMailMessage,
  contactName: string,
  contactAddress: string,
  deadlineDateTime: string,
): ApprovalPreparation {
  const parameters: ToolParameters = {
    conversationId: message.conversationId!,
    contactName,
    contactAddress,
    subject: safeSingleLine(message.subject) || "Senza oggetto",
    sentDateTime: message.sentDateTime!,
    deadlineDateTime,
  };
  const deadline = new Intl.DateTimeFormat("it-IT", {
    timeZone: "Europe/Rome",
    dateStyle: "short",
    timeStyle: "short",
  }).format(new Date(deadlineDateTime));
  return {
    parameters,
    preview: `CREA FOLLOW-UP EMAIL\n\nContatto: ${contactName} <${contactAddress}>\nEmail inviata: ${parameters.subject}\nInviata il: ${parameters.sentDateTime}\nScadenza: ${deadline}\n\nAlla scadenza il bot controllerà in SOLA LETTURA se è arrivata una risposta nella stessa conversazione. Se non c'è, invierà un avviso Telegram. Non invierà email.`,
  };
}

export async function resolveEmailFollowUp(
  graph: MicrosoftGraphClient,
  payload: EmailFollowUpPayload,
): Promise<EmailFollowUpResolution> {
  const validated = validateFollowUpPayload(payload, false);
  const exact = payloadFrom(validated);
  const escapedConversationId = exact.conversationId.replaceAll("'", "''");
  const response = await graph.get<GraphCollection<GraphMailMessage>>(
    "/me/messages",
    {
      "$filter": `conversationId eq '${escapedConversationId}' and receivedDateTime gt ${new Date(exact.sentDateTime).toISOString()}`,
      "$top": "50",
      "$select": "id,conversationId,from,receivedDateTime,subject",
    },
  );
  const expectedAddress = exact.contactAddress.toLocaleLowerCase();
  const replied = response.value.some(
    (message) =>
      message.conversationId === exact.conversationId &&
      message.from?.emailAddress?.address?.toLocaleLowerCase() === expectedAddress &&
      Number.isFinite(Date.parse(message.receivedDateTime ?? "")) &&
      Date.parse(message.receivedDateTime!) > Date.parse(exact.sentDateTime),
  );
  if (replied) return { kind: "replied" };
  return {
    kind: "notify",
    text: `FOLLOW-UP EMAIL\n\nNon risulta ancora una risposta da ${exact.contactName} <${exact.contactAddress}>.\nOggetto: ${exact.subject}\nScadenza: ${exact.deadlineDateTime}\n\nControllo effettuato in sola lettura. Nessuna email è stata inviata.`,
  };
}

export function createEmailFollowUpTools(
  graph: MicrosoftGraphClient,
  scheduler: EmailFollowUpScheduler,
): ToolDefinition[] {
  const execute = async (
    parameters: ToolParameters,
    executionContext: Parameters<ToolDefinition["execute"]>[1],
  ): Promise<ToolExecutionResult> => {
    requireApprovedExecutionContext(executionContext);
    const payload = payloadFrom(parameters);
    const scheduleId = await scheduler.scheduleFollowUp(
      new Date(payload.deadlineDateTime),
      payload,
    );
    return {
      simulated: false,
      message: `Follow-up programmato. ID: ${scheduleId.slice(0, 8)}.`,
      data: { scheduleId },
    };
  };

  return [
    {
      name: "schedule_email_follow_up",
      description:
        "Per richieste come 'se Marco non risponde entro venerdì avvisami': trova la più recente email inviata al contatto, mostra un riepilogo e, soltanto dopo approvazione, programma un controllo in sola lettura alla scadenza. Non invia email.",
      risk: ToolRisk.WRITE_LOW_RISK,
      exposedToModel: true,
      parameters: inputSchema(),
      validate: validateInput,
      validateApproved: validatePrepared,
      prepareApproval: async (parameters) => {
        const response = await graph.get<GraphCollection<GraphMailMessage>>(
          "/me/mailFolders/sentitems/messages",
          {
            "$top": "50",
            "$orderby": "sentDateTime desc",
            "$select":
              "id,conversationId,subject,sentDateTime,toRecipients",
          },
        );
        const needle = normalizeSearch(parameters.contactQuery!);
        for (const message of response.value) {
          if (
            !message.conversationId ||
            message.conversationId.length > MAX_ID_CHARS ||
            !message.sentDateTime ||
            !Number.isFinite(Date.parse(message.sentDateTime))
          ) {
            continue;
          }
          const recipient = (message.toRecipients ?? []).find((candidate) => {
            const name = safeSingleLine(candidate.emailAddress?.name, 200);
            const address = safeSingleLine(candidate.emailAddress?.address, 320);
            return normalizeSearch(`${name} ${address}`).includes(needle);
          });
          const address = safeSingleLine(recipient?.emailAddress?.address, 320);
          if (!recipient || !/^\S+@\S+\.\S+$/u.test(address)) continue;
          const name =
            safeSingleLine(recipient.emailAddress?.name, 200) || address;
          return preparedFollowUp(
            message,
            name,
            address,
            parameters.deadlineDateTime!,
          );
        }
        return {
          parameters,
          preview: "Nessuna email inviata compatibile trovata.",
          noActionResult: {
            simulated: false,
            message:
              "Non ho trovato tra le ultime 50 email inviate un messaggio indirizzato al contatto indicato. Specifica il nome completo o l'indirizzo email.",
          },
        };
      },
      preview: () => "Follow-up email in attesa di preparazione.",
      execute,
    },
  ];
}
