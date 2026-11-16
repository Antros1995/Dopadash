const APPROVED_EXECUTION = Symbol("approved-execution");

export interface ApprovedExecutionContext {
  readonly actionId: string;
  readonly approvedAt: string;
  readonly [APPROVED_EXECUTION]: true;
}

export function createApprovedExecutionContext(
  actionId: string,
  approvedAt: Date,
): ApprovedExecutionContext {
  return Object.freeze({
    actionId,
    approvedAt: approvedAt.toISOString(),
    [APPROVED_EXECUTION]: true as const,
  });
}

export function requireApprovedExecutionContext(
  context: ApprovedExecutionContext | undefined,
): ApprovedExecutionContext {
  if (
    !context ||
    context[APPROVED_EXECUTION] !== true ||
    !/^[0-9a-f-]{36}$/iu.test(context.actionId)
  ) {
    throw new Error("Approved execution context required");
  }
  return context;
}
