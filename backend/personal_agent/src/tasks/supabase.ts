import type { PersonalTask, PersonalTaskGroup } from "./types";

const TASK_GROUPS = new Set<PersonalTaskGroup>(["personal", "work", "personal_work"]);

type TaskBackendEnv = Env & {
  SUPABASE_URL?: string;
  SUPABASE_SERVICE_ROLE_KEY?: string;
  DESKTOP_SUPABASE_USER_ID?: string;
};

function requireTaskBackend(env: Env): { url: string; serviceRoleKey: string; userId: string } {
  const taskEnv = env as TaskBackendEnv;
  if (!taskEnv.SUPABASE_URL || !taskEnv.SUPABASE_SERVICE_ROLE_KEY || !taskEnv.DESKTOP_SUPABASE_USER_ID) {
    throw new Error("Shared tasks integration is not configured");
  }
  return {
    url: taskEnv.SUPABASE_URL.replace(/\/$/u, ""),
    serviceRoleKey: taskEnv.SUPABASE_SERVICE_ROLE_KEY,
    userId: taskEnv.DESKTOP_SUPABASE_USER_ID,
  };
}

async function request<T>(env: Env, path: string, init: RequestInit = {}): Promise<T> {
  const config = requireTaskBackend(env);
  const response = await fetch(`${config.url}/rest/v1/${path}`, {
    ...init,
    headers: {
      apikey: config.serviceRoleKey,
      authorization: `Bearer ${config.serviceRoleKey}`,
      "content-type": "application/json",
      ...init.headers,
    },
  });
  if (!response.ok) throw new Error(`Shared tasks request failed (${response.status})`);
  return response.json() as Promise<T>;
}

export function requireTaskDate(value: string): string {
  if (!/^\d{4}-\d{2}-\d{2}$/u.test(value) || Number.isNaN(Date.parse(`${value}T00:00:00Z`))) {
    throw new Error("Invalid task date");
  }
  return value;
}

export async function listTasks(env: Env, date: string): Promise<PersonalTask[]> {
  const config = requireTaskBackend(env);
  const day = requireTaskDate(date);
  const tasks = await request<PersonalTask[]>(
    env,
    `monitoraggio_personale_tasks?select=id,title,task_group,scheduled_date,completed_at,source,created_at&user_id=eq.${encodeURIComponent(config.userId)}&order=scheduled_date.asc,created_at.asc`,
  );
  return tasks.filter((task) => task.completed_at ? romeDateKey(task.completed_at) === day : task.scheduled_date <= day);
}

function romeDateKey(value: string): string {
  const parsed = new Date(value);
  if (!Number.isFinite(parsed.getTime())) throw new Error("Invalid completion date");
  return new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Rome", year: "numeric", month: "2-digit", day: "2-digit" }).format(parsed);
}

function normalizedTitle(value: string): string {
  return value.trim().replace(/\s+/gu, " ").toLocaleLowerCase("it-IT");
}

export async function completeTaskByTitle(env: Env, input: { title: string; completedAt: string }): Promise<PersonalTask> {
  const completedAt = new Date(input.completedAt);
  if (!Number.isFinite(completedAt.getTime())) throw new Error("Invalid task completion date");
  const openTasks = (await listTasks(env, romeDateKey(completedAt.toISOString()))).filter((task) => !task.completed_at);
  const requested = normalizedTitle(input.title);
  const exact = openTasks.filter((task) => normalizedTitle(task.title) === requested);
  const matches = exact.length > 0 ? exact : openTasks.filter((task) => normalizedTitle(task.title).includes(requested));
  if (matches.length === 0) throw new Error("Task not found");
  if (matches.length > 1) throw new Error("Task title is ambiguous");
  const config = requireTaskBackend(env);
  const rows = await request<PersonalTask[]>(env, `monitoraggio_personale_tasks?id=eq.${encodeURIComponent(matches[0]!.id)}&user_id=eq.${encodeURIComponent(config.userId)}`, {
    method: "PATCH",
    headers: { prefer: "return=representation" },
    body: JSON.stringify({ completed_at: completedAt.toISOString() }),
  });
  const task = rows[0];
  if (!task) throw new Error("Shared task completion returned no task");
  return task;
}

export async function createTask(
  env: Env,
  input: { title: string; group: PersonalTaskGroup; scheduledDate: string; externalId: string },
): Promise<PersonalTask> {
  if (!TASK_GROUPS.has(input.group)) throw new Error("Invalid task group");
  const title = input.title.trim();
  if (!title || title.length > 160) throw new Error("Invalid task title");
  const config = requireTaskBackend(env);
  const rows = await request<PersonalTask[]>(env, "monitoraggio_personale_tasks", {
    method: "POST",
    headers: { prefer: "return=representation" },
    body: JSON.stringify({
      user_id: config.userId,
      title,
      task_group: input.group,
      scheduled_date: requireTaskDate(input.scheduledDate),
      source: "telegram",
      external_id: input.externalId,
    }),
  });
  const task = rows[0];
  if (!task) throw new Error("Shared task creation returned no task");
  return task;
}
