// Local PostgreSQL/WASM checks. No connection to the remote Supabase project.
// Install the isolated test runtime with:
// npm install --prefix .tools/statistics-db-test @electric-sql/pglite
import { createRequire } from 'node:module';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import assert from 'node:assert/strict';
const require = createRequire(resolve('.tools/statistics-db-test/package.json'));
const { PGlite } = require('@electric-sql/pglite');
const db = new PGlite();
const a='11111111-1111-4111-8111-111111111111', b='22222222-2222-4222-8222-222222222222';
const experiment='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
await db.exec(`create schema auth;
  create table auth.users(id uuid primary key);
  create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
  create role anon; create role authenticated; create role service_role bypassrls;
  grant usage on schema public,auth to anon,authenticated,service_role;
  grant execute on function auth.uid() to authenticated;
  insert into auth.users values ('${a}'),('${b}');`);
const migration=readFileSync('supabase/migrations/20261017_body_statistics.sql','utf8');
await db.exec(migration);
await db.exec(migration); // migration is safe to replay
async function owner(id) { await db.exec(`reset role; set role authenticated; set request.jwt.claim.sub='${id}';`); }
async function rejects(sql,code) { await assert.rejects(db.exec(sql),e=>e.code===code); }
await owner(a);
await db.exec(`insert into statistics_experiments(id,user_id,name,start_date,end_date,baseline_start,baseline_end,primary_metric)
  values ('${experiment}','${a}','Test','2026-01-03','2026-01-04','2026-01-01','2026-01-02','heartRateVariabilityMs');
  insert into statistics_preferences(user_id,settings) values ('${a}','{"moving":false}');
  insert into statistics_fitbit_days(user_id,day,synced_at,payload)
    values ('${a}','2026-01-01','2026-01-02T12:00:00Z','{"date":"2026-01-01","heartRateVariabilityMs":40}');
  insert into statistics_fitbit_days(user_id,day,synced_at,payload)
    values ('${a}','2026-01-01','2026-01-01T12:00:00Z','{"date":"2026-01-01","heartRateVariabilityMs":10}')
    on conflict(user_id,day,source) do update set synced_at=excluded.synced_at,payload=excluded.payload;`);
assert.equal((await db.query('select payload from statistics_fitbit_days')).rows[0].payload.heartRateVariabilityMs,40);
await db.exec(`insert into statistics_experiment_logs(user_id,experiment_id,day,calm)
  values ('${a}','${experiment}','2026-01-03',0);`);
assert.equal((await db.query('select session_status from statistics_experiment_logs')).rows[0].session_status,null);
await rejects(`insert into statistics_experiment_logs(user_id,experiment_id,day,session_status) values ('${a}','${experiment}','2026-01-01','completed')`,'23514');
await rejects(`insert into statistics_experiment_logs(user_id,experiment_id,day,calm) values ('${a}','${experiment}','2026-01-04',11)`,'23514');
await owner(b);
for(const table of ['statistics_experiments','statistics_experiment_logs','statistics_fitbit_days','statistics_preferences']) {
  assert.equal((await db.query(`select * from ${table}`)).rows.length,0,`${table}: cross-user read`);
}
await rejects(`insert into statistics_preferences(user_id,settings) values ('${a}','{}')`,'42501');
await rejects(`insert into statistics_experiment_logs(user_id,experiment_id,day) values ('${b}','${experiment}','2026-01-04')`,'23503');
await db.exec(`update statistics_fitbit_days set payload='{"date":"2026-01-01"}' where user_id='${a}';`);
await owner(a);
assert.equal((await db.query('select payload from statistics_fitbit_days')).rows[0].payload.heartRateVariabilityMs,40);
assert.deepEqual((await db.query('select settings from statistics_preferences')).rows[0].settings,{moving:false});
await db.exec('reset role; set role anon');
await rejects('select * from statistics_preferences','42501');
await db.close();
console.log('Statistics schema passed: migration replay, idempotency, stale imports, unknown practice, validation, owner isolation and anonymous access.');
