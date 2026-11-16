-- Organizzatore: una riga per utente con tutti i progetti e i fogli.
-- L'app confronta il campo data->>'savedAt' e tiene la copia salvata per ultima.
-- Si può eseguire più volte senza danni.
begin;
create table if not exists public.monitoraggio_personale_organizer (
  user_id uuid primary key references auth.users(id) on delete cascade,
  data jsonb not null default '{}'::jsonb
    check (jsonb_typeof(data) = 'object' and pg_column_size(data) <= 8000000),
  updated_at timestamptz not null default now()
);
alter table public.monitoraggio_personale_organizer enable row level security;
drop policy if exists "Own organizer" on public.monitoraggio_personale_organizer;
create policy "Own organizer" on public.monitoraggio_personale_organizer
  for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
revoke all on public.monitoraggio_personale_organizer from anon;
grant select, insert, update, delete on public.monitoraggio_personale_organizer to authenticated;
-- Stessa protezione a due fattori delle altre tabelle (20261019_mfa_security.sql).
do $$ begin
  if to_regprocedure('monitoraggio_private.mfa_access_allowed()') is null then
    raise notice 'MFA: funzioni assenti; tabella protetta dalla sola RLS di proprietà.';
  else
    execute 'drop policy if exists monitoraggio_mfa_access on public.monitoraggio_personale_organizer';
    execute 'create policy monitoraggio_mfa_access on public.monitoraggio_personale_organizer as restrictive for all to authenticated using ((select monitoraggio_private.mfa_access_allowed())) with check ((select monitoraggio_private.mfa_access_allowed()))';
    execute 'drop trigger if exists monitoraggio_mfa_write on public.monitoraggio_personale_organizer';
    execute 'create trigger monitoraggio_mfa_write before insert or update or delete on public.monitoraggio_personale_organizer for each row execute function monitoraggio_private.enforce_mfa_write()';
  end if;
end; $$;
do $$ begin
  if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime'
    and schemaname='public' and tablename='monitoraggio_personale_organizer') then
    alter publication supabase_realtime add table public.monitoraggio_personale_organizer;
  end if;
end; $$;
notify pgrst, 'reload schema';
commit;
