# Statistiche del corpo ed esperimenti

La scheda **Statistiche** si apre dalla navigazione principale o dalla home. La
sua barra laterale contiene Panoramica, Sonno, Cuore e recupero, Attività ed
Esperimenti. Le immagini allegate guidano colori, header alpino, card, grafici e
gerarchia; i valori visualizzati provengono esclusivamente dai dati salvati.

## Attivazione

1. Applicare `supabase/migrations/20261017_body_statistics.sql` al progetto
   Supabase già usato dall’app. La migrazione è incrementale, non modifica le
   tabelle preesistenti e può essere rieseguita.
2. Pubblicare il Worker aggiornato in `backend/personal_agent`. La scrittura
   automatica riutilizza `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` e
   `DESKTOP_SUPABASE_USER_ID`, già usati dai task condivisi. La chiave privilegiata
   rimane esclusivamente nel Worker. L’endpoint desktop mantiene autenticazione
   Supabase e whitelist del proprietario esistenti.
3. Aprire Statistiche e sincronizzare. Lo storico datato già raccolto dal Worker
   viene importato in Supabase; il giorno corrente viene aggiornato. Il pulsante
   di recupero richiede sequenzialmente al backend le date mancanti dei periodi
   selezionati (oppure prima/durante per l’esperimento). Può essere interrotto
   conservando i giorni già salvati. L’effettiva disponibilità retroattiva dipende
   da Google Health e dall’integrazione esistente; le date senza misurazioni non
   vengono riempite. “Tutto” comprende lo storico salvato, non una data di inizio
   Fitbit inventata.

Senza schema la pagina presenta un errore con il nome della migrazione. Non usa
local storage come sostituto della persistenza. Nessuna migrazione o pubblicazione
remota è stata eseguita durante l’implementazione: non era disponibile un canale
SQL amministrativo configurato per il progetto.

Il popup “Potential issues detected” del SQL Editor è un avviso preventivo,
non un errore di esecuzione. La migrazione abilita esplicitamente la RLS subito
dopo la creazione di ciascuna tabella. Nella versione iniziale lo faceva tramite
SQL dinamico, che il controllo preventivo potrebbe non riconoscere. Incollare il
file aggiornato completo; se il popup propone l’opzione, scegliere **Run and
enable RLS**. Gli statement `DROP` rimuovono e ricreano soltanto i trigger e le
policy di questa migrazione; lo script non contiene `DROP TABLE`, `TRUNCATE` o
`DELETE FROM`. Un eventuale messaggio con codice `ERROR` nei risultati della
query è invece un errore effettivo e va esaminato separatamente.

## Dati e calcoli

- Tabelle `statistics_fitbit_days`, `statistics_experiments`,
  `statistics_experiment_logs` e `statistics_preferences`, tutte con RLS su
  `auth.uid() = user_id`. Le relazioni fra esperimenti, ripetizioni e diario
  includono il proprietario: un riferimento non può attraversare utenti.
- Uno snapshot per utente/data/fonte, importazioni con upsert, protezione SQL
  contro sovrascritture da snapshot più vecchi. Il payload mantiene campioni,
  orari UTC e campi Fitbit; le colonne specificano fonte, unità, granularità,
  sincronizzazione e fuso Europe/Rome.
- Giorni civili rappresentati come etichette UTC per evitare finestre di 23/25
  ore al cambio dell’ora. Orari del sonno convertiti in Europe/Rome; attribuzione
  delle notti al giorno di risveglio fornito dal backend.
- Finestre di 1, 7, 30, 90 e 365 giorni, tutto lo storico, intervalli personalizzati;
  confronto precedente della stessa durata o personalizzato. Nei confronti di
  durata diversa sono esposti i giorni e le coperture; usare le medie per
  interpretarli. La vista 24 ore espone riepiloghi giornalieri e dati notturni;
  l’andamento cardiaco usa esclusivamente i campioni intraday realmente salvati,
  in fasce di 30 minuti, mantenendo vuote quelle senza dati. Per periodi di più
  giorni, il grafico “Frequenza cardiaca” mostra le **medie giornaliere** su tutto
  l’intervallo. Il selettore “Giornata media” mostra invece il profilo orario
  medio del periodo: ogni data contribuisce una volta per fascia di 30 minuti,
  con conteggio dei giorni effettivamente disponibili nel dettaglio di ogni
  punto. Il riferimento segue lo stesso tipo di aggregazione; la media mobile
  a 7 giorni è applicata solo all’andamento delle medie giornaliere. La media del
  periodo attribuisce uguale peso a ogni giornata con campioni, senza privilegiare
  quelle più registrate. La FC media resta distinta dalla FC a riposo. Nel giorno
  di cambio dell’ora, la vista 24 ore mantiene i 46/50 intervalli effettivi e
  distingue gli orari ripetuti; il profilo medio prima media gli orari ripetuti
  all’interno della stessa data. Non vengono ricostruiti intervalli mancanti.
- Medie sui soli valori validi, totali etichettati, copertura, numerosità,
  deviazione standard campionaria negli esperimenti; settimane parziali marcate.
  La media mobile usa fino a 7 giorni civili e conserva vuoti i giorni mancanti.
  Non si usano le vecchie liste di trend prive di date come se fossero uno storico.
- I nuovi snapshot distinguono disponibilità e zero nelle metriche di attività.
  Negli snapshot precedenti uno zero privo di provenienza è ambiguo e viene
  escluso dalle statistiche. La sincronizzazione backend aggiunge la provenienza
  ai nuovi campioni; quelli storici non vengono reinterpretati arbitrariamente.
- Le fasi mancanti non vengono stimate: una notte con sola durata è visibile in
  “Durata”. Le barre settimanali del sonno sono medie per notte, quelle di attività
  sono totali sui giorni disponibili.

## Esperimenti

Creazione con nome, descrizione, domanda, attività, durata, giorni della
settimana, orario facoltativo, periodi modificabili, metriche e note. Sono
disponibili bozza, avvio, modifica, conclusione, archiviazione/ripristino e
ripetizione collegata al test originale senza copiarne le sessioni.

Il diario registra una giornata alla volta: completata, parziale, saltata o non
registrata; durata, orario, calma/stress 0–10, note e sei fattori di contesto.
Anche nei giorni del riferimento si possono annotare contesto e valutazioni.
I campi di contesto distinguono sì, no e sconosciuto; una riga assente non è una
sessione saltata. Una registrazione può essere modificata o eliminata.

Il confronto usa i periodi propri dell’esperimento, visualizzati esplicitamente,
e non i filtri temporali delle altre viste. Le esclusioni per fattore sono
esplicite, reversibili e salvate con le preferenze; viene mostrato il numero di
giorni esclusi. Gli esperimenti in corso espongono i giorni trascorsi e il
carattere provvisorio del confronto. Con meno di due osservazioni valide per
periodo non viene formulata un’osservazione comparativa. Le differenze non sono
classificate automaticamente come miglioramenti; nessuna conclusione clinica,
causale o significatività statistica viene generata.

I risultati sono calcolati dai dati correnti, senza cache di aggregati. La scheda
attiva rilegge Supabase ogni 5 minuti. Il JSON esportato contiene dati datati,
registrazioni manuali, configurazione del confronto, unità, coperture ed esclusioni.

## Verifica senza browser

```powershell
dart analyze lib/features/statistics lib/features/fitbit/data/fitbit_repository.dart lib/features/shell/presentation/home_shell.dart lib/features/shell/presentation/dashboard_frame.dart test/features/statistics
flutter test --no-pub
flutter build web --release --dart-define-from-file=config/dart_defines.local.json
```

I test Flutter verificano calcoli, dati mancanti, DST, preferenze, concorrenza fra
selezioni e layout a 328, 390, 1024 e 1586 px, inclusi moduli e stati vuoti. I
test di repository usano un trasporto HTTP controllato. I test backend verificano
la scrittura degli snapshot e gli errori, senza credenziali reali.

Per verificare la migrazione in un PostgreSQL locale WASM isolato:

```powershell
npm install --prefix .tools/statistics-db-test @electric-sql/pglite
node tool/test-statistics-schema.mjs
```

Questo controllo esegue realmente lo SQL, RLS inclusa, con utenti di test: verifica
riesecuzione, deduplicazione, importazioni obsolete, isolamento e vincoli. Non
equivale a una verifica sul progetto Supabase remoto. Non è stato aperto alcun
browser e non viene dichiarata una verifica visiva dell’interfaccia.

La build Web release è riuscita. L’analisi mirata non rileva problemi e i 30 test
di Statistiche e Fitbit sono passati, incluso il salvataggio tramite moduli.
I test backend mirati passano (8); la suite completa esegue 99 test con successo,
ma il runner Vitest segnala come suite non riconosciuta il file Spese
`expenses-download.test.mjs`, scritto per `node:test`.
La suite Flutter generale ha inoltre segnalato cinque
fallimenti fuori da questa funzionalità: quattro verifiche della home cercano il
testo “Sonno” che non compare nella composizione corrente; un test Spese non
trova il selettore del filtro atteso. L’analisi generale segnala anche lint e un
import inutilizzato in file estranei alla sezione. Questi risultati non sono
presentati come una suite generale pulita.
