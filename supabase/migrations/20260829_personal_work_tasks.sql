-- Task groups and colours for the dedicated Monitoraggio table.
alter table public.monitoraggio_personale_tasks
  drop constraint if exists monitoraggio_personale_tasks_task_group_check;

alter table public.monitoraggio_personale_tasks
  add constraint monitoraggio_personale_tasks_task_group_check
  check (task_group in ('personal', 'work', 'personal_work'));

alter table public.monitoraggio_personale_tasks
  add column if not exists color text not null default 'black';

alter table public.monitoraggio_personale_tasks
  drop constraint if exists monitoraggio_personale_tasks_color_check;

alter table public.monitoraggio_personale_tasks
  add constraint monitoraggio_personale_tasks_color_check
  check (color in ('black', 'red', 'blue', 'green', 'yellow'));

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'monitoraggio_personale_tasks'
  ) then
    alter publication supabase_realtime
      add table public.monitoraggio_personale_tasks;
  end if;
end;
$$;
