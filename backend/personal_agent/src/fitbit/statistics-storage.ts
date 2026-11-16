import type { FitbitDaySnapshot } from './types';

/** Uses the same server-only Supabase configuration as shared tasks. */
export async function persistStatisticsDay(env: Env, day: FitbitDaySnapshot): Promise<void> {
  const config = env as Env & {
    SUPABASE_URL?: string; SUPABASE_SERVICE_ROLE_KEY?: string; DESKTOP_SUPABASE_USER_ID?: string;
  };
  if (!config.SUPABASE_URL || !config.SUPABASE_SERVICE_ROLE_KEY || !config.DESKTOP_SUPABASE_USER_ID) {
    throw new Error('Statistics Supabase persistence is not configured');
  }
  const response = await fetch(`${config.SUPABASE_URL.replace(/\/$/u, '')}/rest/v1/statistics_fitbit_days?on_conflict=user_id,day,source`, {
    method: 'POST',
    headers: {
      apikey: config.SUPABASE_SERVICE_ROLE_KEY,
      authorization: `Bearer ${config.SUPABASE_SERVICE_ROLE_KEY}`,
      'content-type': 'application/json', prefer: 'resolution=merge-duplicates,return=minimal',
    },
    body: JSON.stringify({user_id: config.DESKTOP_SUPABASE_USER_ID, day: day.date, source: 'fitbit',
      synced_at: day.syncedAt, finalized: day.finalized, payload: day}),
    signal: AbortSignal.timeout(15000),
  });
  if (!response.ok) throw new Error(`Statistics persistence failed (${response.status})`);
}
