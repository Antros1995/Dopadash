-- Vestiti: gli outfit dell'utente e le loro foto.
-- Una riga per outfit; le foto stanno nell'archivio privato "outfit-photos",
-- in cartelle intestate all'utente. Si può eseguire più volte senza danni.
begin;

create table if not exists public.monitoraggio_personale_outfits (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null default '' check (char_length(name) <= 120),
  seasons text[] not null default '{}'::text[],
  styles text[] not null default '{}'::text[],
  -- [{ "slot": "top" | "bottom" | "shoes", "path": "<user_id>/<outfit>/<file>.jpg" }]
  pieces jsonb not null default '[]'::jsonb check (jsonb_typeof(pieces) = 'array'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists monitoraggio_personale_outfits_user_idx
  on public.monitoraggio_personale_outfits (user_id, created_at desc);

alter table public.monitoraggio_personale_outfits enable row level security;
drop policy if exists "Own outfits" on public.monitoraggio_personale_outfits;
create policy "Own outfits" on public.monitoraggio_personale_outfits
  for all to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
revoke all on public.monitoraggio_personale_outfits from anon;
grant select, insert, update, delete on public.monitoraggio_personale_outfits to authenticated;

-- Stessa protezione a due fattori delle altre tabelle.
do $$ begin
  if to_regprocedure('monitoraggio_private.mfa_access_allowed()') is not null then
    execute 'drop policy if exists monitoraggio_mfa_access on public.monitoraggio_personale_outfits';
    execute 'create policy monitoraggio_mfa_access on public.monitoraggio_personale_outfits as restrictive for all to authenticated using ((select monitoraggio_private.mfa_access_allowed())) with check ((select monitoraggio_private.mfa_access_allowed()))';
    execute 'drop trigger if exists monitoraggio_mfa_write on public.monitoraggio_personale_outfits';
    execute 'create trigger monitoraggio_mfa_write before insert or update or delete on public.monitoraggio_personale_outfits for each row execute function monitoraggio_private.enforce_mfa_write()';
  end if;
end; $$;

-- Archivio privato delle foto: solo immagini, al massimo 10 MB l'una.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('outfit-photos', 'outfit-photos', false, 10485760, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "outfit_photos_select_own" on storage.objects;
create policy "outfit_photos_select_own" on storage.objects
  for select to authenticated
  using (bucket_id = 'outfit-photos' and (storage.foldername(name))[1] = (select auth.uid())::text);
drop policy if exists "outfit_photos_insert_own" on storage.objects;
create policy "outfit_photos_insert_own" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'outfit-photos' and (storage.foldername(name))[1] = (select auth.uid())::text);
drop policy if exists "outfit_photos_delete_own" on storage.objects;
create policy "outfit_photos_delete_own" on storage.objects
  for delete to authenticated
  using (bucket_id = 'outfit-photos' and (storage.foldername(name))[1] = (select auth.uid())::text);

-- Aggiornamento in tempo reale tra computer e telefono.
do $$ begin
  if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime'
    and schemaname='public' and tablename='monitoraggio_personale_outfits') then
    alter publication supabase_realtime add table public.monitoraggio_personale_outfits;
  end if;
end; $$;

notify pgrst, 'reload schema';
commit;
