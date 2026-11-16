begin;

create table if not exists public.statistics_fitbit_days (
  user_id uuid not null references auth.users(id) on delete cascade,
  day date not null,
  source text not null default 'fitbit' check (source = 'fitbit'),
  timezone text not null default 'Europe/Rome' check (timezone = 'Europe/Rome'),
  granularity text not null default 'day' check (granularity = 'day'),
  synced_at timestamptz not null,
  finalized boolean not null default false,
  payload jsonb not null check (jsonb_typeof(payload) = 'object'),
  units jsonb not null default '{"sleepMinutes":"min","sleepEfficiency":"%","restingHeartRate":"bpm","heartRateVariabilityMs":"ms","steps":"steps","distanceKm":"km","activeMinutes":"min"}',
  primary key (user_id, day, source),
  check (payload ? 'date' and payload->>'date' = day::text),
  check (coalesce(payload->>'source', 'fitbit') = source)
);

-- Keep RLS explicit immediately after CREATE TABLE, including for SQL Editor checks.
alter table public.statistics_fitbit_days enable row level security;

-- A delayed import must never replace a more recent wearable snapshot.
create or replace function public.statistics_keep_newest_snapshot()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.synced_at < old.synced_at then return old; end if;
  return new;
end; $$;
drop trigger if exists statistics_keep_newest on public.statistics_fitbit_days;
create trigger statistics_keep_newest before update on public.statistics_fitbit_days
for each row execute function public.statistics_keep_newest_snapshot();

create table if not exists public.statistics_experiments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (length(trim(name)) between 1 and 160),
  description text not null default '',
  objective text not null default '',
  protocol jsonb not null default '{}' check (jsonb_typeof(protocol) = 'object'),
  start_date date not null,
  end_date date not null,
  baseline_start date not null,
  baseline_end date not null,
  primary_metric text not null,
  secondary_metrics text[] not null default '{}',
  initial_notes text not null default '',
  status text not null default 'draft' check (status in ('draft','running','completed','archived')),
  repeated_from uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, id),
  foreign key (user_id, repeated_from) references public.statistics_experiments(user_id, id),
  check (end_date >= start_date and end_date - start_date <= 3652),
  check (baseline_end >= baseline_start and baseline_end < start_date),
  check (baseline_end - baseline_start <= 3652),
  check (primary_metric in ('sleepMinutes','sleepEfficiency','restingHeartRate','heartRateVariabilityMs','steps','distanceKm','activeMinutes','calm','stress')),
  check (secondary_metrics <@ array['sleepMinutes','sleepEfficiency','restingHeartRate','heartRateVariabilityMs','steps','distanceKm','activeMinutes','calm','stress']::text[]),
  check (repeated_from is distinct from id)
);

alter table public.statistics_experiments enable row level security;

create table if not exists public.statistics_experiment_logs (
  user_id uuid not null references auth.users(id) on delete cascade,
  experiment_id uuid not null,
  day date not null,
  session_status text check (session_status in ('completed','partial','skipped')),
  duration_minutes integer check (duration_minutes between 0 and 1440),
  practice_time time,
  timezone text not null default 'Europe/Rome' check (timezone = 'Europe/Rome'),
  calm numeric check (calm between 0 and 10),
  stress numeric check (stress between 0 and 10),
  context jsonb not null default '{}' check (jsonb_typeof(context) = 'object'),
  notes text not null default '',
  source text not null default 'manual' check (source = 'manual'),
  updated_at timestamptz not null default now(),
  primary key (user_id, experiment_id, day),
  foreign key (user_id, experiment_id) references public.statistics_experiments(user_id, id) on delete cascade
);

alter table public.statistics_experiment_logs enable row level security;

create table if not exists public.statistics_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  settings jsonb not null default '{}' check (jsonb_typeof(settings) = 'object'),
  updated_at timestamptz not null default now()
);

alter table public.statistics_preferences enable row level security;

create index if not exists statistics_experiments_owner_date on public.statistics_experiments(user_id, start_date desc);
create index if not exists statistics_logs_owner_date on public.statistics_experiment_logs(user_id, day);

create or replace function public.statistics_validate_log()
returns trigger language plpgsql set search_path = public as $$
declare e public.statistics_experiments;
begin
  select * into e from public.statistics_experiments
    where id = new.experiment_id and user_id = new.user_id;
  if not found then raise exception 'Experiment unavailable' using errcode = '23503'; end if;
  if not (new.day between e.baseline_start and e.baseline_end or new.day between e.start_date and e.end_date) then
    raise exception 'Day outside experiment periods' using errcode = '23514';
  end if;
  if new.day > (now() at time zone 'Europe/Rome')::date then
    raise exception 'Cannot record future practice' using errcode = '23514';
  end if;
  if new.day < e.start_date and (new.session_status is not null or new.duration_minutes is not null or new.practice_time is not null) then
    raise exception 'Baseline accepts context and ratings, not practice sessions' using errcode = '23514';
  end if;
  if exists (select 1 from jsonb_each(new.context) x where x.key not in ('training','caffeine','alcohol','illness','travel','routine')
    or x.value not in ('true'::jsonb,'false'::jsonb,'null'::jsonb)) then
    raise exception 'Invalid context factor' using errcode = '23514';
  end if;
  return new;
end; $$;
drop trigger if exists statistics_validate_log on public.statistics_experiment_logs;
create trigger statistics_validate_log before insert or update on public.statistics_experiment_logs
for each row execute function public.statistics_validate_log();

create or replace function public.statistics_touch_updated_at()
returns trigger language plpgsql set search_path = public as $$
begin new.updated_at := now(); return new; end; $$;

do $$ declare t text; begin
  foreach t in array array['statistics_fitbit_days','statistics_experiments','statistics_experiment_logs','statistics_preferences'] loop
    execute format('revoke all on public.%I from anon', t);
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
    execute format('grant all on public.%I to service_role', t);
    execute format('drop policy if exists owner_access on public.%I', t);
    execute format('create policy owner_access on public.%I for all to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id)', t);
    if t <> 'statistics_fitbit_days' then
      execute format('drop trigger if exists statistics_touch on public.%I', t);
      execute format('create trigger statistics_touch before update on public.%I for each row execute function public.statistics_touch_updated_at()', t);
    end if;
  end loop;
end; $$;

notify pgrst, 'reload schema';
commit;
