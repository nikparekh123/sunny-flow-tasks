/**
 * market-tape — the market around the book, from Yahoo, every 30 s from
 * 4:00 to 20:00 New York time on weekdays.
 *
 *   SPY QQQ IWM            the Today row, through pre-market and after hours
 *   ^VIX                   a level, not a price
 *   ^N225 ^GDAXI ^NSEI 000001.SS   the Overnight card (pre-market only)
 *   INTU ADBE PYPL VZ TMUS the Watchlist (Nik, 12 Oct 2026; fixed for now)
 *
 * ⚠ YAHOO FOR NOW, THETA LATER. Our Theta plan is options only, and options
 * do not trade before 9:30 or after 4:00, so the option-implied spot cannot
 * move out of hours; VIX needs Theta's index plan. Nik (12 Oct 2026): start
 * with Yahoo, move to Theta stock prices in about a month. Yahoo is
 * unofficial: it wants a cookie and a "crumb", and it refuses my Mac outright
 * (429), so this only ever runs from Supabase.
 *
 * ONE REQUEST for all 13 symbols (v7 quote). Two passes per cron call, 30 s
 * apart, like mp-refresh. Writes `market_live` (one row per symbol) and,
 * once the regular session has closed, that day's close into `daily_closes`
 * for the symbols nothing else captures, so the range filters can look back.
 *
 * Body: { force?: true } runs outside the window; { backfill?: true } loads
 * three months of daily closes for every symbol here.
 *
 * ⚠ DEPLOY WITH verify_jwt = false, like every cron-called function here.
 * pg_cron's cron_invoke_function sends the vault's sb_secret key, which is
 * not a JWT, so a verify_jwt function answers 401 to every scheduled call
 * (12 Oct 2026: the first deploys did exactly that).
 */
const BUILD = '2026-10-12.1';
const UA = {
  'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 '
    + '(KHTML, like Gecko) Version/17.0 Safari/605.1.15',
  Accept: 'application/json, text/plain, */*',
  'Accept-Language': 'en-US,en;q=0.9',
};
const SYMBOLS: { s: string; label: string; kind: 'index' | 'vix' | 'global' | 'watch' }[] = [
  { s: 'SPY', label: 'SPY', kind: 'index' },
  { s: 'QQQ', label: 'QQQ', kind: 'index' },
  { s: 'IWM', label: 'IWM', kind: 'index' },
  { s: '^VIX', label: 'VIX', kind: 'vix' },
  { s: '^N225', label: 'Nikkei 225', kind: 'global' },
  { s: '^GDAXI', label: 'DAX', kind: 'global' },
  { s: '^NSEI', label: 'Nifty 50', kind: 'global' },
  { s: '000001.SS', label: 'Shanghai Composite', kind: 'global' },
  { s: 'INTU', label: 'INTU', kind: 'watch' },
  { s: 'ADBE', label: 'ADBE', kind: 'watch' },
  { s: 'PYPL', label: 'PYPL', kind: 'watch' },
  { s: 'VZ', label: 'VZ', kind: 'watch' },
  { s: 'TMUS', label: 'TMUS', kind: 'watch' },
];
/* SPY, QQQ and IWM closes already come from mp-refresh's tapes. */
const CLOSES_HERE = SYMBOLS.filter((x) => x.kind === 'vix' || x.kind === 'watch').map((x) => x.s);

/* Kept for the life of the isolate; refetched once on any refusal. */
let session: { cookie: string; crumb: string } | null = null;

async function newSession(): Promise<{ cookie: string; crumb: string }> {
  const c = await fetch('https://fc.yahoo.com', { headers: UA, redirect: 'manual' });
  const cookie = (c.headers.get('set-cookie') ?? '').split(';')[0];
  await c.body?.cancel();
  if (!cookie) throw new Error('yahoo: no cookie');
  const r = await fetch('https://query2.finance.yahoo.com/v1/test/getcrumb', { headers: { ...UA, Cookie: cookie } });
  const crumb = (await r.text()).trim();
  if (!r.ok || !crumb || crumb.length > 40) throw new Error(`yahoo crumb ${r.status}`);
  return { cookie, crumb };
}

// deno-lint-ignore no-explicit-any
async function quotes(): Promise<any[]> {
  for (let attempt = 0; attempt < 2; attempt++) {
    if (!session) session = await newSession();
    const r = await fetch(`https://query2.finance.yahoo.com/v7/finance/quote?symbols=`
      + `${encodeURIComponent(SYMBOLS.map((x) => x.s).join(','))}&crumb=${encodeURIComponent(session.crumb)}`,
      { headers: { ...UA, Cookie: session.cookie }, signal: AbortSignal.timeout(10_000) });
    if (r.status === 401 || r.status === 403) { await r.body?.cancel(); session = null; continue; }
    if (!r.ok) throw new Error(`yahoo quote ${r.status}`);
    const j = await r.json();
    return j?.quoteResponse?.result ?? [];
  }
  throw new Error('yahoo refused twice');
}

const ts = (s?: number) => (s ? new Date(s * 1000).toISOString() : null);
const n = (v: unknown) => (typeof v === 'number' && isFinite(v) ? v : null);

function nyParts(d = new Date()) {
  const p = Object.fromEntries(new Intl.DateTimeFormat('en-US', {
    timeZone: 'America/New_York', weekday: 'short', hour: '2-digit', minute: '2-digit',
    year: 'numeric', month: '2-digit', day: '2-digit', hourCycle: 'h23',
  }).formatToParts(d).map((x) => [x.type, x.value]));
  return { wd: p.weekday, mins: Number(p.hour) * 60 + Number(p.minute), date: `${p.year}-${p.month}-${p.day}` };
}

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
  const url = Deno.env.get('SUPABASE_URL')!;
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const h = { apikey: key, Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' };
  const upsert = async (table: string, conflict: string, rows: unknown[]) => {
    if (!rows.length) return;
    const r = await fetch(`${url}/rest/v1/${table}?on_conflict=${conflict}`, {
      method: 'POST', headers: { ...h, Prefer: 'resolution=merge-duplicates,return=minimal' },
      body: JSON.stringify(rows),
    });
    if (!r.ok) throw new Error(`${table} ${r.status} ${(await r.text()).slice(0, 200)}`);
  };
  let body: { force?: boolean; backfill?: boolean } = {};
  try { if (req.method === 'POST') body = await req.json(); } catch { /* no body is fine */ }

  try {
    if (body.backfill) {
      const out: Record<string, number> = {};
      for (const s of CLOSES_HERE) {
        const r = await fetch(`https://query2.finance.yahoo.com/v8/finance/chart/${encodeURIComponent(s)}`
          + `?range=3mo&interval=1d`, { headers: UA });
        if (!r.ok) { out[s] = -r.status; await r.body?.cancel(); continue; }
        const res = (await r.json())?.chart?.result?.[0];
        const t: number[] = res?.timestamp ?? [];
        const c: (number | null)[] = res?.indicators?.quote?.[0]?.close ?? [];
        const rows = t.map((x, i) => ({ ticker: s, date: nyParts(new Date(x * 1000)).date, close_price: c[i] }))
          .filter((x) => x.close_price != null);
        await upsert('daily_closes', 'ticker,date', rows);
        out[s] = rows.length;
      }
      return new Response(JSON.stringify({ ok: true, build: BUILD, backfill: out }),
        { headers: { 'Content-Type': 'application/json' } });
    }

    const ny = nyParts();
    const weekday = !['Sat', 'Sun'].includes(ny.wd);
    if (!body.force && !(weekday && ny.mins >= 4 * 60 && ny.mins < 20 * 60)) {
      return new Response(JSON.stringify({ ok: true, build: BUILD, skipped: 'outside 4:00-20:00 ET weekdays' }),
        { headers: { 'Content-Type': 'application/json' } });
    }

    const passes: Record<string, unknown>[] = [];
    for (let pass = 0; pass < 2; pass++) {
      if (pass === 1) await new Promise((r) => setTimeout(r, 30_000 - (Date.now() % 30_000)));
      const t0 = Date.now();
      const res = await quotes();
      const now = new Date().toISOString();
      const rows = SYMBOLS.map((x) => {
        const q = res.find((r) => r.symbol === x.s);
        if (!q || n(q.regularMarketPrice) == null) return null;
        const state = String(q.marketState ?? '');
        const pre = n(q.preMarketPrice), post = n(q.postMarketPrice);
        /* The figure a card shows: the session it is in, or the last one. */
        const price = state.startsWith('PRE') && pre != null ? pre
          : state.startsWith('POST') && post != null ? post : n(q.regularMarketPrice);
        return {
          symbol: x.s, label: x.label, kind: x.kind, market_state: state || null,
          price, prev_close: n(q.regularMarketPreviousClose),
          regular_price: n(q.regularMarketPrice), regular_change: n(q.regularMarketChange),
          regular_change_pct: n(q.regularMarketChangePercent),
          pre_price: pre, pre_change_pct: n(q.preMarketChangePercent),
          post_price: post, post_change_pct: n(q.postMarketChangePercent),
          regular_time: ts(q.regularMarketTime),
          ext_time: ts(state.startsWith('PRE') ? q.preMarketTime : q.postMarketTime),
          captured_at: now,
        };
      }).filter(Boolean) as Record<string, unknown>[];
      await upsert('market_live', 'symbol', rows);

      /* After the US close, today's regular close is final: keep it. */
      if (ny.mins >= 16 * 60 + 5) {
        const closes = rows
          .filter((r) => CLOSES_HERE.includes(String(r.symbol)) && r.regular_time
            && nyParts(new Date(String(r.regular_time))).date === ny.date)
          .map((r) => ({ ticker: r.symbol, date: ny.date, close_price: r.regular_price }));
        await upsert('daily_closes', 'ticker,date', closes);
      }
      passes.push({ pass, symbols: rows.length, ms: Date.now() - t0 });
    }

    await upsert('sync_heartbeat', 'feed', [{
      feed: 'market-tape', ran_at: new Date().toISOString(), rows_written: Number(passes.at(-1)?.symbols ?? 0),
      detail: `yahoo · ${passes.map((p) => p.symbols).join('/')} symbols`,
    }]);
    return new Response(JSON.stringify({ ok: true, build: BUILD, passes }),
      { headers: { 'Content-Type': 'application/json' } });
  } catch (e) {
    return new Response(JSON.stringify({ ok: false, build: BUILD, error: String(e) }),
      { status: 500, headers: { 'Content-Type': 'application/json' } });
  }
});
