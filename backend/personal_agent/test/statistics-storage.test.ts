import { afterEach, expect, it, vi } from 'vitest';
import { persistStatisticsDay } from '../src/fitbit/statistics-storage';
import type { FitbitDaySnapshot } from '../src/fitbit/types';

afterEach(() => vi.restoreAllMocks());
const env = {SUPABASE_URL:'https://project.supabase.co',SUPABASE_SERVICE_ROLE_KEY:'server-secret',DESKTOP_SUPABASE_USER_ID:'owner'} as unknown as Env;
const day = {date:'2026-10-17',source:'fitbit',syncedAt:'2026-10-17T12:00:00Z',finalized:false} as FitbitDaySnapshot;
it('upserts an idempotent dated snapshot for the configured owner, keeping credentials in headers', async () => {
  const request = vi.spyOn(globalThis,'fetch').mockResolvedValue(new Response(null,{status:204}));
  await persistStatisticsDay(env,day);
  const [url,init] = request.mock.calls[0]!;
  expect(url).toContain('on_conflict=user_id,day,source');
  const row=JSON.parse(init!.body as string);
  expect(row).toMatchObject({user_id:'owner',day:'2026-10-17',source:'fitbit',payload:day});
  expect(init!.body).not.toContain('server-secret');
});
it('does not claim a successful write on database failure',async () => {
  vi.spyOn(globalThis,'fetch').mockResolvedValue(new Response(null,{status:403}));
  await expect(persistStatisticsDay(env,day)).rejects.toThrow('403');
});
it('rejects missing owner configuration without contacting the database',async () => {
  const request=vi.spyOn(globalThis,'fetch');
  await expect(persistStatisticsDay({} as Env,day)).rejects.toThrow('not configured');
  expect(request).not.toHaveBeenCalled();
});
