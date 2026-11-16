-- Dedicated task list for DopaDash and its Telegram bot.
-- The explicit prefix avoids touching similarly named resources owned by other apps.
create table if not exists public.monitoraggio_personale_tasks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null check (char_length(btrim(title)) between 1 and 160),
  task_group text not null check (task_group in ('personal', 'work', 'personal_work')),
  color text not null default 'black' check (color in ('black', 'red', 'blue', 'green', 'yellow')),
  scheduled_date date not null,
  completed_at timestamptz,
  source text not null default 'desktop' check (source in ('desktop', 'telegram')),
  external_id text unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists monitoraggio_personale_tasks_user_date_idx
  on public.monitoraggio_personale_tasks (user_id, scheduled_date, created_at);

alter table public.monitoraggio_personale_tasks enable row level security;

create policy "Users manage their own monitoraggio tasks"
  on public.monitoraggio_personale_tasks for all to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Name this function specifically for this table so it cannot replace a
-- similarly named helper used by another application in the same project.
create or replace function public.set_monitoraggio_personale_tasks_updated_at_20260828()
returns trigger language plpgsql security invoker set search_path = public as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists monitoraggio_personale_tasks_set_updated_at
  on public.monitoraggio_personale_tasks;
create trigger monitoraggio_personale_tasks_set_updated_at
  before update on public.monitoraggio_personale_tasks
  for each row execute function public.set_monitoraggio_personale_tasks_updated_at_20260828();
