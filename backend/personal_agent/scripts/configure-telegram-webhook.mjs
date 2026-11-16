import { readFile } from "node:fs/promises";

function parseDevVars(content) {
  return Object.fromEntries(
    content
      .split(/\r?\n/)
      .map((line) => line.trim())
      .filter((line) => line.length > 0 && !line.startsWith("#"))
      .map((line) => {
        const separator = line.indexOf("=");
        const key = line.slice(0, separator).trim();
        const value = line
          .slice(separator + 1)
          .trim()
          .replace(/^['"]|['"]$/g, "");
        return [key, value];
      }),
  );
}

const workerUrl = process.argv[2]?.replace(/\/$/, "");
if (!workerUrl?.startsWith("https://")) {
  throw new Error(
    "Uso: npm run telegram:webhook -- https://<worker>.workers.dev",
  );
}

const vars = parseDevVars(await readFile(".dev.vars", "utf8"));
const token = vars.TELEGRAM_BOT_TOKEN;
const secret = vars.TELEGRAM_WEBHOOK_SECRET;
if (!token || !secret) {
  throw new Error(
    "TELEGRAM_BOT_TOKEN e TELEGRAM_WEBHOOK_SECRET devono essere presenti in .dev.vars",
  );
}

const response = await fetch(`https://api.telegram.org/bot${token}/setWebhook`, {
  method: "POST",
  headers: { "content-type": "application/json" },
  body: JSON.stringify({
    url: `${workerUrl}/telegram/webhook`,
    secret_token: secret,
    allowed_updates: ["message", "callback_query"],
    max_connections: 1,
    drop_pending_updates: true,
  }),
});

const result = await response.json();
if (!response.ok || !result.ok) {
  throw new Error(`Telegram setWebhook fallita (HTTP ${response.status})`);
}

console.log("Webhook Telegram configurato correttamente.");
