import {
  decryptSecret,
  encryptSecret,
  randomBase64Url,
  sha256Base64Url,
} from "./crypto";
import type {
  MicrosoftConnectionState,
  MicrosoftProfile,
  MicrosoftTokenResponse,
} from "./types";

export const MICROSOFT_SCOPES = [
  "openid",
  "profile",
  "offline_access",
  "https://graph.microsoft.com/User.Read",
  "https://graph.microsoft.com/Mail.Read",
  "https://graph.microsoft.com/Calendars.ReadWrite",
] as const;

const REQUIRED_GRAPH_SCOPES = [
  "User.Read",
  "Mail.Read",
  "Calendars.ReadWrite",
] as const;

const OAUTH_TTL_MS = 10 * 60 * 1_000;
const TOKEN_EXPIRY_MARGIN_MS = 2 * 60 * 1_000;

export function emptyMicrosoftConnection(): MicrosoftConnectionState {
  return {
    status: "DISCONNECTED",
    oauthState: null,
    pkceVerifier: null,
    oauthExpiresAt: null,
    accessToken: null,
    refreshToken: null,
    accessTokenExpiresAt: null,
    connectedAt: null,
    accountLabel: null,
  };
}

export interface MicrosoftAuthConfig {
  clientId: string;
  clientSecret: string;
  tenantId: string;
  redirectUri: string;
  encryptionKey: string;
}

function authority(config: MicrosoftAuthConfig): string {
  if (!/^[A-Za-z0-9.-]+$/u.test(config.tenantId)) {
    throw new Error("Invalid Microsoft tenant ID");
  }
  return `https://login.microsoftonline.com/${config.tenantId}/oauth2/v2.0`;
}

export async function beginMicrosoftAuthorization(
  config: MicrosoftAuthConfig,
  now = new Date(),
  fileAccess = false,
): Promise<{ state: MicrosoftConnectionState; url: string }> {
  const oauthState = randomBase64Url(24);
  const verifier = randomBase64Url(64);
  const challenge = await sha256Base64Url(verifier);
  const query = new URLSearchParams({
    client_id: config.clientId,
    response_type: "code",
    redirect_uri: config.redirectUri,
    response_mode: "query",
    scope: requestedScopes(fileAccess).join(" "),
    state: oauthState,
    code_challenge: challenge,
    code_challenge_method: "S256",
    // Corporate SSO sessions must not silently select the work account when
    // the user wants to connect a personal Outlook account.
    prompt: "select_account",
  });

  return {
    state: {
      ...emptyMicrosoftConnection(),
      status: "PENDING",
      oauthState,
      pkceVerifier: await encryptSecret(verifier, config.encryptionKey),
      oauthExpiresAt: new Date(now.getTime() + OAUTH_TTL_MS).toISOString(),
      fileAccess,
    },
    url: `${authority(config)}/authorize?${query.toString()}`,
  };
}

async function tokenRequest(
  config: MicrosoftAuthConfig,
  parameters: Record<string, string>,
  fileAccess = false,
): Promise<MicrosoftTokenResponse> {
  const response = await fetch(`${authority(config)}/token`, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: config.clientId,
      client_secret: config.clientSecret,
      scope: requestedScopes(fileAccess).join(" "),
      ...parameters,
    }),
  });
  if (!response.ok) {
    throw new Error(`Microsoft token exchange failed with status ${response.status}`);
  }
  return response.json<MicrosoftTokenResponse>();
}

function tokenExpiry(token: MicrosoftTokenResponse, now: Date): string {
  return new Date(now.getTime() + token.expires_in * 1_000).toISOString();
}

function requestedScopes(fileAccess: boolean): readonly string[] {
  return fileAccess ? [...MICROSOFT_SCOPES, "https://graph.microsoft.com/Files.Read"] : MICROSOFT_SCOPES;
}

function validateRequiredGraphScopes(token: MicrosoftTokenResponse, fileAccess = false): void {
  const granted = new Set(
    token.scope
      .split(/\s+/u)
      .filter(Boolean)
      .map((scope) => scope.split("/").at(-1)?.toLocaleLowerCase() ?? ""),
  );
  const missing = [...REQUIRED_GRAPH_SCOPES, ...(fileAccess ? ["Files.Read"] : [])].filter(
    (scope) => !granted.has(scope.toLocaleLowerCase()),
  );
  if (missing.length > 0) {
    throw new Error(
      `Microsoft consent missing required delegated scopes: ${missing.join(", ")}`,
    );
  }
}

export async function completeMicrosoftAuthorization(
  connection: MicrosoftConnectionState,
  config: MicrosoftAuthConfig,
  code: string,
  returnedState: string,
  now = new Date(),
): Promise<{ state: MicrosoftConnectionState; accessToken: string }> {
  if (
    connection.status !== "PENDING" ||
    !connection.oauthState ||
    !connection.pkceVerifier ||
    !connection.oauthExpiresAt ||
    connection.oauthState !== returnedState ||
    Date.parse(connection.oauthExpiresAt) <= now.getTime()
  ) {
    throw new Error("Invalid or expired Microsoft OAuth state");
  }

  const verifier = await decryptSecret(
    connection.pkceVerifier,
    config.encryptionKey,
  );
  const token = await tokenRequest(config, {
    grant_type: "authorization_code",
    code,
    redirect_uri: config.redirectUri,
    code_verifier: verifier,
  }, connection.fileAccess === true);
  validateRequiredGraphScopes(token, connection.fileAccess === true);
  if (!token.refresh_token) {
    throw new Error("Microsoft did not return a refresh token");
  }

  return {
    accessToken: token.access_token,
    state: {
      status: "CONNECTED",
      oauthState: null,
      pkceVerifier: null,
      oauthExpiresAt: null,
      accessToken: await encryptSecret(token.access_token, config.encryptionKey),
      refreshToken: await encryptSecret(token.refresh_token, config.encryptionKey),
      accessTokenExpiresAt: tokenExpiry(token, now),
      connectedAt: now.toISOString(),
      accountLabel: null,
      fileAccess: connection.fileAccess === true,
    },
  };
}

export async function getValidMicrosoftAccessToken(
  connection: MicrosoftConnectionState,
  config: MicrosoftAuthConfig,
  now = new Date(),
  forceRefresh = false,
): Promise<{ state: MicrosoftConnectionState; accessToken: string }> {
  if (
    connection.status !== "CONNECTED" ||
    !connection.accessToken ||
    !connection.refreshToken ||
    !connection.accessTokenExpiresAt
  ) {
    throw new Error("Outlook is not connected");
  }

  if (
    !forceRefresh &&
    Date.parse(connection.accessTokenExpiresAt) - TOKEN_EXPIRY_MARGIN_MS >
    now.getTime()
  ) {
    return {
      state: connection,
      accessToken: await decryptSecret(connection.accessToken, config.encryptionKey),
    };
  }

  const refreshToken = await decryptSecret(
    connection.refreshToken,
    config.encryptionKey,
  );
  const token = await tokenRequest(config, {
    grant_type: "refresh_token",
    refresh_token: refreshToken,
  }, connection.fileAccess === true);
  validateRequiredGraphScopes(token, connection.fileAccess === true);
  const nextRefreshToken = token.refresh_token ?? refreshToken;
  return {
    accessToken: token.access_token,
    state: {
      ...connection,
      accessToken: await encryptSecret(token.access_token, config.encryptionKey),
      refreshToken: await encryptSecret(nextRefreshToken, config.encryptionKey),
      accessTokenExpiresAt: tokenExpiry(token, now),
    },
  };
}

export async function readMicrosoftProfile(
  accessToken: string,
): Promise<MicrosoftProfile> {
  const response = await fetch(
    "https://graph.microsoft.com/v1.0/me?$select=displayName,mail,userPrincipalName",
    { headers: { authorization: `Bearer ${accessToken}` } },
  );
  if (!response.ok) {
    throw new Error(`Microsoft profile request failed with status ${response.status}`);
  }
  return response.json<MicrosoftProfile>();
}
