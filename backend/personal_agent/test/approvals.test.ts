import { describe, expect, it, vi } from "vitest";

import {
  createPendingAction,
  resolveApproval,
} from "../src/approvals/service";
import { ToolRisk } from "../src/security/risk";
import type { ToolDefinition } from "../src/tools/types";

function testTool(execute = vi.fn(async () => ({
  simulated: true as const,
  message: "Simulazione eseguita",
}))): ToolDefinition {
  return {
    name: "test_write_mock",
    description: "test",
    risk: ToolRisk.WRITE_LOW_RISK,
    exposedToModel: true,
    parameters: {},
    validate(input) {
      const candidate = input as Record<string, unknown>;
      if (typeof candidate.value !== "string" || Object.keys(candidate).length !== 1) {
        throw new Error("invalid");
      }
      return { value: candidate.value };
    },
    preview: (parameters) => `Valore: ${parameters.value}`,
    execute,
  };
}

describe("Approval service", () => {
  it("does not execute a write before approval", () => {
    const execute = vi.fn(async () => ({
      simulated: true as const,
      message: "ok",
    }));
    createPendingAction(testTool(execute), { value: "originale" });
    expect(execute).not.toHaveBeenCalled();
  });

  it("rejected actions cannot execute", async () => {
    const execute = vi.fn(async () => ({ simulated: true as const, message: "ok" }));
    const tool = testTool(execute);
    const action = createPendingAction(tool, { value: "originale" }, new Date(0), "a1");
    const rejected = await resolveApproval({
      actions: [action],
      actionId: "a1",
      decision: "reject",
      agentMode: "ACTIVE",
      getTool: () => tool,
      now: new Date(1),
      onApproved: () => undefined,
    });
    expect(rejected.result.outcome).toBe("rejected");
    expect(execute).not.toHaveBeenCalled();

    const retry = await resolveApproval({
      actions: rejected.actions,
      actionId: "a1",
      decision: "approve",
      agentMode: "ACTIVE",
      getTool: () => tool,
      now: new Date(2),
      onApproved: () => undefined,
    });
    expect(retry.result.outcome).toBe("already_handled");
    expect(execute).not.toHaveBeenCalled();
  });

  it("expired actions cannot execute", async () => {
    const execute = vi.fn(async () => ({ simulated: true as const, message: "ok" }));
    const tool = testTool(execute);
    const action = createPendingAction(tool, { value: "originale" }, new Date(0), "a1");
    const result = await resolveApproval({
      actions: [action],
      actionId: "a1",
      decision: "approve",
      agentMode: "ACTIVE",
      getTool: () => tool,
      now: new Date(11 * 60 * 1_000),
      onApproved: () => undefined,
    });
    expect(result.result.outcome).toBe("expired");
    expect(execute).not.toHaveBeenCalled();
  });

  it("executes the exact saved payload once", async () => {
    const execute = vi.fn(async () => ({ simulated: true as const, message: "ok" }));
    const tool = testTool(execute);
    const parameters = { value: "originale" };
    const action = createPendingAction(tool, parameters, new Date(0), "a1");
    parameters.value = "modificato dopo la creazione";

    const first = await resolveApproval({
      actions: [action],
      actionId: "a1",
      decision: "approve",
      agentMode: "ACTIVE",
      getTool: () => tool,
      now: new Date(1),
      onApproved: () => undefined,
    });
    expect(first.result.outcome).toBe("executed");
    expect(execute).toHaveBeenCalledOnce();
    expect(execute).toHaveBeenCalledWith(
      { value: "originale" },
      expect.objectContaining({
        actionId: "a1",
        approvedAt: "1970-01-01T00:00:00.001Z",
      }),
    );

    const second = await resolveApproval({
      actions: first.actions,
      actionId: "a1",
      decision: "approve",
      agentMode: "ACTIVE",
      getTool: () => tool,
      now: new Date(2),
      onApproved: () => undefined,
    });
    expect(second.result.outcome).toBe("already_handled");
    expect(execute).toHaveBeenCalledOnce();
  });

  it("blocks approval while the kill switch is active", async () => {
    const execute = vi.fn(async () => ({ simulated: true as const, message: "ok" }));
    const tool = testTool(execute);
    const action = createPendingAction(tool, { value: "originale" }, new Date(0), "a1");
    const result = await resolveApproval({
      actions: [action],
      actionId: "a1",
      decision: "approve",
      agentMode: "STOPPED",
      getTool: () => tool,
      now: new Date(1),
      onApproved: () => undefined,
    });
    expect(result.result.outcome).toBe("blocked");
    expect(execute).not.toHaveBeenCalled();
  });
});
