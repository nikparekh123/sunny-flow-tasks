/**
 * sunny-sd: the SD calculator for one name (handoff 2026-11-11-sd-calculator, SunnySD.dc.html). The app's sheet (SD chip
 * on the Positions chart) and the web's card (SD layer under the Positions chart) draw what this sends; every number
 * is worked out here, in _shared/sd-engine.ts, so both read the same.
 *
 * POST { t: 'NKE', book?: 'S' | 'N' }. For each of the next expiries (the first five, then the next monthly after
 * them): the 1 SD move on that expiry's own IV, the Every SD rows (ATM to 2 SD a side, snapped to the chain's listed
 * strikes, the mid or a Black-Scholes estimate marked est, thin markets marked liq, the 5-year won rate), the suggested
 * call and put with the signals that moved them, and the ±1 SD band. Plus the name: price, today's move, the default
 * counts (Nik D1: calls one per 100 shares plus one per OTM hedge call; puts the ones sold, else 5) and the sold
 * strikes with their breakevens for the chart lines.
 *
 * POSITIONS PAGE (handoff 2026-11-13-positions, Nik's answers 13 Nov 2026). Optional, so older clients still decode:
 *   tech    the latest ticker_technicals row: 20/50/100/200-day, RSI 14, HV20; IV rank with the year's low and high of
 *           the saved 30-day IV (ticker_iv_daily, the same numbers the rules use); support and resistance zones.
 *   day     the session's range for touched and closed through (§3.9.3, A1): d = the session (today from 9:30 on a
 *           trading day, else the last one), prev = the stored close before it (daily_closes, the base of the app's
 *           day move), high and low (Yahoo's day high and low, else its daily bar; always holding the price; Polygon's
 *           stock snapshot is not on our plan),
 *           last = the price, closedToday = that session has closed, close = its stored close (daily_closes, 4:30 PM),
 *           the price itself from the bell until it is stored. src says where high and low came from.
 *   closes  the last 30 sessions' closes (daily_closes, Yahoo's bars where a day is missing); today only once stored.
 *   events  the next earnings date (earnTime, earnEst) and the next declared ex-dividend date with its amount;
 *           exDivEst is the estimate (last ex date plus a period) when none is declared, never put in exDiv.
 *   exps[i].ivK    [K, iv] per strike, put IV below the price and call IV above (the other side where one is
 *                  missing), within 4 SD or 15%: option_chain_next's mid IV, else this reply's own chain (ivKsrc).
 *   exps[i].gamma  the latest gamma_view_day view for that expiry (the dealer-gamma walls labelled Ceiling, Floor,
 *                  Accelerator or Unclear, gex in dollars per 1% move, conf 1 to 3 dots as gex-walls gamma.ts
 *                  dots() grades them) with its Flip and regime; else that expiry's gex_walls open-interest walls
 *                  (Ceiling above, Floor below, conf 1, src 'oi').
 *   sold[i].z0, sold[i].fill   where the strike sat when sold (option_fill_context, one row per opening sale, written
 *                  by option-fill-context): contract-weighted over the open lots of that leg in this book.
 *
 * ⚠ WHO MAY CALL: a signed-in user (their token) or the scheduler's key (x-cron-key / x-admin-key, for checks). The
 * book's legs are read AS THE CALLER (RLS: members of the book only); market data with the service key.
 * Chains: Theta Data's real-time NBBO when MARKS_SOURCE is `theta` (as chain-next), else Polygon's snapshot. After the
 * close the quotes are the closing ones, so premiums are the closing mid (Nik A3).
 * No em dashes in any words written here (Nik).
 */
import { calc, cover, CFG, dir, f1, f2, fk, heldPair, ITM, KS, netDelta, pc, row, won, bs as bsQ, type Expiry, type Fx, type Leg, type Name, type Quote, type Row } from '../_shared/sd-engine.ts';

const BUILD = '2026-11-13.1';
const URL_ = Deno.env.get('SUPABASE_URL')!;
const ANON = Deno.env.get('SUPABASE_ANON_KEY')!;
const SK = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const POLY = Deno.env.get('POLYGON_API_KEY') ?? '';
const THETA_URL = Deno.env.get('THETA_URL') ?? '';
const THETA_KEY = Deno.env.get('THETA_PROXY_KEY') ?? '';
const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-cron-key' };
const json = (s: number, b: unknown) => new Response(JSON.stringify(b), { status: s, headers: { ...cors, 'Content-Type': 'application/json' } });
type Row_ = Record<string, any>;
const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const WD = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const md = (d: string) => `${MON[Number(d.slice(5, 7)) - 1]} ${Number(d.slice(8, 10))}`;
const wmd = (d: string) => `${WD[new Date(d + 'T12:00:00Z').getUTCDay()]} ${md(d)}`;

async function caller(req: Request): Promise<{ auth: string; key: string } | null> {
  const cron = Deno.env.get('CRON_SECRET');
  if (cron && (req.headers.get('x-cron-key') === cron || req.headers.get('x-admin-key') === cron)) return { auth: `Bearer ${SK}`, key: SK };
  const auth = req.headers.get('authorization') ?? '';
  if (!auth.startsWith('Bearer ')) return null;
  const r = await fetch(`${URL_}/auth/v1/user`, { headers: { apikey: ANON, Authorization: auth } });
  await r.body?.cancel();
  return r.ok ? { auth, key: ANON } : null;
}
const db = async (path: string, who?: { auth: string; key: string }): Promise<Row_[]> => {
  const r = await fetch(`${URL_}/rest/v1/${path}`, { headers: { apikey: who?.key ?? SK, Authorization: who?.auth ?? `Bearer ${SK}` } });
  return r.ok ? await r.json() : [];
};
/** Every row: PostgREST stops at 1,000 rows, so read in Range pages (the path must carry an order). */
const dbPage = async (path: string, who?: { auth: string; key: string }): Promise<Row_[]> => {
  const out: Row_[] = [];
  for (let from = 0; ; from += 1000) {
    const r = await fetch(`${URL_}/rest/v1/${path}`, { headers: { apikey: who?.key ?? SK, Authorization: who?.auth ?? `Bearer ${SK}`, Range: `${from}-${from + 999}` } });
    if (!r.ok) { await r.body?.cancel(); return out; }
    const rows = await r.json() as Row_[];
    out.push(...rows);
    if (rows.length < 1000) return out;
  }
};

// ── New York's clock ──
const nyParts = () => {
  const p = Object.fromEntries(new Intl.DateTimeFormat('en-CA', { timeZone: 'America/New_York', year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', hour12: false })
    .formatToParts(new Date()).map((x) => [x.type, x.value]));
  return { day: `${p.year}-${p.month}-${p.day}`, mins: (Number(p.hour) % 24) * 60 + Number(p.minute) };
};
const addDays = (d: string, n: number) => { const x = new Date(d + 'T12:00:00Z'); x.setUTCDate(x.getUTCDate() + n); return x.toISOString().slice(0, 10); };

// ── Yahoo: five years of daily bars (the market feed's source, as sunny-chart) ──
const UA = { 'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15',
  Accept: 'application/json, text/plain, */*', 'Accept-Language': 'en-US,en;q=0.9' };
let session: { cookie: string; crumb: string } | null = null;
async function yahooSession() {
  const c = await fetch('https://fc.yahoo.com', { headers: UA, redirect: 'manual' });
  await c.body?.cancel();
  const cookie = (c.headers.get('set-cookie') ?? '').split(';')[0];
  if (!cookie) throw new Error('yahoo: no cookie');
  const r = await fetch('https://query2.finance.yahoo.com/v1/test/getcrumb', { headers: { ...UA, Cookie: cookie } });
  const crumb = (await r.text()).trim();
  if (!r.ok || !crumb || crumb.length > 40) throw new Error(`yahoo crumb ${r.status}`);
  return { cookie, crumb };
}
async function bars(t: string): Promise<{ meta: Row_; d: string[]; c: number[]; h: number[]; l: number[] }> {
  for (let attempt = 0; attempt < 2; attempt++) {
    if (!session) session = await yahooSession();
    const r = await fetch(`https://query2.finance.yahoo.com/v8/finance/chart/${encodeURIComponent(t)}?range=5y&interval=1d&includePrePost=false&crumb=${encodeURIComponent(session.crumb)}`,
      { headers: { ...UA, Cookie: session.cookie }, signal: AbortSignal.timeout(12_000) });
    if (r.status === 401 || r.status === 403) { await r.body?.cancel(); session = null; continue; }
    if (!r.ok) { await r.body?.cancel(); throw new Error(`yahoo chart ${r.status}`); }
    const res = (await r.json())?.chart?.result?.[0];
    if (!res) throw new Error('yahoo chart: no result');
    const ts: number[] = res.timestamp ?? [], q = res.indicators?.quote?.[0] ?? {};
    const d: string[] = [], c: number[] = [], h: number[] = [], l: number[] = [];
    ts.forEach((s, i) => {
      if (q.close?.[i] == null) return;
      d.push(new Date(s * 1000).toLocaleDateString('en-CA', { timeZone: 'America/New_York' }));
      c.push(q.close[i]); h.push(q.high?.[i] ?? q.close[i]); l.push(q.low?.[i] ?? q.close[i]);
    });
    return { meta: res.meta ?? {}, d, c, h, l };
  }
  throw new Error('yahoo chart: refused');
}

// ── Chains: Theta (real-time NBBO) or Polygon ──
interface Ct { side: 'call' | 'put'; K: number; bid: number | null; ask: number | null; oi: number | null; iv: number | null }
async function thetaGet(path: string): Promise<Row_[]> {
  const r = await fetch(`${THETA_URL}${path}&format=json`, { headers: { 'x-proxy-key': THETA_KEY }, signal: AbortSignal.timeout(15_000) }).catch(() => null);
  if (!r || !r.ok) return [];
  return ((await r.json())?.response ?? []) as Row_[];
}
const ncdf0 = (x: number) => { const t = 1 / (1 + 0.3275911 * Math.abs(x) / Math.SQRT2);
  const y = 1 - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t * Math.exp(-x * x / 2);
  return x >= 0 ? (1 + y) / 2 : (1 - y) / 2; };
const bs0 = (call: boolean, S: number, K: number, T: number, v: number) => { const sq = v * Math.sqrt(T), d1 = (Math.log(S / K) + 0.5 * v * v * T) / sq, d2 = d1 - sq;
  return call ? S * ncdf0(d1) - K * ncdf0(d2) : K * ncdf0(-d2) - S * ncdf0(-d1); };
const ivFrom = (call: boolean, px: number, S: number, K: number, T: number): number | null => {
  const intr = Math.max(0, call ? S - K : K - S);
  if (!(px > intr + 0.005) || T <= 0) return null;
  let lo = 0.01, hi = 4;
  for (let i = 0; i < 60; i++) { const m = (lo + hi) / 2; if (bs0(call, S, K, T, m) < px) lo = m; else hi = m; }
  return (lo + hi) / 2;
};
/** The stock price the chain's quotes imply (C - P + K where the call and put are closest), as chain-next. */
function impliedSpot(cs: Ct[], T: number): number | null {
  const by = new Map<number, { c?: number; p?: number }>();
  for (const x of cs) { if (!(x.bid! > 0 && x.ask! > 0)) continue; const e = by.get(x.K) ?? {}; e[x.side === 'call' ? 'c' : 'p'] = (x.bid! + x.ask!) / 2; by.set(x.K, e); }
  let best: number | null = null, gap = Infinity;
  for (const [K, e] of by) { if (e.c == null || e.p == null) continue; if (Math.abs(e.c - e.p) < gap) { gap = Math.abs(e.c - e.p); best = e.c - e.p + K * Math.exp(-0.04 * T); } }
  return best;
}
async function expirations(t: string, useTheta: boolean): Promise<string[]> {
  if (useTheta) {
    const rows = await thetaGet(`/v3/option/list/expirations?symbol=${t}`);
    const xs = rows.map((x) => String(x.expiration ?? x.date ?? '')).filter(Boolean).map((e) => (e.includes('-') ? e : `${e.slice(0, 4)}-${e.slice(4, 6)}-${e.slice(6, 8)}`));
    if (xs.length) return [...new Set(xs)].sort();
  }
  const out = new Set<string>();
  let url: string | null = `https://api.polygon.io/v3/reference/options/contracts?underlying_ticker=${t}&expiration_date.gte=${nyParts().day}&expiration_date.lte=${addDays(nyParts().day, 75)}&limit=1000&sort=expiration_date&order=asc&apiKey=${POLY}`;
  for (let i = 0; url && i < 4; i++) {
    const r: Response = await fetch(url, { signal: AbortSignal.timeout(12_000) });
    if (!r.ok) break;
    const j = await r.json();
    for (const c of j.results ?? []) if (c.expiration_date) out.add(c.expiration_date);
    url = j.next_url ? `${j.next_url}&apiKey=${POLY}` : null;
  }
  return [...out].sort();
}
async function chain(t: string, ex: string, useTheta: boolean, T: number): Promise<{ cs: Ct[]; spot: number | null }> {
  if (useTheta) {
    const e8 = ex.replaceAll('-', '');
    const [qr, oi] = await Promise.all([thetaGet(`/v3/option/snapshot/quote?symbol=${t}&expiration=${e8}`), thetaGet(`/v3/option/snapshot/open_interest?symbol=${t}&expiration=${e8}`)]);
    const oiBy = new Map(oi.map((r) => [`${String(r.contract?.right).toLowerCase()}|${Number(r.contract?.strike)}`, Number(r.data?.[0]?.open_interest)]));
    const cs: Ct[] = qr.filter((r) => r.data?.[0]).map((r) => {
      const side = String(r.contract.right).toLowerCase() === 'call' ? 'call' : 'put', K = Number(r.contract.strike);
      const bid = Number(r.data[0].bid), ask = Number(r.data[0].ask), o = oiBy.get(`${side}|${K}`);
      return { side, K, bid: bid > 0 ? bid : null, ask: ask > 0 ? ask : null, oi: Number.isFinite(o) ? o! : null, iv: null } as Ct;
    });
    const spot = impliedSpot(cs, T);
    if (spot) {
      for (const x of cs) { const mid = x.bid && x.ask ? (x.bid + x.ask) / 2 : null; x.iv = mid ? ivFrom(x.side === 'call', mid, spot, x.K, T) : null; }
      return { cs, spot };
    }
  }
  const out: Ct[] = [];
  let url: string | null = `https://api.polygon.io/v3/snapshot/options/${t}?expiration_date=${ex}&limit=250&apiKey=${POLY}`;
  let spot: number | null = null;
  for (let i = 0; url && i < 4; i++) {
    const r: Response = await fetch(url, { signal: AbortSignal.timeout(12_000) });
    if (!r.ok) break;
    const j = await r.json();
    for (const c of j.results ?? []) {
      const side = c.details?.contract_type, K = c.details?.strike_price;
      if ((side !== 'call' && side !== 'put') || typeof K !== 'number') continue;
      const b = c.last_quote?.bid, a = c.last_quote?.ask;
      out.push({ side, K, bid: b > 0 ? b : null, ask: a > 0 ? a : null, oi: typeof c.open_interest === 'number' ? c.open_interest : null,
        iv: typeof c.implied_volatility === 'number' && c.implied_volatility > 0 ? c.implied_volatility : null });
      if (!spot && c.underlying_asset?.price > 0) spot = c.underlying_asset.price;
    }
    url = j.next_url ? `${j.next_url}&apiKey=${POLY}` : null;
  }
  return { cs: out, spot };
}

// ── History: HV20, RSI 14 (Wilder) ──
const hvAt = (c: number[], i: number) => { // 20 daily log returns ending at i
  if (i < 20) return null;
  const r: number[] = []; for (let j = i - 19; j <= i; j++) r.push(Math.log(c[j] / c[j - 1]));
  const mu = r.reduce((a, b) => a + b, 0) / r.length, v = r.reduce((a, b) => a + (b - mu) ** 2, 0) / (r.length - 1);
  return Math.sqrt(v * 252);
};
const rsi14 = (c: number[]) => {
  if (c.length < 16) return 50;
  let up = 0, dn = 0;
  for (let i = 1; i <= 14; i++) { const x = c[i] - c[i - 1]; if (x > 0) up += x; else dn -= x; }
  up /= 14; dn /= 14;
  for (let i = 15; i < c.length; i++) { const x = c[i] - c[i - 1]; up = (up * 13 + Math.max(0, x)) / 14; dn = (dn * 13 + Math.max(0, -x)) / 14; }
  return dn > 0 ? 100 - 100 / (1 + up / dn) : 100;
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  const who = await caller(req);
  if (!who) return json(401, { error: 'sign in' });
  const body = await req.json().catch(() => ({})) as Row_;
  const t = String(body.t ?? '').toUpperCase(), book = String(body.book ?? 'S').toUpperCase();
  if (!/^[A-Z.]{1,6}$/.test(t) || !/^[A-Z]$/.test(book)) return json(400, { error: 'send t and book' });
  const useTheta = String(body.source ?? Deno.env.get('MARKS_SOURCE') ?? 'polygon').toLowerCase() === 'theta' && !!THETA_URL && !!THETA_KEY;
  const t0 = Date.now(), { day: today, mins } = nyParts();

  try {
    const [hist, ivRows, earn, divs, cal, snap, quote, allEx, gex, techRows, dcl, chainNext, gvRows, myTrades, mlive, calToday] = await Promise.all([
      bars(t),
      db(`ticker_iv_daily?ticker=eq.${t}&select=snapshot_date,atm_iv&atm_iv=gt.0&order=snapshot_date.asc&limit=2000`),
      db(`earnings_events?ticker=eq.${t}&report_date=gte.${today}&select=report_date,report_time,date_estimated&order=report_date.asc&limit=1`),
      db(`dividends?ticker=eq.${t}&ex_date=gte.${addDays(today, -400)}&select=ex_date,cash_amount,frequency&order=ex_date.asc`),
      db(`market_calendar?date=gte.${today}&date=lte.${addDays(today, 120)}&kind=eq.closed&select=date`),
      db(`home_snapshot?book_id=eq.${book}&select=inputs:payload->brief_inputs,strategies:payload->strategies,names:payload->brief->names`, who),
      db(`ticker_quotes_latest?ticker=eq.${t}&select=spot,day_change_pct`),
      expirations(t, useTheta),
      // The walls card (Nik 11 Nov: walls are a nudge, never the rule): each expiry's last logged walls.
      db(`gex_walls?ticker=eq.${t}&expiry=not.is.null&day=gte.${addDays(today, -7)}&select=day,expiry,flip,call_wall,call_wall2,put_wall,put_wall2,call_wall_gex,call_wall2_gex,put_wall_gex,put_wall2_gex&order=day.desc,id.asc`),
      // Positions page (2026-11-13): technicals and zones, stored closes, the chain's mid IV per strike, dealer gamma
      // by expiry, this book's trades in the name (as the caller), the quote feed's previous close, today's bell.
      db(`ticker_technicals?ticker=eq.${t}&order=day.desc&limit=1&select=day,sma20,sma50,sma100,sma200,rsi14,hv20,zones`),
      db(`daily_closes?ticker=eq.${t}&date=gte.${addDays(today, -70)}&date=lte.${today}&order=date.asc&select=date,close_price`),
      dbPage(`option_chain_next?ticker=eq.${t}&iv=gt.0&order=expiry.asc,side.asc,strike.asc&select=expiry,side,strike,iv`),
      dbPage(`gamma_view_day?ticker=eq.${t}&day=gte.${addDays(today, -5)}&view=like.20*&order=day.desc,view.asc&select=day,view,flip:data->flip,regime:data->regime,walls:data->walls`),
      dbPage(`option_trades?book_id=eq.${book}&ticker=eq.${t}&voided_at=is.null&expiry=gte.${today}&order=id.asc&select=id,action,option_type,direction,contracts,strike,expiry,trade_date`, who),
      db(`market_live?symbol=eq.${t}&select=prev_close,captured_at`),
      db(`market_calendar?date=eq.${today}&select=kind,closes`),
    ]);

    // ── Expiries: the first five, then the next monthly after them; today's only while it still trades ──
    const closed = new Set(cal.map((x) => String(x.date)));
    const monthly = (e: string) => { const d = new Date(e + 'T12:00:00Z'), wd = d.getUTCDay(), dd = d.getUTCDate(); return (wd === 5 && dd >= 15 && dd <= 21) || (wd === 4 && dd >= 14 && dd <= 20); };
    const live = allEx.filter((e) => e > today || (e === today && mins < 16 * 60));
    const pick = live.slice(0, 5);
    const nm = live.slice(5).find(monthly);
    if (nm) pick.push(nm);
    if (!pick.length) return json(200, { ok: false, build: BUILD, t, error: 'no expiries' });
    const tradingDays = (ex: string) => { let n = 0; for (let d = addDays(today, 1); d <= ex; d = addDays(d, 1)) { const w = new Date(d + 'T12:00:00Z').getUTCDay(); if (w !== 0 && w !== 6 && !closed.has(d)) n++; } return n; };
    const calDays = (ex: string) => Math.round((Date.parse(ex + 'T12:00:00Z') - Date.parse(today + 'T12:00:00Z')) / 86_400_000);
    const yrs = (ex: string) => { const td = tradingDays(ex); return td > 0 ? td / 252 : Math.max(0.25, (16 * 60 - mins) / 60) / (6.5 * 252); };
    const chains = await Promise.all(pick.map((ex) => chain(t, ex, useTheta, yrs(ex))));
    // A check of one expiry's raw chain, for the scheduler's key only.
    if (typeof body.debug === 'string' && who.key === SK) {
      const i = pick.indexOf(body.debug);
      return json(200, { pick, spot: chains[i]?.spot ?? null, cs: (chains[i]?.cs ?? []).sort((a, b) => a.K - b.K) });
    }

    // ── The price: the chain's own (Theta's implied spot), else the quote feed, else the last bar ──
    const lastBar = hist.c.at(-1) ?? 0;
    const S = chains[0].spot ?? (Number(quote[0]?.spot) > 0 ? Number(quote[0].spot) : Number(hist.meta.regularMarketPrice ?? lastBar));
    const sess = hist.d.map((d, i) => ({ d, c: hist.c[i], h: hist.h[i], l: hist.l[i] })).filter((b) => b.d < today);
    const prev = sess.at(-1)?.c ?? S;
    const closes = sess.map((b) => b.c), withNow = [...closes, S];
    const S5 = sess.length >= 5 ? sess[sess.length - 5].c : closes[0];
    const S5d = sess.length >= 5 ? sess[sess.length - 5].d : today;
    const hv20 = hvAt(withNow, withNow.length - 1) ?? 0.3;
    const rsi = Math.round(rsi14(withNow.slice(-120)));
    const last20 = hist.d.map((d, i) => ({ d, h: hist.h[i], l: hist.l[i] })).slice(-20);
    const sup = Math.min(...last20.map((b) => b.l)), res = Math.max(...last20.map((b) => b.h));
    // The momentum rules' inputs (Nik 11 Nov): the 50-day and 200-day of the closes, the 52-week low, today's move.
    const avg = (n: number) => (closes.length >= n ? closes.slice(-n).reduce((a, b) => a + b, 0) / n : null);
    const ma50 = avg(50), ma200 = avg(200);
    const lows = hist.l.slice(-252).filter((x) => x > 0), lo52 = lows.length >= 200 ? Math.min(...lows) : null;
    const day1 = prev > 0 ? S / prev - 1 : 0;
    const wallBy = new Map<string, Row_>();
    for (const w of gex) if (!wallBy.has(String(w.expiry))) wallBy.set(String(w.expiry), w);

    // ── IV: the 30-day (saved daily), 5 sessions ago, rank over a year; the 5-year line for won (Nik A1) ──
    const ivBy = new Map(ivRows.map((r) => [String(r.snapshot_date), Number(r.atm_iv)]));
    const ivLast = ivRows.at(-1), iv30 = ivLast ? Number(ivLast.atm_iv) : hv20;
    const iv5r = [...ivRows].reverse().find((r) => String(r.snapshot_date) <= S5d), iv5 = iv5r ? Number(iv5r.atm_iv) : iv30;
    const yr = ivRows.filter((r) => String(r.snapshot_date) >= addDays(today, -365)).map((r) => Number(r.atm_iv));
    const ivLo = yr.length ? Math.min(...yr) : iv30, ivHi = yr.length ? Math.max(...yr) : iv30;
    const rank = ivHi > ivLo ? ((iv30 - ivLo) / (ivHi - ivLo)) * 100 : 50;
    const limited = !ivRows.length ? 'none' : String(ivRows[0].snapshot_date) > addDays(today, -330) ? 'limited' : null;
    const ratios: number[] = [];
    const ivDay: (number | null)[] = closes.map((_, i) => {
      const hv = hvAt(closes, i), v = ivBy.get(sess[i].d);
      if (v && hv) ratios.push(v / hv);
      return v ?? null;
    });
    ratios.sort((a, b) => a - b);
    const ratioMed = ratios.length >= 20 ? ratios[Math.floor(ratios.length / 2)] : 1.15;
    let estDays = 0;
    for (let i = 0; i < ivDay.length; i++) if (ivDay[i] == null) { const hv = hvAt(closes, i); ivDay[i] = hv ? hv * ratioMed : null; if (hv) estDays++; }
    const histEst = closes.length ? estDays / closes.length > 0.5 : true;

    // ── The book in this name, read as the caller ──
    const inputs = snap[0]?.inputs, nameIn = (inputs?.names ?? []).find((x: Row_) => x.t === t);
    const legs: Row_[] = nameIn?.legs ?? [];
    const L = (kind: string): Leg[] => legs.filter((l) => l.kind === kind).map((l) => ({ K: Number(l.K), n: Math.abs(Number(l.q)), ex: String(l.ex), at: l.at == null ? null : Number(l.at), iv: Number(l.iv) || 0, days: Number(l.days) || 0 }));
    const shares = legs.filter((l) => l.kind === 'shares').reduce((a, l) => a + Number(l.q), 0);
    const r = Number(inputs?.r ?? 0.04);
    const divYr = divs.filter((d) => String(d.ex_date) >= addDays(today, -370) && String(d.ex_date) < today);
    const q = S > 0 ? divYr.reduce((a, d) => a + Number(d.cash_amount), 0) / S : 0;
    const name: Name = { t, S, S5, iv5, iv30, hv20, rank, ratio: hv20 > 0 ? iv30 / hv20 : 1, rsi, sup, res, r, q, shares, ma50, ma200, lo52, day1,
      soldCalls: L('sc'), soldPuts: L('sp'), longCalls: L('otm'), longPuts: L('ins') };
    const leaps = L('leaps');
    const cv = cover(name), nd = netDelta(name, leaps);
    const counts = { calls: Math.floor(shares / 100) + name.longCalls.reduce((a, l) => a + l.n, 0), puts: name.soldPuts.reduce((a, l) => a + l.n, 0) || 5 };

    // ── Earnings and the ex-dividend date ──
    const er = earn[0] ? { d: String(earn[0].report_date), time: earn[0].report_time ? String(earn[0].report_time) : null } : null;
    const before = (ex: string) => !!er && (er.d < ex || (er.d === ex && er.time !== 'amc'));
    const exDiv = divs.find((d) => String(d.ex_date) >= today);

    // ── Positions page inputs by expiry: the chain's mid IV per strike, and dealer gamma (latest view per expiry) ──
    const cnBy = new Map<string, Row_[]>();
    for (const r of chainNext) { const e = String(r.expiry); (cnBy.get(e) ?? cnBy.set(e, []).get(e)!).push(r); }
    const gvBy = new Map<string, Row_>();
    for (const r of gvRows) if (!gvBy.has(String(r.view))) gvBy.set(String(r.view), r);   // newest day first
    const r4 = (v: number) => +v.toFixed(4);
    const ivKOf = (ex: string, cs: Ct[], m: number): { ivK: [number, number][]; src: string } | null => {
      const rows = cnBy.get(ex) ?? [];
      const src = rows.length ? 'chain_next' : useTheta ? 'theta' : 'polygon';
      const pts = rows.length ? rows.map((r) => ({ side: String(r.side), K: Number(r.strike), iv: Number(r.iv) })) : cs.map((x) => ({ side: x.side, K: x.K, iv: x.iv ?? 0 }));
      const by = new Map<number, { call?: number; put?: number }>();
      for (const x of pts) if (x.iv > 0 && x.K > 0) { const e = by.get(x.K) ?? {}; e[x.side === 'put' ? 'put' : 'call'] = x.iv; by.set(x.K, e); }
      const lim = Math.max(4 * m, 0.15);
      const ivK = [...by.keys()].filter((K) => Math.abs(Math.log(K / S)) <= lim).sort((a, b) => a - b).map((K): [number, number] => {
        const e = by.get(K)!, v = K < S ? (e.put ?? e.call)! : (e.call ?? e.put)!;
        return [K, r4(v)];
      });
      return ivK.length ? { ivK, src } : null;
    };
    const gammaOf = (ex: string) => {
      const g = gvBy.get(ex);
      if (g && Array.isArray(g.walls)) {
        const walls = (g.walls as Row_[]).filter((w) => Number(w.k) > 0).map((w) => ({
          K: Number(w.k), kind: (['ceiling', 'floor', 'accelerator'].includes(String(w.label)) ? String(w.label) : 'unclear') as 'ceiling' | 'floor' | 'accelerator' | 'unclear',
          gex: Math.round(Number(w.gex) || 0), conf: Math.min(3, Math.max(1, Math.round(Number(w.conf) || 1))) as 1 | 2 | 3 })).sort((a, b) => a.K - b.K);
        return { day: String(g.day), flip: Number(g.flip) > 0 ? Number(g.flip) : null, walls, regime: g.regime ? String(g.regime) : null, src: 'tape' };
      }
      const wl = wallBy.get(ex);
      if (!wl) return null;
      const walls = ([[wl.call_wall, wl.call_wall_gex], [wl.call_wall2, wl.call_wall2_gex], [wl.put_wall, wl.put_wall_gex], [wl.put_wall2, wl.put_wall2_gex]] as unknown[][])
        .filter(([k]) => Number(k) > 0).map(([k, gx]) => ({ K: Number(k), kind: (Number(k) > S ? 'ceiling' : 'floor') as 'ceiling' | 'floor', gex: Math.round(Number(gx) || 0), conf: 1 as const }))
        .filter((w, i, a) => a.findIndex((x) => x.K === w.K) === i).sort((a, b) => a.K - b.K);
      return { day: String(wl.day), flip: Number(wl.flip) > 0 ? Number(wl.flip) : null, walls, regime: null, src: 'oi' };
    };

    // ── Each expiry ──
    const exps = pick.map((ex, i) => {
      const { cs } = chains[i], T = yrs(ex);
      const strikes = [...new Set(cs.map((x) => x.K))].sort((a, b) => a - b);
      const by = new Map(cs.map((x) => [`${x.side}|${x.K}`, x]));
      const near = strikes.length ? strikes.reduce((a, b) => (Math.abs(b - S) < Math.abs(a - S) ? b : a)) : S;
      const ivs = [by.get(`call|${near}`)?.iv, by.get(`put|${near}`)?.iv].filter((v): v is number => !!v && v > 0);
      const iv = ivs.length ? ivs.reduce((a, b) => a + b, 0) / ivs.length : iv30;
      const quoteK = (K: number, put: boolean): Quote => {
        const x = by.get(`${put ? 'put' : 'call'}|${K}`);
        if (x?.bid && x?.ask) { const mid = (x.bid + x.ask) / 2; return { mid, bid: x.bid, ask: x.ask, oi: x.oi, est: false, liq: (x.ask - x.bid) / mid > CFG.spr || (x.oi != null && x.oi < CFG.oi) }; }
        return { mid: bsQ(S, K, T, r, q, x?.iv ?? iv, put), bid: x?.bid ?? null, ask: x?.ask ?? null, oi: x?.oi ?? null, est: true, liq: x?.oi != null && x.oi < CFG.oi };
      };
      const e: Expiry = { ex, label: md(ex), long: wmd(ex), td: tradingDays(ex), cd: calDays(ex), T, iv, strikes, quote: quoteK, earnB: before(ex) };
      const R = calc(name, e, { atm: true }), m = R.m, H = won(closes, ivDay, Math.max(1, e.td));
      const out = (rw: Row, put: boolean) => ({ k: rw.k, K: rw.K, pct: rw.x, kA: +rw.kA.toFixed(4), pr: +rw.pr.toFixed(4), be: +rw.be.toFixed(4), itm: +rw.itm.toFixed(4),
        est: rw.est, liq: rw.liq, won: H.n ? +(put ? H.put(rw.kA) : H.call(rw.kA)).toFixed(4) : null });
      // The signals (card136): only what matters.
      const sig: Row_[] = [];
      const sg = (o: Row_) => sig.push({ tag: '', tagTone: 'mu', s: '', vTone: 'ink', fx: [] as Fx[], ...o });
      const wk = S / S5 - 1, dS = (v: number) => Math.log(v / S) / m;
      sg({ key: 'wk', k: 'This week', v: dir(wk), vTone: wk < 0 ? 'red' : 'green', tag: f1(Math.abs(R.z)) + ' SD', fx: R.fx.wk });
      // The trend the put table reads (Nik 11 Nov): the 50-day and 200-day, and the 52-week low.
      // One short word as the value (a card is narrow); the averages say why underneath.
      const f50 = ma50 ? f2(ma50) : '', f200 = ma200 ? f2(ma200) : '';
      sg({ key: 'tr', k: 'Trend', v: R.trend === 'up' ? 'Up' : R.trend === 'mid' ? 'Mixed' : 'Down',
        vTone: R.trend === 'up' ? 'green' : R.trend === 'down' ? 'red' : 'ink',
        s: R.trend === 'up' ? `Over the 50-day ${f50} and the 200-day ${f200}`
          : R.trend === 'down' ? (f50 ? `Under the 50-day ${f50}` : 'No 50-day yet')
          : f200 ? `Over the 50-day ${f50}, under the 200-day ${f200}` : (f50 ? `Over the 50-day ${f50}` : 'No 50-day yet') });
      sg({ key: 'iv', k: 'IV edge', v: R.rich ? 'Rich' : R.cheap ? 'Cheap' : 'None',
        s: limited === 'none' ? 'No saved IV · based on recent volatility' : `IV30 ${pc(iv30)} · HV20 ${pc(hv20)} · rank ${Math.round(rank)}${limited ? ' · limited history' : ''}`, fx: R.fx.iv });
      // Walls and the 20-day range: a nudge card only, they move no strike (Nik 11 Nov).
      const wl = wallBy.get(ex);
      const ceil = wl ? [wl.call_wall, wl.call_wall2].map(Number).filter((k) => k > S).sort((a, b) => a - b)[0] ?? null : null;
      const floor = wl ? [wl.put_wall, wl.put_wall2].map(Number).filter((k) => k > 0 && k < S).sort((a, b) => b - a)[0] ?? null : null;
      const rng = `20-day ${f2(sup)} to ${f2(res)}`;
      if (ceil != null || floor != null) {
        const nx: Fx[] = [];
        if (ceil != null) nx.push(['n', `Call ${fk(R.C.K)} ${R.C.K > ceil ? 'over' : R.C.K === ceil ? 'at' : 'under'} the ceiling`]);
        if (floor != null) nx.push(['n', `Put ${fk(R.P.K)} ${R.P.K < floor ? 'under' : R.P.K === floor ? 'at' : 'over'} the floor`]);
        sg({ key: 'lv', k: 'Walls', v: ceil != null ? 'Ceiling ' + fk(ceil) : 'Floor ' + fk(floor!),
          tag: ceil != null ? f1(dS(ceil)) + ' SD up' : f1(-dS(floor!)) + ' SD down',
          s: [ceil != null && floor != null ? `Floor ${fk(floor)}, ${f1(-dS(floor))} SD down` : '', rng].filter(Boolean).join(' · '), fx: nx });
      } else sg({ key: 'lv', k: '20-day range', v: `${f2(sup)} to ${f2(res)}`, s: `${f1(-dS(sup))} SD down · ${f1(dS(res))} SD up` });
      if (R.ernB && er) sg({ key: 'er', k: 'Earnings', v: md(er.d), tag: 'before expiry', tagTone: 'or', s: '', fx: R.fx.er, erExp: true });
      if (exDiv && String(exDiv.ex_date) < ex && name.soldCalls.some((x) => x.K < S)) sg({ key: 'ex', k: 'Ex-dividend', v: md(String(exDiv.ex_date)), tag: 'call in the money', tagTone: 'or', s: 'Early assignment risk' });
      if (cv.naked || nd < 0) sg({ key: 'cv', k: 'Your calls', v: cv.naked ? cv.naked + ' naked' : 'Net short', vTone: 'or', s: 'Net delta ' + (nd < 0 ? 'short ' : 'long ') + Math.round(Math.abs(nd)).toLocaleString('en-US') });
      const ik = ivKOf(ex, cs, m), gm = gammaOf(ex);
      return { e, R, H, sig, data: {
        ex, label: e.label, long: e.long, td: e.td, cd: e.cd, T: +T.toFixed(6), iv: +iv.toFixed(4), m: +m.toFixed(5), earn: e.earnB,
        ...(ik ? { ivK: ik.ivK, ivKsrc: ik.src } : {}), ...(gm ? { gamma: gm } : {}),
        band: [+(S * Math.exp(-m)).toFixed(4), +(S * Math.exp(m)).toFixed(4)],
        sug: { kc: R.kc, kp: R.kp, mvC: R.mvC, mvP: R.mvP, capC: R.capC, capP: R.capP, C: out(R.C, false), P: out(R.P, true) },
        rows: { c: KS.map((k) => out(row(name, e, k, false), false)), p: KS.map((k) => out(row(name, e, k, true), true)) },
        // q: the 5-year moves as 401 quantiles, for the sale's chance of profit (handoff sd-whatif-totals 1.9).
        sig, hist: { n: H.n, est: histEst, q: H.q } } };
    });
    // The earnings card's implied move: the ATM straddle of the first expiry after the report, over the price.
    const first = exps.find((x) => x.e.earnB);
    if (first) {
      const K = first.e.strikes.length ? first.e.strikes.reduce((a, b) => (Math.abs(b - S) < Math.abs(a - S) ? b : a)) : S;
      const mv = (first.e.quote(K, false).mid + first.e.quote(K, true).mid) / S;
      for (const x of exps) for (const s of x.sig) if (s.key === 'er') { s.s = '±' + pc(mv) + ' implied move'; delete s.erExp; }
    }

    const strategy = snap[0]?.strategies?.[t] ?? (snap[0]?.names ?? []).find((x: Row_) => x?.t === t)?.strategy ?? null;
    const shortName = (snap[0]?.names ?? []).find((x: Row_) => x?.t === t)?.name ?? hist.meta.shortName ?? t;

    // ── Sold, in SD: where each sold leg sat when sold. This book's open lots (pooled FIFO per contract, opens by id,
    //    as sunny-home), then their option_fill_context rows, weighted by the contracts still open. ──
    const lotsBy = new Map<string, { id: string; n: number; d: string }[]>();
    {
      const groups = new Map<string, Row_[]>();
      for (const x of myTrades) { const k = `${x.option_type}|${x.direction}|${Number(x.strike)}|${x.expiry}`; (groups.get(k) ?? groups.set(k, []).get(k)!).push(x); }
      for (const [k, rows] of groups) {
        if (!k.split('|')[1].startsWith('short')) continue;
        let closeQty = rows.filter((x) => x.action === 'close').reduce((a, x) => a + Number(x.contracts), 0);
        const live: { id: string; n: number; d: string }[] = [];
        for (const o of rows.filter((x) => x.action === 'open').sort((a, b) => (a.id < b.id ? -1 : 1))) {
          const take = Math.min(closeQty, Number(o.contracts)); closeQty -= take;
          if (Number(o.contracts) - take > 0) live.push({ id: String(o.id), n: Number(o.contracts) - take, d: String(o.trade_date) });
        }
        const [ty, , K, ex] = k.split('|');
        if (live.length) lotsBy.set(`${ty}|${Number(K)}|${ex}`, live);
      }
    }
    const lotIds = [...lotsBy.values()].flat().map((x) => x.id);
    const fcRows: Row_[] = [];
    for (let i = 0; i < lotIds.length; i += 80) fcRows.push(...await db(`option_fill_context?option_trade_id=in.(${lotIds.slice(i, i + 80).join(',')})&select=option_trade_id,underlying,iv,td,z0,approx`, who));
    const fcBy = new Map(fcRows.map((x) => [String(x.option_trade_id), x]));
    const fillOf = (put: boolean, K: number, ex: string): { z0: number | null; fill?: Row_ } => {
      const lots = lotsBy.get(`${put ? 'put' : 'call'}|${K}|${ex}`) ?? [];
      const got = lots.map((l) => ({ l, f: fcBy.get(l.id) })).filter((x) => x.f && x.f.z0 != null);
      const w = got.reduce((a, x) => a + x.l.n, 0);
      if (!w) return { z0: null };
      const avg = (f: (x: typeof got[number]) => number) => got.reduce((a, x) => a + x.l.n * f(x), 0) / w;
      return { z0: r4(avg((x) => Number(x.f!.z0))), fill: { S: r4(avg((x) => Number(x.f!.underlying))), iv: r4(avg((x) => Number(x.f!.iv))),
        td: Math.round(avg((x) => Number(x.f!.td))), approx: got.length < lots.length || got.some((x) => x.f!.approx !== false),
        d: got.map((x) => x.l.d).sort()[0] } };
    };

    // ── The session's range (§3.9.3, A1) and the last 30 closes ──
    const dc = new Map(dcl.map((x) => [String(x.date), Number(x.close_price)]));
    const isSess = (d: string) => { const w = new Date(d + 'T12:00:00Z').getUTCDay(); return w !== 0 && w !== 6 && !closed.has(d); };
    const bell = calToday[0]?.kind === 'early_close' && calToday[0]?.closes ? Number(String(calToday[0].closes).slice(0, 2)) * 60 + Number(String(calToday[0].closes).slice(3, 5)) : 16 * 60;
    const liveSess = isSess(today) && mins >= 9 * 60 + 30;
    const barAt = (d: string) => { const i = hist.d.lastIndexOf(d); return i >= 0 ? { c: hist.c[i], h: hist.h[i], l: hist.l[i] } : null; };
    const sessBefore = (d: string) => { const xs = [...new Set([...hist.d, ...dc.keys()])].filter((x) => x < d && isSess(x)).sort(); return xs.at(-1) ?? null; };
    const sd0 = liveSess ? today : (sessBefore(today) ?? today);
    const pd0 = sessBefore(sd0);
    const prevC = (pd0 && dc.get(pd0)) || (liveSess && Number(mlive[0]?.prev_close) > 0 ? Number(mlive[0].prev_close) : null) || (pd0 ? barAt(pd0)?.c : null) || prev;
    let day: Row_;
    if (liveSess) {
      const m = hist.meta, ymt = Number(m.regularMarketTime) > 0 ? new Date(Number(m.regularMarketTime) * 1000).toLocaleDateString('en-CA', { timeZone: 'America/New_York' }) : null;
      const bt = barAt(today);
      // Yahoo's day high and low (Polygon's stock snapshot is not on our plan: 403 NOT_AUTHORIZED, 13 Nov 2026).
      const src = ymt === today && Number(m.regularMarketDayHigh) > 0 && Number(m.regularMarketDayLow) > 0 ? 'yahoo' : bt ? 'bars' : 'price';
      const hi0 = src === 'yahoo' ? Number(m.regularMarketDayHigh) : bt ? bt.h : S;
      const lo0 = src === 'yahoo' ? Number(m.regularMarketDayLow) : bt ? bt.l : S;
      const done = mins >= bell;
      day = { d: today, prev: r4(prevC), high: r4(Math.max(hi0, S)), low: r4(Math.min(lo0, S)), last: r4(S), closedToday: done,
        ...(done ? { close: r4(dc.get(today) ?? S), closeStored: dc.has(today) } : {}), src };
    } else {
      const bt = barAt(sd0), c = dc.get(sd0) ?? bt?.c ?? S;
      day = { d: sd0, prev: r4(prevC), high: r4(Math.max(bt?.h ?? c, c)), low: r4(Math.min(bt?.l ?? c, c)), last: r4(c), closedToday: true,
        close: r4(c), closeStored: dc.has(sd0), src: bt ? 'bars' : 'price' };
    }
    const cmap = new Map<string, number>();
    hist.d.forEach((d, i) => { if (d < today && isSess(d)) cmap.set(d, hist.c[i]); });
    for (const [d, c] of dc) if (c > 0 && isSess(d)) cmap.set(d, c);
    const closes30 = [...cmap.entries()].sort((a, b) => (a[0] < b[0] ? -1 : 1)).slice(-30).map(([d, c]) => ({ d, c: r4(c) }));

    // ── Technicals (the latest ticker_technicals row) with IV rank on the year of saved 30-day IV ──
    const tr = techRows[0] ?? null;
    const nn = (v: unknown) => (v == null || !Number.isFinite(Number(v)) ? null : r4(Number(v)));
    const tech = {
      day: tr ? String(tr.day) : null,
      sma20: nn(tr?.sma20), sma50: nn(tr?.sma50 ?? ma50), sma100: nn(tr?.sma100), sma200: nn(tr?.sma200 ?? ma200),
      rsi14: nn(tr?.rsi14 ?? rsi), hv20: nn(tr?.hv20 ?? hv20),
      ivRank: yr.length >= 2 && ivHi > ivLo ? r4(rank) : null, ivLow52: yr.length ? r4(ivLo) : null, ivHigh52: yr.length ? r4(ivHi) : null,
      ivDays: yr.length,
      zones: (Array.isArray(tr?.zones) ? tr.zones as Row_[] : []).map((z) => ({ kind: z.kind === 'support' ? 'support' : 'resistance', lo: Number(z.lo), hi: Number(z.hi), mid: Number(z.mid), strength: Number(z.strength), last: z.last ?? null })),
    };

    // ── Events: next earnings, next declared ex-dividend (the estimate apart) ──
    let exDivEst: string | null = null;
    if (!exDiv) {
      const lastDv = [...divs].filter((d) => String(d.ex_date) < today).at(-1);
      if (lastDv) { let d = String(lastDv.ex_date); const step = Math.round(365 / (Number(lastDv.frequency) || 4)); while (d < today) d = addDays(d, step); exDivEst = d; }
    }
    const events = { earnings: er?.d ?? null, earnTime: er?.time ?? null, earnEst: earn[0] ? earn[0].date_estimated === true : null,
      exDiv: exDiv ? String(exDiv.ex_date) : null, divAmt: exDiv ? Number(exDiv.cash_amount) : null, exDivEst };
    return json(200, {
      ok: true, v: 1, build: BUILD, source: useTheta ? 'theta' : 'polygon', ms: Date.now() - t0,
      t, name: shortName, strategy, S: +S.toFixed(4), prev: +prev.toFixed(4), move: prev > 0 ? +(S / prev - 1).toFixed(5) : 0,
      open: mins >= 9 * 60 + 30 && mins < 16 * 60, today,
      // The 20% day opens the calls to ATM, a 2 SD drop in an uptrend the puts to one strike in the money.
      cfg: { cLo: exps.some((x) => x.R.kc === 0) ? 0 : CFG.cLo, cHi: CFG.cHi, pLo: exps.some((x) => x.R.kp < 0) ? ITM : CFG.pLo, pHi: CFG.pHi },
      counts,
      // The chart lines: what was sold, at the values from when it was sold.
      // got (what was got a share) and iv (its own IV) price a held leg that ends after the chosen expiry (sale, 1.9).
      // z0 and fill (Positions page): the strike's SD when sold, from option_fill_context.
      sold: [...name.soldCalls.map((l) => ({ put: false, K: l.K, n: l.n, ex: l.ex, be: l.at != null ? +(l.K + l.at).toFixed(4) : null, got: l.at, iv: l.iv || null, ...fillOf(false, l.K, l.ex) })),
             ...name.soldPuts.map((l) => ({ put: true, K: l.K, n: l.n, ex: l.ex, be: l.at != null ? +(l.K - l.at).toFixed(4) : null, got: l.at, iv: l.iv || null, ...fillOf(true, l.K, l.ex) }))],
      // How many calls are covered (1.4): shares, and the OTM calls bought with their expiries. r and q price held legs.
      cover: { shares, otm: name.longCalls.map((l) => ({ ex: l.ex, n: l.n })) },
      r: +r.toFixed(4), q: +q.toFixed(4),
      // Positions page (2026-11-13): see the header.
      tech, day, closes: closes30, events,
      exps: exps.map((x) => x.data),
      // What you hold (Nik 11 Nov): each expiry where you have sold calls AND sold puts, as one pair, at the sale prices.
      held: [...new Set(name.soldCalls.map((l) => l.ex))].filter((ex) => name.soldPuts.some((l) => l.ex === ex)).sort().flatMap((ex) => {
        const cs = name.soldCalls.filter((l) => l.ex === ex), ps = name.soldPuts.filter((l) => l.ex === ex);
        const m = exps.find((x) => x.data.ex === ex)?.data.m ?? iv30 * Math.sqrt(yrs(ex));
        const h = heldPair(cs, ps, S, m);
        if (!h || h.dn == null) return [];
        const side = (ls: Leg[]) => ls.map((l) => ({ K: l.K, n: l.n })).sort((a, b) => a.K - b.K);
        const r4 = (v: number | null) => (v == null ? null : +v.toFixed(4));
        return [{ ex, label: md(ex), calls: side(cs), puts: side(ps), tot: Math.round(h.tot),
          up: r4(h.up), dn: r4(h.dn), sdUp: r4(h.sdUp), sdDn: r4(h.sdDn), cop: r4(h.cop) }];
      }),
    });
  } catch (e) {
    return json(502, { ok: false, build: BUILD, t, error: String((e as Error)?.message ?? e) });
  }
});
