import type { ConversationMemoryItem } from "../memory/types";
import type { ToolDefinition } from "../tools/types";

export interface ModelToolCall {
  name: string;
  arguments: unknown;
}

export type ToolCallDecision =
  | { kind: "output"; output: string }
  | { kind: "approval_required"; actionId: string; text: string }
  | { kind: "blocked"; text: string };

export interface GenerateTextInput {
  message: string;
  conversation: ConversationMemoryItem[];
  longTermMemories: string[];
  tools: ToolDefinition[];
  handleToolCall(call: ModelToolCall): Promise<ToolCallDecision>;
  requestId: string;
  safetyIdentifier: string;
}

export interface GenerateTextResult {
  text: string;
  approvalRequest?: { actionId: string };
  usage: {
    inputTokens: number | null;
    outputTokens: number | null;
    estimatedCostUsd: number | null;
  };
}

export interface AiProvider {
  generateText(input: GenerateTextInput): Promise<GenerateTextResult>;
}
