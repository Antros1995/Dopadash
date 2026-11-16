# Personal Agent — backend opzionale (Cloudflare Worker)

Questo Worker è **facoltativo**: l'app funziona anche senza. Serve solo se vuoi:

- un assistente su **Telegram** che crea attività e promemoria;
- leggere il calendario **Outlook** nella dashboard;
- collegare **Fitbit** (tramite Google Health API) per sonno, passi e battito.

Il browser non riceve mai i token di Outlook o Fitbit: restano cifrati nel
Durable Object del Worker. Il Worker verifica la sessione Supabase e accetta
solo l'utente indicato in `DESKTOP_SUPABASE_USER_ID`.

```text
GET /api/desktop/calendar?date=YYYY-MM-DD
Authorization: Bearer <sessione Supabase>
```

## Prerequisiti

- Node.js 22 o successivo;
- un account Cloudflare (il piano gratuito basta per iniziare);
- un progetto Supabase con le migrazioni di `../../supabase/migrations`;
- l'UUID del tuo utente in Supabase > Authentication > Users.

## Verifica locale

Dalla cartella `backend/personal_agent`:

```powershell
npm ci
npm run typecheck
npm test
Copy-Item .dev.vars.example .dev.vars
npx wrangler dev
```

Compila `.dev.vars` solo sul tuo computer: è escluso da git e non va mai
condiviso. Per la dashboard locale, `DESKTOP_ALLOWED_ORIGINS` deve contenere
`http://localhost:7358`.

## Pubblicazione su Cloudflare

I segreti si inseriscono in modo interattivo, mai dentro i comandi o nei file:

```powershell
npx wrangler login
npx wrangler secret put SUPABASE_URL
npx wrangler secret put SUPABASE_PUBLISHABLE_KEY
npx wrangler secret put SUPABASE_SERVICE_ROLE_KEY
npx wrangler secret put DESKTOP_SUPABASE_USER_ID
npx wrangler secret put DESKTOP_ALLOWED_ORIGINS
npm run check
npm run deploy
```

Usa l'UUID Supabase, non l'email, per `DESKTOP_SUPABASE_USER_ID`. In
`DESKTOP_ALLOWED_ORIGINS` inserisci origini esatte separate da virgola, per
esempio `http://localhost:7358,https://la-tua-app.pages.dev`.

La chiave `SUPABASE_SERVICE_ROLE_KEY` resta solo nel Worker: non va mai messa
nell'app Flutter.

## Telegram (facoltativo)

1. Crea un bot con [@BotFather](https://t.me/BotFather) e copia il token.
2. Scrivi `/start` al bot, poi esegui `scripts/get-telegram-ids.ps1` per
   leggere il tuo `user_id` e `chat_id`.
3. Salva i segreti `OPENAI_API_KEY`, `TELEGRAM_BOT_TOKEN`,
   `TELEGRAM_WEBHOOK_SECRET`, `TELEGRAM_ALLOWED_USER_ID` e
   `TELEGRAM_ALLOWED_CHAT_ID` con `npx wrangler secret put`.
4. Dopo il deploy: `npm run telegram:webhook -- https://<tuo-worker>.workers.dev`.

Esempi di messaggi:

- `Ricordami domani alle 9 di andare dal medico` → proposta di evento Outlook.
- `Crea un task domani: chiamare il medico` → attività personale condivisa.
- `Crea un'attività lavoro ...` → lista lavoro.
- `Quali task ho oggi?` → lettura delle liste attività.

Ogni scrittura chiede prima l'approvazione su Telegram.

## Outlook (facoltativo)

Registra un'app in Microsoft Entra ID con redirect
`https://<tuo-worker>.workers.dev/oauth/microsoft/callback`, poi salva
`MICROSOFT_CLIENT_ID`, `MICROSOFT_CLIENT_SECRET`, `MICROSOFT_REDIRECT_URI` e
`MICROSOFT_TOKEN_ENCRYPTION_KEY` (32 byte casuali in base64) come segreti.
Collega l'account dal bot con `/outlook_connect`.

## Fitbit (facoltativo)

Il Durable Object aggiorna il giorno corrente ogni 15 minuti; al cambio data
legge un'ultima volta il giorno precedente e lo segna come definitivo.

1. Crea un progetto Google Cloud, abilita la **Google Health API** e crea un
   client OAuth 2.0 di tipo Web con redirect
   `https://<tuo-worker>.workers.dev/oauth/fitbit/callback`.
2. Configura il consenso OAuth, aggiungi il tuo account come utente di test e
   abilita gli scope Google Health in sola lettura.
3. Salva `GOOGLE_HEALTH_CLIENT_ID`, `GOOGLE_HEALTH_CLIENT_SECRET`,
   `GOOGLE_HEALTH_REDIRECT_URI` e `GOOGLE_HEALTH_TOKEN_ENCRYPTION_KEY` come
   segreti, poi `npm run deploy`.
4. Apri la dashboard, premi **Collega Fitbit** e autorizza attività,
   frequenza cardiaca, sonno e profilo.

Il braccialetto non comunica direttamente con la dashboard: si sincronizza con
l'app Fitbit sul telefono e il Worker legge i dati arrivati alla Google Health
API.
