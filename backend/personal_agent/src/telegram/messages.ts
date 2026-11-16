import { APP_NAME, APP_VERSION } from "../config/constants";
import type { AgentStatus } from "../agent/types";
import type { MemoryView } from "../memory/types";

export function helpMessage(): string {
  return `${APP_NAME.toUpperCase()} — v${APP_VERSION}

Comandi:
/status      - stato agente
/stop        - blocca l'agente
/start       - riattiva l'agente
/memory      - mostra la memoria
/remember X  - memorizza esplicitamente X
/forget      - cancella tutta la memoria
/newchat     - azzera il contesto della chat
/memory_on   - abilita la memoria
/memory_off  - disabilita la memoria
/outlook_connect    - collega Outlook
/outlook_disconnect - scollega Outlook
/reminders          - mostra i promemoria programmati
/reminder_cancel ID - cancella un promemoria Telegram
/followups          - mostra i follow-up email
/email_status       - stato del monitor email importanti
/help               - mostra questo messaggio

Modalità:
SAFE MODE ON

Outlook, se collegato, è reale. Il bot legge email e calendario; crea un evento soltanto dopo la tua approvazione. Non invia email e non modifica o cancella eventi.`;
}

export function statusMessage(status: AgentStatus): string {
  return `${APP_NAME}

Version: ${APP_VERSION}
Status: ${status.mode}
Safe mode: ON
AI: ${status.aiConnected ? "CONNECTED" : "NOT CONNECTED"}
Telegram whitelist: ${status.telegramWhitelist}
Memory: ${status.memoryEnabled ? "ON" : "OFF"}
Outlook: ${status.outlook}
Task condivisi: ${status.sharedTasks}
Email Agent: ${status.importantEmailMonitor}
Follow-up attivi: ${status.followUps}
Habit: ${status.habit}
Pending approvals: ${status.pendingApprovals}`;
}

export function memoryMessage(memory: MemoryView): string {
  const facts =
    memory.longTerm.length === 0
      ? "- nessuna"
      : memory.longTerm.map((item) => `- ${item.content}`).join("\n");
  return `MEMORIA

Stato: ${memory.enabled ? "ON" : "OFF"}
Elementi nel contesto recente: ${memory.conversationItems}

Memorie esplicite:
${facts}`;
}
