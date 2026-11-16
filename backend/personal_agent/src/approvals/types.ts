import type { ToolRisk } from "../security/risk";
import type { ToolParameters } from "../tools/types";

export type PendingActionStatus =
  | "PENDING"
  | "APPROVED"
  | "REJECTED"
  | "EXECUTED"
  | "FAILED"
  | "EXPIRED";

export interface PendingAction {
  id: string;
  toolName: string;
  risk: ToolRisk;
  parameters: ToolParameters;
  preview: string;
  status: PendingActionStatus;
  createdAt: string;
  expiresAt: string;
  completedAt: string | null;
  result: string | null;
}

export type ApprovalDecision = "approve" | "reject";

export interface ApprovalResult {
  outcome:
    | "executed"
    | "rejected"
    | "expired"
    | "already_handled"
    | "not_found"
    | "blocked"
    | "failed";
  text: string;
}
