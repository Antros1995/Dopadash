-- Posta shares the existing task table, per-user RLS and realtime publication.
begin;
alter table public.monitoraggio_personale_tasks
  drop constraint if exists monitoraggio_personale_tasks_task_group_check;
alter table public.monitoraggio_personale_tasks
  add constraint monitoraggio_personale_tasks_task_group_check
  check (task_group in ('personal', 'work', 'personal_work', 'posta'));
alter table public.monitoraggio_personale_tasks
  add column if not exists due_at timestamp without time zone,
  add column if not exists calendar_event_id text,
  add column if not exists deleted_at timestamptz;
create unique index if not exists monitoraggio_personale_tasks_calendar_event_idx
  on public.monitoraggio_personale_tasks (user_id, calendar_event_id)
  where calendar_event_id is not null;

-- Atomic import preserves completion, colour, manual rescheduling and deletion.
create or replace function public.monitoraggio_personale_import_posta(
  p_tasks jsonb, p_migrate boolean default false
) returns setof public.monitoraggio_personale_tasks
language plpgsql security invoker set search_path = public as $$
declare
  owner_id uuid := auth.uid();
  item jsonb;
  event_id text;
  result public.monitoraggio_personale_tasks;
begin
  if owner_id is null then raise exception 'Authentication required'; end if;
  if jsonb_typeof(p_tasks) <> 'array' or jsonb_array_length(p_tasks) > 500 then
    raise exception 'Invalid Posta import';
  end if;
  for item in select value from jsonb_array_elements(p_tasks) loop
    event_id := item->>'calendar_event_id';
    if event_id is null or length(event_id) not between 1 and 1000 then
      raise exception 'Invalid calendar identity';
    end if;
    if (item->>'scheduled_date')::date < date '2026-10-12' then
      raise exception 'Calendar history before Posta activation';
    end if;
    insert into public.monitoraggio_personale_tasks as stored (
      id, user_id, title, task_group, color, scheduled_date, due_at,
      calendar_event_id, completed_at, deleted_at, source
    ) values (
      md5(owner_id::text || ':posta:' || event_id)::uuid,
      owner_id, left(btrim(item->>'title'), 160), 'posta',
      coalesce(item->>'color', 'blue'), (item->>'scheduled_date')::date,
      (item->>'due_at')::timestamp, event_id,
      case when p_migrate then (item->>'completed_at')::timestamptz else null end,
      case when p_migrate then (item->>'deleted_at')::timestamptz else null end,
      'desktop'
    ) on conflict (user_id, calendar_event_id) where calendar_event_id is not null
    do update set
      title = case when stored.deleted_at is null then excluded.title else stored.title end,
      scheduled_date = case
        when stored.deleted_at is null and (stored.due_at is null or stored.scheduled_date = stored.due_at::date)
          then excluded.scheduled_date else stored.scheduled_date end,
      due_at = case when stored.deleted_at is null then excluded.due_at else stored.due_at end,
      deleted_at = coalesce(stored.deleted_at, excluded.deleted_at)
    returning * into result;
    return next result;
  end loop;
end;
$$;
revoke all on function public.monitoraggio_personale_import_posta(jsonb, boolean) from public, anon;
grant execute on function public.monitoraggio_personale_import_posta(jsonb, boolean) to authenticated;
do $$ begin
  if not exists (select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public'
      and tablename = 'monitoraggio_personale_tasks') then
    alter publication supabase_realtime add table public.monitoraggio_personale_tasks;
  end if;
end; $$;
notify pgrst, 'reload schema';
commit;
