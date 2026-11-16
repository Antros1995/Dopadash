# Layout iPhone e anteprima locale

La navigazione compatta si attiva sotto 700 px; sui telefoni iOS/Android resta
attiva anche in orizzontale fino a 1000 px, se il lato corto è inferiore a 600 px.
La sidebar fissa viene sostituita da una barra inferiore e da un menu con sezioni,
pagine, sincronizzazione e impostazioni. La tastiera nasconde la barra inferiore.
Le aree sicure del dispositivo vengono rispettate.

Sul telefono ModularBoard impagina i moduli in verticale senza cambiare o salvare
le coordinate desktop. Le card con contenuto vincolato hanno un’altezza mobile
dedicata, adattata anche al testo ingrandito. Statistiche usa filtri compatti,
metriche su due colonne, grafici con meno etichette e lettura dei valori al tocco.
Spese presenta le transazioni in schede; To Do, Borsa e Investimenti dispongono
titoli e azioni su più righe. I rami desktop conservano la presentazione esistente.

## Avvio sulla rete Wi-Fi

Eseguire dalla radice del repository, usando Flutter e Node disponibili localmente:

```powershell
flutter build web --release --no-pub --no-wasm-dry-run --dart-define-from-file=config/dart_defines.local.json --dart-define=LOCAL_API_PROXY=true --output=build/web-responsive
node tool/serve-local.mjs build/web-responsive 7359 0.0.0.0 192.168.1.50
```

PC: `http://localhost:7359`. iPhone sulla stessa Wi-Fi: `http://192.168.1.50:7359`.
Il PC e il server devono rimanere accesi. Sostituire l’IP con quello attuale del PC
se la rete lo cambia.

Il flag LOCAL_API_PROXY riguarda soltanto questa anteprima HTTP locale. Le chiamate
al Personal Agent passano attraverso il server locale per evitare il blocco CORS
dell’origine Wi-Fi; l’autenticazione Supabase e il controllo dell’utente sul backend
restano attivi. Sono accettati solo percorsi prestabiliti, richieste autenticate e
origini locali esplicitamente elencate. Le build normali non usano questo proxy.

## Verifica

I widget test coprono 375, 390 e 430 px in verticale, 844 px in orizzontale,
notch e indicatore Home, testo al 130%, tastiera, navigazione delle pagine,
filtri e grafici al tocco, e ritorno al desktop con coordinate salvate intatte.
Le viste e i form di Statistiche sono controllati anche a 328, 1024 e 1586 px.
Spese viene controllato anche a 320 px; il filtro categorie gestisce le righe
Excel senza descrizione senza duplicare l’opzione «Tutte le categorie».
Verifica finale: 46 test mirati superati, analisi statica dei file interessati
senza errori, build web release e risposte HTTP su localhost e indirizzo Wi-Fi.
Non è stata eseguita una prova fisica con Safari su iPhone.
