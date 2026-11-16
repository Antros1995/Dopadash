// Isolated PostgreSQL/WASM security checks; never connects to Supabase.
// Runtime: npm install --prefix .tools/statistics-db-test @electric-sql/pglite
import { createRequire } from 'node:module';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import assert from 'node:assert/strict';
const require = createRequire(resolve('.tools/statistics-db-test/package.json'));
const { PGlite } = require('@electric-sql/pglite');
const db = new PGlite();
const owner = '11111111-1111-4111-8111-111111111111';
const other = '22222222-2222-4222-8222-222222222222';
const tables = [
  'monitoraggio_personale_tasks', 'monitoraggio_personale_expenses_settings',
  'statistics_fitbit_days', 'statistics_experiments', 'statistics_experiment_logs',
  'statistics_preferences', 'habits', 'habit_logs', 'habit_log_values', 'daily_screen_times',
];
await db.exec(`
  create schema auth;
  create role anon; create role authenticated; create role service_role bypassrls;
  create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;
  create function auth.uid() returns uuid language sql stable as $$select (auth.jwt()->>'sub')::uuid$$;
  create function auth.role() returns text language sql stable as $$select auth.jwt()->>'role'$$;
  create table auth.mfa_factors(id text primary key, user_id uuid, status text);
  grant usage on schema public,auth to anon,authenticated,service_role;
`);
for (const table of tables) {
  await db.exec(`create table public.${table}(user_id uuid primary key, value int);
    alter table public.${table} enable row level security;
    create policy owner_access on public.${table} to authenticated
      using(auth.uid()=user_id) with check(auth.uid()=user_id);
    grant select,insert,update,delete on public.${table} to authenticated,service_role;
    insert into public.${table} values('${owner}',1),('${other}',9);`);
}
// Mirror a legacy SECURITY DEFINER RPC which would otherwise bypass RLS.
await db.exec(`create function public.test_definer_write() returns void language sql security definer set search_path='' as $$
  update public.habit_logs set value=77 where user_id=auth.uid();
$$; grant execute on function public.test_definer_write() to authenticated;`);
const migration = readFileSync('supabase/migrations/20261019_mfa_security.sql', 'utf8');
await db.exec(migration);
await db.exec(migration);
async function asUser(id, aal, role='authenticated') {
  await db.exec(`reset role; set role ${role}; set request.jwt.claims='${JSON.stringify({sub:id,aal,role})}';`);
}
async function rejects(sql, code='42501') {
  await assert.rejects(db.exec(sql), error=>error.code===code);
}
await asUser(owner, 'aal1');
for (const table of tables) {
  assert.equal((await db.query(`select * from ${table}`)).rows.length,1);
  await db.exec(`update ${table} set value=2 where user_id='${owner}'`);
}
await db.exec('reset role');
await db.exec(`insert into auth.mfa_factors values('pending','${owner}','unverified')`);
await asUser(owner,'aal1');
assert.equal((await db.query('select * from habits')).rows.length,1);
await db.exec('reset role');
await db.exec(`update auth.mfa_factors set status='verified' where id='pending'`);
await asUser(owner,'aal1');
for (const table of tables) {
  assert.equal((await db.query(`select * from ${table}`)).rows.length,0, `${table}: aal1 read denied`);
  await db.exec(`update ${table} set value=3; delete from ${table};`);
  await rejects(`insert into ${table} values('${owner}',3) on conflict(user_id) do update set value=excluded.value`);
}
await rejects('select public.test_definer_write()');
await asUser(owner,undefined);
assert.equal((await db.query('select * from habits')).rows.length,0);
await asUser(owner,'aal2');
for (const table of tables) {
  const rows = (await db.query(`select * from ${table}`)).rows;
  assert.deepEqual(rows,[{user_id:owner,value:2}], `${table}: aal1 writes had no effect`);
  await rejects(`insert into ${table} values('${other}',3) on conflict(user_id) do update set value=3`);
  await db.exec(`update ${table} set value=4 where user_id='${owner}'`);
  await db.exec(`delete from ${table} where user_id='${owner}'; insert into ${table} values('${owner}',5)`);
}
await db.exec('select public.test_definer_write()');
assert.equal((await db.query('select value from habit_logs')).rows[0].value,77);
await asUser(other,'aal1');
assert.deepEqual((await db.query('select * from habits')).rows,[{user_id:other,value:9}]);
await asUser(owner,undefined,'service_role');
await db.exec(`update habits set value=8 where user_id='${owner}'`);
assert.equal((await db.query('select * from habits')).rows.length,2);
await db.exec('reset role; set role anon');
await rejects('select * from habits');
await rejects('select monitoraggio_private.mfa_access_allowed()');
await db.exec('reset role');
await db.exec(`delete from auth.mfa_factors where user_id='${owner}'`);
await asUser(owner,'aal1');
assert.equal((await db.query('select * from habits')).rows.length,1);
await db.close();
console.log('MFA schema passed: replay, all 10 tables, opt-in, stale/missing AAL, owner isolation, CRUD, SECURITY DEFINER write protection, service role and anonymous access.');
