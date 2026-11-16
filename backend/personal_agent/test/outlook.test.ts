import { afterEach, describe, expect, it, vi } from "vitest";

import {
  beginMicrosoftAuthorization,
  completeMicrosoftAuthorization,
  emptyMicrosoftConnection,
  MICROSOFT_SCOPES,
} from "../src/outlook/auth";
import { decryptSecret } from "../src/outlook/crypto";
import {
  MicrosoftGraphClient,
  microsoftErrorUserHint,
} from "../src/outlook/graph";
import { createOutlookTools } from "../src/outlook/tools";

const encryptionKey = btoa(String.fromCharCode(...new Uint8Array(32).fill(7)));
const config = {
  clientId: "00000000-0000-4000-8000-000000000001",
  clientSecret: "test-secret",
  tenantId: "common",
  redirectUri: "https://example.workers.dev/oauth/microsoft/callback",
  encryptionKey,
};

afterEach(() => vi.restoreAllMocks());

describe("Microsoft OAuth", () => {
  it("requests only the configured delegated scopes with PKCE", async () => {
    const authorization = await beginMicrosoftAuthorization(config, new Date(0));
    const url = new URL(authorization.url);
    expect(url.searchParams.get("scope")?.split(" ")).toEqual(MICROSOFT_SCOPES);
    expect(url.searchParams.get("code_challenge_method")).toBe("S256");
    expect(url.searchParams.get("prompt")).toBe("select_account");
    expect(authorization.state.pkceVerifier).not.toBeNull();
    expect(authorization.state.status).toBe("PENDING");
  });

  it("rejects an incorrect OAuth state before exchanging tokens", async () => {
    const fetchSpy = vi.spyOn(globalThis, "fetch");
    const authorization = await beginMicrosoftAuthorization(config, new Date(0));
    await expect(
      completeMicrosoftAuthorization(
        authorization.state,
        config,
        "authorization-code",
        "wrong-state",
        new Date(1),
      ),
    ).rejects.toThrow("Invalid or expired");
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it("encrypts tokens before returning persistent state", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(
      new Response(
        JSON.stringify({
          token_type: "Bearer",
          scope: "User.Read Mail.Read Calendars.ReadWrite",
          expires_in: 3600,
          access_token: "access-token",
          refresh_token: "refresh-token",
        }),
        { status: 200, headers: { "content-type": "application/json" } },
      ),
    );
    const authorization = await beginMicrosoftAuthorization(config, new Date(0));
    const completed = await completeMicrosoftAuthorization(
      authorization.state,
      config,
      "authorization-code",
      authorization.state.oauthState!,
      new Date(1),
    );
    expect(JSON.stringify(completed.state)).not.toContain("refresh-token");
    expect(
      await decryptSecret(completed.state.refreshToken!, encryptionKey),
    ).toBe("refresh-token");
  });

  it("rejects a token that omitted the delegated mail permission", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(
      new Response(
        JSON.stringify({
          token_type: "Bearer",
          scope: "User.Read Calendars.ReadWrite",
          expires_in: 3600,
          access_token: "profile-only-token",
          refresh_token: "refresh-token",
        }),
        { status: 200, headers: { "content-type": "application/json" } },
      ),
    );
    const authorization = await beginMicrosoftAuthorization(config, new Date(0));
    await expect(
      completeMicrosoftAuthorization(
        authorization.state,
        config,
        "authorization-code",
        authorization.state.oauthState!,
        new Date(1),
      ),
    ).rejects.toThrow("Mail.Read");
  });

  it("starts disconnected without credentials in state", () => {
    expect(emptyMicrosoftConnection()).toMatchObject({
      status: "DISCONNECTED",
      accessToken: null,
      refreshToken: null,
    });
  });
});

describe("Microsoft Graph read-only tools", () => {
  it("maps Graph failures to safe user guidance", () => {
    expect(
      microsoftErrorUserHint(
        new Error("Microsoft Graph request failed with status 403 (ErrorAccessDenied)"),
      ),
    ).toContain("Calendars.ReadWrite");
    expect(
      microsoftErrorUserHint(
        new Error("Microsoft Graph request failed with status 400 (BadRequest)"),
      ),
    ).toContain("rifiutato i dati");
    expect(microsoftErrorUserHint(new Error("unrelated"))).toBeNull();
  });

  it("use only GET requests against the Graph v1.0 host", async () => {
    const fetchSpy = vi.spyOn(globalThis, "fetch").mockImplementation(
      async () =>
        new Response(JSON.stringify({ value: [] }), {
          status: 200,
          headers: { "content-type": "application/json" },
        }),
    );
    const graph = new MicrosoftGraphClient(async () => "access-token");
    const tools = createOutlookTools(graph);

    await tools.find((tool) => tool.name === "search_email")!.execute({
      query: "Marco",
    });
    await tools.find((tool) => tool.name === "read_calendar")!.execute({
      startDateTime: "2026-08-13T00:00:00+02:00",
      endDateTime: "2026-08-14T00:00:00+02:00",
    });

    for (const call of fetchSpy.mock.calls) {
      const request = call[0];
      const url = request instanceof URL ? request : new URL(String(request));
      expect(url.origin).toBe("https://graph.microsoft.com");
      expect(url.pathname.startsWith("/v1.0/")).toBe(true);
      expect(call[1]?.method ?? "GET").toBe("GET");
    }
  });

  it("exposes no Outlook write tool", () => {
    const tools = createOutlookTools(new MicrosoftGraphClient(async () => "token"));
    expect(tools.map((tool) => tool.name)).toEqual([
      "search_email",
      "read_email",
      "read_calendar",
      "find_calendar_events",
    ]);
  });

  it("refreshes the token once after a Graph 401", async () => {
    const tokenCalls: boolean[] = [];
    const graph = new MicrosoftGraphClient(async (forceRefresh) => {
      tokenCalls.push(forceRefresh);
      return forceRefresh ? "fresh-token" : "stale-token";
    });
    const fetchSpy = vi
      .spyOn(globalThis, "fetch")
      .mockImplementationOnce(
        async () =>
          new Response(
            JSON.stringify({ error: { code: "InvalidAuthenticationToken" } }),
            { status: 401 },
          ),
      )
      .mockImplementationOnce(
        async () =>
          new Response(JSON.stringify({ value: [] }), {
            status: 200,
            headers: { "content-type": "application/json" },
          }),
      );

    await graph.get("/me/messages");
    expect(tokenCalls).toEqual([false, true]);
    expect(fetchSpy).toHaveBeenCalledTimes(2);
    expect(fetchSpy.mock.calls[1]?.[1]?.headers).toMatchObject({
      authorization: "Bearer fresh-token",
    });
  });
});
