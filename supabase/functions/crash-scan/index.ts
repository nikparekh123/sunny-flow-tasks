/**
 * crash-scan — the daily crash scanner (Nik, 18 Oct 2026; research/crash-scan/).
 *
 *   scan  (about 4:15-5:30 PM New York): Polygon grouped daily bars, split-adjusted, for the session and
 *         the one before. Any crash_universe stock that closed 15%+ lower becomes a crash_events row and a
 *         heads-up push ('crash'). Also marks `taken` on recent events from option_trades (puts sold on
 *         that name on day 2).
 *   day2  (about 3:25-3:50 PM New York, the session after the crash): the A+B trade as tested: sell puts
 *         2% out (highest strike at or below), nearest expiry at least 3 days out, about $100K of strike
 *         (floor(100,000 / (strike x 100)), at least 1), live bid/ask from Theta's option snapshot.
 *         At most 5 crash trades open (taken in the last 28 days): past that the push says so.
 *         Push 'crash_trade'.
 *
 * Body: { mode?: 'auto' | 'scan' | 'day2', date?: 'YYYY-MM-DD' (scan a past session), dry?: true (write nothing),
 *         ticker?: 'NKE' (day2 dry run for one name) }. The cron sends nothing: 'auto' picks by New York time.
 * Backtest (247 crashes, 2024-26): the trade averaged +1.2% a crash at the bid, 7 in 10 made money.
 */
const BUILD = '2026-10-18.2';
const DROP = -0.15, OTM = 0.02, PER_TRADE = 100_000, MAX_OPEN = 5;
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
const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const DOW = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
const short = (iso: string) => `${MON[Number(iso.slice(5, 7)) - 1]} ${Number(iso.slice(8, 10))}`;
const money = (v: number) => `$${v >= 1000 ? Math.round(v).toLocaleString('en-US') : v.toFixed(2)}`;

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

async function grouped(date: string): Promise<Map<string, number>> {
  const r = await fetch(`https://api.polygon.io/v2/aggs/grouped/locale/us/market/stocks/${date}?adjusted=true&apiKey=${POLY}`);
  if (!r.ok) throw new Error(`polygon grouped ${date}: ${r.status}`);
  const j = await r.json();
  return new Map(((j.results ?? []) as Row[]).filter((x) => x.T && x.c).map((x) => [String(x.T), Number(x.c)]));
}

async function scan(date: string, dry: boolean, closed: Set<string>) {
  if (!isTrading(date, closed)) return { date, skipped: 'not a trading day' };
  let prev = addDays(date, -1);
  while (!isTrading(prev, closed)) prev = addDays(prev, -1);
  const [today, before] = await Promise.all([grouped(date), grouped(prev)]);
  if (today.size < 1000) return { date, waiting: `Polygon has ${today.size} bars for ${date} so far` };
  const uni = (await get('crash_universe?select=ticker')).map((r) => String(r.ticker));
  let entry = addDays(date, 1);
  while (!isTrading(entry, closed)) entry = addDays(entry, 1);
  const found = uni.filter((t) => today.has(t) && before.has(t)).map((t) => ({
    ticker: t, day: date, prev_close: before.get(t)!, close: today.get(t)!,
    drop_pct: Math.round((today.get(t)! / before.get(t)! - 1) * 10000) / 100, entry_day: entry,
  })).filter((e) => e.drop_pct <= DROP * 100).sort((a, b) => a.drop_pct - b.drop_pct);
  let fresh: Row[] = found;
  if (!dry && found.length) {
    fresh = await send('POST', 'crash_events?on_conflict=ticker,day', found, 'resolution=ignore-duplicates,return=representation');
    if (fresh.length) await send('POST', 'alert_dispatch?on_conflict=dedup_key', fresh.map((e) => ({
      category: 'crash', dedup_key: `crash|${e.ticker}|${e.day}`, ticker: e.ticker, book_id: 'S',
      title: `${e.ticker} fell ${Math.abs(Number(e.drop_pct)).toFixed(1)}% today`,
      body: `Closed at ${money(Number(e.close))}, from ${money(Number(e.prev_close))}. Day 2 is ${DOW[new Date(e.entry_day + 'T12:00:00Z').getUTCDay()]}: the trade comes at 3:30 PM.`,
      meta: { drop_pct: e.drop_pct, entry_day: e.entry_day },
    })), 'resolution=ignore-duplicates,return=minimal');
  }
  /* Taken: puts sold on the name on its day 2 (IBKR trades in option_trades). */
  let marked = 0;
  if (!dry) {
    for (const e of await get(`crash_events?entry_day=gte.${addDays(date, -7)}&entry_day=lte.${date}&or=(taken.is.null,taken.eq.false)&select=id,ticker,entry_day`)) {
      const t = await get(`option_trades?ticker=ilike.${e.ticker}&option_type=eq.put&direction=eq.short&action=eq.open&trade_date=eq.${e.entry_day}&voided_at=is.null&select=id&limit=1`);
      if (t.length) { await send('PATCH', `crash_events?id=eq.${e.id}`, { taken: true }); marked++; }
    }
  }
  return { date, previous: prev, entry_day: entry, crashes: found.map((e) => `${e.ticker} ${e.drop_pct}%`), new: fresh.length, taken_marked: marked };
}

/* Option quotes from Theta (live snapshot, as chain-next's Planner reads): our Polygon plan has stocks,
   not options (its options snapshot answers 403). The spot is what the chain's own quotes imply
   (call - put + strike where they are closest), Polygon's last trade as the fallback. */
const THETA_URL = Deno.env.get('THETA_URL') ?? '', THETA_KEY = Deno.env.get('THETA_PROXY_KEY') ?? '';
async function theta(path: string): Promise<Row[]> {
  const r = await fetch(`${THETA_URL}${path}&format=json`, { headers: { 'x-proxy-key': THETA_KEY }, signal: AbortSignal.timeout(15_000) });
  if (!r.ok) return [];
  return ((await r.json())?.response ?? []) as Row[];
}
function impliedSpot(rows: Array<{ side: string; k: number; bid: number; ask: number }>, T: number): number | null {
  const by = new Map<number, { c?: number; p?: number }>();
  for (const r of rows) {
    if (!(r.bid > 0 && r.ask > 0)) continue;
    const e = by.get(r.k) ?? {}; e[r.side === 'call' ? 'c' : 'p'] = (r.bid + r.ask) / 2; by.set(r.k, e);
  }
  let best: number | null = null, gap = Infinity;
  for (const [k, e] of by) {
    if (e.c == null || e.p == null) continue;
    if (Math.abs(e.c - e.p) < gap) { gap = Math.abs(e.c - e.p); best = e.c - e.p + k * Math.exp(-0.04 * T); }
  }
  return best;
}
async function polygonSpot(ticker: string): Promise<number> {
  const r = await fetch(`https://api.polygon.io/v2/snapshot/locale/us/markets/stocks/tickers/${ticker}?apiKey=${POLY}`);
  if (!r.ok) return 0;
  const t = (await r.json())?.ticker ?? {};
  return Number(t.lastTrade?.p ?? t.min?.c ?? t.day?.c ?? 0);
}

async function tradeFor(ticker: string, today: string) {
  const exps = (await theta(`/v3/option/list/expirations?symbol=${ticker}`)).map((x) => String(x.expiration))
    .map((e) => (e.includes('-') ? e : `${e.slice(0, 4)}-${e.slice(4, 6)}-${e.slice(6)}`)).filter((e) => e >= addDays(today, 3)).sort();
  if (!exps.length) return { error: 'no expiry 3+ days out' };
  const expiry = exps[0], T = Math.max(1, (Date.parse(expiry) - Date.parse(today)) / 864e5) / 365;
  const rows = (await theta(`/v3/option/snapshot/quote?symbol=${ticker}&expiration=${expiry.replaceAll('-', '')}`))
    .filter((r) => r.data?.[0]).map((r) => ({ side: String(r.contract.right).toLowerCase(), k: Number(r.contract.strike),
      bid: Number(r.data[0].bid), ask: Number(r.data[0].ask) }));
  if (!rows.length) return { error: 'no option quotes', expiry };
  const spot = impliedSpot(rows, T) ?? await polygonSpot(ticker);
  if (!spot) return { error: 'no price', expiry };
  const pick = rows.filter((r) => r.side === 'put' && r.bid > 0 && r.ask > 0 && r.k <= spot * (1 - OTM)).sort((a, b) => b.k - a.k)[0];
  if (!pick) return { error: 'no strike 2% out', spot, expiry };
  const K = pick.k, bid = pick.bid, ask = pick.ask, mid = (bid + ask) / 2;
  const n = Math.max(1, Math.floor(PER_TRADE / (K * 100)));
  return { expiry, strike: K, pct_out: Math.round((1 - K / spot) * 1000) / 10, contracts: n, bid, ask, mid: Math.round(mid * 100) / 100,
           credit_mid: Math.round(mid * 100 * n), credit_bid: Math.round(bid * 100 * n), cash: Math.round(K * 100 * n),
           spot: Math.round(spot * 100) / 100, at: new Date().toISOString() };
}

async function day2(today: string, dry: boolean, closed: Set<string>, one?: string) {
  if (!isTrading(today, closed)) return { date: today, skipped: 'not a trading day' };
  const events = one ? [{ id: null, ticker: one, day: today }] :
    await get(`crash_events?entry_day=eq.${today}&suggestion=is.null&select=id,ticker,day,drop_pct`);
  const open = (await get(`crash_events?taken=eq.true&entry_day=gte.${addDays(today, -28)}&select=id`)).length;
  const done: Row[] = [];
  for (const e of events) {
    const s: Row = await tradeFor(String(e.ticker), today).catch((err) => ({ error: String(err).slice(0, 160) }));
    s.open_before = open; s.limit = open >= MAX_OPEN;
    done.push({ ticker: e.ticker, ...s });
    if (dry || !e.id) continue;
    await send('PATCH', `crash_events?id=eq.${e.id}`, { suggestion: s });
    if (s.error) continue;
    await send('POST', 'alert_dispatch?on_conflict=dedup_key', [{
      category: 'crash_trade', dedup_key: `crash_trade|${e.ticker}|${e.day}`, ticker: e.ticker, book_id: 'S',
      title: s.limit ? `${e.ticker} day 2: ${MAX_OPEN} crash trades already open` : `${e.ticker} day 2: sell ${s.contracts} × ${short(s.expiry)} ${money(s.strike)} puts`,
      body: s.limit ? `The rule says skip. If you take it: sell ${s.contracts} × ${short(s.expiry)} ${money(s.strike)} puts, ${s.pct_out}% out, bid ${money(s.bid)} / ask ${money(s.ask)}.`
        : `${s.pct_out}% out. Bid ${money(s.bid)} / ask ${money(s.ask)} / mid ${money(s.mid)}: about ${money(s.credit_mid)} credit, ${money(s.cash)} cash tied up. Past crashes: +1.2% a trade on average, 7 in 10 made money.`,
      meta: s,
    }], 'resolution=ignore-duplicates,return=minimal');
  }
  return { date: today, open, trades: done };
}

Deno.serve(async (req) => {
  if (!(await callerOk(req))) return new Response(JSON.stringify({ ok: false, error: 'not allowed' }), { status: 401 });
  if (!POLY) return new Response(JSON.stringify({ ok: false, error: 'POLYGON_API_KEY is not set' }), { status: 500 });
  let body: Row = {};
  try { body = await req.json(); } catch { /* cron sends nothing */ }
  const now = ny(); const date = body.date ?? now.date; const dry = !!body.dry;
  try {
    const closed = await closedDays(addDays(date, -10), addDays(date, 10));
    let mode = body.mode ?? 'auto';
    if (mode === 'auto') mode = now.mins >= 15 * 60 + 25 && now.mins <= 15 * 60 + 50 ? 'day2' : now.mins >= 16 * 60 + 15 && now.mins <= 17 * 60 + 30 ? 'scan' : 'idle';
    const out = mode === 'scan' ? await scan(date, dry, closed) : mode === 'day2' ? await day2(date, dry, closed, body.ticker) : { idle: `${now.date} ${Math.floor(now.mins / 60)}:${String(now.mins % 60).padStart(2, '0')} New York` };
    return new Response(JSON.stringify({ ok: true, build: BUILD, mode, dry, ...out }), { headers: { 'Content-Type': 'application/json' } });
  } catch (e) {
    return new Response(JSON.stringify({ ok: false, build: BUILD, error: String(e).slice(0, 300) }), { status: 500 });
  }
});
