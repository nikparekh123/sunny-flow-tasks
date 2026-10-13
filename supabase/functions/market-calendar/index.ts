/**
 * market-calendar — US exchange holidays and early closes for this year and
 * next, from Theta's calendar, saved daily into `market_calendar`.
 *
 * What reads it: the status line (block 01: "Thanksgiving · opens Fri 9:30",
 * "Open · closes early at 1:00"), the Holiday deck card (block 05) and the
 * weekly report's Coming up (block 06). Exchange days only: Columbus Day and
 * Veterans Day close the bond market, not the stock market, so they are not
 * here and get no card (Nik accepted that, 12 Oct 2026).
 *
 * ⚠ SAVED, NEVER HARD-CODED. Theta gives dates and types only; the NAME is
 * ours, by the NYSE rule each date satisfies, so an unplanned closure (a day
 * of mourning) still lands, just named "Market closed". If Theta is down the
 * stored rows stand; a closed day is never shown as open.
 *
 * ⚠ DEPLOY WITH verify_jwt = false (cron sends an sb_secret key, not a JWT).
 */
const BUILD = '2026-10-12.1';

/** Easter Sunday, anonymous Gregorian algorithm. */
function easter(y: number): string {
  const a = y % 19, b = Math.floor(y / 100), c = y % 100, d = Math.floor(b / 4), e = b % 4;
  const f = Math.floor((b + 8) / 25), g = Math.floor((b - f + 1) / 3);
  const h = (19 * a + b - d - g + 15) % 30, i = Math.floor(c / 4), k = c % 4;
  const l = (32 + 2 * e + 2 * i - h - k) % 7, m = Math.floor((a + 11 * h + 22 * l) / 451);
  const mo = Math.floor((h + l - 7 * m + 114) / 31), da = ((h + l - 7 * m + 114) % 31) + 1;
  return `${y}-${String(mo).padStart(2, '0')}-${String(da).padStart(2, '0')}`;
}

function nameOf(iso: string, early: boolean): string {
  const [y, mo, d] = iso.split('-').map(Number);
  const wd = new Date(Date.UTC(y, mo - 1, d)).getUTCDay(); // 0 Sun .. 6 Sat
  const goodFriday = new Date(Date.parse(easter(y) + 'T00:00:00Z') - 2 * 864e5).toISOString().slice(0, 10);
  if (early) {
    if (mo === 7 && d <= 3) return 'Day before Independence Day';
    if (mo === 11 && wd === 5 && d >= 23 && d <= 29) return 'Day after Thanksgiving';
    if (mo === 12 && d === 24) return 'Christmas Eve';
    return 'Early close';
  }
  if ((mo === 1 && d <= 2) || (mo === 12 && d === 31)) return "New Year's Day";
  if (mo === 1 && wd === 1 && d >= 15 && d <= 21) return 'Martin Luther King Jr. Day';
  if (mo === 2 && wd === 1 && d >= 15 && d <= 21) return "Presidents' Day";
  if (iso === goodFriday) return 'Good Friday';
  if (mo === 5 && wd === 1 && d >= 25) return 'Memorial Day';
  if (mo === 6 && d >= 18 && d <= 20) return 'Juneteenth';
  if (mo === 7 && d >= 3 && d <= 5) return 'Independence Day';
  if (mo === 9 && wd === 1 && d <= 7) return 'Labor Day';
  if (mo === 11 && wd === 4 && d >= 22 && d <= 28) return 'Thanksgiving';
  if (mo === 12 && d >= 24 && d <= 26) return 'Christmas';
  return 'Market closed';
}

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
  const theta = Deno.env.get('THETA_URL')!;
  const pk = Deno.env.get('THETA_PROXY_KEY')!;
  try {
    const y = Number(new Intl.DateTimeFormat('en-US', { timeZone: 'America/New_York', year: 'numeric' })
      .format(new Date()));
    const rows: Record<string, unknown>[] = [];
    for (const year of [y, y + 1]) {
      const r = await fetch(`${theta}/v3/calendar/year_holidays?year=${year}&format=json`,
        { headers: { 'x-proxy-key': pk }, signal: AbortSignal.timeout(15_000) });
      if (!r.ok) throw new Error(`theta ${year} ${r.status} ${(await r.text()).slice(0, 120)}`);
      const j = await r.json();
      for (const d of (j?.response ?? []) as { date: string; type: string; open: string | null; close: string | null }[]) {
        const early = d.type === 'early_close';
        if (!early && d.type !== 'full_close') continue;
        rows.push({
          date: d.date, kind: early ? 'early_close' : 'closed',
          opens: d.open, closes: d.close, name: nameOf(d.date, early),
          source: 'theta', fetched_at: new Date().toISOString(),
        });
      }
    }
    if (rows.length < 8) throw new Error(`only ${rows.length} days from theta`);
    const h = { apikey: key, Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' };
    const w = await fetch(`${url}/rest/v1/market_calendar?on_conflict=date`, {
      method: 'POST', headers: { ...h, Prefer: 'resolution=merge-duplicates,return=minimal' },
      body: JSON.stringify(rows),
    });
    if (!w.ok) throw new Error(`write ${w.status} ${(await w.text()).slice(0, 200)}`);
    await fetch(`${url}/rest/v1/sync_heartbeat?on_conflict=feed`, {
      method: 'POST', headers: { ...h, Prefer: 'resolution=merge-duplicates,return=minimal' },
      body: JSON.stringify([{ feed: 'market-calendar', ran_at: new Date().toISOString(),
        rows_written: rows.length, detail: `theta · ${y}-${y + 1} · ${rows.length} days` }]),
    });
    return new Response(JSON.stringify({ ok: true, build: BUILD, days: rows.map((r) => `${r.date} ${r.name}`) }),
      { headers: { 'Content-Type': 'application/json' } });
  } catch (e) {
    return new Response(JSON.stringify({ ok: false, build: BUILD, error: String(e) }),
      { status: 500, headers: { 'Content-Type': 'application/json' } });
  }
});
