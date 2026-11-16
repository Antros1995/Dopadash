import { constantTimeEquals } from "../security/auth";

export interface DesktopAuthEnv {
  SUPABASE_URL: string;
  SUPABASE_PUBLISHABLE_KEY: string;
  DESKTOP_SUPABASE_USER_ID: string;
  DESKTOP_ALLOWED_ORIGINS: string;
}

export interface DesktopUser {
  id: string;
  email: string | null;
}

export class DesktopRequestError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
  ) {
    super(message);
    this.name = "DesktopRequestError";
  }
}

type Fetcher = typeof fetch;

interface SupabaseUserBody {
  id?: unknown;
  email?: unknown;
  factors?: unknown;
}

function requireMfaIfEnrolled(body: SupabaseUserBody, token: string): void {
  if (body.factors != null && !Array.isArray(body.factors)) {
    throw new DesktopRequestError(503, "authentication_unavailable", "Supabase returned invalid factors");
  }
  const enrolled = Array.isArray(body.factors) && body.factors.some(
    (factor: unknown) => typeof factor === "object" && factor !== null &&
      "status" in factor && factor.status === "verified",
  );
  if (!enrolled) return;

  // Only inspect claims AFTER Supabase has validated this exact bearer token.
  // Local decoding alone is not signature verification.
  try {
    const parts = token.split(".");
    if (parts.length !== 3 || !parts[1]) throw new Error("Invalid JWT");
    const encoded = parts[1].replace(/-/gu, "+").replace(/_/gu, "/");
    const payload: unknown = JSON.parse(atob(encoded.padEnd(Math.ceil(encoded.length / 4) * 4, "=")));
    if (typeof payload === "object" && payload !== null &&
        "aal" in payload && payload.aal === "aal2" &&
        "sub" in payload && payload.sub === body.id) return;
  } catch {
    // Missing, malformed, or insufficient claims all fail closed for MFA users.
  }
  throw new DesktopRequestError(403, "mfa_required", "Verify your Authenticator code before accessing the personal agent");
}

function configuredValue(value: string | undefined, name: string): string {
  const normalized = value?.trim() ?? "";
  if (!normalized) {
    throw new DesktopRequestError(
      503,
      "desktop_api_not_configured",
      `${name} is not configured`,
    );
  }
  return normalized;
}

function supabaseUserEndpoint(rawUrl: string): URL {
  let url: URL;
  try {
    url = new URL(configuredValue(rawUrl, "SUPABASE_URL"));
  } catch (error) {
    if (error instanceof DesktopRequestError) throw error;
    throw new DesktopRequestError(
      503,
      "desktop_api_not_configured",
      "SUPABASE_URL is invalid",
    );
  }
  if (url.protocol !== "https:") {
    throw new DesktopRequestError(
      503,
      "desktop_api_not_configured",
      "SUPABASE_URL must use HTTPS",
    );
  }
  url.pathname = `${url.pathname.replace(/\/$/u, "")}/auth/v1/user`;
  url.search = "";
  url.hash = "";
  return url;
}

function bearerToken(request: Request): string {
  const authorization = request.headers.get("authorization") ?? "";
  const match = /^Bearer ([^\s]{20,8192})$/u.exec(authorization);
  if (!match?.[1]) {
    throw new DesktopRequestError(
      401,
      "invalid_session",
      "A valid Supabase bearer token is required",
    );
  }
  return match[1];
}

export function desktopCorsHeaders(
  request: Request,
  rawAllowedOrigins: string,
): Headers {
  const configured = configuredValue(
    rawAllowedOrigins,
    "DESKTOP_ALLOWED_ORIGINS",
  );
  const origins = configured
    .split(",")
    .map((value) => value.trim())
    .filter(Boolean);
  const origin = request.headers.get("origin");
  const headers = new Headers({ vary: "Origin" });

  // Requests made by Workers, tests, or trusted command-line clients may omit
  // Origin. Browser cross-origin requests always include it.
  if (!origin) return headers;
  // A configured Cloudflare Pages origin (https://<project>.pages.dev) also
  // admits its preview deployments (https://<hash>.<project>.pages.dev).
  const isPagesPreview = origins.some((allowed) => {
    const project = /^https:\/\/([a-z0-9-]+)\.pages\.dev$/u.exec(allowed)?.[1];
    return (
      project !== undefined &&
      new RegExp(`^https://[a-z0-9-]+\\.${project}\\.pages\\.dev$`, "u").test(origin)
    );
  });
  if (!isPagesPreview && !origins.some((allowed) => constantTimeEquals(origin, allowed))) {
    throw new DesktopRequestError(
      403,
      "origin_not_allowed",
      "This origin is not allowed",
    );
  }

  headers.set("access-control-allow-origin", origin);
  headers.set("access-control-allow-methods", "GET, POST, OPTIONS");
  headers.set("access-control-allow-headers", "Authorization, Content-Type");
  headers.set("access-control-max-age", "86400");
  return headers;
}

export async function authorizeDesktopRequest(
  request: Request,
  env: DesktopAuthEnv,
  fetcher: Fetcher = fetch,
): Promise<DesktopUser> {
  const token = bearerToken(request);
  const publishableKey = configuredValue(
    env.SUPABASE_PUBLISHABLE_KEY,
    "SUPABASE_PUBLISHABLE_KEY",
  );
  const ownerId = configuredValue(
    env.DESKTOP_SUPABASE_USER_ID,
    "DESKTOP_SUPABASE_USER_ID",
  );
  let response: Response;
  try {
    response = await fetcher(supabaseUserEndpoint(env.SUPABASE_URL), {
      headers: {
        apikey: publishableKey,
        authorization: `Bearer ${token}`,
      },
    });
  } catch {
    throw new DesktopRequestError(
      503,
      "authentication_unavailable",
      "Supabase authentication is temporarily unavailable",
    );
  }
  if (!response.ok) {
    throw new DesktopRequestError(
      401,
      "invalid_session",
      "The Supabase session is invalid or expired",
    );
  }

  let body: SupabaseUserBody;
  try {
    const parsed: unknown = await response.json();
    if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) {
      throw new Error("Invalid user response");
    }
    body = parsed as SupabaseUserBody;
  } catch {
    throw new DesktopRequestError(
      503,
      "authentication_unavailable",
      "Supabase returned an invalid response",
    );
  }
  if (typeof body.id !== "string" || body.id.length > 128) {
    throw new DesktopRequestError(
      503,
      "authentication_unavailable",
      "Supabase returned an invalid user",
    );
  }
  if (!constantTimeEquals(body.id, ownerId)) {
    throw new DesktopRequestError(
      403,
      "user_not_allowed",
      "This account is not allowed to access the personal agent",
    );
  }
  requireMfaIfEnrolled(body, token);
  return {
    id: body.id,
    email:
      typeof body.email === "string" ? body.email.slice(0, 320) : null,
  };
}
