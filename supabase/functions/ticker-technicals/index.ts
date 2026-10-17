/**
 * ticker-technicals — the Planner's inputs for next week's calls (Nik, 16 Oct 2026).
 *
 * Nik's five questions (memory: planner five questions): is selling worth it,
 * where is the price likely by Friday, what is coming up, where are the walls,
 * how much room is there. This job answers the first, second and fourth from
 * data we already have, for ONE name until Nik has looked at it (TICKERS).
 *
 *   ticker_technicals  one row a trading day: SMA 20/50/200, EMA 20/50, RSI 14
 *                      (Wilder), 5- and 21-day change, realised volatility 20/30,
 *                      the ~30-day ATM IV (ticker_iv_daily), IV rank and
 *                      percentile over the last year, richness = IV / HV20.
 *   ticker_walls       replaced each run: turning points (daily highs and lows
 *                      that held 5 sessions either side, last 6 months, merged
 *                      within 1.5%, strength = touches), the moving-average
 *                      lines, the open-interest walls on the next two Fridays
 *                      (option_chain_next), and Nik's own levels (ticker_levels).
 *
 * Bars: Polygon daily aggregates (OHLCV, adjusted). In the session the last row
 * uses the live price as today's close, so a 15-minute run reads live.
 * Run by pg_cron: every 15 minutes in market hours and once after the close.
 */

const BUILD = '2026-10-16.1';
/* ⚠ ONE NAME FOR NOW (Nik, 16 Oct 2026: "do this only for one ticker for now
   to test it"). Widen to the book and the watchlist once he has seen NKE. */
const TICKERS = ['NKE'];
const KEEP_DAYS = 260;          // rows written each run (a year of trading days)
const PIVOT = 5;                // a turning point beats 5 sessions either side
const SWING_LOOKBACK = 126;     // about 6 months of sessions
const MERGE_PCT = 1.5;          // turning points within 1.5% are one wall

const URL_ = Deno.env.get('SUPABASE_URL')!;
const KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const H = { apikey: KEY, Authorization: `Bearer ${KEY}`, 'Content-Type': 'application/json' };
type Row = Record<string, unknown>;

async function get(q: string): Promise<Row[]> {
  const r = await fetch(`${URL_}/rest/v1/${q}`, { headers: H });
  if (!r.ok) throw new Error(`${q.split('?')[0]}: ${r.status} ${(await r.text()).slice(0, 200)}`);
  return await r.json();
}
async function send(method: string, q: string, body?: unknown, prefer = 'return=minimal') {
  const r = await fetch(`${URL_}/rest/v1/${q}`, { method, headers: { ...H, Prefer: prefer }, body: body ? JSON.stringify(body) : undefined });
  if (!r.ok) throw new Error(`${method} ${q.split('?')[0]}: ${r.status} ${(await r.text()).slice(0, 200)}`);
}

const nyDate = (d = new Date()) => d.toLocaleDateString('en-CA', { timeZone: 'America/New_York' });
const r4 = (v: number | null) => (v == null || !Number.isFinite(v) ? null : Math.round(v * 10000) / 10000);

/* ── indicators over a close series, one value per day (null until enough data) ── */
function sma(c: number[], n: number): (number | null)[] {
  let s = 0; return c.map((v, i) => { s += v; if (i >= n) s -= c[i - n]; return i >= n - 1 ? s / n : null; });
}
function ema(c: number[], n: number): (number | null)[] {
  const k = 2 / (n + 1); let e: number | null = null;
  return c.map((v, i) => {
    if (i < n - 1) return null;
    e = e == null ? c.slice(0, n).reduce((a, b) => a + b, 0) / n : v * k + e * (1 - k);
    return e;
  });
}
function rsi(c: number[], n = 14): (number | null)[] {
  let g = 0, l = 0;
  return c.map((v, i) => {
    if (i === 0) return null;
    const ch = v - c[i - 1], up = Math.max(0, ch), dn = Math.max(0, -ch);
    if (i <= n) { g += up / n; l += dn / n; if (i < n) return null; }
    else { g = (g * (n - 1) + up) / n; l = (l * (n - 1) + dn) / n; }
    return l === 0 ? 100 : 100 - 100 / (1 + g / l);
  });
}
function hv(c: number[], n: number): (number | null)[] {
  return c.map((_, i) => {
    if (i < n) return null;
    const r = []; for (let j = i - n + 1; j <= i; j++) r.push(Math.log(c[j] / c[j - 1]));
    const m = r.reduce((a, b) => a + b, 0) / r.length;
    return Math.sqrt(r.reduce((a, b) => a + (b - m) ** 2, 0) / (r.length - 1) * 252);
  });
}
const chg = (c: number[], n: number) => c.map((v, i) => (i >= n ? (v / c[i - n] - 1) * 100 : null));

/* ── walls from turning points: a daily high (low) that beat PIVOT sessions on
   either side, last SWING_LOOKBACK sessions, merged when within MERGE_PCT ── */
function turningPoints(hi: number[], lo: number[], days: string[]) {
  const from = Math.max(PIVOT, hi.length - SWING_LOOKBACK), to = hi.length - PIVOT;
  const pts: { kind: 'swing_high' | 'swing_low'; p: number; d: string }[] = [];
  for (let i = from; i < to; i++) {
    const wH = hi.slice(i - PIVOT, i + PIVOT + 1), wL = lo.slice(i - PIVOT, i + PIVOT + 1);
    if (hi[i] === Math.max(...wH)) pts.push({ kind: 'swing_high', p: hi[i], d: days[i] });
    if (lo[i] === Math.min(...wL)) pts.push({ kind: 'swing_low', p: lo[i], d: days[i] });
  }
  pts.sort((a, b) => a.p - b.p);
  const groups: typeof pts[] = [];
  for (const x of pts) {
    const g = groups.at(-1);
    const mean = g ? g.reduce((s, y) => s + y.p, 0) / g.length : 0;
    if (g && Math.abs(x.p - mean) / mean * 100 <= MERGE_PCT) g.push(x); else groups.push([x]);
  }
  return groups.map((g) => ({
    price: g.reduce((s, y) => s + y.p, 0) / g.length, touches: g.length,
    last: g.map((y) => y.d).sort().at(-1)!, highs: g.filter((y) => y.kind === 'swing_high').length,
  }));
}

/* ⚠ WHO MAY CALL: the scheduler (x-cron-key), the service role, or an admin call. */
async function callerOk(req: Request): Promise<boolean> {
  const cron = Deno.env.get('CRON_SECRET');
  if (cron && (req.headers.get('x-cron-key') === cron || req.headers.get('x-admin-key') === cron)) return true;
  return (req.headers.get('authorization') ?? '') === `Bearer ${KEY}`;
}

Deno.serve(async (req) => {
  if (!(await callerOk(req))) return new Response(JSON.stringify({ ok: false, error: 'not allowed' }), { status: 401 });
  const poly = Deno.env.get('POLYGON_API_KEY');
  if (!poly) return new Response(JSON.stringify({ ok: false, error: 'POLYGON_API_KEY is not set' }), { status: 500 });
  const today = nyDate();
  const out: Row[] = [];
  for (const t of TICKERS) {
    try {
      const from = nyDate(new Date(Date.now() - 2 * 365 * 864e5));
      const r = await fetch(`https://api.polygon.io/v2/aggs/ticker/${t}/range/1/day/${from}/${today}?adjusted=true&sort=asc&limit=50000&apiKey=${poly}`);
      if (!r.ok) throw new Error(`polygon ${r.status}`);
      const bars = ((await r.json()).results ?? []) as { t: number; o: number; h: number; l: number; c: number; v: number }[];
      if (bars.length < 210) throw new Error(`only ${bars.length} bars`);
      const days = bars.map((b) => nyDate(new Date(b.t)));
      const close = bars.map((b) => b.c), high = bars.map((b) => b.h), low = bars.map((b) => b.l);
      /* In the session, today's row reads the live price (ticker_quotes_live). */
      const live = (await get(`ticker_quotes_live?ticker=eq.${t}&select=spot,captured_at`))[0];
      const spot = live?.spot != null ? Number(live.spot) : null;
      if (spot && String(live.captured_at).slice(0, 10) >= today.slice(0, 10)) {
        if (days.at(-1) === today) { close[close.length - 1] = spot; high[high.length - 1] = Math.max(high.at(-1)!, spot); low[low.length - 1] = Math.min(low.at(-1)!, spot); }
        else if (days.at(-1)! < today) { days.push(today); close.push(spot); high.push(spot); low.push(spot); }
      }
      const s20 = sma(close, 20), s50 = sma(close, 50), s200 = sma(close, 200), e20 = ema(close, 20), e50 = ema(close, 50);
      const rs = rsi(close), h20 = hv(close, 20), h30 = hv(close, 30), c5 = chg(close, 5), c21 = chg(close, 21);
      const ivRows = await get(`ticker_iv_daily?ticker=eq.${t}&select=snapshot_date,atm_iv&order=snapshot_date.asc`);
      const ivBy = new Map(ivRows.map((x) => [String(x.snapshot_date), Number(x.atm_iv)]));
      const ivSeries = days.map((d) => ivBy.get(d) ?? null);
      const rows: Row[] = [];
      for (let i = Math.max(0, days.length - KEEP_DAYS); i < days.length; i++) {
        const iv = ivSeries[i];
        /* IV rank and percentile over the trailing year of stored IV (needs 120+ days). */
        const yr = ivSeries.slice(Math.max(0, i - 251), i + 1).filter((x): x is number => x != null);
        const rank = iv != null && yr.length >= 120 && Math.max(...yr) > Math.min(...yr)
          ? (iv - Math.min(...yr)) / (Math.max(...yr) - Math.min(...yr)) * 100 : null;
        const pct = iv != null && yr.length >= 120 ? yr.filter((x) => x < iv).length / yr.length * 100 : null;
        rows.push({ ticker: t, day: days[i], close: r4(close[i]), sma20: r4(s20[i]), sma50: r4(s50[i]), sma200: r4(s200[i]),
          ema20: r4(e20[i]), ema50: r4(e50[i]), rsi14: r4(rs[i]), chg5_pct: r4(c5[i]), chg21_pct: r4(c21[i]),
          hv20: r4(h20[i]), hv30: r4(h30[i]), atm_iv: r4(iv), iv_rank: r4(rank), iv_pctile: r4(pct),
          richness: r4(iv != null && h20[i] ? iv / h20[i]! : null), updated_at: new Date().toISOString() });
      }
      await send('POST', 'ticker_technicals?on_conflict=ticker,day', rows, 'resolution=merge-duplicates,return=minimal');

      /* ── walls ── */
      const px = close.at(-1)!, n = close.length - 1;
      const walls: Row[] = [];
      const tp = turningPoints(high, low, days);
      const above = tp.filter((w) => w.price > px).sort((a, b) => a.price - b.price).slice(0, 3);
      const below = tp.filter((w) => w.price < px).sort((a, b) => b.price - a.price).slice(0, 3);
      for (const w of [...above, ...below]) {
        walls.push({ ticker: t, kind: w.price > px ? 'swing_high' : 'swing_low', price: r4(w.price), strength: w.touches,
          note: `${w.touches} touch${w.touches === 1 ? '' : 'es'}, last ${w.last}` });
      }
      for (const [kind, v] of [['sma50', s50[n]], ['sma200', s200[n]], ['ema20', e20[n]], ['ema50', e50[n]]] as const) {
        if (v != null) walls.push({ ticker: t, kind, price: r4(v), note: v > px ? 'above the price' : 'below the price' });
      }
      const chain = await get(`option_chain_next?ticker=eq.${t}&select=expiry,side,strike,oi&order=expiry.asc`);
      /* The next two Fridays after today (a Friday's own expiry is done: next-week basis). */
      for (const ex of [...new Set(chain.map((c) => String(c.expiry)))].filter((e) => e > today).sort().slice(0, 2)) {
        const top = (side: string, keep: (k: number) => boolean) => chain
          .filter((c) => String(c.expiry) === ex && c.side === side && Number(c.oi) > 0 && keep(Number(c.strike)))
          .sort((a, b) => Number(b.oi) - Number(a.oi))[0];
        const c = top('call', (k) => k > px), p = top('put', (k) => k < px);
        if (c) walls.push({ ticker: t, kind: 'oi_call', price: Number(c.strike), strength: Number(c.oi), expiry: ex, note: `${c.oi} calls open` });
        if (p) walls.push({ ticker: t, kind: 'oi_put', price: Number(p.strike), strength: Number(p.oi), expiry: ex, note: `${p.oi} puts open` });
      }
      for (const m of await get(`ticker_levels?ticker=eq.${t}&select=kind,price,note`)) {
        walls.push({ ticker: t, kind: 'manual', price: Number(m.price), note: [m.kind, m.note].filter(Boolean).join(' · ') || null });
      }
      await send('DELETE', `ticker_walls?ticker=eq.${t}`);
      if (walls.length) await send('POST', 'ticker_walls', walls.map((w) => ({ strength: null, expiry: null, note: null, ...w })));
      const last = rows.at(-1)!;
      out.push({ ticker: t, day: last.day, close: last.close, rsi14: last.rsi14, iv_rank: last.iv_rank, walls: walls.length });
    } catch (e) {
      out.push({ ticker: t, error: (e as Error).message });
    }
  }
  return new Response(JSON.stringify({ ok: true, build: BUILD, today, out }), { headers: { 'Content-Type': 'application/json' } });
});
