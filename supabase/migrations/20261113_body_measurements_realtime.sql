-- Facoltativo: fa arrivare in tempo reale anche le misure del corpo (peso,
-- vita, ecc.) tra app per iPhone e app nuova. Abitudini, cellulare, emozioni,
-- concentrazione e movimento sono già in tempo reale.
-- Senza questo file le misure si aggiornano comunque riaprendo la scheda.
-- Si può eseguire più volte senza danni.
do $$ begin
  if to_regclass('public.body_measurements') is null then
    raise notice 'Tabella body_measurements assente: niente da fare.';
    return;
  end if;
  alter table public.body_measurements replica identity full;
  if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime'
    and schemaname='public' and tablename='body_measurements') then
    alter publication supabase_realtime add table public.body_measurements;
  end if;
end; $$;
