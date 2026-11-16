import type { AgentGateway } from "../agent/types";
import { getTelegramUpdateIdentity, isAuthorizedTelegramUpdate } from "../security/auth";
import { normalizeIncomingMessage } from "../security/input";
import { helpMessage, memoryMessage, statusMessage } from "./messages";
import type { TelegramClient, TelegramUpdate } from "./types";

export interface TelegramProcessorDependencies {
  agent: AgentGateway;
  telegram: TelegramClient;
  rateLimit(userId: string): Promise<boolean>;
}

export interface TelegramProcessorConfig {
  allowedUserId: string;
  allowedChatId: string;
}

export type ProcessUpdateResult =
  | "ignored"
  | "unauthorized"
  | "rate_limited"
  | "processed";

const MICROSOFT_PERMISSION_MANAGEMENT_URL =
  "https://account.live.com/consent/Manage";

function asksForMicrosoftPermissionManagement(text: string): boolean {
  const normalized = text
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/gu, "")
    .toLocaleLowerCase();
  const mentionsPermissions = /\b(autorizzazion\w*|permess\w*)\b/u.test(normalized);
  const asksToRemove = /\b(togli\w*|rimuov\w*|revoc\w*|cancell\w*)\b/u.test(
    normalized,
  );
  const asksForLocation = /\b(sito|link|pagina|dove|come)\b/u.test(normalized);
  return mentionsPermissions && asksToRemove && asksForLocation;
}

function parseCommand(text: string): string | null {
  if (!text.startsWith("/")) return null;
  const token = text.split(/\s+/, 1)[0] ?? "";
  return token.split("@", 1)[0]?.toLowerCase() ?? null;
}

function commandArgument(text: string): string {
  const separator = text.search(/\s/);
  return separator === -1 ? "" : text.slice(separator).trim();
}

async function processCallback(
  update: TelegramUpdate,
  dependencies: TelegramProcessorDependencies,
  requestId: string,
): Promise<ProcessUpdateResult> {
  const callback = update.callback_query;
  if (!callback?.message || typeof callback.data !== "string") return "ignored";

  const match = /^pa:(approve|reject):([0-9a-f-]{36})$/i.exec(callback.data);
  if (!match) {
    await dependencies.telegram.answerCallbackQuery(callback.id, "Richiesta non valida.");
    return "processed";
  }

  const decision = match[1] === "approve" ? "approve" : "reject";
  const result = await dependencies.agent.decideAction(match[2]!, decision, requestId);
  await dependencies.telegram.answerCallbackQuery(callback.id, result.text);
  const original = callback.message.text?.trim() ?? "Richiesta di approvazione";
  await dependencies.telegram.editMessageText(
    callback.message.chat.id,
    callback.message.message_id,
    `${original}\n\n${result.text}`,
  );
  return "processed";
}

export async function processTelegramUpdate(
  update: TelegramUpdate,
  dependencies: TelegramProcessorDependencies,
  config: TelegramProcessorConfig,
  requestId: string,
): Promise<ProcessUpdateResult> {
  if (
    !isAuthorizedTelegramUpdate(update, {
      userId: config.allowedUserId,
      chatId: config.allowedChatId,
    })
  ) {
    return "unauthorized";
  }
  const identity = getTelegramUpdateIdentity(update);
  if (!identity) return "ignored";

  if (!(await dependencies.rateLimit(identity.userId))) {
    const chatId = Number(identity.chatId);
    await dependencies.telegram.sendMessage(chatId, "Troppe richieste. Riprova tra poco.");
    return "rate_limited";
  }

  if (update.callback_query) {
    return processCallback(update, dependencies, requestId);
  }

  const message = update.message;
  if (!message?.from || typeof message.text !== "string") return "ignored";
  const text = normalizeIncomingMessage(message.text);
  if (text.length === 0) return "ignored";

  const command = parseCommand(text);
  switch (command) {
    case "/help":
      await dependencies.telegram.sendMessage(message.chat.id, helpMessage());
      break;
    case "/status":
      await dependencies.telegram.sendMessage(
        message.chat.id,
        statusMessage(await dependencies.agent.getStatus()),
      );
      break;
    case "/stop":
      await dependencies.agent.stop();
      await dependencies.telegram.sendMessage(
        message.chat.id,
        "Agente fermato. Nessuna richiesta AI o azione verrà eseguita fino a /start.",
      );
      break;
    case "/start":
      await dependencies.agent.start();
      await dependencies.telegram.sendMessage(
        message.chat.id,
        "Agente riattivato. SAFE MODE resta ON.",
      );
      break;
    case "/memory":
      await dependencies.telegram.sendMessage(
        message.chat.id,
        memoryMessage(await dependencies.agent.getMemory()),
      );
      break;
    case "/remember": {
      const content = commandArgument(text);
      if (!content) {
        await dependencies.telegram.sendMessage(
          message.chat.id,
          "Scrivi cosa memorizzare, per esempio: /remember Preferisco risposte concise",
        );
        break;
      }
      const memory = await dependencies.agent.remember(content);
      await dependencies.telegram.sendMessage(
        message.chat.id,
        memory.enabled
          ? "Memoria salvata. Usa /memory per controllarla."
          : "Memoria disattivata: usa /memory_on prima di salvare.",
      );
      break;
    }
    case "/forget":
      await dependencies.agent.clearMemory();
      await dependencies.telegram.sendMessage(
        message.chat.id,
        "Memoria e contesto della conversazione cancellati.",
      );
      break;
    case "/newchat":
      await dependencies.agent.clearConversation();
      await dependencies.telegram.sendMessage(
        message.chat.id,
        "Contesto recente cancellato. Le memorie esplicite restano disponibili.",
      );
      break;
    case "/memory_on":
      await dependencies.agent.setMemoryEnabled(true);
      await dependencies.telegram.sendMessage(message.chat.id, "Memoria attivata.");
      break;
    case "/memory_off":
      await dependencies.agent.setMemoryEnabled(false);
      await dependencies.telegram.sendMessage(
        message.chat.id,
        "Memoria disattivata. I dati esistenti restano salvati ma non vengono usati.",
      );
      break;
    case "/outlook_connect": {
      const connection = await dependencies.agent.beginMicrosoftConnect();
      await dependencies.telegram.sendMessage(
        message.chat.id,
        `Apri questo link entro 10 minuti e accedi a Microsoft:\n\n${connection.url}\n\nVerranno richiesti lettura email, gestione calendario e accesso offline. Il bot usa la scrittura soltanto per creare eventi che approvi su Telegram.`,
      );
      break;
    }
    case "/outlook_disconnect":
      await dependencies.agent.disconnectMicrosoft();
      await dependencies.telegram.sendMessage(
        message.chat.id,
        "Outlook scollegato dal bot. I token salvati sono stati rimossi.",
      );
      break;
    case "/reminders": {
      const reminders = await dependencies.agent.listReminders();
      const body =
        reminders.length === 0
          ? "Nessun promemoria programmato."
          : reminders
              .map(
                (reminder) =>
                  `- ${reminder.id.slice(0, 8)} | ${reminder.recurring ?? reminder.scheduledAt} | ${reminder.description}`,
              )
              .join("\n");
      await dependencies.telegram.sendMessage(
        message.chat.id,
        `PROMEMORIA PROGRAMMATI\n\n${body}`,
      );
      break;
    }
    case "/reminder_cancel": {
      const id = commandArgument(text);
      if (!id) {
        await dependencies.telegram.sendMessage(
          message.chat.id,
          "Indica l'ID mostrato da /reminders. Esempio: /reminder_cancel a1b2c3d4",
        );
        break;
      }
      const result = await dependencies.agent.cancelReminder(id);
      const response =
        result.outcome === "cancelled"
          ? `Promemoria ${result.reminder.id.slice(0, 8)} cancellato. Nessun evento Outlook è stato modificato o cancellato.`
          : result.outcome === "ambiguous"
            ? "ID ambiguo: usa più caratteri dell'ID mostrato da /reminders."
            : "Promemoria non trovato: potrebbe essere già stato eseguito o cancellato.";
      await dependencies.telegram.sendMessage(message.chat.id, response);
      break;
    }
    case "/followups": {
      const followUps = (await dependencies.agent.listReminders()).filter(
        (reminder) => reminder.kind === "EMAIL_FOLLOW_UP",
      );
      await dependencies.telegram.sendMessage(
        message.chat.id,
        followUps.length === 0
          ? "Nessun follow-up email programmato."
          : `FOLLOW-UP EMAIL\n\n${followUps
              .map(
                (followUp) =>
                  `- ${followUp.id.slice(0, 8)} | ${followUp.scheduledAt} | ${followUp.description}`,
              )
              .join("\n")}`,
      );
      break;
    }
    case "/email_status": {
      const status = await dependencies.agent.getStatus();
      await dependencies.telegram.sendMessage(
        message.chat.id,
        `Email Agent: ${status.importantEmailMonitor}\nClassificazioni: INFORMATIONAL, IMPORTANT, ACTION_REQUIRED\nNotifiche automatiche: solo IMPORTANT e ACTION_REQUIRED\nInvio email: NON DISPONIBILE`,
      );
      break;
    }
    case null: {
      const status = await dependencies.agent.getStatus();
      if (status.mode === "STOPPED") {
        await dependencies.telegram.sendMessage(
          message.chat.id,
          "L'agente è fermo. Usa /start per riattivarlo.",
        );
        break;
      }

      if (asksForMicrosoftPermissionManagement(text)) {
        await dependencies.telegram.sendMessage(
          message.chat.id,
          `Puoi revocare le autorizzazioni Microsoft da qui:\n${MICROSOFT_PERMISSION_MANAGEMENT_URL}`,
        );
        break;
      }

      const result = await dependencies.agent.chat(
        text,
        requestId,
        identity.userId,
      );
      await dependencies.telegram.sendMessage(
        message.chat.id,
        result.text,
        result.kind === "approval_required"
          ? { approvalActionId: result.actionId }
          : undefined,
      );
      break;
    }
    default:
      await dependencies.telegram.sendMessage(
        message.chat.id,
        `Comando non riconosciuto.\n\n${helpMessage()}`,
      );
  }

  return "processed";
}
