import type { ToolRisk } from "../security/risk";
import type { ApprovedExecutionContext } from "../approvals/execution-context";

export type ToolParameters = Record<string, string>;

export interface ToolExecutionResult {
  simulated: boolean;
  message: string;
  data?: unknown;
}

export interface ApprovalPreparation {
  parameters: ToolParameters;
  preview: string;
  noActionResult?: ToolExecutionResult;
}

export interface ToolDefinition {
  name: string;
  description: string;
  risk: ToolRisk;
  exposedToModel: boolean;
  parameters: Record<string, unknown>;
  validate(input: unknown): ToolParameters;
  validateApproved?(input: unknown): ToolParameters;
  prepareApproval?(parameters: ToolParameters): Promise<ApprovalPreparation>;
  preview(parameters: ToolParameters): string;
  execute(
    parameters: ToolParameters,
    approval?: ApprovedExecutionContext,
  ): Promise<ToolExecutionResult>;
}
