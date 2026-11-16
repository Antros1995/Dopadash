import { fetchProductionMarketSeries as fetchMarketSeries } from './markets/production-market-data';
import { validateExpenseLink, ExpenseDownloadError } from './expenses/onedrive-download.mjs';
import {
  AGENT_INSTANCE_NAME,
  APP_VERSION,
  SAFE_MODE,
} from "./config/constants";
import { getRuntimeConfig } from "./config/runtime";
import { handleTelegramWebhook } from "./telegram/webhook";
import type { AgentGateway } from "./agent/types";
import {
  authorizeDesktopRequest,
  desktopCorsHeaders,
  DesktopRequestError,
  type DesktopAuthEnv,
} from "./desktop/auth";
import { requireCalendarDate } from "./outlook/calendar-view";
import {
  MarketDataError,
  requireMarketPeriod,
  requireMarketSymbol,
} from "./markets/market-data";

export { PersonalAgent as PersonalAgentV2 } from "./agent/personal-agent";

function json(
  data: unknown,
  status = 200,
  requestId?: string,
  extraHeaders?: HeadersInit,
): Response {
  const headers = new Headers(extraHeaders);
  headers.set("content-type", "application/json; charset=utf-8");
  if (requestId) headers.set("x-request-id", requestId);
  return new Response(JSON.stringify(data), { status, headers });
}

function desktopJson(
  data: unknown,
  status: number,
  requestId: string,
  corsHeaders: Headers,
): Response {
  corsHeaders.set("cache-control", "no-store");
  corsHeaders.set("x-content-type-options", "nosniff");
  return json(data, status, requestId, corsHeaders);
}

export default {
  async fetch(request, env, ctx): Promise<Response> {
    const requestId = crypto.randomUUID();
    const url = new URL(request.url);

    if (
      url.pathname === "/api/desktop/calendar" ||
      url.pathname === "/api/desktop/outlook/connect" ||
      url.pathname === "/api/desktop/markets" ||
      url.pathname === "/api/desktop/expenses/workbook" ||
      url.pathname === "/api/desktop/fitbit" ||
      url.pathname === "/api/desktop/fitbit/history" ||
      url.pathname === "/api/desktop/fitbit/connect"
    ) {
      const desktopEnv = env as Env & DesktopAuthEnv;
      let corsHeaders: Headers;
      try {
        corsHeaders = desktopCorsHeaders(
          request,
          desktopEnv.DESKTOP_ALLOWED_ORIGINS,
        );
      } catch (error) {
        const desktopError = error instanceof DesktopRequestError
          ? error
          : new DesktopRequestError(503, "desktop_api_not_configured", "Desktop API unavailable");
        return desktopJson(
          { error: desktopError.code, requestId },
          desktopError.status,
          requestId,
          new Headers(),
        );
      }

      if (request.method === "OPTIONS") {
        return new Response(null, { status: 204, headers: corsHeaders });
      }
      const isConnect = url.pathname === "/api/desktop/outlook/connect";
      const isMarkets = url.pathname === "/api/desktop/markets";
      const isExpenses = url.pathname === "/api/desktop/expenses/workbook";
      const isFitbitConnect = url.pathname === "/api/desktop/fitbit/connect";
      const isFitbit = url.pathname === "/api/desktop/fitbit";
      const methodAllowed = isFitbit
        ? request.method === "GET" || request.method === "POST"
        : request.method === (isConnect || isFitbitConnect || isExpenses ? "POST" : "GET");
      if (!methodAllowed) {
        return desktopJson(
          { error: "method_not_allowed", requestId },
          405,
          requestId,
          corsHeaders,
        );
      }

      try {
        await authorizeDesktopRequest(request, desktopEnv);
        if (isExpenses) {
          const body = await request.text();
          if (body.length > 8192) return desktopJson({ error: 'Link troppo lungo' }, 413, requestId, corsHeaders);
          let input: unknown;
          try { input = (JSON.parse(body) as { url?: unknown }).url; }
          catch { return desktopJson({ error: 'Link non valido' }, 400, requestId, corsHeaders); }
          try {
            const agent = env.PERSONAL_AGENT.getByName(AGENT_INSTANCE_NAME) as AgentGateway;
            const result = await agent.readExpenseWorkbook(validateExpenseLink(input));
            if (!result.bytes) return desktopJson({ error: result.error }, result.status ?? 503, requestId, corsHeaders);
            corsHeaders.set('content-type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
            corsHeaders.set('cache-control', 'no-store');
            corsHeaders.set('x-content-type-options', 'nosniff');
            return new Response(result.bytes, { headers: corsHeaders });
          } catch (error) {
            return desktopJson({ error: error instanceof ExpenseDownloadError ? error.message : 'Excel non disponibile' },
              error instanceof ExpenseDownloadError ? error.status : 503, requestId, corsHeaders);
          }
        }
        if (isMarkets) {
          const symbol = requireMarketSymbol(url.searchParams.get("symbol"));
          const period = requireMarketPeriod(url.searchParams.get("period"));
          const market = await fetchMarketSeries(symbol, period);
          if (period === "max") {
            console.info("Desktop market history loaded", { requestId, symbol, points: market.points.length });
          }
          return desktopJson(market, 200, requestId, corsHeaders);
        }
        const agent = env.PERSONAL_AGENT.getByName(
          AGENT_INSTANCE_NAME,
        ) as AgentGateway;
        if (url.pathname === "/api/desktop/fitbit/history") {
          return desktopJson(await agent.readFitbitHistory(), 200, requestId, corsHeaders);
        }
        if (isFitbitConnect) {
          const authorization = await agent.beginFitbitConnect();
          return desktopJson(
            { authorizationUrl: authorization.url },
            200,
            requestId,
            corsHeaders,
          );
        }
        if (isFitbit) {
          if (request.method === "POST") {
            const body = (await request.json()) as {
              date?: unknown;
              mindfulnessMinutes?: unknown;
            };
            const date = typeof body.date === "string" ? body.date : "";
            const minutes = body.mindfulnessMinutes;
            if (
              minutes !== null &&
              (typeof minutes !== "number" || !Number.isInteger(minutes))
            ) {
              return desktopJson(
                { error: "invalid_mindfulness_minutes", requestId },
                400,
                requestId,
                corsHeaders,
              );
            }
            const fitbit = await agent.setFitbitMindfulness(date, minutes as number | null);
            return desktopJson(fitbit, 200, requestId, corsHeaders);
          }
          const date = url.searchParams.get("date") ?? "";
          const fitbit = await agent.readFitbitDay(date);
          return desktopJson(fitbit, 200, requestId, corsHeaders);
        }
        if (isConnect) {
          const authorization = await agent.beginMicrosoftConnect(url.searchParams.get('files') === 'read');
          return desktopJson(
            { authorizationUrl: authorization.url },
            200,
            requestId,
            corsHeaders,
          );
        }
        const date = requireCalendarDate(url.searchParams.get("date") ?? "");
        const calendar = await agent.readCalendarDay(date);
        return desktopJson(calendar, 200, requestId, corsHeaders);
      } catch (error) {
        if (error instanceof DesktopRequestError) {
          return desktopJson(
            { error: error.code, requestId },
            error.status,
            requestId,
            corsHeaders,
          );
        }
        if (error instanceof MarketDataError) {
          if (isMarkets && url.searchParams.get("period") === "max") {
            console.warn("Desktop market history failed", {
              requestId,
              symbol: url.searchParams.get("symbol")?.slice(0, 24),
              status: error.status,
              code: error.code,
            });
          }
          return desktopJson(
            { error: error.code, requestId },
            error.status,
            requestId,
            corsHeaders,
          );
        }
        const message = error instanceof Error ? error.message : "";
        if (message === "Invalid calendar date") {
          return desktopJson(
            { error: "invalid_date", requestId },
            400,
            requestId,
            corsHeaders,
          );
        }
        if (message === "Invalid Fitbit date") {
          return desktopJson(
            { error: "invalid_date", requestId },
            400,
            requestId,
            corsHeaders,
          );
        }
        if (
          /Microsoft integration is not configured|Microsoft account is not connected|refresh token unavailable/iu.test(
            message,
          )
        ) {
          return desktopJson(
            { error: "outlook_not_connected", requestId },
            409,
            requestId,
            corsHeaders,
          );
        }
        if (isFitbit || isFitbitConnect) {
          const status = /status (\d{3})\b/u.exec(message)?.[1];
          const category = /token exchange failed/u.test(message)
            ? "token_refresh_or_exchange"
            : /not connected|OAuth state/u.test(message)
              ? "authentication"
              : /API request failed/u.test(message)
                ? "health_api"
                : /invalid token response|refresh token/u.test(message)
                  ? "token_response"
                  : "worker_or_network";
          console.error("Desktop Fitbit request failed", { requestId, category, status });
          return desktopJson(
            { error: `fitbit_${category}`, requestId },
            502,
            requestId,
            corsHeaders,
          );
        }
        console.error("Desktop calendar request failed", {
          requestId,
          message: message.slice(0, 300),
        });
        return desktopJson(
          { error: "calendar_unavailable", requestId },
          502,
          requestId,
          corsHeaders,
        );
      }
    }

    if (request.method === "GET" && url.pathname === "/health") {
      return json(
        { status: "ok", version: APP_VERSION, safeMode: SAFE_MODE },
        200,
        requestId,
      );
    }

    if (request.method === "GET" && url.pathname === "/health/markets") {
      try {
        const probe = await fetchMarketSeries("^GSPC", "1d");
        return json(
          {
            status: "ok",
            source: "live",
            symbol: probe.symbol,
            points: probe.points.length,
            updatedAt: probe.updatedAt,
          },
          200,
          requestId,
          { "cache-control": "no-store" },
        );
      } catch (error) {
        console.error("Market data health check failed", {
          requestId,
          message: error instanceof Error ? error.message.slice(0, 200) : "",
        });
        return json(
          { status: "unavailable", source: "live", requestId },
          503,
          requestId,
          { "cache-control": "no-store" },
        );
      }
    }

    if (request.method === "GET" && url.pathname === "/status") {
      getRuntimeConfig(env);
      const agent = env.PERSONAL_AGENT.getByName(
        AGENT_INSTANCE_NAME,
      ) as AgentGateway;
      const status = await agent.getStatus();
      return json(
        {
          status: status.mode,
          version: APP_VERSION,
          safeMode: status.safeMode,
          aiConnected: status.aiConnected,
          outlook: status.outlook,
          importantEmailMonitor: status.importantEmailMonitor,
          followUps: status.followUps,
        },
        200,
        requestId,
      );
    }

    if (request.method === "POST" && url.pathname === "/telegram/webhook") {
      return handleTelegramWebhook(request, env, ctx, requestId);
    }

    if (
      request.method === "GET" &&
      url.pathname === "/oauth/microsoft/callback"
    ) {
      const error = url.searchParams.get("error");
      if (error) {
        return new Response(
          "Collegamento Microsoft annullato o rifiutato. Puoi chiudere questa pagina.",
          { status: 400, headers: { "content-type": "text/plain; charset=utf-8" } },
        );
      }
      const code = url.searchParams.get("code") ?? "";
      const state = url.searchParams.get("state") ?? "";
      if (!code || !state || code.length > 4_096 || state.length > 512) {
        return new Response("Richiesta Microsoft non valida.", { status: 400 });
      }

      try {
        const agent = env.PERSONAL_AGENT.getByName(
          AGENT_INSTANCE_NAME,
        ) as AgentGateway;
        const result = await agent.completeMicrosoftConnect(code, state);
        const account = result.accountLabel ? ` (${result.accountLabel})` : "";
        return new Response(
          `Outlook collegato correttamente${account}. Puoi chiudere questa pagina e tornare alla dashboard.`,
          { status: 200, headers: { "content-type": "text/plain; charset=utf-8" } },
        );
      } catch {
        return new Response(
          "Collegamento Microsoft non riuscito o scaduto. Torna alla dashboard e premi di nuovo Collega Outlook.",
          { status: 400, headers: { "content-type": "text/plain; charset=utf-8" } },
        );
      }
    }

    if (request.method === "GET" && url.pathname === "/oauth/fitbit/callback") {
      const error = url.searchParams.get("error");
      if (error) {
        return new Response(
          "Collegamento Fitbit annullato o rifiutato. Puoi chiudere questa pagina.",
          { status: 400, headers: { "content-type": "text/plain; charset=utf-8" } },
        );
      }
      const code = url.searchParams.get("code") ?? "";
      const state = url.searchParams.get("state") ?? "";
      if (!code || !state || code.length > 4_096 || state.length > 512) {
        return new Response("Richiesta Fitbit non valida.", { status: 400 });
      }
      try {
        const agent = env.PERSONAL_AGENT.getByName(
          AGENT_INSTANCE_NAME,
        ) as AgentGateway;
        const result = await agent.completeFitbitConnect(code, state);
        const device = result.deviceName ? ` (${result.deviceName})` : "";
        return new Response(
          `Fitbit collegato correttamente${device}. I dati vengono aggiornati ogni 15 minuti. Puoi chiudere questa pagina.`,
          { status: 200, headers: { "content-type": "text/plain; charset=utf-8" } },
        );
      } catch (error) {
        console.error("Fitbit OAuth callback failed", {
          requestId,
          message: error instanceof Error ? error.message.slice(0, 300) : "unknown",
        });
        return new Response(
          "Collegamento Fitbit non riuscito o scaduto. Torna alla dashboard e riprova.",
          {
            status: 400,
            headers: {
              "content-type": "text/plain; charset=utf-8",
              "x-request-id": requestId,
            },
          },
        );
      }
    }

    return json({ error: "Not found", requestId }, 404, requestId);
  },
} satisfies ExportedHandler<Env>;
