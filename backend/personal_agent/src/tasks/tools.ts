import { requireApprovedExecutionContext } from "../approvals/execution-context";
import { ToolRisk } from "../security/risk";
import type { ToolDefinition, ToolParameters } from "../tools/types";
import { completeTaskByTitle, createTask, listTasks, requireTaskDate } from "./supabase";
import type { PersonalTaskGroup } from "./types";

const GROUP_LABEL: Record<PersonalTaskGroup, string> = { personal: "personali", work: "lavoro", personal_work: "lavoro personale" };

function parameters(input: unknown, create: boolean): ToolParameters {
  if (!input || typeof input !== "object" || Array.isArray(input)) throw new Error("Invalid task parameters");
  const candidate = input as Record<string, unknown>;
  const expected = create ? ["title", "group", "scheduledDate"] : ["scheduledDate"];
  if (Object.keys(candidate).length !== expected.length || expected.some((key) => typeof candidate[key] !== "string")) {
    throw new Error("Invalid task parameters");
  }
  const scheduledDate = requireTaskDate(candidate.scheduledDate as string);
  if (!create) return { scheduledDate };
  const title = (candidate.title as string).trim();
  const group = candidate.group as PersonalTaskGroup;
  if (!title || title.length > 160 || !["personal", "work", "personal_work"].includes(group)) throw new Error("Invalid task parameters");
  return { title, group, scheduledDate };
}

function completionParameters(input: unknown): ToolParameters {
  if (!input || typeof input !== "object" || Array.isArray(input)) throw new Error("Invalid task completion parameters");
  const candidate = input as Record<string, unknown>;
  if (Object.keys(candidate).length !== 2 || typeof candidate.title !== "string" || typeof candidate.completedAt !== "string") throw new Error("Invalid task completion parameters");
  const title = candidate.title.trim();
  const completedAt = new Date(candidate.completedAt);
  if (!title || title.length > 160 || !Number.isFinite(completedAt.getTime())) throw new Error("Invalid task completion parameters");
  return { title, completedAt: completedAt.toISOString() };
}

function displayDate(value: string): string {
  const [year, month, day] = value.split("-");
  return `${day}/${month}/${year}`;
}

export function createSharedTaskTools(env: Env): ToolDefinition[] {
  return [{
    name: "list_shared_tasks",
    description: "Legge i task della data indicata. Usa questo tool per domande come 'quali task ho oggi?', includendo task personali, lavoro e lavoro personale.",
    risk: ToolRisk.READ_ONLY,
    exposedToModel: true,
    parameters: { type: "object", properties: { scheduledDate: { type: "string", description: "Data YYYY-MM-DD Europe/Rome" } }, required: ["scheduledDate"], additionalProperties: false },
    validate: (input) => parameters(input, false),
    preview: (value) => `Lettura task del ${value.scheduledDate}`,
    execute: async (value) => {
      const tasks = await listTasks(env, value.scheduledDate!);
      return { simulated: false, message: tasks.length ? `Attività del ${value.scheduledDate}: ${tasks.map((task) => `[${GROUP_LABEL[task.task_group]}] ${task.title} (data originaria ${displayDate(task.scheduled_date)})${task.completed_at ? " (completata)" : ""}`).join("; ")}` : `Nessuna attività per il ${value.scheduledDate}.`, data: tasks };
    },
  }, {
    name: "complete_shared_task",
    description: "Completa un task persistente identificandolo dal titolo. Usalo quando l'utente dice che ha fatto, finito, eseguito o completato un task. Richiede approvazione Telegram.",
    risk: ToolRisk.WRITE_LOW_RISK,
    exposedToModel: true,
    parameters: { type: "object", properties: { title: { type: "string" }, completedAt: { type: "string", description: "Data e ora attuali ISO 8601 con offset Europe/Rome" } }, required: ["title", "completedAt"], additionalProperties: false },
    validate: completionParameters,
    preview: (value) => `CONFERMA COMPLETAMENTO ATTIVITÀ\n\nAttività: ${value.title}\n\nL’attività resterà nello storico con la data originaria.`,
    execute: async (value, context) => {
      requireApprovedExecutionContext(context);
      const task = await completeTaskByTitle(env, { title: value.title!, completedAt: value.completedAt! });
      return { simulated: false, message: `Attività completata: ${task.title}. Data originaria: ${displayDate(task.scheduled_date)}.`, data: task };
    },
  }, {
    name: "create_shared_task",
    description: "Propone un task condiviso, non un evento Outlook. Usalo soltanto quando l'utente dice task o attività. group: personal se non specificato, work per lavoro, personal_work per lavoro personale. Richiede approvazione Telegram.",
    risk: ToolRisk.WRITE_LOW_RISK,
    exposedToModel: true,
    parameters: { type: "object", properties: { title: { type: "string" }, group: { type: "string", enum: ["personal", "work", "personal_work"] }, scheduledDate: { type: "string", description: "Data YYYY-MM-DD Europe/Rome" } }, required: ["title", "group", "scheduledDate"], additionalProperties: false },
    validate: (input) => parameters(input, true),
    preview: (value) => `CONFERMA CREAZIONE ATTIVITÀ\n\nTitolo: ${value.title}\nElenco: ${GROUP_LABEL[value.group! as PersonalTaskGroup]}\nData: ${value.scheduledDate}\n\nNon verrà creato alcun evento Outlook.`,
    execute: async (value, context) => {
      const approval = requireApprovedExecutionContext(context);
      const task = await createTask(env, { title: value.title!, group: value.group! as PersonalTaskGroup, scheduledDate: value.scheduledDate!, externalId: approval.actionId });
      return { simulated: false, message: `Attività creata nell'elenco ${GROUP_LABEL[task.task_group]}: ${task.title}.`, data: task };
    },
  }];
}
