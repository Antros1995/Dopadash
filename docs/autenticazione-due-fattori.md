# Autenticazione in due passaggi

La web app usa la MFA TOTP nativa di Supabase: email/password, poi un codice
temporaneo generato da un'app Authenticator. L'account resta utilizzabile senza
MFA finché il proprietario non completa l'attivazione con un codice valido.

## Pubblicazione

Le modifiche sono preparate nel progetto locale. Per attivare la protezione sul
sito pubblico servono **database, Worker e frontend aggiornati**.

1. Nel progetto Supabase verificare in Authentication → MFA che Authenticator
   TOTP sia abilitato. Non servono SMS o servizi a pagamento per i codici TOTP.
2. Eseguire nel SQL Editor, come amministratore, il file
   `supabase/migrations/20261019_mfa_security.sql`, dopo le migrazioni dei dati
   già usate dall'app. Non elimina dati o tabelle. `DROP POLICY` e `DROP TRIGGER`
   sostituiscono soltanto le regole MFA omonime, rendendo il file ripetibile.
   Se una tabella esistente non ha già RLS, l'intera migrazione si interrompe:
   configurare prima le sue regole di appartenenza, senza aggirare il controllo.
   Le tabelle assenti vengono segnalate con NOTICE; ripetere questa migrazione
   dopo averle create. Lo schema `monitoraggio_private` deve restare fuori
   dagli schemi esposti dalla Data API.
3. Da PowerShell, nella cartella del progetto, compilare e pubblicare:

```powershell
$env:NODE_USE_SYSTEM_CA = "1"

flutter build web --release --no-pub --no-wasm-dry-run --dart-define-from-file=config/dart_defines.production.json --dart-define=LOCAL_API_PROXY=false

Push-Location backend/personal_agent
& .\node_modules\.bin\wrangler.cmd deploy
Pop-Location

& .\backend\personal_agent\node_modules\.bin\wrangler.cmd pages deploy .\build\web --project-name monitoraggio-personale-desktop --branch main
```

Pubblicare il Worker dalla cartella indicata mantiene il progetto Cloudflare
già configurato. I segreti remoti esistenti non vanno copiati nel frontend.
Non attivare il fattore prima di aver completato tutti e tre gli aggiornamenti.

## Attivazione e utilizzo

Aprire il sito aggiornato e accedere normalmente. In **Impostazioni → Sicurezza
e 2FA**, scegliere un nome e premere **Attiva verifica in due passaggi**.
Scansionare il QR con l'Authenticator. Se si usa lo stesso iPhone, premere
**Mostra chiave manuale** e aggiungere nell'Authenticator un account TOTP usando
quella chiave. Inserire il codice di sei cifre e confermare.

Il QR viene disegnato localmente: la chiave non è inviata a servizi QR esterni,
salvata nelle preferenze o scritta nei log. Dopo la conferma viene rimossa dallo
stato della schermata. Chiudere una configurazione incompleta prova a eliminare
solo il fattore appena creato, verificando che sia ancora non confermato. Le
configurazioni rimaste incomplete si possono eliminare dalle impostazioni.

Ai successivi login l'app richiede il codice prima di caricare la dashboard.
Una sessione già verificata mantiene il livello `aal2` durante il normale
rinnovo: non viene richiesto un codice ogni minuto. Il recupero password via
email passa dallo stesso controllo MFA. Quando si abilita un nuovo fattore,
Supabase può richiedere un nuovo accesso sugli altri dispositivi.
Il token verificato viene passato subito anche ai canali Realtime già aperti,
senza attendere il successivo rinnovo automatico della sessione.

Collegare un secondo Authenticator come riserva. Per rimuovere un fattore serve
un nuovo codice da uno degli Authenticator collegati: quello di riserva permette
anche di rimuovere un dispositivo perso. Rimuovere l'ultimo disattiva la MFA.
Se si perdono tutti gli Authenticator, occorre recuperare l'account attraverso
l'amministratore del progetto Supabase, che può rimuovere il fattore dopo aver
verificato l'identità. Il solo link email non aggira la MFA. Questa integrazione
non inventa codici di recupero alternativi a quelli gestiti da Supabase.

## Protezioni server

- Il Worker convalida il bearer token presso Supabase, controlla il proprietario
  autorizzato e, in presenza di un fattore verificato, richiede `aal2` nello
  stesso token. Un token non verificato restituisce `403 mfa_required`.
- Il database aggiunge policy **restrittive**, oltre a quelle di appartenenza
  esistenti. Per l'utente con MFA attiva, le sessioni `aal1` non leggono o
  modificano le tabelle dell'app. I trigger proteggono anche le scritture delle
  RPC esistenti eseguite con `SECURITY DEFINER`.
- Il controllo usa i fattori verificati attuali in `auth.mfa_factors`, senza
  fidarsi soltanto di una vecchia lista presente nel token. Gli account che non
  hanno attivato MFA mantengono l'accesso normale. La service role resta riservata
  alle integrazioni fidate lato server; le API desktop verificano la MFA prima
  di richiamarle.

**Account condiviso con 1 Abitudini:** Supabase MFA appartiene all'account,
non al solo sito. Le tabelle routine (`habits`, `habit_logs`, `habit_log_values`,
`daily_screen_times`) sono condivise: dopo l'attivazione, anche un'altra app che
accede a quelle tabelle con lo stesso account deve completare MFA. Aggiornare
prima anche il suo login se si vuole continuare a usarla con quell'account.

L'utente ha confermato di usare entrambe le app. Il documento da trasferire al
progetto mobile è [HANDOFF_2FA_APP_MOBILE.md](HANDOFF_2FA_APP_MOBILE.md).
L'attivazione del fattore reale prosegue dopo l'aggiornamento dell'app mobile.

Le nuove tabelle e nuove API aggiunte in futuro devono applicare lo stesso
controllo. Eventuali nuove RPC `SECURITY DEFINER` che leggono dati devono
verificare la MFA esplicitamente, poiché possono ignorare RLS.

## Verifiche riproducibili

```powershell
flutter test test/features/auth test/core/sync/authorized_agent_request_test.dart
flutter analyze lib/features/auth lib/features/shell/presentation/home_shell.dart test/features/auth
node tool/test-mfa-schema.mjs

Push-Location backend/personal_agent
& .\node_modules\.bin\vitest.cmd run test/desktop-auth.test.ts
& .\node_modules\.bin\tsc.cmd --noEmit
Pop-Location
```

I test database usano PostgreSQL/WASM locale, senza connessioni al progetto
reale. Il runtime PGlite si installa con
`npm install --prefix .tools/statistics-db-test @electric-sql/pglite`.
I test UI coprono desktop, iPhone, schermi da 320 px, testo ingrandito e tastiera.
La conferma finale con un Authenticator reale si esegue personalmente dopo la
pubblicazione, senza condividere chiave e codici in chat.

Riferimenti: [Supabase MFA](https://supabase.com/docs/guides/auth/auth-mfa),
[Authenticator TOTP](https://supabase.com/docs/guides/auth/auth-mfa/totp).
