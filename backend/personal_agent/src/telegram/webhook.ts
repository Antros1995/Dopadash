import { AGENT_INSTANCE_NAME, MAX_WEBHOOK_BODY_BYTES } from "../config/constants";
import { getRuntimeConfig } from "../config/runtime";
import { constantTimeEquals, isAuthorizedTelegramUpdate } from "../security/auth";
import { log, serializeError } from "../storage/logger";
import type { AgentGateway } from "../agent/types";
import { microsoftErrorUserHint } from "../outlook/graph";
import { BotApiTelegramClient } from "./client";
import { processTelegramUpdate } from "./processor";
import type { TelegramUpdate } from "./types";

function textByteLength(value: string): number {
  return new TextEncoder().encode(value).byteLength;
}

function getAgent(env: Env): AgentGateway {
  return env.PERSONAL_AGENT.getByName(AGENT_INSTANCE_NAME) as AgentGateway;
}

async function processSafely(
  update: TelegramUpdate,
  env: Env,
  requestId: string,
): Promise<void> {
  const config = getRuntimeConfig(env);
  const telegram = new BotApiTelegramClient(env.TELEGRAM_BOT_TOKEN);

  try {
    const result = await processTelegramUpdate(
      update,
      {
        agent: getAgent(env),
        telegram,
        rateLimit: async (userId) => {
          const outcome = await env.TELEGRAM_RATE_LIMITER.limit({ key: userId });
          return outcome.success;
        },
      },
      config.telegram,
      requestId,
    );

    log(result === "unauthorized" ? "warn" : "info", {
      event: "telegram_update_processed",
      requestId,
      updateId: update.update_id,
      result,
    });
  } catch (error) {
    const userHint = microsoftErrorUserHint(error);
    log("error", {
      event: "telegram_update_failed",
      requestId,
      updateId: update.update_id,
      error: serializeError(error, [env.TELEGRAM_BOT_TOKEN, env.OPENAI_API_KEY]),
    });

    if (
      isAuthorizedTelegramUpdate(update, {
        userId: config.telegram.allowedUserId,
        chatId: config.telegram.allowedChatId,
      })
    ) {
      try {
        if (update.callback_query) {
          await telegram.answerCallbackQuery(
            update.callback_query.id,
            `Operazione non riuscita. ID: ${requestId}`,
          );
        }
        const chatId =
          update.message?.chat.id ?? update.callback_query?.message?.chat.id;
        if (chatId !== undefined) {
          await telegram.sendMessage(
            chatId,
            `Non sono riuscito a completare l'operazione.${userHint ? `\n${userHint}` : ""}\nID errore: ${requestId}`,
          );
        }
      } catch (notificationError) {
        log("error", {
          event: "telegram_error_notification_failed",
          requestId,
          error: serializeError(notificationError, [env.TELEGRAM_BOT_TOKEN]),
        });
      }
    }
  }
}

export async function handleTelegramWebhook(
  request: Request,
  env: Env,
  ctx: ExecutionContext,
  requestId: string,
): Promise<Response> {
  const actualSecret =
    request.headers.get("X-Telegram-Bot-Api-Secret-Token") ?? "";
  if (!constantTimeEquals(actualSecret, env.TELEGRAM_WEBHOOK_SECRET)) {
    log("warn", { event: "telegram_webhook_rejected", requestId });
    return new Response("Forbidden", { status: 403 });
  }

  const declaredLength = Number.parseInt(
    request.headers.get("content-length") ?? "0",
    10,
  );
  if (declaredLength > MAX_WEBHOOK_BODY_BYTES) {
    return new Response("Payload too large", { status: 413 });
  }

  const rawBody = await request.text();
  if (textByteLength(rawBody) > MAX_WEBHOOK_BODY_BYTES) {
    return new Response("Payload too large", { status: 413 });
  }

  let update: TelegramUpdate;
  try {
    update = JSON.parse(rawBody) as TelegramUpdate;
  } catch {
    return new Response("Invalid JSON", { status: 400 });
  }

  if (!Number.isSafeInteger(update.update_id)) {
    return new Response("Invalid update", { status: 400 });
  }

  ctx.waitUntil(processSafely(update, env, requestId));
  return new Response("OK", { status: 200 });
}
