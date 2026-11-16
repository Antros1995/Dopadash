import { describe, expect, it } from "vitest";

import {
  authorizeDesktopRequest,
  desktopCorsHeaders,
  DesktopRequestError,
  type DesktopAuthEnv,
} from "../src/desktop/auth";

const env: DesktopAuthEnv = {
  SUPABASE_URL: "https://project.supabase.co",
  SUPABASE_PUBLISHABLE_KEY: "sb_publishable_test",
  DESKTOP_SUPABASE_USER_ID: "owner-id",
  DESKTOP_ALLOWED_ORIGINS: "http://localhost:7358,https://app.example.com",
};

function request(origin = "http://localhost:7358"): Request {
  return new Request("https://worker.example/api/desktop/calendar", {
    headers: {
      authorization: `Bearer ${"x".repeat(30)}`,
      origin,
    },
  });
}

describe("desktop authentication", () => {
  const mfaUser = { id: "owner-id", factors: [{ id: "totp-id", status: "verified", factor_type: "totp" }] };
  function jwtRequest(payload: unknown): Request {
    const token = `eyJhbGciOiJIUzI1NiJ9.${btoa(JSON.stringify(payload)).replace(/=/gu, "").replace(/\+/gu, "-").replace(/\//gu, "_")}.testsignature`;
    return new Request("https://worker.example/api/desktop/fitbit", { headers: { authorization: `Bearer ${token}` } });
  }

  it("requires aal2 for an owner with a verified factor", async () => {
    const fetcher: typeof fetch = async () => Response.json(mfaUser);
    for (const claims of [{ sub: "owner-id", aal: "aal1" }, { sub: "owner-id" }, { aal: "aal2" }, { sub: "different-user", aal: "aal2" }]) {
      await expect(authorizeDesktopRequest(jwtRequest(claims), env, fetcher))
        .rejects.toMatchObject({ status: 403, code: "mfa_required" });
    }
    await expect(authorizeDesktopRequest(jwtRequest({ sub: "owner-id", aal: "aal2" }), env, fetcher))
      .resolves.toMatchObject({ id: "owner-id" });
  });

  it("does not trust elevated claims before Supabase validates the token", async () => {
    const fetcher: typeof fetch = async () => new Response("invalid", { status: 401 });
    await expect(authorizeDesktopRequest(jwtRequest({ sub: "owner-id", aal: "aal2" }), env, fetcher))
      .rejects.toMatchObject({ status: 401, code: "invalid_session" });
  });

  it("rejects malformed tokens for MFA accounts", async () => {
    await expect(authorizeDesktopRequest(request(), env, async () => Response.json(mfaUser)))
      .rejects.toMatchObject({ status: 403, code: "mfa_required" });
  });

  it("keeps unenrolled and unverified-only accounts working", async () => {
    for (const factors of [[], [{ status: "unverified", factor_type: "totp" }]]) {
      await expect(authorizeDesktopRequest(jwtRequest({ sub: "owner-id", aal: "aal1" }), env,
        async () => Response.json({ id: "owner-id", factors })))
        .resolves.toMatchObject({ id: "owner-id" });
    }
  });

  it("fails closed when Supabase returns malformed authentication data", async () => {
    for (const body of [null, [], { id: "owner-id", factors: {} }]) {
      await expect(authorizeDesktopRequest(request(), env, async () => Response.json(body)))
        .rejects.toMatchObject({ status: 503, code: "authentication_unavailable" });
    }
  });

  it("validates the bearer token with Supabase and accepts only the owner", async () => {
    let capturedUrl = "";
    let capturedHeaders: HeadersInit | undefined;
    const fetcher: typeof fetch = async (input, options) => {
      capturedUrl = String(input);
      capturedHeaders = options?.headers;
      return Response.json({ id: "owner-id", email: "owner@example.com" });
    };
    const user = await authorizeDesktopRequest(request(), env, fetcher);
    expect(user).toEqual({ id: "owner-id", email: "owner@example.com" });
    expect(capturedUrl).toBe("https://project.supabase.co/auth/v1/user");
    expect((capturedHeaders as Record<string, string>).apikey).toBe(
      "sb_publishable_test",
    );
  });

  it("rejects another valid Supabase user", async () => {
    const fetcher: typeof fetch = async () =>
      Response.json({ id: "different-user" });
    await expect(
      authorizeDesktopRequest(request(), env, fetcher),
    ).rejects.toMatchObject({ status: 403, code: "user_not_allowed" });
  });

  it("returns CORS headers only for an allowlisted browser origin", () => {
    const headers = desktopCorsHeaders(request(), env.DESKTOP_ALLOWED_ORIGINS);
    expect(headers.get("access-control-allow-origin")).toBe(
      "http://localhost:7358",
    );
    expect(() =>
      desktopCorsHeaders(request("https://evil.example"), env.DESKTOP_ALLOWED_ORIGINS),
    ).toThrow(DesktopRequestError);
  });

  it("accepts a configured Pages origin and its preview deployments", () => {
    const allowed = `${env.DESKTOP_ALLOWED_ORIGINS},https://my-dashboard.pages.dev`;
    for (const origin of [
      "https://my-dashboard.pages.dev",
      "https://abc12345.my-dashboard.pages.dev",
    ]) {
      expect(desktopCorsHeaders(request(origin), allowed).get("access-control-allow-origin"))
        .toBe(origin);
    }
    for (const origin of [
      "https://evil.my-dashboard.pages.dev.attacker.com",
      "https://other-project.pages.dev",
      "https://abc12345.my-dashboard.pages.dev",
    ]) {
      const configured = origin.includes("abc12345")
        ? env.DESKTOP_ALLOWED_ORIGINS
        : allowed;
      expect(() => desktopCorsHeaders(request(origin), configured)).toThrow(
        DesktopRequestError,
      );
    }
  });
});
