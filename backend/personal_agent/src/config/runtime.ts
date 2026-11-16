import { SAFE_MODE } from "./constants";

export interface RuntimeConfig {
  ai: {
    provider: "openai";
    model: string;
    maxOutputTokens: number;
    timeoutMs: number;
  };
  telegram: {
    allowedUserId: string;
    allowedChatId: string;
  };
  safeMode: true;
  microsoft: {
    configured: boolean;
    clientId: string;
    clientSecret: string;
    tenantId: string;
    redirectUri: string;
    encryptionKey: string;
  };
  fitbit: {
    configured: boolean;
    clientId: string;
    clientSecret: string;
    redirectUri: string;
    encryptionKey: string;
  };
  sharedTasks: { configured: boolean };
}

function positiveInteger(value: string, fallback: number): number {
  const parsed = Number.parseInt(value, 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}

export function getRuntimeConfig(env: Env): RuntimeConfig {
  if (env.SAFE_MODE !== "true" || !SAFE_MODE) {
    throw new Error("SAFE_MODE must remain enabled during the experimental phase");
  }

  if (env.AI_PROVIDER !== "openai") {
    throw new Error(`Unsupported AI provider: ${env.AI_PROVIDER}`);
  }

  return {
    ai: {
      provider: "openai",
      model: env.AI_MODEL,
      maxOutputTokens: positiveInteger(env.AI_MAX_OUTPUT_TOKENS, 1_200),
      timeoutMs: positiveInteger(env.AI_TIMEOUT_MS, 25_000),
    },
    telegram: {
      allowedUserId: env.TELEGRAM_ALLOWED_USER_ID,
      allowedChatId: env.TELEGRAM_ALLOWED_CHAT_ID,
    },
    safeMode: SAFE_MODE,
    microsoft: {
      configured: Boolean(
        env.MICROSOFT_CLIENT_ID &&
          env.MICROSOFT_CLIENT_SECRET &&
          env.MICROSOFT_TENANT_ID &&
          env.MICROSOFT_REDIRECT_URI &&
          env.MICROSOFT_TOKEN_ENCRYPTION_KEY,
      ),
      clientId: env.MICROSOFT_CLIENT_ID ?? "",
      clientSecret: env.MICROSOFT_CLIENT_SECRET ?? "",
      tenantId: env.MICROSOFT_TENANT_ID ?? "",
      redirectUri: env.MICROSOFT_REDIRECT_URI ?? "",
      encryptionKey: env.MICROSOFT_TOKEN_ENCRYPTION_KEY ?? "",
    },
    fitbit: {
      configured: Boolean(
        env.GOOGLE_HEALTH_CLIENT_ID &&
          env.GOOGLE_HEALTH_CLIENT_SECRET &&
          env.GOOGLE_HEALTH_REDIRECT_URI &&
          env.GOOGLE_HEALTH_TOKEN_ENCRYPTION_KEY,
      ),
      clientId: env.GOOGLE_HEALTH_CLIENT_ID ?? "",
      clientSecret: env.GOOGLE_HEALTH_CLIENT_SECRET ?? "",
      redirectUri: env.GOOGLE_HEALTH_REDIRECT_URI ?? "",
      encryptionKey: env.GOOGLE_HEALTH_TOKEN_ENCRYPTION_KEY ?? "",
    },
    sharedTasks: {
      configured: Boolean(
        (env as Env & { SUPABASE_URL?: string }).SUPABASE_URL &&
          (env as Env & { SUPABASE_SERVICE_ROLE_KEY?: string }).SUPABASE_SERVICE_ROLE_KEY &&
          (env as Env & { DESKTOP_SUPABASE_USER_ID?: string }).DESKTOP_SUPABASE_USER_ID,
      ),
    },
  };
}
