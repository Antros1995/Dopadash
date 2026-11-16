import type {
  ApprovalDecision,
  ApprovalResult,
  PendingAction,
} from "./types";
import { decideToolPolicy } from "../security/risk";
import type { ToolDefinition, ToolParameters } from "../tools/types";
import { createApprovedExecutionContext } from "./execution-context";

export const APPROVAL_TTL_MS = 10 * 60 * 1_000;
const MAX_STORED_ACTIONS = 30;

export function createPendingAction(
  tool: ToolDefinition,
  parameters: ToolParameters,
  now = new Date(),
  id = crypto.randomUUID(),
  preparedPreview?: string,
): PendingAction {
  const exactParameters = JSON.parse(JSON.stringify(parameters)) as ToolParameters;
  return {
    id,
    toolName: tool.name,
    risk: tool.risk,
    parameters: exactParameters,
    preview: preparedPreview ?? tool.preview(exactParameters),
    status: "PENDING",
    createdAt: now.toISOString(),
    expiresAt: new Date(now.getTime() + APPROVAL_TTL_MS).toISOString(),
    completedAt: null,
    result: null,
  };
}

export function expireActions(
  actions: PendingAction[],
  now = new Date(),
): PendingAction[] {
  const nowMs = now.getTime();
  return actions
    .map((action) =>
      action.status === "PENDING" && Date.parse(action.expiresAt) <= nowMs
        ? { ...action, status: "EXPIRED" as const, completedAt: now.toISOString() }
        : action,
    )
    .slice(-MAX_STORED_ACTIONS);
}

export function appendPendingAction(
  actions: PendingAction[],
  action: PendingAction,
): PendingAction[] {
  return [...expireActions(actions), action].slice(-MAX_STORED_ACTIONS);
}

export function pendingCount(actions: PendingAction[], now = new Date()): number {
  return expireActions(actions, now).filter((action) => action.status === "PENDING")
    .length;
}

function replaceAction(
  actions: PendingAction[],
  actionId: string,
  update: (action: PendingAction) => PendingAction,
): PendingAction[] {
  return actions.map((action) => (action.id === actionId ? update(action) : action));
}

export interface ResolveApprovalInput {
  actions: PendingAction[];
  actionId: string;
  decision: ApprovalDecision;
  agentMode: "ACTIVE" | "STOPPED";
  getTool(name: string): ToolDefinition | undefined;
  now?: Date;
  onApproved(actions: PendingAction[]): void;
}

export interface ResolveApprovalOutput {
  actions: PendingAction[];
  result: ApprovalResult;
  toolName?: string;
  error?: unknown;
}

export async function resolveApproval(
  input: ResolveApprovalInput,
): Promise<ResolveApprovalOutput> {
  const now = input.now ?? new Date();
  let actions = expireActions(input.actions, now);
  const action = actions.find((candidate) => candidate.id === input.actionId);

  if (!action) {
    return { actions, result: { outcome: "not_found", text: "Azione non trovata." } };
  }
  if (input.agentMode === "STOPPED") {
    return {
      actions,
      result: { outcome: "blocked", text: "Agente fermo: azione non eseguita." },
    };
  }
  if (action.status === "EXPIRED") {
    return {
      actions,
      result: { outcome: "expired", text: "Approvazione scaduta. Ricrea l'azione." },
    };
  }
  if (action.status !== "PENDING") {
    return {
      actions,
      result: {
        outcome: "already_handled",
        text: `Azione già gestita (${action.status}).`,
      },
    };
  }

  if (input.decision === "reject") {
    actions = replaceAction(actions, input.actionId, (current) => ({
      ...current,
      status: "REJECTED",
      completedAt: now.toISOString(),
    }));
    return {
      actions,
      result: { outcome: "rejected", text: "Azione rifiutata. Nulla è stato eseguito." },
      toolName: action.toolName,
    };
  }

  const tool = input.getTool(action.toolName);
  if (
    !tool ||
    tool.risk !== action.risk ||
    decideToolPolicy(tool.risk, input.agentMode) !== "REQUIRE_APPROVAL"
  ) {
    return {
      actions,
      result: {
        outcome: "blocked",
        text: "Azione bloccata dalla policy di sicurezza.",
      },
    };
  }

  const validated = (tool.validateApproved ?? tool.validate)(action.parameters);
  if (JSON.stringify(validated) !== JSON.stringify(action.parameters)) {
    return {
      actions,
      result: { outcome: "blocked", text: "I parametri salvati non sono più validi." },
    };
  }

  actions = replaceAction(actions, input.actionId, (current) => ({
    ...current,
    status: "APPROVED",
  }));
  input.onApproved(actions);

  try {
    const execution = await tool.execute(
      action.parameters,
      createApprovedExecutionContext(action.id, now),
    );
    const completedAt = new Date(now.getTime() + 1).toISOString();
    actions = replaceAction(actions, input.actionId, (current) => ({
      ...current,
      status: "EXECUTED",
      completedAt,
      result: execution.message,
    }));
    return {
      actions,
      result: { outcome: "executed", text: execution.message },
      toolName: tool.name,
    };
  } catch (error) {
    const completedAt = new Date(now.getTime() + 1).toISOString();
    actions = replaceAction(actions, input.actionId, (current) => ({
      ...current,
      status: "FAILED",
      completedAt,
      result: null,
    }));
    return {
      actions,
      result: { outcome: "failed", text: "Operazione non riuscita." },
      toolName: tool.name,
      error,
    };
  }
}
