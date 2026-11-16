import { describe, expect, it } from "vitest";

import {
  constantTimeEquals,
  isAuthorizedTelegramUpdate,
} from "../src/security/auth";
import {
  AUTHORIZED_CHAT_ID,
  AUTHORIZED_USER_ID,
  callbackUpdate,
  update,
} from "./fixtures";

const whitelist = {
  userId: AUTHORIZED_USER_ID,
  chatId: AUTHORIZED_CHAT_ID,
};

describe("Telegram security", () => {
  it("accepts the authorized user and chat", () => {
    expect(isAuthorizedTelegramUpdate(update("ciao"), whitelist)).toBe(true);
  });

  it("rejects an unauthorized user", () => {
    expect(isAuthorizedTelegramUpdate(update("ciao", 999), whitelist)).toBe(
      false,
    );
  });

  it("rejects an unauthorized chat", () => {
    expect(
      isAuthorizedTelegramUpdate(update("ciao", 123456789, 999), whitelist),
    ).toBe(false);
  });

  it("authenticates callback queries with both user and chat", () => {
    expect(
      isAuthorizedTelegramUpdate(
        callbackUpdate(
          "00000000-0000-4000-8000-000000000001",
          "approve",
        ),
        whitelist,
      ),
    ).toBe(true);
    expect(
      isAuthorizedTelegramUpdate(
        callbackUpdate(
          "00000000-0000-4000-8000-000000000001",
          "approve",
          999,
        ),
        whitelist,
      ),
    ).toBe(false);
  });

  it("compares webhook secrets exactly", () => {
    expect(constantTimeEquals("valid_secret", "valid_secret")).toBe(true);
    expect(constantTimeEquals("invalid", "valid_secret")).toBe(false);
    expect(constantTimeEquals("valid_secret_extra", "valid_secret")).toBe(
      false,
    );
  });
});
