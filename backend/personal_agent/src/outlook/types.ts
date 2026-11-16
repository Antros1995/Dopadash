export interface EncryptedValue {
  iv: string;
  ciphertext: string;
}

export interface MicrosoftConnectionState {
  status: "DISCONNECTED" | "PENDING" | "CONNECTED";
  oauthState: string | null;
  pkceVerifier: EncryptedValue | null;
  oauthExpiresAt: string | null;
  accessToken: EncryptedValue | null;
  refreshToken: EncryptedValue | null;
  accessTokenExpiresAt: string | null;
  connectedAt: string | null;
  accountLabel: string | null;
  fileAccess?: boolean;
}

export interface MicrosoftTokenResponse {
  token_type: string;
  scope: string;
  expires_in: number;
  access_token: string;
  refresh_token?: string;
}

export interface MicrosoftProfile {
  displayName?: string;
  mail?: string | null;
  userPrincipalName?: string;
}
