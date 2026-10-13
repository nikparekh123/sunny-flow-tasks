/**
 * dividends-sync — declared dividends for every name in the book, daily, from
 * Polygon's reference endpoint (still on our plan), into `dividends`.
 *
 * What reads it: the weekly report's Coming up (block 06). An ex-dividend
 * date on a name with calls sold is when early assignment gets likely: the
 * holder exercises the day before to collect the dividend. Nik kept ex-dates
 * in Coming up, 12 Oct 2026.
 *
 * ⚠ FIVE CALLS A MINUTE. Polygon answers 429 on the sixth, so the listing's
 * pages go 12.5 s apart. A name that has never paid is still looked for every
 * day: a first declaration is exactly the news.
 *
 * ⚠ DEPLOY WITH verify_jwt = false (cron sends an sb_secret key, not a JWT).
 */
const BUILD = '2026-10-13.4';
/* Supabase's background-task hook: the work outlives the response. */
declare const EdgeRuntime: { waitUntil(p: Promise<unknown>): void };

/* ⚠ ANSWERS AT ONCE, WORKS IN THE BACKGROUND. Nine names at 12.5 s is close
   to the 150 s request limit, which cut the first runs off mid-answer. The
   result lands in sync_heartbeat (`detail`) instead of the response. */
/* ⚠ WHO MAY CALL (audit, 13 Oct 2026). verify_jwt is off so pg_cron can call
   in, so the function checks instead: the scheduler's x-cron-key (vault
   `cron_secret`, secret CRON_SECRET; sent as x-admin-key for a manual
   admin call), the service-role key, or, where `users`
   is set, a signed-in user of the app or website. Anyone else gets a 401. */
async function callerOk(req: Request, users: boolean): Promise<boolean> {
  const cron = Deno.env.get('CRON_SECRET');
  if (cron && (req.headers.get('x-cron-key') === cron || req.headers.get('x-admin-key') === cron)) return true;
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
  /* {wait:true}: run in the open and return the per-name result (checks). */
  let body: { wait?: boolean } = {};
  try { if (req.method === 'POST') body = await req.json(); } catch { /* cron sends {} */ }
  if (body.wait) return await run();
  const job = run();
  try { EdgeRuntime.waitUntil(job); } catch { /* local run: just await below */ }
  return new Response(JSON.stringify({ ok: true, build: BUILD, started: true }),
    { status: 202, headers: { 'Content-Type': 'application/json' } });
});

async function run(): Promise<Response> {
  const url = Deno.env.get('SUPABASE_URL')!;
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const poly = Deno.env.get('POLYGON_API_KEY')!;
  const h = { apikey: key, Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' };
  try {
    const today = new Date().toLocaleDateString('en-CA', { timeZone: 'America/New_York' });
    /* The book only: names with an option leg still to expire, plus shares
       IBKR says are held at the last close. `positions` is not used: it still
       lists names long gone (33 on 13 Oct, against 9 in the book), and at
       13 s a name that ran past the 150 s request limit. */
    const lastClose = (await fetch(`${url}/rest/v1/account_positions_daily?select=report_date&order=report_date.desc&limit=1`,
      { headers: h }).then((r) => r.json()))[0]?.report_date;
    const [legs, shares] = await Promise.all([
      fetch(`${url}/rest/v1/option_trades?voided_at=is.null&expiry=gte.${today}&select=ticker`, { headers: h }).then((r) => r.json()),
      lastClose ? fetch(`${url}/rest/v1/account_positions_daily?report_date=eq.${lastClose}&asset_category=eq.STK&select=symbol`,
        { headers: h }).then((r) => r.json()) : Promise.resolve([]),
    ]);
    const names = [...new Set([...legs.map((r: { ticker: string }) => r.ticker),
      ...shares.map((r: { symbol: string }) => r.symbol)].map((t: string) => String(t).toUpperCase()))].sort();
    const out: Record<string, string | number> = {};
    let wrote = 0;
    /* ⚠ ONE LISTING, NOT ONE CALL A NAME (13 Oct 2026). Asking per name took
       over 150 s for nine names. Polygon lists every declared dividend in the
       market by ex-date, so the next 60 days come in a page or two, and the
       book's names are picked out here. */
    const until = new Date(Date.parse(today + 'T12:00:00Z') + 60 * 864e5).toISOString().slice(0, 10);
    let next: string | null = `https://api.polygon.io/v3/reference/dividends?ex_dividend_date.gte=${today}`
      + `&ex_dividend_date.lte=${until}&limit=1000&order=asc&sort=ex_dividend_date`;
    const want = new Set(names);
    const rows: Record<string, unknown>[] = [];
    for (let pageN = 0; next && pageN < 4; pageN++) {
      if (pageN > 0) await new Promise((r) => setTimeout(r, 12_500));
      const r: Response = await fetch(`${next}&apiKey=${poly}`, { signal: AbortSignal.timeout(30_000) });
      if (!r.ok) { out._listing = `HTTP ${r.status}`; await r.body?.cancel(); break; }
      const j = await r.json();
      for (const x of (j?.results ?? []) as Record<string, string | number>[]) {
        const t = String(x.ticker ?? '').toUpperCase();
        if (!want.has(t) || !x.ex_dividend_date) continue;
        rows.push({ ticker: t, ex_date: String(x.ex_dividend_date).slice(0, 10),
          pay_date: x.pay_date ? String(x.pay_date).slice(0, 10) : null,
          record_date: x.record_date ? String(x.record_date).slice(0, 10) : null,
          declared_on: x.declaration_date ? String(x.declaration_date).slice(0, 10) : null,
          cash_amount: Number(x.cash_amount ?? 0) || null, frequency: Number(x.frequency ?? 0) || null,
          dividend_type: x.dividend_type ? String(x.dividend_type) : null, source: 'polygon',
          updated_at: new Date().toISOString() });
      }
      next = j?.next_url ? String(j.next_url) : null;
    }
    if (rows.length) {
      const w = await fetch(`${url}/rest/v1/dividends?on_conflict=ticker,ex_date`, {
        method: 'POST', headers: { ...h, Prefer: 'resolution=merge-duplicates,return=minimal' },
        body: JSON.stringify(rows),
      });
      if (!w.ok) out._write = `write ${w.status}`; else wrote = rows.length;
    }
    for (const t of names) out[t] = (rows.filter((x) => x.ticker === t).map((x) => String(x.ex_date)).sort()[0]) ?? 'none declared';
    const errors = Object.values(out).filter((v) => String(v).startsWith('HTTP') || String(v).startsWith('write')).length;
    if (!errors) {
      await fetch(`${url}/rest/v1/sync_heartbeat?on_conflict=feed`, {
        method: 'POST', headers: { ...h, Prefer: 'resolution=merge-duplicates,return=minimal' },
        body: JSON.stringify([{ feed: 'dividends-sync', ran_at: new Date().toISOString(), rows_written: wrote,
          detail: `polygon · ${names.length} names · next ex ${Object.entries(out).filter(([, v]) => /^\d{4}-/.test(String(v))).map(([k, v]) => `${k} ${v}`).join(', ') || 'none declared'}` }]),
      });
    }
    return new Response(JSON.stringify({ ok: !errors, build: BUILD, next_ex: out }),
      { headers: { 'Content-Type': 'application/json' } });
  } catch (e) {
    return new Response(JSON.stringify({ ok: false, build: BUILD, error: String(e) }),
      { status: 500, headers: { 'Content-Type': 'application/json' } });
  }
}
