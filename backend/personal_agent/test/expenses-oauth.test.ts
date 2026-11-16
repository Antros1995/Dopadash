import { afterEach, expect, it, vi } from "vitest";
import { beginMicrosoftAuthorization, completeMicrosoftAuthorization, getValidMicrosoftAccessToken } from "../src/outlook/auth";
import { decryptSecret } from "../src/outlook/crypto";

const config = { clientId: "test-client", clientSecret: "test-secret", tenantId: "common",
  redirectUri: "https://example.workers.dev/oauth/microsoft/callback",
  encryptionKey: btoa(String.fromCharCode(...new Uint8Array(32).fill(7))) };
afterEach(() => vi.restoreAllMocks());

it("requests Files.Read only on explicit OneDrive connect and retains encrypted consent on refresh", async () => {
  const regular = await beginMicrosoftAuthorization(config, new Date(0));
  expect(new URL(regular.url).searchParams.get("scope")).not.toContain("Files.Read");
  const pending = await beginMicrosoftAuthorization(config, new Date(0), true);
  expect(new URL(pending.url).searchParams.get("scope")).toContain("https://graph.microsoft.com/Files.Read");
  expect(new URL(pending.url).searchParams.get("scope")).not.toContain("Files.ReadWrite");
  const fetchSpy = vi.spyOn(globalThis, "fetch").mockImplementation(async (_url, options) => {
    expect((options!.body as URLSearchParams).get("scope")).toContain("Files.Read");
    return new Response(JSON.stringify({ token_type: "Bearer", scope: "User.Read Mail.Read Calendars.ReadWrite Files.Read",
      expires_in: 3600, access_token: "secret-access", refresh_token: "secret-refresh" }));
  });
  const complete = await completeMicrosoftAuthorization(pending.state, config, "code", pending.state.oauthState!, new Date(1));
  expect(complete.state.fileAccess).toBe(true);
  expect(JSON.stringify(complete.state)).not.toContain("secret-access");
  expect(await decryptSecret(complete.state.refreshToken!, config.encryptionKey)).toBe("secret-refresh");
  const renewed = await getValidMicrosoftAccessToken(complete.state, config, new Date(2), true);
  expect(renewed.state.fileAccess).toBe(true);
  expect(fetchSpy).toHaveBeenCalledTimes(2);
});

it("refuses a OneDrive connection when Microsoft omits Files.Read", async () => {
  const pending = await beginMicrosoftAuthorization(config, new Date(0), true);
  vi.spyOn(globalThis, "fetch").mockResolvedValue(new Response(JSON.stringify({
    token_type: "Bearer", scope: "User.Read Mail.Read Calendars.ReadWrite", expires_in: 3600,
    access_token: "secret-access", refresh_token: "secret-refresh" })));
  await expect(completeMicrosoftAuthorization(pending.state, config, "code", pending.state.oauthState!, new Date(1))).rejects.toThrow("Files.Read");
});
