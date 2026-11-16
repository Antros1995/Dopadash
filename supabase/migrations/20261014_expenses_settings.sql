begin;
create table if not exists public.monitoraggio_personale_expenses_settings (
  user_id uuid primary key references auth.users(id) on delete cascade,
  source_url text not null default '',
  default_limit numeric not null default 1900 check (default_limit >= 0),
  monthly_budgets jsonb not null default '{}'::jsonb,
  chart_metrics text[] not null default '{}'::text[],
  updated_at timestamptz not null default now()
);
alter table public.monitoraggio_personale_expenses_settings enable row level security;
drop policy if exists "Own expense settings" on public.monitoraggio_personale_expenses_settings;
create policy "Own expense settings" on public.monitoraggio_personale_expenses_settings
  for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
grant select, insert, update, delete on public.monitoraggio_personale_expenses_settings to authenticated;
create or replace function public.monitoraggio_personale_save_expenses_settings(
  p_source_url text default null, p_month text default null,
  p_limit numeric default null, p_chart_metrics text[] default null
) returns setof public.monitoraggio_personale_expenses_settings
language plpgsql security invoker set search_path = public as $$
declare owner_id uuid := auth.uid();
begin
  if owner_id is null then raise exception 'Authentication required'; end if;
  if p_source_url is not null and length(p_source_url) > 4096 then raise exception 'Invalid source'; end if;
  if p_month is not null and (p_month !~ '^20[0-9]{2}-(0[1-9]|1[0-2])$' or p_limit is null or p_limit < 0) then
    raise exception 'Invalid monthly budget';
  end if;
  return query insert into public.monitoraggio_personale_expenses_settings as stored
    (user_id, source_url, monthly_budgets, chart_metrics)
    values (owner_id, coalesce(p_source_url, ''),
      case when p_month is null then '{}'::jsonb else jsonb_build_object(p_month,p_limit) end,
      coalesce(p_chart_metrics,'{}'::text[]))
    on conflict (user_id) do update set
      source_url = coalesce(p_source_url,stored.source_url),
      monthly_budgets = stored.monthly_budgets || case when p_month is null then '{}'::jsonb else jsonb_build_object(p_month,p_limit) end,
      chart_metrics = coalesce(p_chart_metrics,stored.chart_metrics), updated_at = now()
    returning stored.*;
end; $$;
revoke all on function public.monitoraggio_personale_save_expenses_settings(text,text,numeric,text[]) from public, anon;
grant execute on function public.monitoraggio_personale_save_expenses_settings(text,text,numeric,text[]) to authenticated;
do $$ begin
  if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime'
    and schemaname='public' and tablename='monitoraggio_personale_expenses_settings') then
    alter publication supabase_realtime add table public.monitoraggio_personale_expenses_settings;
  end if;
end; $$;
notify pgrst, 'reload schema';
commit;
