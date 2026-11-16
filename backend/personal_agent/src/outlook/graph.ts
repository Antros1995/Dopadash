import { downloadGraphExpenseWorkbook } from "../expenses/onedrive-download.mjs";

interface MicrosoftGraphErrorBody {
  error?: { code?: string };
}

export function microsoftErrorUserHint(error: unknown): string | null {
  const message = error instanceof Error ? error.message : String(error);
  if (
    /status 401\b/u.test(message) ||
    /Outlook is not connected/u.test(message) ||
    /Microsoft token exchange failed/u.test(message) ||
    /Microsoft consent missing required delegated scopes/u.test(message)
  ) {
    return "Il collegamento Outlook deve essere rinnovato con /outlook_disconnect e /outlook_connect.";
  }
  if (/status 403\b/u.test(message)) {
    return "Microsoft ha negato la scrittura: verifica il consenso Calendars.ReadWrite e ricollega Outlook.";
  }
  if (/status 400\b/u.test(message)) {
    return "Microsoft ha rifiutato i dati dell'evento; il payload non è stato eseguito.";
  }
  return null;
}

function safeGraphError(response: Response, bodyText: string): string {
  try {
    const body = JSON.parse(bodyText) as MicrosoftGraphErrorBody;
    if (body.error?.code) return body.error.code.slice(0, 100);
  } catch {
    // Some Microsoft 401 responses have an empty or non-JSON body.
  }

  const challenge = response.headers.get("www-authenticate") ?? "";
  const challengeError = /\berror="([A-Za-z0-9_.-]{1,100})"/u.exec(challenge)?.[1];
  return challengeError ?? "unknown";
}

export class MicrosoftGraphClient {
  constructor(
    private readonly getAccessToken: (forceRefresh: boolean) => Promise<string>,
  ) {}

  async get<T>(path: string, query?: Record<string, string>): Promise<T> {
    return this.send<T>("GET", path, query, undefined, "Europe/Rome");
  }

  async downloadExpenseWorkbook(link: string): Promise<Uint8Array> {
    return downloadGraphExpenseWorkbook(link, this.getAccessToken);
  }

  async getUtc<T>(path: string, query?: Record<string, string>): Promise<T> {
    return this.send<T>("GET", path, query, undefined, "UTC");
  }

  async post<T>(path: string, body: unknown): Promise<T> {
    return this.send<T>("POST", path, undefined, body);
  }

  private async send<T>(
    method: "GET" | "POST",
    path: string,
    query?: Record<string, string>,
    body?: unknown,
    preferredTimeZone = "Europe/Rome",
  ): Promise<T> {
    const url = new URL(`https://graph.microsoft.com/v1.0${path}`);
    for (const [name, value] of Object.entries(query ?? {})) {
      url.searchParams.set(name, value);
    }

    let response = await this.request(
      url,
      false,
      method,
      body,
      preferredTimeZone,
    );
    if (response.status === 401) {
      response = await this.request(
        url,
        true,
        method,
        body,
        preferredTimeZone,
      );
    }
    if (!response.ok) {
      const graphCode = safeGraphError(response, await response.text());
      throw new Error(
        `Microsoft Graph request failed with status ${response.status} (${graphCode})`,
      );
    }
    return response.json<T>();
  }

  private async request(
    url: URL,
    forceRefresh: boolean,
    method: "GET" | "POST",
    body?: unknown,
    preferredTimeZone = "Europe/Rome",
  ): Promise<Response> {
    return fetch(url, {
      method,
      headers: {
        authorization: `Bearer ${await this.getAccessToken(forceRefresh)}`,
        prefer: `outlook.timezone="${preferredTimeZone}", outlook.body-content-type="text"`,
        ...(body === undefined ? {} : { "content-type": "application/json" }),
      },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    });
  }
}
