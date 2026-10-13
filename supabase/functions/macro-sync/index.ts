/**
 * macro-sync — the US releases the weekly report lists under Coming up:
 * the inflation report (CPI) and the jobs report, from FRED's release
 * calendar, daily into `macro_events`. Fed decisions are entered by hand
 * (the Fed publishes the year's meetings once; rows run to June 2027).
 *
 * ⚠ NEVER OVERWRITES. Rows already there (manual or investing.com) win: a
 * FRED date only fills a release that has no row yet, by (date, name, US).
 * Names follow the table's convention, the reference month in brackets:
 * the 14 Oct release is "CPI (September 2026)".
 *
 * ⚠ DEPLOY WITH verify_jwt = false (cron sends an sb_secret key, not a JWT).
 */
const BUILD = '2026-10-13.1';
const RELEASES = [
  { id: 10, name: 'CPI', category: 'inflation', time: '08:30:00' },
  { id: 50, name: 'Jobs report', category: 'jobs', time: '08:30:00' },
];
const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September',
  'October', 'November', 'December'];

/* ⚠ WHO MAY CALL (audit, 13 Oct 2026). verify_jwt is off so pg_cron can call
   in, so the function checks instead: the scheduler's x-cron-key (vault
   `cron_secret`, secret CRON_SECRET), the service-role key, or, where `users`
   is set, a signed-in user of the app or website. Anyone else gets a 401. */
async function callerOk(req: Request, users: boolean): Promise<boolean> {
  const cron = Deno.env.get('CRON_SECRET');
  if (cron && req.headers.get('x-cron-key') === cron) return true;
  const auth = req.headers.get('authorization') ?? '';
  if (auth && auth === `Bearer ${Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')}`) return true;
  if (!users || !auth.startsWith('Bearer ')) return false;
  const r = await fetch(`${Deno.env.get('SUPABASE_URL')}/auth/v1/user`,
    { headers: { apikey: Deno.env.get('SUPABASE_ANON_KEY') ?? '', Authorization: auth } });
  await r.body?.cancel();
  return r.ok;
}
const refused = () => new Response(JSON.stringify({ ok: false, error: 'not allowed' }),
  { status: 401, headers: { 'Content-Type': 'application/json' } });

Deno.serve(async (req) => {
  if (req.method !== 'OPTIONS' && !(await callerOk(req, false))) return refused();
  const url = Deno.env.get('SUPABASE_URL')!;
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const fred = Deno.env.get('FRED_API_KEY')!;
  const h = { apikey: key, Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' };
  try {
    const today = new Date().toLocaleDateString('en-CA', { timeZone: 'America/New_York' });
    const rows: Record<string, unknown>[] = [];
    const seen: Record<string, string[]> = {};
    for (const r of RELEASES) {
      const q = await fetch(`https://api.stlouisfed.org/fred/release/dates?release_id=${r.id}&api_key=${fred}`
        + `&file_type=json&include_release_dates_with_no_data=true&realtime_start=${today}`
        + `&sort_order=asc&limit=20`, { signal: AbortSignal.timeout(15_000) });
      if (!q.ok) throw new Error(`fred ${r.id} ${q.status}`);
      const dates = ((await q.json())?.release_dates ?? []).map((x: { date: string }) => x.date)
        .filter((d: string) => d >= today).slice(0, 8);
      seen[r.name] = dates;
      for (const d of dates) {
        const [y, m] = d.split('-').map(Number);
        const ref = new Date(Date.UTC(y, m - 2, 1));
        rows.push({ event_date: d, event_time: r.time, timezone: 'America/New_York', country: 'US',
          name: `${r.name} (${MONTHS[ref.getUTCMonth()]} ${ref.getUTCFullYear()})`,
          category: r.category, importance: 3, source: 'fred', source_id: `fred:${r.id}:${d}` });
      }
    }
    if (rows.length) {
      const w = await fetch(`${url}/rest/v1/macro_events?on_conflict=event_date,name,country`, {
        method: 'POST', headers: { ...h, Prefer: 'resolution=ignore-duplicates,return=minimal' },
        body: JSON.stringify(rows),
      });
      if (!w.ok) throw new Error(`write ${w.status} ${(await w.text()).slice(0, 200)}`);
    }
    await fetch(`${url}/rest/v1/sync_heartbeat?on_conflict=feed`, {
      method: 'POST', headers: { ...h, Prefer: 'resolution=merge-duplicates,return=minimal' },
      body: JSON.stringify([{ feed: 'macro-sync', ran_at: new Date().toISOString(), rows_written: rows.length,
        detail: `fred · ${Object.entries(seen).map(([k, v]) => `${k} ${v.length}`).join(' · ')}` }]),
    });
    return new Response(JSON.stringify({ ok: true, build: BUILD, seen }), { headers: { 'Content-Type': 'application/json' } });
  } catch (e) {
    return new Response(JSON.stringify({ ok: false, build: BUILD, error: String(e) }),
      { status: 500, headers: { 'Content-Type': 'application/json' } });
  }
});
