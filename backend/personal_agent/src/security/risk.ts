export enum ToolRisk {
  READ_ONLY = "READ_ONLY",
  WRITE_LOW_RISK = "WRITE_LOW_RISK",
  WRITE_HIGH_RISK = "WRITE_HIGH_RISK",
  FORBIDDEN = "FORBIDDEN",
}

export type ToolPolicyDecision = "EXECUTE" | "REQUIRE_APPROVAL" | "BLOCK";

export function decideToolPolicy(
  risk: ToolRisk,
  agentMode: "ACTIVE" | "STOPPED",
): ToolPolicyDecision {
  if (agentMode === "STOPPED" || risk === ToolRisk.FORBIDDEN) return "BLOCK";
  if (risk === ToolRisk.READ_ONLY) return "EXECUTE";
  return "REQUIRE_APPROVAL";
}
