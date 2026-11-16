import type { TelegramUpdate } from "../telegram/types";

export interface TelegramWhitelist {
  userId: string;
  chatId: string;
}

export interface TelegramUpdateIdentity {
  userId: string;
  chatId: string;
}

export function getTelegramUpdateIdentity(
  update: TelegramUpdate,
): TelegramUpdateIdentity | null {
  if (update.message?.from) {
    return {
      userId: String(update.message.from.id),
      chatId: String(update.message.chat.id),
    };
  }

  const callback = update.callback_query;
  if (callback?.message) {
    return {
      userId: String(callback.from.id),
      chatId: String(callback.message.chat.id),
    };
  }
  return null;
}

export function isAuthorizedTelegramUpdate(
  update: TelegramUpdate,
  whitelist: TelegramWhitelist,
): boolean {
  const identity = getTelegramUpdateIdentity(update);
  return Boolean(
    identity &&
      identity.userId === whitelist.userId &&
      identity.chatId === whitelist.chatId,
  );
}

export function constantTimeEquals(actual: string, expected: string): boolean {
  const encoder = new TextEncoder();
  const actualBytes = encoder.encode(actual);
  const expectedBytes = encoder.encode(expected);
  const length = Math.max(actualBytes.length, expectedBytes.length);
  let difference = actualBytes.length ^ expectedBytes.length;

  for (let index = 0; index < length; index += 1) {
    difference |= (actualBytes[index] ?? 0) ^ (expectedBytes[index] ?? 0);
  }

  return difference === 0;
}
