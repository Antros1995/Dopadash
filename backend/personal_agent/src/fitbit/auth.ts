import {
  decryptSecret,
  encryptSecret,
  randomBase64Url,
  sha256Base64Url,
} from "../outlook/crypto";
import type { FitbitConnectionState, FitbitTokenResponse } from "./types";

const AUTHORIZE_URL = "https://accounts.google.com/o/oauth2/v2/auth";
const TOKEN_URL = "https://oauth2.googleapis.com/token";
const SCOPES = [
  "https://www.googleapis.com/auth/googlehealth.activity_and_fitness.readonly",
  "https://www.googleapis.com/auth/googlehealth.health_metrics_and_measurements.readonly",
  "https://www.googleapis.com/auth/googlehealth.sleep.readonly",
  "https://www.googleapis.com/auth/googlehealth.settings.readonly",
] as const;
const OAUTH_TTL_MS = 10 * 60_000;
const EXPIRY_MARGIN_MS = 2 * 60_000;

export interface FitbitAuthConfig {
  clientId: string;
  clientSecret: string;
  redirectUri: string;
  encryptionKey: string;
}

export function emptyFitbitConnection(): FitbitConnectionState {
  return {
    status: "DISCONNECTED",
    oauthState: null,
    pkceVerifier: null,
    oauthExpiresAt: null,
    accessToken: null,
    refreshToken: null,
    accessTokenExpiresAt: null,
    connectedAt: null,
    fitbitUserId: null,
    deviceName: null,
    syncScheduleId: null,
    days: {},
  };
}

async function requestToken(
  config: FitbitAuthConfig,
  body: Record<string, string>,
): Promise<FitbitTokenResponse> {
  const response = await fetch(TOKEN_URL, {
    method: "POST",
    headers: {
      "content-type": "application/x-www-form-urlencoded",
    },
    body: new URLSearchParams({
      client_id: config.clientId,
      client_secret: config.clientSecret,
      ...body,
    }),
  });
  if (!response.ok) {
    throw new Error(`Google Health token exchange failed with status ${response.status}`);
  }
  const token = await response.json<FitbitTokenResponse>();
  if (!token.access_token) {
    throw new Error("Google OAuth returned an invalid token response");
  }
  return token;
}

function expiresAt(token: FitbitTokenResponse, now: Date): string {
  return new Date(now.getTime() + token.expires_in * 1_000).toISOString();
}

export async function beginFitbitAuthorization(
  config: FitbitAuthConfig,
  previousDays: FitbitConnectionState["days"],
  now = new Date(),
): Promise<{ state: FitbitConnectionState; url: string }> {
  const oauthState = randomBase64Url(24);
  const verifier = randomBase64Url(64);
  const challenge = await sha256Base64Url(verifier);
  const query = new URLSearchParams({
    client_id: config.clientId,
    response_type: "code",
    redirect_uri: config.redirectUri,
    scope: SCOPES.join(" "),
    state: oauthState,
    code_challenge: challenge,
    code_challenge_method: "S256",
    prompt: "consent",
    access_type: "offline",
    include_granted_scopes: "true",
  });
  return {
    state: {
      ...emptyFitbitConnection(),
      status: "PENDING",
      oauthState,
      pkceVerifier: await encryptSecret(verifier, config.encryptionKey),
      oauthExpiresAt: new Date(now.getTime() + OAUTH_TTL_MS).toISOString(),
      days: previousDays,
    },
    url: `${AUTHORIZE_URL}?${query.toString()}`,
  };
}

export async function completeFitbitAuthorization(
  connection: FitbitConnectionState,
  config: FitbitAuthConfig,
  code: string,
  returnedState: string,
  now = new Date(),
): Promise<{ state: FitbitConnectionState; accessToken: string }> {
  if (
    connection.status !== "PENDING" ||
    !connection.oauthState ||
    !connection.pkceVerifier ||
    !connection.oauthExpiresAt ||
    connection.oauthState !== returnedState ||
    Date.parse(connection.oauthExpiresAt) <= now.getTime()
  ) {
    throw new Error("Invalid or expired Fitbit OAuth state");
  }
  const verifier = await decryptSecret(connection.pkceVerifier, config.encryptionKey);
  const token = await requestToken(config, {
    grant_type: "authorization_code",
    code,
    redirect_uri: config.redirectUri,
    code_verifier: verifier,
  });
  if (!token.refresh_token) {
    throw new Error("Google Health did not return a refresh token");
  }
  return {
    accessToken: token.access_token,
    state: {
      ...emptyFitbitConnection(),
      status: "CONNECTED",
      accessToken: await encryptSecret(token.access_token, config.encryptionKey),
      refreshToken: await encryptSecret(token.refresh_token, config.encryptionKey),
      accessTokenExpiresAt: expiresAt(token, now),
      connectedAt: now.toISOString(),
      fitbitUserId: null,
      days: connection.days,
    },
  };
}

export async function getValidFitbitAccessToken(
  connection: FitbitConnectionState,
  config: FitbitAuthConfig,
  now = new Date(),
  forceRefresh = false,
): Promise<{ state: FitbitConnectionState; accessToken: string }> {
  if (
    connection.status !== "CONNECTED" ||
    !connection.accessToken ||
    !connection.refreshToken ||
    !connection.accessTokenExpiresAt
  ) {
    throw new Error("Fitbit is not connected");
  }
  if (!forceRefresh && Date.parse(connection.accessTokenExpiresAt) - EXPIRY_MARGIN_MS > now.getTime()) {
    return {
      state: connection,
      accessToken: await decryptSecret(connection.accessToken, config.encryptionKey),
    };
  }
  const refreshToken = await decryptSecret(connection.refreshToken, config.encryptionKey);
  const token = await requestToken(config, {
    grant_type: "refresh_token",
    refresh_token: refreshToken,
  });
  const nextRefreshToken = token.refresh_token ?? refreshToken;
  return {
    accessToken: token.access_token,
    state: {
      ...connection,
      accessToken: await encryptSecret(token.access_token, config.encryptionKey),
      refreshToken: await encryptSecret(nextRefreshToken, config.encryptionKey),
      accessTokenExpiresAt: expiresAt(token, now),
    },
  };
}
