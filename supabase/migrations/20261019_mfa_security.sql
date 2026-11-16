-- MFA is opt-in per account. Existing ownership policies are preserved.
-- Run after the app's data migrations. Does not enable MFA for any user.
begin;

create schema if not exists monitoraggio_private;
revoke all on schema monitoraggio_private from public, anon;
grant usage on schema monitoraggio_private to authenticated;

create or replace function monitoraggio_private.mfa_access_allowed()
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select auth.uid() is not null
    and coalesce(auth.jwt() ->> 'aal', '') in ('aal1', 'aal2')
    and (
      auth.jwt() ->> 'aal' = 'aal2'
      or not exists (
        select 1 from auth.mfa_factors
        where user_id = auth.uid() and status = 'verified'
      )
    );
$$;
revoke all on function monitoraggio_private.mfa_access_allowed() from public, anon;
grant execute on function monitoraggio_private.mfa_access_allowed() to authenticated;

-- RLS can be bypassed by existing SECURITY DEFINER write RPCs. The trigger
-- also checks those writes, using the caller's JWT role, not current_user.
create or replace function monitoraggio_private.enforce_mfa_write()
returns trigger
language plpgsql security definer
set search_path = ''
as $$
begin
  if auth.role() = 'authenticated'
     and not monitoraggio_private.mfa_access_allowed() then
    raise exception 'Authenticator verification required' using errcode = '42501';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;
revoke all on function monitoraggio_private.enforce_mfa_write() from public, anon, authenticated;

do $$
declare
  t text;
  target regclass;
begin
  foreach t in array array[
    'monitoraggio_personale_tasks',
    'monitoraggio_personale_expenses_settings',
    'statistics_fitbit_days',
    'statistics_experiments',
    'statistics_experiment_logs',
    'statistics_preferences',
    'habits', 'habit_logs', 'habit_log_values', 'daily_screen_times'
  ] loop
    target := to_regclass(format('public.%I', t));
    if target is null then
      raise notice 'MFA: table public.% is absent; skipped. Reapply after creating it.', t;
      continue;
    end if;
    -- Avoid silently changing access for an existing table with no RLS setup.
    if not (select relrowsecurity from pg_class where oid = target) then
      raise exception 'MFA: public.% needs ownership RLS policies before this migration', t;
    end if;
    execute format('drop policy if exists monitoraggio_mfa_access on %s', target);
    execute format(
      'create policy monitoraggio_mfa_access on %s as restrictive for all to authenticated using ((select monitoraggio_private.mfa_access_allowed())) with check ((select monitoraggio_private.mfa_access_allowed()))', target
    );
    execute format('drop trigger if exists monitoraggio_mfa_write on %s', target);
    execute format(
      'create trigger monitoraggio_mfa_write before insert or update or delete on %s for each row execute function monitoraggio_private.enforce_mfa_write()', target
    );
  end loop;
end;
$$;

commit;
