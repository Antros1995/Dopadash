type LogLevel = "info" | "warn" | "error";

interface LogEntry {
  event: string;
  requestId: string;
  [key: string]: unknown;
}

function redact(value: string, secrets: readonly string[]): string {
  return secrets.reduce(
    (redacted, secret) =>
      secret.length > 0 ? redacted.replaceAll(secret, "[REDACTED]") : redacted,
    value,
  );
}

export function serializeError(
  error: unknown,
  secrets: readonly string[],
): Record<string, string> {
  if (!(error instanceof Error)) {
    return { message: redact(String(error), secrets) };
  }

  return {
    name: error.name,
    message: redact(error.message, secrets),
    stack: redact(error.stack ?? "", secrets),
  };
}

export function log(level: LogLevel, entry: LogEntry): void {
  const record = JSON.stringify({
    timestamp: new Date().toISOString(),
    level,
    ...entry,
  });

  if (level === "error") console.error(record);
  else if (level === "warn") console.warn(record);
  else console.log(record);
}
