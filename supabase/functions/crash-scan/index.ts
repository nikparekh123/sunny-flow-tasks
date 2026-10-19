/**
 * crash-scan — Aftershock, the daily crash scanner (Nik, 18-19 Oct 2026; handoff 26 blocks 26 and 03b;
 * research in research/crash-scan/).
 *
 *   scan   from 4:15 PM New York, every 5 minutes until done. Today's closes come from Theta (Nik, 19 Oct 2026:
 *          "use Theta data"): its 15-minute-delayed stock snapshot shows the 16:00 close from 4:15 PM; until the
 *          Theta stock plan is live on the proxy, Theta's end-of-day bar (published about 5:15 PM); Polygon's
 *          grouped bars last (our Polygon plan releases them only some time after the close: 403 until then).
 *          The prior close is Polygon's grouped bar for the previous session (split-adjusted). Any
 *          crash_universe name 15%+ below the prior close becomes a crash_events row; crash_scans records
 *          the scan; names whose Day 2 is today get their Day 2 close. One push on crash days:
 *          "Aftershock" / "2 crashes: ADBE 18.5%, DECK 16.7%", opening the Aftershock page. Also marks
 *          `taken` on recent events from option_trades (puts sold on the name on day 2), which tags the
 *          position Aftershock.
 *
 * No trade instructions anywhere (Nik, 19 Oct 2026: "no need for instruction on when to enter and how much").
 * Body: { mode?: 'auto' | 'scan', date?: 'YYYY-MM-DD' (scan a past session), dry?: true, silent?: true (no push),
 *         source?: 'theta-delayed' | 'theta-eod' | 'grouped' (force one source, for tests) }.
 * The cron sends nothing: 'auto' picks by New York time.
 */
const BUILD = '2026-10-19.5';
const THETA_URL = Deno.env.get('THETA_URL') ?? '';
const THETA_KEY = Deno.env.get('THETA_PROXY_KEY') ?? '';
const DROP = -0.15;
let SILENT = false;    // body.silent: seed past days without pushing
const URL_ = Deno.env.get('SUPABASE_URL')!;
const KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const POLY = Deno.env.get('POLYGON_API_KEY') ?? '';
const H = { apikey: KEY, Authorization: `Bearer ${KEY}`, 'Content-Type': 'application/json' };
type Row = Record<string, any>;

async function get(q: string): Promise<Row[]> {
  const r = await fetch(`${URL_}/rest/v1/${q}`, { headers: H });
  if (!r.ok) throw new Error(`${q.split('?')[0]}: ${r.status} ${(await r.text()).slice(0, 200)}`);
  return await r.json();
}
async function send(method: string, q: string, body: unknown, prefer = 'return=minimal'): Promise<Row[]> {
  const r = await fetch(`${URL_}/rest/v1/${q}`, { method, headers: { ...H, Prefer: prefer }, body: JSON.stringify(body) });
  if (!r.ok) throw new Error(`${method} ${q.split('?')[0]}: ${r.status} ${(await r.text()).slice(0, 200)}`);
  return prefer.includes('representation') ? await r.json() : [];
}
const ny = (d = new Date()) => {
  const p = Object.fromEntries(new Intl.DateTimeFormat('en-CA', { timeZone: 'America/New_York', year: 'numeric', month: '2-digit',
    day: '2-digit', hour: '2-digit', minute: '2-digit', hour12: false }).formatToParts(d).map((x) => [x.type, x.value]));
  return { date: `${p.year}-${p.month}-${p.day}`, mins: Number(p.hour) % 24 * 60 + Number(p.minute) };
};
const addDays = (iso: string, n: number) => new Date(Date.parse(iso + 'T12:00:00Z') + n * 864e5).toISOString().slice(0, 10);
const pct = (v: number) => `${Math.abs(v).toFixed(1)}%`;

async function callerOk(req: Request): Promise<boolean> {
  const cron = Deno.env.get('CRON_SECRET');
  if (cron && (req.headers.get('x-cron-key') === cron || req.headers.get('x-admin-key') === cron)) return true;
  return (req.headers.get('authorization') ?? '') === `Bearer ${KEY}`;
}
async function closedDays(from: string, to: string): Promise<Set<string>> {
  const rows = await get(`market_calendar?kind=eq.closed&date=gte.${from}&date=lte.${to}&select=date`);
  return new Set(rows.map((r) => String(r.date)));
}
const isTrading = (d: string, closed: Set<string>) => { const w = new Date(d + 'T12:00:00Z').getUTCDay(); return w !== 0 && w !== 6 && !closed.has(d); };
const stepDay = (d: string, dir: 1 | -1, closed: Set<string>) => { let x = addDays(d, dir); while (!isTrading(x, closed)) x = addDays(x, dir); return x; };

async function grouped(date: string): Promise<Map<string, number>> {
  const r = await fetch(`https://api.polygon.io/v2/aggs/grouped/locale/us/market/stocks/${date}?adjusted=true&apiKey=${POLY}`);
  if (!r.ok) throw new Error(`polygon grouped ${date}: ${r.status}`);
  return new Map((((await r.json()).results ?? []) as Row[]).filter((x) => x.T && x.c).map((x) => [String(x.T), Number(x.c)]));
}
async function groupedOrEmpty(date: string): Promise<Map<string, number>> {
  try { return await grouped(date); } catch { return new Map(); }
}

/** One Theta row per name, 12 at a time (Theta takes one symbol per request). */
async function thetaEach(uni: string[], path: (t: string) => string, pick: (rows: Row[]) => number | null): Promise<Map<string, number>> {
  const out = new Map<string, number>(); let i = 0;
  const worker = async () => {
    while (i < uni.length) {
      const t = uni[i++];
      try {
        const r = await fetch(`${THETA_URL}${path(t)}&format=json`, { headers: { 'x-proxy-key': THETA_KEY }, signal: AbortSignal.timeout(15_000) });
        if (!r.ok) { await r.body?.cancel(); continue; }
        const txt = await r.text();
        if (!txt.startsWith('{')) continue;               // "No data found", plan refusals: plain text
        const v = pick((JSON.parse(txt)?.response ?? []) as Row[]);
        if (v && v > 0) out.set(t, v);
      } catch { /* one name missing is fine */ }
    }
  };
  await Promise.all(Array.from({ length: 12 }, worker));
  return out;
}
const flat = (x: Row) => (x?.data?.[0] ?? x) as Row;
const stamp = (x: Row) => String(x.created ?? x.timestamp ?? x.date ?? '');
/** Today's 16:00 close from Theta's 15-minute-delayed snapshot (stock plan): only a print stamped today at or after 16:00. */
async function thetaSnapshot(uni: string[], date: string) {
  return thetaEach(uni, (t) => `/v3/stock/snapshot/ohlc?symbol=${encodeURIComponent(t)}`, (rows) => {
    const x = flat(rows[0] ?? {}); const st = stamp(x);
    return st.slice(0, 10) === date && st.slice(11, 16) >= '16:00' ? Number(x.close) : null;
  });
}
/** The session's end-of-day bar from Theta (published about 5:15 PM New York; free on our plan). */
async function thetaEod(uni: string[], date: string) {
  const d = date.replaceAll('-', '');
  return thetaEach(uni, (t) => `/v3/stock/history/eod?symbol=${encodeURIComponent(t)}&start_date=${d}&end_date=${d}`, (rows) => {
    const x = rows.map(flat).find((y) => stamp(y).slice(0, 10) === date);
    return x ? Number(x.close) : null;
  });
}

async function push(date: string, crashes: Row[], dry: boolean) {
  if (dry || SILENT || !crashes.length) return;
  const list = [...crashes].sort((a, b) => Number(a.drop_pct) - Number(b.drop_pct));
  await send('POST', 'alert_dispatch?on_conflict=dedup_key', [{
    category: 'aftershock', dedup_key: `aftershock|${date}`, book_id: 'S', ticker: list[0].ticker,
    title: 'Aftershock',
    body: `${list.length} crash${list.length === 1 ? '' : 'es'}: ${list.map((e) => `${e.ticker} ${pct(Number(e.drop_pct))}`).join(', ')}`,
    deep_link: 'sunny://aftershock', meta: { day: date, tickers: list.map((e) => e.ticker) },
  }], 'resolution=ignore-duplicates,return=minimal');
}

/** Settle Day 2: names whose Day 2 is `date` get that close and their move since the crash close. */
async function day2(date: string, closeOf: (t: string) => number | undefined, dry: boolean) {
  const due = await get(`crash_events?entry_day=eq.${date}&select=id,ticker,close`);
  const done: string[] = [];
  for (const e of due) {
    const c = closeOf(String(e.ticker));
    if (!c) continue;
    const p = Math.round((c / Number(e.close) - 1) * 10000) / 100;
    done.push(`${e.ticker} ${p}%`);
    if (!dry) await send('PATCH', `crash_events?id=eq.${e.id}`, { day2_close: c, day2_pct: p });
  }
  return done;
}

let srcPick: string | null = null;    // body.source: force one source (tests)
async function scan(date: string, dry: boolean, closed: Set<string>) {
  if (!isTrading(date, closed)) return { date, skipped: 'not a trading day' };
  const have = (await get(`crash_scans?day=eq.${date}&select=source,crashes`))[0];
  if (have && !dry) return { date, skipped: 'already scanned' };
  const prev = stepDay(date, -1, closed);
  const uni = (await get('crash_universe?select=ticker')).map((r) => String(r.ticker));
  // Today's closes: Theta's delayed snapshot, else Theta's end-of-day bar, else Polygon. Enough = 90% of the names.
  const enough = (m: Map<string, number>) => uni.filter((t) => m.has(t)).length >= uni.length * 0.9;
  let today = new Map<string, number>(); let source = '';
  const want = String(srcPick ?? '');
  // Two big names first, so a source that has nothing yet costs 2 requests, not 516.
  const has = async (fn: (u: string[], d: string) => Promise<Map<string, number>>) => (await fn(['AAPL', 'MSFT'], date)).size > 0;
  const theta = !!THETA_URL && !!THETA_KEY;
  if (theta && (!want || want === 'theta-delayed') && date === ny().date && await has(thetaSnapshot)) {
    today = await thetaSnapshot(uni, date); source = 'theta-delayed';
  }
  if (!enough(today) && theta && (!want || want === 'theta-eod') && await has(thetaEod)) { today = await thetaEod(uni, date); source = 'theta-eod'; }
  if (!enough(today) && (!want || want === 'grouped')) { today = await groupedOrEmpty(date); source = 'grouped'; }
  if (!enough(today)) return { date, waiting: `closes for ${date} not out yet (Theta delayed, Theta end of day, Polygon)` };
  let before = await groupedOrEmpty(prev);
  if (!enough(before) && THETA_URL && THETA_KEY) before = await thetaEod(uni, prev);
  if (!enough(before)) return { date, waiting: `prior closes for ${prev} missing` };
  const entry = stepDay(date, 1, closed);
  const rows = uni.filter((t) => today.has(t) && before.has(t)).map((t) => ({
    ticker: t, day: date, prev_close: before.get(t)!, close: today.get(t)!,
    drop_pct: Math.round((today.get(t)! / before.get(t)! - 1) * 10000) / 100, entry_day: entry,
  }));
  const crashes = rows.filter((e) => e.drop_pct <= DROP * 100);
  const known = new Set((await get(`crash_events?day=eq.${date}&select=ticker`)).map((r) => String(r.ticker)));
  const added = crashes.filter((e) => !known.has(e.ticker));
  if (!dry) {
    for (const e of crashes.filter((x) => known.has(x.ticker))) {
      await send('PATCH', `crash_events?ticker=eq.${e.ticker}&day=eq.${date}`, { prev_close: e.prev_close, close: e.close, drop_pct: e.drop_pct });
    }
    if (added.length) await send('POST', 'crash_events?on_conflict=ticker,day', added, 'resolution=ignore-duplicates,return=minimal');
    await send('POST', 'crash_scans?on_conflict=day', [{ day: date, scanned_at: new Date().toISOString(), universe: uni.length,
      crashes: known.size + added.length, source, updated_at: new Date().toISOString() }], 'resolution=merge-duplicates,return=minimal');
  }
  await push(date, crashes, dry);
  const d2 = await day2(date, (t) => today.get(t), dry);
  let marked = 0;
  if (!dry) {
    for (const e of await get(`crash_events?entry_day=gte.${addDays(date, -7)}&entry_day=lte.${date}&or=(taken.is.null,taken.eq.false)&select=id,ticker,entry_day`)) {
      const t = await get(`option_trades?ticker=ilike.${e.ticker}&option_type=eq.put&direction=eq.short&action=eq.open&trade_date=eq.${e.entry_day}&voided_at=is.null&select=id&limit=1`);
      if (t.length) { await send('PATCH', `crash_events?id=eq.${e.id}`, { taken: true }); marked++; }
    }
  }
  return { date, previous: prev, source, names: uni.filter((t) => today.has(t) && before.has(t)).length, crashes: crashes.map((e) => `${e.ticker} ${e.drop_pct}%`), added: added.length, day2: d2, taken_marked: marked };
}

Deno.serve(async (req) => {
  if (!(await callerOk(req))) return new Response(JSON.stringify({ ok: false, error: 'not allowed' }), { status: 401 });
  if (!POLY) return new Response(JSON.stringify({ ok: false, error: 'POLYGON_API_KEY is not set' }), { status: 500 });
  let body: Row = {};
  try { body = await req.json(); } catch { /* cron sends nothing */ }
  const now = ny(); const date = body.date ?? now.date; const dry = !!body.dry; SILENT = !!body.silent; srcPick = body.source ?? null;
  try {
    const closed = await closedDays(addDays(date, -10), addDays(date, 10));
    let mode = body.mode ?? 'auto';
    if (mode === 'auto') mode = now.mins >= 16 * 60 + 15 && now.mins <= 19 * 60 ? 'scan' : 'idle';
    // A missed session (no closes came in its evening) is scanned first, quietly: its crashes are Day 2 today.
    let catchup: Row | null = null;
    if (mode === 'scan' && !body.date) {
      const last = stepDay(date, -1, closed);
      if (!(await get(`crash_scans?day=eq.${last}&select=day`)).length) {
        const keep = SILENT; SILENT = true; catchup = await scan(last, dry, closed); SILENT = keep;
      }
    }
    const out = mode === 'scan' ? { ...(await scan(date, dry, closed)), ...(catchup ? { catchup } : {}) }
      : { idle: `${now.date} ${Math.floor(now.mins / 60)}:${String(now.mins % 60).padStart(2, '0')} New York` };
    return new Response(JSON.stringify({ ok: true, build: BUILD, mode, dry, ...out }), { headers: { 'Content-Type': 'application/json' } });
  } catch (e) {
    return new Response(JSON.stringify({ ok: false, build: BUILD, error: String(e).slice(0, 300) }), { status: 500 });
  }
});
