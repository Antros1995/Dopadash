# Sincronizzazione delle sessioni lunghe

La correzione interessa sessione, rete e controller. Il layout e i componenti
dell’interfaccia rimangono quelli esistenti.

Le richieste manuali al Personal Agent usano `auth.getSession()` prima di inviare
il token, come le query del client Supabase. Se il server risponde 401, viene
tentato un solo rinnovo con ripetizione della richiesta; il tentativo viene
interrotto se cambia l’account o l’utente esce. Il rinnovo simultaneo viene
condiviso dal client Supabase. Le risposte 403 non vengono ripetute.

`AppSyncCoordinator` controlla la sessione prima di aggiornare i dati: al ritorno
in primo piano, al focus della finestra, al ripristino della rete e ogni minuto
mentre l’app è attiva. Gli eventi ravvicinati vengono accorpati. Un controllo
fallito viene riprovato dopo 10 secondi senza ricaricare la pagina.

Routine, attività, calendario e salute vengono aggiornati; Spese, Borsa e
Statistiche vengono aggiornate quando sono aperte. Restano attivi i controlli
esistenti ogni 20 secondi per Spese e ogni 30 secondi per routine e attività.
Lo storico Fitbit di Statistiche viene riallineato al massimo ogni 5 minuti,
mentre le letture dei dati già presenti sul server seguono il controllo centrale.

Le richieste Supabase hanno un limite sia per le intestazioni sia per il corpo
della risposta. I controller sbloccano le operazioni scadute, ignorano risposte
obsolete e notifiche dopo la chiusura. Le routine conservano le scritture fallite
in memoria e le riprovano prima di leggere il server: un aggiornamento remoto
non sostituisce una modifica locale ancora da salvare. Le scritture accodate
superate da un’ulteriore modifica della stessa giornata vengono saltate.

Gli errori temporanei del flusso auth sono gestiti senza cancellare la sessione
salvata. Una sessione revocata o non recuperabile resta soggetta al normale logout
del client Supabase. La chiusura della scheda conserva il comportamento esistente
delle cache: questa modifica non aggiunge persistenza offline alle routine.

I browser possono sospendere timer e rete delle schede in background. Il recupero
avviene automaticamente al ritorno alla finestra; la sincronizzazione con Fitbit
dipende anche dai dati già arrivati al servizio del dispositivo.

I test simulano ore in background, perdita e ritorno della connessione, rinnovi
concorrenti, token rifiutati, richieste bloccate, scritture non salvate e risposte
tardive. Nessuna modifica a schema SQL, impostazioni Supabase o backend distribuito.
La correzione va attivata pubblicando una nuova build web del frontend.

Verifica finale: 80 test distinti superati, fra recupero della sessione,
controller, repository, Statistiche e impaginazione mobile/desktop; analisi
statica mirata senza segnalazioni. La prova delle ore in background usa un
orologio simulato; non sostituisce una sessione reale di più ore su Safari/PC.
