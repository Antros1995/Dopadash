import { fitTelegramMessage } from "../security/input";
import type { TelegramClient } from "./types";

interface TelegramApiResponse {
  ok: boolean;
  description?: string;
}

export class BotApiTelegramClient implements TelegramClient {
  constructor(private readonly botToken: string) {}

  async sendMessage(
    chatId: number,
    text: string,
    options?: { approvalActionId?: string },
  ): Promise<void> {
    const actionId = options?.approvalActionId;
    await this.call("sendMessage", {
      chat_id: chatId,
      text: fitTelegramMessage(text),
      ...(actionId
        ? {
            reply_markup: {
              inline_keyboard: [
                [
                  { text: "✅ Approva", callback_data: `pa:approve:${actionId}` },
                  { text: "❌ Rifiuta", callback_data: `pa:reject:${actionId}` },
                ],
              ],
            },
          }
        : {}),
    });
  }

  async answerCallbackQuery(callbackQueryId: string, text: string): Promise<void> {
    await this.call("answerCallbackQuery", {
      callback_query_id: callbackQueryId,
      text: text.slice(0, 200),
    });
  }

  async editMessageText(
    chatId: number,
    messageId: number,
    text: string,
  ): Promise<void> {
    await this.call("editMessageText", {
      chat_id: chatId,
      message_id: messageId,
      text: fitTelegramMessage(text),
      reply_markup: { inline_keyboard: [] },
    });
  }

  private async call(method: string, payload: Record<string, unknown>): Promise<void> {
    const response = await fetch(
      `https://api.telegram.org/bot${this.botToken}/${method}`,
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(payload),
      },
    );

    const body = await response.json<TelegramApiResponse>();
    if (!response.ok || !body.ok) {
      throw new Error(`Telegram ${method} failed with status ${response.status}`);
    }
  }
}
