import {
  MAX_INCOMING_MESSAGE_CHARS,
  MAX_TELEGRAM_MESSAGE_CHARS,
} from "../config/constants";

export function normalizeIncomingMessage(text: string): string {
  const normalized = text.trim();
  if (normalized.length === 0) return "";
  return normalized.slice(0, MAX_INCOMING_MESSAGE_CHARS);
}

export function fitTelegramMessage(text: string): string {
  const normalized = text.trim();
  if (normalized.length <= MAX_TELEGRAM_MESSAGE_CHARS) return normalized;
  return `${normalized.slice(0, MAX_TELEGRAM_MESSAGE_CHARS - 1)}…`;
}
