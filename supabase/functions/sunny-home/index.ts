/**
 * sunny-home — the new app's Home page in one row (handoff 18, Step 2).
 *
 * ⚠ ONE READ EVERY 30 s (Nik, 12 Oct 2026: "make the new app much faster").
 * This builds every number Home shows after each price pass and stores it as
 * a single row in `home_snapshot`; the app reads that row and nothing else on
 * the tick. Insight words, Performance and the Theta check are NOT on the
 * tick (blocks 22, 20, 07): they are worked out on open, pull and the close.
 *
 * ⚠ THE PAYLOAD IS NEVER RETURNED BY THIS FUNCTION. It is deployed with
 * verify_jwt = false (the scheduler sends an sb_secret key, not a JWT), so
 * anyone can call it; the account data only leaves through `home_snapshot`,
 * which RLS keeps to the signed-in app.
 *
 * Sources: option_trades (paged), option_greeks_live, ticker_quotes_live,
 * market_live (Yahoo), account_value_daily / account_positions_daily (IBKR
 * Daily Flex, both accounts), market_calendar, earnings_events,
 * earnings_season, daily_closes, and Theta for an earnings card's priced move.
 *
 * Body: { passes?: 1|2 } (cron sends nothing: two passes in market hours,
 * 30 s apart, a quiet pass every 10 minutes otherwise).
 */
const BUILD = '2026-10-19.1';
const BOOK_START = '2026-08-31';          // PNL_GLOSSARY: the stock-replacement shift
const WATCH = ['INTU', 'ADBE', 'PYPL', 'VZ', 'TMUS', 'SPCX', 'TSLA', 'APP'];   // + SPCX TSLA APP (Nik, 14 Oct 2026); keep earnings-sync's WATCH in step
/* ⚠ WRITE RULES FROM RESEARCH (Nik, 14 Oct 2026, docs/TSLA_SPCX_RESEARCH.md).
   A name here does not take the roll sheet: its calls are `cover` of its LEAPs,
   all at the first strike `otmPct`% or more above spot, every week; Inventory
   counts it full at that share. Dormant until the name is held. */
const WRITE_RULES: Record<string, { cover: number; otmPct: number }> = {
  TSLA: { cover: 0.7, otmPct: 3 },   // sideways view: B, 3% out on 70%
  SPCX: { cover: 0.5, otmPct: 5 },   // very bullish: deep LEAP, 5% out on 50%
};
const coverOf = (t: string, leaps: number) =>
  WRITE_RULES[t] ? Math.floor(leaps * WRITE_RULES[t].cover + 0.5) : leaps;
/* Options on these trade to 4:15 ET (block 01). One config; extend here. */
const TRADE_TO_415 = ['SPY', 'QQQ', 'IWM', 'DIA'];
/* The weekly put write as a share of the puts bought (Nik, 13 Oct 2026). */
const PUT_SHARE = 0.3;
/* The in-the-money put overlay (Nik, 15 Oct 2026; forward test in research/itm-puts):
   long puts on half the LEAPs, weekly puts sold on half of those, at the first strike
   at least otmPct% below spot and never above a long put's strike, so each one stays
   covered. Held names only for now. */
/* ONE RULE (Nik, 16 Oct 2026): the Planner sells calls on every LEAP, the full
   quantity; delta is kept by BUYING the quarterly and yearly upside calls, never
   by selling fewer. The 20% cushion trim (15 Oct) is gone. The Delta card's band
   still runs 10 points higher the week a name reports. */
const DELTA_EARN_BUMP = 10;
/* ⚠ THE READ RULE (NKE weekly rule, trial; Nik 17 Oct 2026; docs/STRATEGIES.md).
   NKE ONLY for now. The week's write comes from the daily reads
   (ticker_technicals.reads, written by ticker-technicals), as tested in
   research/target-study/playbook_replay.py ('candidate, 10% free'):
     IV skip -> nothing that week; earnings before expiry -> every call at 1 SD, no puts;
     else the menu: start 0.6 SD (0.8 if momentum bullish), one step wider if stretched up
     or momentum + technicals both bullish, one step closer (20% at the money + 0.6 SD)
     if stretched down or fundamentals bearish, never past 1 SD; breakout week -> the
     next strike above the 5-day high; ex-dividend before expiry with calls within 2%
     -> two thirds of the calls; puts on half the long puts at 0.6 SD (0.8 if momentum
     bearish), none if stretched down, never above a long put's strike.
   `cover` is the share of the LEAPs sold (54 of 60: 10% kept free). NKE's one exception
   to ONE RULE below. Inventory still counts every LEAP (its max is coverage). Reads
   older than READS_STALE_DAYS fall back to the roll-sheet rule. */
const READ_RULES: Record<string, { cover: number }> = { NKE: { cover: 0.9 } };
const READ_MENU: [number, number][] = [[0.2, 0.6], [0, 0.6], [0, 0.8], [0, 1.0]];   // [at-the-money share, SD of the rest]
const READS_STALE_DAYS = 5;
const PUT_RULES: Record<string, { share: number; otmPct: number }> = {
  NKE: { share: 0.5, otmPct: 2 }, LULU: { share: 0.5, otmPct: 2 },
  BABA: { share: 0.5, otmPct: 2 }, NFLX: { share: 0.5, otmPct: 2 },
  UBER: { share: 0.5, otmPct: 2 },          // added 15 Oct 2026 once UBER had long puts (Nik)
};

const URL_ = Deno.env.get('SUPABASE_URL')!;
const KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const THETA = Deno.env.get('THETA_URL') ?? '';
const THETA_KEY = Deno.env.get('THETA_PROXY_KEY') ?? '';
const H = { apikey: KEY, Authorization: `Bearer ${KEY}`, 'Content-Type': 'application/json' };

// deno-lint-ignore no-explicit-any
type Row = Record<string, any>;

async function get(q: string): Promise<Row[]> {
  const r = await fetch(`${URL_}/rest/v1/${q}`, { headers: H });
  if (!r.ok) throw new Error(`${q.split('?')[0]} ${r.status} ${(await r.text()).slice(0, 160)}`);
  return await r.json();
}
/** PostgREST caps a read at 1,000 rows, silently: page anything that grows.
 *  The first page asks for the total, and the rest are fetched side by side
 *  (audit, 13 Oct 2026: sequential pages were most of the build). The query
 *  must carry a deterministic order, or pages can overlap. */
async function page(q: string): Promise<Row[]> {
  const one = async (from: number, count = false) => {
    const r = await fetch(`${URL_}/rest/v1/${q}`, { headers: { ...H, Range: `${from}-${from + 999}`,
      ...(count ? { Prefer: 'count=exact' } : {}) } });
    if (!r.ok) throw new Error(`${q.split('?')[0]} ${r.status} ${(await r.text()).slice(0, 160)}`);
    return { rows: await r.json() as Row[], total: Number((r.headers.get('content-range') ?? '').split('/')[1]) };
  };
  const first = await one(0, true);
  if (first.rows.length < 1000) return first.rows;
  const total = Number.isFinite(first.total) && first.total > 0 ? Math.min(first.total, 100_000) : null;
  if (total == null) {             // no count: fall back to one page at a time
    const out = [...first.rows];
    for (let from = 1000; from < 100_000; from += 1000) {
      const { rows } = await one(from); out.push(...rows); if (rows.length < 1000) break;
    }
    return out;
  }
  const rest = await Promise.all(Array.from({ length: Math.ceil(total / 1000) - 1 }, (_, i) => one((i + 1) * 1000)));
  return [...first.rows, ...rest.flatMap((x) => x.rows)];
}

function ny(d = new Date()) {
  const p = Object.fromEntries(new Intl.DateTimeFormat('en-US', {
    timeZone: 'America/New_York', weekday: 'short', hour: '2-digit', minute: '2-digit',
    year: 'numeric', month: '2-digit', day: '2-digit', hourCycle: 'h23',
  }).formatToParts(d).map((x) => [x.type, x.value]));
  return { wd: p.weekday as string, mins: Number(p.hour) * 60 + Number(p.minute),
           date: `${p.year}-${p.month}-${p.day}` };
}
const addDays = (iso: string, n: number) =>
  new Date(Date.parse(iso + 'T12:00:00Z') + n * 864e5).toISOString().slice(0, 10);
const r2 = (v: number) => Math.round(v * 100) / 100;
const num = (v: unknown) => (v === null || v === undefined || v === '' ? null : Number(v));

// ── Black-Scholes, only for an earnings card's straddle (spot from parity) ──
function impliedSpot(rows: { side: string; k: number; bid: number; ask: number }[], T: number): number | null {
  const by = new Map<number, { c?: number; p?: number }>();
  for (const r of rows) {
    if (!(r.bid > 0 && r.ask > 0)) continue;
    const e = by.get(r.k) ?? {}; const mid = (r.bid + r.ask) / 2;
    if (r.side === 'call') e.c = mid; else e.p = mid; by.set(r.k, e);
  }
  let best: { k: number; c: number; p: number } | null = null;
  for (const [k, e] of by) {
    if (e.c == null || e.p == null) continue;
    if (!best || Math.abs(e.c - e.p) < Math.abs(best.c - best.p)) best = { k, c: e.c, p: e.p };
  }
  return best ? best.c - best.p + best.k * Math.exp(-0.04 * T) : null;
}

async function thetaJson(path: string): Promise<Row[]> {
  const r = await fetch(`${THETA}${path}&format=json`,
    { headers: { 'x-proxy-key': THETA_KEY }, signal: AbortSignal.timeout(12_000) });
  if (!r.ok) return [];
  return ((await r.json())?.response ?? []) as Row[];
}

/** The move options price in for a report: the at-the-money straddle on the
 *  first expiry after it, over the spot (block 04: "±8.2% move"). */
async function pricedMove(ticker: string, reportDate: string, time: string | null): Promise<number | null> {
  if (!THETA) return null;
  const exps = (await thetaJson(`/v3/option/list/expirations?symbol=${ticker}`))
    .map((r) => String(r.expiration ?? r.date ?? '')).filter(Boolean)
    .map((e) => e.includes('-') ? e : `${e.slice(0, 4)}-${e.slice(4, 6)}-${e.slice(6, 8)}`).sort();
  /* A before-the-open report is priced into that day's expiry; after the
     close, only the next one. */
  const exp = exps.find((e) => time === 'bmo' ? e >= reportDate : e > reportDate);
  if (!exp) return null;
  const q = await thetaJson(`/v3/option/snapshot/quote?symbol=${ticker}&expiration=${exp.replaceAll('-', '')}`);
  const rows = q.filter((r) => r.data?.[0]).map((r) => ({
    side: String(r.contract.right).toLowerCase(), k: Number(r.contract.strike),
    bid: Number(r.data[0].bid), ask: Number(r.data[0].ask) }));
  const T = Math.max(1 / 365, (Date.parse(exp + 'T20:00:00Z') - Date.now()) / (365 * 864e5));
  const S = impliedSpot(rows, T);
  if (!S) return null;
  let atm: number | null = null;
  for (const r of rows) if (atm == null || Math.abs(r.k - S) < Math.abs(atm - S)) atm = r.k;
  const c = rows.find((r) => r.k === atm && r.side === 'call'), p = rows.find((r) => r.k === atm && r.side === 'put');
  if (!c || !p || !(c.ask > 0) || !(p.ask > 0)) return null;
  const straddle = (c.bid > 0 ? (c.bid + c.ask) / 2 : c.ask / 2) + (p.bid > 0 ? (p.bid + p.ask) / 2 : p.ask / 2);
  return r2(straddle / S * 100);
}


// ── Black-Scholes for the roll (r = 4%, no dividend: the backend's standard) ──
const RATE = 0.04;
const ncdf = (x: number) => { const t = 1 / (1 + 0.2316419 * Math.abs(x));
  const d = 0.3989423 * Math.exp(-x * x / 2);
  const p = d * t * (0.3193815 + t * (-0.3565638 + t * (1.781478 + t * (-1.821256 + t * 1.330274))));
  return x > 0 ? 1 - p : p; };
const npdf = (x: number) => Math.exp(-x * x / 2) / Math.sqrt(2 * Math.PI);
function bsCall(S: number, K: number, T: number, v: number) {
  const d1 = (Math.log(S / K) + (RATE + v * v / 2) * T) / (v * Math.sqrt(T)), d2 = d1 - v * Math.sqrt(T);
  return { price: S * ncdf(d1) - K * Math.exp(-RATE * T) * ncdf(d2), delta: ncdf(d1),
           thetaDay: (-(S * npdf(d1) * v) / (2 * Math.sqrt(T)) - RATE * K * Math.exp(-RATE * T) * ncdf(d2)) / 365 };
}
function ivCall(mid: number, S: number, K: number, T: number): number | null {
  if (!(mid > Math.max(0, S - K * Math.exp(-RATE * T)))) return null;
  let lo = 0.01, hi = 3;
  for (let i = 0; i < 60; i++) { const m = (lo + hi) / 2; if (bsCall(S, K, T, m).price > mid) hi = m; else lo = m; }
  return (lo + hi) / 2;
}

type LegLite = { ticker: string; strike: number; expiry: string; n: number; mark: number | null; iv: number | null;
                 delta: number | null; theta: number | null; underlying: number | null };
/** The roll for a dragging LEAP: next January a year further out, at the
 *  strike nearest 0.725 delta (Nik: "around 70 to 75 delta"). */
const ROLL_DELTA = 0.725;
/* `ratioNow` and `ratioAfter` are the book's 2-week ratio (the Theta card's
   number, the one the 3x line is drawn on), now and with this LEAP's theta
   swapped for the new one's; never today's single-day ratio. */
async function rollFor(l: LegLite, oldTh: number, ratioNow: number | null, ratioAfter: (newTh: number) => number | null,
                       commPer: number, spotNow: number | null): Promise<Row> {
  const exps = (await thetaJson(`/v3/option/list/expirations?symbol=${l.ticker}`))
    .map((r) => String(r.expiration ?? r.date ?? '')).filter(Boolean)
    .map((e) => e.includes('-') ? e : `${e.slice(0, 4)}-${e.slice(4, 6)}-${e.slice(6, 8)}`).sort();
  const wantYear = Number(l.expiry.slice(0, 4)) + 1;
  const exp = exps.find((e) => e.startsWith(`${wantYear}-01`)) ?? exps.filter((e) => e > l.expiry).at(-1);
  if (!exp) return { error: 'no later expiry listed' };
  const ex = exp.replaceAll('-', '');
  const [q, oi, oiOld] = await Promise.all([
    thetaJson(`/v3/option/snapshot/quote?symbol=${l.ticker}&expiration=${ex}`),
    thetaJson(`/v3/option/snapshot/open_interest?symbol=${l.ticker}&expiration=${ex}`),
    thetaJson(`/v3/option/snapshot/open_interest?symbol=${l.ticker}&expiration=${l.expiry.replaceAll('-', '')}`),
  ]);
  const T = Math.max(1 / 365, (Date.parse(exp + 'T20:00:00Z') - Date.now()) / (365 * 864e5));
  const rows = q.filter((r) => r.data?.[0]).map((r) => ({ side: String(r.contract.right).toLowerCase(),
    k: Number(r.contract.strike), bid: Number(r.data[0].bid), ask: Number(r.data[0].ask) }));
  /* ⚠ OUR LIVE SPOT, NOT THIS CHAIN'S PARITY: a year-plus out, dividends
     drag parity (NKE Jan 2029 read 34.01 against 35.33). */
  const S = spotNow ?? l.underlying ?? impliedSpot(rows, T) ?? 0;
  let pick: Row | null = null;
  for (const r of rows.filter((x) => x.side === 'call' && x.bid > 0 && x.ask > 0)) {
    const mid = (r.bid + r.ask) / 2, v = ivCall(mid, S, r.k, T);
    if (v == null) continue;
    const g = bsCall(S, r.k, T, v);
    if (!pick || Math.abs(g.delta - ROLL_DELTA) < Math.abs(Number(pick.delta) - ROLL_DELTA)) pick = { k: r.k, mid, iv: v, ...g };
  }
  if (!pick) return { error: 'no priced call on ' + exp };
  const oiOf = (rs: Row[], k: number) => Number(rs.find((r) => String(r.contract.right).toLowerCase() === 'call'
    && Number(r.contract.strike) === k)?.data?.[0]?.open_interest ?? NaN) || null;
  const n = l.n, oldMark = l.mark ?? 0;
  const newTh = Math.abs(Number(pick.thetaDay)) * n * 100;
  return {
    close: { expiry: l.expiry, strike: l.strike, contracts: n, price: r2(oldMark) },
    open: { expiry: exp, strike: Number(pick.k), contracts: n, price: r2(Number(pick.mid)) },
    net_debit: Math.round((Number(pick.mid) - oldMark) * n * 100),
    commission_fees: r2(commPer * n * 2),
    theta_day: { old: Math.round(oldTh), new: Math.round(newTh) },
    time_value_left: { old: Math.round(Math.max(0, oldMark - Math.max(0, S - l.strike)) * n * 100),
                       new: Math.round(Math.max(0, Number(pick.mid) - Math.max(0, S - Number(pick.k))) * n * 100) },
    iv: { old: l.iv, new: r2(Number(pick.iv)) },
    delta: { old: l.delta, new: r2(Number(pick.delta)) },
    open_interest: { old: oiOf(oiOld, l.strike), new: oiOf(oi, Number(pick.k)) },
    book_ratio: { now: ratioNow, after: (() => { const a = ratioAfter(newTh); return a == null ? null : r2(a); })() },
    spot: r2(S),
  };
}

/* opts.dry (admin, mode 'theta_check'): run the check now and write nothing to
   theta_checks or the heartbeat; opts.price prices the roll for that ticker's
   LEAPs (or '*' for all) whether or not they flag. For checking the check. */
async function build(mode: 'tick' | 'theta_check' | 'history' | 'last_week' = 'tick',
                     opts: { dry?: boolean; price?: string } = {}): Promise<{ payload: Row; ms: number; steps: Record<string, number> }> {
  let checkSummary: Row[] | null = null;
  /* Where the build's time goes, returned with the timings (no data). */
  const steps: Record<string, number> = {};
  let tStep = Date.now();
  const step = (label: string) => { const n = Date.now(); steps[label] = n - tStep; tStep = n; };
  const t0 = Date.now();
  const now = ny();
  const today = now.date;
  const monthsBack = (iso: string, m: number) => {
    const [y, mo] = iso.split('-').map(Number);
    const d = new Date(Date.UTC(y, mo - 1 - m, 1));
    return d.toISOString().slice(0, 10);
  };
  /* Rolling 3 calendar months (block 15), never before the book: Nik took the
     proposal to start the charts on 1 Sep 2026. */
  const winStart = [monthsBack(today, 2), '2026-09-01'].sort().at(-1)!;
  const marksFrom = [addDays(today, -45), addDays(winStart, -10), addDays(BOOK_START, -5)].sort()[0];

  const [trades, greeks, quotes, market, acctDays, cal, earn, seasons, closes, runs, sells, lots, savedReports, macro,
         openChecks, divs, posAll, lmd, chainRows, savedHistory, divPast, upQuotes] = await Promise.all([
    page('option_trades?voided_at=is.null&order=id.asc&select=id,ticker,trade_date,action,option_type,'
      + 'direction,contracts,strike,premium,expiry,executed_at,commission,net_cash,realized_pl,realized_pl_source,note'),
    /* One row per leg ever marked: grows with every trade, so paged. */
    page('option_greeks_live?order=option_trade_id.asc&select=option_trade_id,last_mark,iv,delta,gamma,theta,vega,underlying,captured_at'),
    get('ticker_quotes_live?select=ticker,spot,day_change_pct,captured_at'),
    get('market_live?select=*'),
    get(`account_value_daily?report_date=gte.${addDays(BOOK_START, -5)}&order=report_date.desc`),
    get(`market_calendar?date=gte.${addDays(BOOK_START, -40)}&date=lte.${addDays(today, 120)}&order=date.asc`),
    get(`earnings_events?report_date=gte.${addDays(today, -1)}&report_date=lte.${addDays(today, 70)}`
      + '&select=ticker,report_date,report_time,date_estimated,source&order=report_date.asc'),
    get('earnings_season?select=*&order=starts.desc&limit=6'),
    page(`daily_closes?date=gte.${[addDays(today, -45), addDays(BOOK_START, -7)].sort()[0]}&order=date.asc,ticker.asc&select=ticker,date,close_price`),
    get('ibkr_sync_runs?status=eq.success&order=finished_at.desc&limit=1&select=finished_at'),
    get(`share_sells?voided_at=is.null&trade_date=gte.${BOOK_START}&select=ticker,trade_date,quantity,price,realized_pl`),
    get(`share_lots?voided_at=is.null&acquired_date=gte.${BOOK_START}&select=ticker,acquired_date,qty_original,cost_per_share`),
    get(`reports?shown_on=gte.${addDays(today, -1)}&select=kind,period_start,payload`),
    get(`macro_events?event_date=gte.${today}&event_date=lte.${addDays(today, 21)}&importance=gte.3`
      + '&category=in.(inflation,jobs,rates)&order=event_date.asc&select=event_date,event_time,name'),
    get('theta_checks?status=eq.open&select=*&order=found_on.asc'),
    get(`dividends?ex_date=gte.${today}&ex_date=lte.${addDays(today, 45)}&select=ticker,ex_date,pay_date,cash_amount&order=ex_date.asc`),
    /* ⚠ ONE ROUND TRIP (audit, 13 Oct 2026). These used to wait their turn
       mid-build and cost ~0.3 s of a 0.55 s build. IBKR's daily positions
       cover both the live value's anchor and the value side's history. */
    page(`account_positions_daily?report_date=gte.${[addDays(winStart, -10), addDays(BOOK_START, -3)].sort()[0]}&order=report_date.asc,account_id.asc,conid.asc`
      + '&select=report_date,account_id,conid,symbol,underlying,asset_category,put_call,strike,expiry,multiplier,position,'
      + 'mark_price,position_value,cost_basis_money'),
    page(`leg_marks_daily?day=gte.${marksFrom}&order=day.asc,option_trade_id.asc`
      + '&select=option_trade_id,day,mark,delta,theta,underlying'),
    page('option_chain_next?select=ticker,expiry,side,strike,mid,delta,iv,oi,spot'
      + '&order=ticker.asc,expiry.asc,side.asc,strike.asc'),
    page('account_history?order=day.asc&select=day,nav,cash,margin,interest_cum,commission_cum,dividends_cum,'
      + 'realized_cum,unrealized,time_value,capital_long,shares_value,groups'),
    get(`dividends?pay_date=gt.${BOOK_START}&pay_date=lte.${today}&select=ticker,ex_date,pay_date&order=pay_date.asc,ticker.asc`),
    /* The 3- and 12-month upside calls the Planner sizes (chain-next, 15 min). */
    get('option_chain_upside?select=ticker,tenor,expiry,strike,mid,delta,spot&order=ticker.asc,tenor.asc,strike.asc'),
  ]);

  step('reads');
  // ── Trading days (calendar-aware) ──
  const closed = new Set(cal.filter((c) => c.kind === 'closed').map((c) => String(c.date)));
  const isTrading = (d: string) => {
    const wd = new Date(d + 'T12:00:00Z').getUTCDay();
    return wd !== 0 && wd !== 6 && !closed.has(d);
  };
  const prevTrading = (d: string) => { let x = addDays(d, -1); while (!isTrading(x)) x = addDays(x, -1); return x; };
  const nextTrading = (d: string) => { let x = addDays(d, 1); while (!isTrading(x)) x = addDays(x, 1); return x; };

  // ── Open legs: pooled FIFO per contract, as mp-refresh and the iOS app ──
  const keyOf = (t: Row) => `${String(t.ticker).toUpperCase()}|${t.option_type}|${t.direction}|${Number(t.strike)}|${t.expiry}`;
  const groups = new Map<string, Row[]>();
  for (const t of trades) { const k = keyOf(t); (groups.get(k) ?? groups.set(k, []).get(k)!).push(t); }
  const gBy = new Map(greeks.map((g) => [String(g.option_trade_id), g]));
  type Leg = { ticker: string; type: 'call' | 'put'; side: 'sold' | 'bought'; strike: number; expiry: string;
    n: number; avg: number; opened: string; mark: number | null; iv: number | null; delta: number | null;
    theta: number | null; gamma: number | null; vega: number | null; underlying: number | null; marked_at: string | null;
    mark_wk?: number | null };
  const legs: Leg[] = [];
  for (const rows of groups.values()) {
    const opens = rows.filter((r) => r.action === 'open').sort((a, b) => (a.id < b.id ? -1 : 1));
    let closeQty = rows.filter((r) => r.action === 'close').reduce((s, r) => s + Number(r.contracts), 0);
    const left = opens.map((o) => ({ o, n: Number(o.contracts) }));
    for (const s of left) { const take = Math.min(closeQty, s.n); s.n -= take; closeQty -= take; if (closeQty <= 0) break; }
    const live = left.filter((s) => s.n > 0);
    const f = rows[0];
    if (!live.length || String(f.expiry) < today) continue;
    const n = live.reduce((s, x) => s + x.n, 0);
    const g = live.map((s) => gBy.get(String(s.o.id))).filter(Boolean)
      .sort((a, b) => String(b!.captured_at).localeCompare(String(a!.captured_at)))[0];
    legs.push({
      ticker: String(f.ticker).toUpperCase(), type: f.option_type, side: f.direction === 'short' ? 'sold' : 'bought',
      strike: Number(f.strike), expiry: String(f.expiry), n,
      avg: r2(live.reduce((s, x) => s + x.n * Number(x.o.premium), 0) / n * 10000) / 10000,
      opened: live.map((s) => String(s.o.trade_date)).sort()[0],
      mark: num(g?.last_mark), iv: num(g?.iv), delta: num(g?.delta), theta: num(g?.theta),
      gamma: num(g?.gamma), vega: num(g?.vega), underlying: num(g?.underlying), marked_at: g?.captured_at ?? null,
    });
  }
  legs.sort((a, b) => a.ticker.localeCompare(b.ticker) || a.expiry.localeCompare(b.expiry) || a.strike - b.strike);
  const book = [...new Set(legs.map((l) => l.ticker))].sort();
  /* ⚠ UPSIDE CALLS ARE NOT LEAPS (Nik, 16 Oct 2026). The 3- and 12-month calls
     bought out of the money for a big jump carry no sold call, are not on the
     Inventory shelf or in Payback, and are not part of the delta base; they
     count in long delta only. A bought call is upside if it was 8%+ out of the
     money on the day it was opened, or out of the money with 13 months or less
     to run. Every LEAP was in or at the money when bought (PEP 140 at 140.34). */
  const priceOn = (t: string, d: string) => {
    let b: number | null = null;
    for (const c of closes) if (c.ticker === t && String(c.date) <= d) b = Number(c.close_price);
    return b;
  };
  const upside = new Set(legs.filter((l) => {
    if (l.side !== 'bought' || l.type !== 'call') return false;
    const S = priceOn(l.ticker, l.opened) ?? l.underlying;
    if (!S) return false;
    const months = (Date.parse(l.expiry) - Date.parse(l.opened)) / (30.44 * 864e5);
    return l.strike >= S * 1.08 || (l.strike > S && months <= 13);
  }));
  const isLeap = (l: Leg) => l.side === 'bought' && l.type === 'call' && !upside.has(l);
  const upKeys = new Set([...upside].map((l) => `${l.ticker}|call|${l.strike}|${l.expiry}`));

  /* ── Hourly closes for the Positions Chart cards (handoff 22, block 13) ──
     The last five sessions that have opened (today once it is past 9:30),
     10:00 to 16:00 New York, from our own 30 s quotes (`hourly_closes`).
     `ahead` lists the sessions still to come in the next week, so a sold
     card can run its empty hours into the expiry. Started here, awaited at
     the payload: it runs beside the rest of the build. */
  const sessions: string[] = [];
  for (let d = isTrading(today) && now.mins >= 9 * 60 + 30 ? today : prevTrading(today); sessions.length < 5; d = prevTrading(d)) sessions.unshift(d);
  const ahead: string[] = [];
  /* To next Friday (eleven days from a Monday): the Planner (block 14b)
     runs its empty hours to the Friday it plans for. Positions keeps only
     the days up to each card's own expiry. */
  for (let d = addDays(sessions[4], 1); d <= addDays(today, 11); d = addDays(d, 1)) if (isTrading(d)) ahead.push(d);
  const hoursP: Promise<Row> = book.length
    ? fetch(`${URL_}/rest/v1/rpc/hourly_closes`, { method: 'POST', headers: H,
        body: JSON.stringify({ p_tickers: book, p_days: sessions }) })
      .then(async (r) => {
        if (!r.ok) throw new Error(`hourly_closes ${r.status} ${(await r.text()).slice(0, 160)}`);
        const px: Record<string, (number | null)[]> = Object.fromEntries(book.map((t) => [t, Array(35).fill(null)]));
        for (const x of await r.json() as Row[]) {
          const j = sessions.indexOf(String(x.day));
          if (px[x.ticker] && j >= 0) px[x.ticker][j * 7 + Number(x.hr) - 10] = Math.round(Number(x.spot) * 1000) / 1000;
        }
        return { days: sessions, ahead, px };
      })
      /* A failed read must not stop Home: the cards fall back to the price. */
      .catch((e) => ({ days: sessions, ahead, px: {}, error: String(e).slice(0, 160) }))
    : Promise.resolve({ days: sessions, ahead, px: {} });

  /* ── REALIZED, per docs/PNL_GLOSSARY.md (Nik chose the glossary for the
     header, 12 Oct 2026). Only what closed: sold options bought back or
     expired, bought options sold or expired, and shares sold. IBKR's AVERAGE
     cost (28 Sep ruling), and IBKR's own realized_pl wherever the Daily Flex
     delivered it (it carries commissions and handles assignments: an assigned
     option books 0, its premium lives in the share sale). Booked on the close
     date, or the expiry date for a leg left to expire. A leg is in or out by
     when it was OPENED: nothing opened before 31 Aug 2026 counts. */
  /* `leg` names the line on the report ("NKE 36C"), `how` says how it closed,
     `basis` is the credit (sold) or cost (bought) behind it, for "kept 92%". */
  type Ev = { d: string; ticker: string; kind: 'calls sold' | 'puts sold' | 'calls bought' | 'puts bought' | 'shares';
              amt: number; leg: string; how: 'expired' | 'closed' | 'assigned' | 'exercised' | 'sold'; basis: number; exp?: string };
  const realized: Ev[] = [];
  /* Premium in hand on open shorts, as dated cash moves: the credit on the
     sale, taken back out when the leg closes or expires (its result is then in
     `realized`). Payback's "made" = realized + this (Nik, 13 Oct 2026). */
  const heldFlows: { d: string; amt: number }[] = [];
  const heldCost = new Map<string, { n: number; cost: number }>();
  for (const [k, rows] of groups) {
    const fills = [...rows].sort((a, b) => String(a.trade_date).localeCompare(String(b.trade_date))
      || String(a.executed_at ?? '').localeCompare(String(b.executed_at ?? ''))
      || (a.action === 'open' ? -1 : 1));
    const firstOpen = fills.find((f) => f.action === 'open');
    if (!firstOpen || String(firstOpen.trade_date) < BOOK_START) continue;
    const f0 = fills[0];
    const short = f0.direction === 'short';
    const kind = `${f0.option_type === 'call' ? 'calls' : 'puts'} ${short ? 'sold' : 'bought'}` as Ev['kind'];
    const leg = `${String(f0.ticker).toUpperCase()} ${r2(Number(f0.strike))}${f0.option_type === 'call' ? 'C' : 'P'}`;
    const exp = String(f0.expiry);
    let qty = 0, cost = 0;
    for (const t of fills) {
      const n = Number(t.contracts), px = Number(t.premium) * 100;
      if (t.action === 'open') { qty += n; cost += n * px; if (short) heldFlows.push({ d: String(t.trade_date), amt: n * px }); continue; }
      const avg = qty > 0 ? cost / qty : 0;
      if (short) heldFlows.push({ d: String(t.trade_date), amt: -n * avg });
      const ib = t.realized_pl != null && t.realized_pl_source === 'ibkr' ? Number(t.realized_pl) : null;
      const amt = ib ?? (short ? n * (avg - px) : n * (px - avg));
      const code = String(t.note ?? '').match(/IBKR (A|Ex|Ep) lifecycle/)?.[1];
      const how = code === 'Ep' ? 'expired' : code === 'A' ? 'assigned' : code === 'Ex' ? 'exercised' : 'closed';
      realized.push({ d: String(t.trade_date), ticker: String(f0.ticker).toUpperCase(), kind, amt, leg, how,
        basis: n * avg, exp });
      cost -= n * avg; qty -= n;
    }
    if (qty > 0.0001 && String(f0.expiry) < today) {
      realized.push({ d: exp, ticker: String(f0.ticker).toUpperCase(), kind, amt: short ? cost : -cost, leg,
        how: 'expired', basis: cost, exp });
      if (short) heldFlows.push({ d: exp, amt: -cost });
    } else if (qty > 0.0001) {
      heldCost.set(k, { n: qty, cost });
    }
  }
  /* Shares sold count only when the lot was bought inside the book: the
     31 Aug / 1 Sep unwind of the old share blocks is history, the September
     put assignments sold on the 21st are not. */
  for (const s of sells) {
    const t = String(s.ticker).toUpperCase(), d = String(s.trade_date);
    if (!lots.some((l) => String(l.ticker).toUpperCase() === t && String(l.acquired_date) <= d)) continue;
    realized.push({ d, ticker: t, kind: 'shares', amt: Number(s.realized_pl ?? 0), leg: `${t} shares`, how: 'sold',
      basis: 0 });
  }
  /* Average cost of what is still held, IBKR's method, for every open leg. */
  for (const l of legs) {
    const h = heldCost.get(`${l.ticker}|${l.type}|${l.side === 'sold' ? 'short' : 'long'}|${l.strike}|${l.expiry}`);
    if (h && h.n > 0) l.avg = Math.round(h.cost / h.n / 100 * 10000) / 10000;
  }

  // Contract marks (either side), for valuing IBKR's positions.
  const markOf = new Map<string, { mark: number; at: string }>();
  for (const t of trades) {
    const g = gBy.get(String(t.id)); if (!g || g.last_mark == null) continue;
    const k = `${String(t.ticker).toUpperCase()}|${t.option_type}|${Number(t.strike)}|${t.expiry}`;
    const cur = markOf.get(k);
    if (!cur || String(g.captured_at) > cur.at) markOf.set(k, { mark: Number(g.last_mark), at: String(g.captured_at) });
  }
  const spotOf = new Map<string, number>();
  for (const q of quotes) if (q.spot != null) spotOf.set(String(q.ticker).toUpperCase(), Number(q.spot));
  for (const m of market) if (m.price != null && !spotOf.has(String(m.symbol))) spotOf.set(String(m.symbol), Number(m.price));

  step('legs+realized');
  // ── Account: IBKR's last close, moved by today's prices and fills ──
  const anchor = acctDays.find((d) => Number(d.accounts) >= 2) ?? null;
  let account: Row = { ok: false, why: 'no IBKR daily statement yet' };
  if (anchor) {
    const D = String(anchor.report_date);
    const posD = posAll.filter((p) => String(p.report_date) === D);
    let moveHeld = 0, mvNow = 0, unpriced = 0;
    for (const p of posD) {
      const q = Number(p.position), m = Number(p.multiplier ?? 1), was = Number(p.mark_price);
      let nowMark: number | null;
      if (p.asset_category === 'OPT') {
        const type = p.put_call === 'C' ? 'call' : 'put';
        nowMark = String(p.expiry) < today ? 0
          : (markOf.get(`${String(p.underlying).toUpperCase()}|${type}|${Number(p.strike)}|${p.expiry}`)?.mark ?? null);
      } else {
        nowMark = spotOf.get(String(p.symbol).toUpperCase()) ?? null;
      }
      if (nowMark == null) { unpriced++; nowMark = was; }
      moveHeld += q * m * (nowMark - was);
      mvNow += q * m * nowMark;
    }
    /* Fills since that close: their cash, plus what they hold now at the mark. */
    let fills = 0, cashIn = 0, commToday = 0, nFills = 0;
    for (const t of trades) {
      if (String(t.trade_date) <= D) continue;
      const sells = (t.direction === 'short') === (t.action === 'open');
      const ct = Number(t.contracts);
      const cash = t.net_cash != null ? Number(t.net_cash) : (sells ? 1 : -1) * Number(t.premium) * ct * 100;
      const qty = (t.action === 'open' ? 1 : -1) * (t.direction === 'short' ? -1 : 1) * ct;
      const k = `${String(t.ticker).toUpperCase()}|${t.option_type}|${Number(t.strike)}|${t.expiry}`;
      const mk = String(t.expiry) < today ? 0 : (markOf.get(k)?.mark ?? Number(t.premium));
      fills += cash + qty * 100 * mk; cashIn += cash; mvNow += qty * 100 * mk;
      commToday += Number(t.commission ?? 0); nFills++;
    }
    const navD = Number(anchor.nav);
    const value = navD + moveHeld + fills;
    /* "Today" is against the last close before today. On a weekend or a
       holiday that is the last session's own move. */
    const prevClose = prevTrading(today);
    const tradingToday = isTrading(today);
    let base = navD, baseDate = D, stale = false;
    if (!tradingToday) {
      const before = acctDays.find((d) => String(d.report_date) < D && Number(d.accounts) >= 2);
      if (before) { base = Number(before.nav); baseDate = String(before.report_date); }
    } else if (D !== prevClose) stale = true;
    const sum = (from: string, f: string) => acctDays
      .filter((d) => String(d.report_date) >= from && String(d.report_date) <= D)
      .reduce((s, d) => s + Number(d[f] ?? 0), 0);
    const monthStart = today.slice(0, 8) + '01';
    const realizedSince = (from: string) => r2(realized.filter((e) => e.d >= from && e.d <= today)
      .reduce((s, e) => s + e.amt, 0));
    /* UNREALIZED, glossary: open positions only, paper only. Bought legs at
       mark against their average cost; sold legs at minus their mark (the
       premium on an open short is NOT in it, it is PREMIUM_UNREALIZED);
       shares at spot against IBKR's cost basis. */
    let unrealized = 0, tvSold = 0;
    for (const l of legs) {
      const m = l.mark ?? 0;
      unrealized += l.side === 'bought' ? (m - l.avg) * l.n * 100 : -m * l.n * 100;
      if (l.side === 'sold') {
        const S = spotOf.get(l.ticker) ?? l.underlying ?? 0;
        const intrinsic = l.type === 'call' ? Math.max(0, S - l.strike) : Math.max(0, l.strike - S);
        tvSold += Math.max(0, m - intrinsic) * l.n * 100;
      }
    }
    for (const p of posD) {
      if (p.asset_category !== 'STK') continue;
      const spot = spotOf.get(String(p.symbol).toUpperCase()) ?? Number(p.mark_price);
      unrealized += Number(p.position) * spot - Number(p.cost_basis_money ?? 0);
    }
    account = {
      ok: true,
      value: r2(value),
      today: { amount: r2(value - base), pct: base ? r2((value - base) / Math.abs(base) * 100) : null, vs: baseDate,
               stale_anchor: stale },
      market_value: r2(mvNow),
      cash: r2(Number(anchor.cash) + cashIn),
      /* Block 02 (handoff 19): Market value is renamed Margin, account value
         plus net borrowed across both accounts (Nik, 13 Oct 2026). */
      margin: r2(value + Math.max(0, -(Number(anchor.cash) + cashIn))),
      /* Both accounts, net (Nik: never one account alone). Commission and
         interest in IBKR's sign: negative is a cost. */
      /* Nik, 12 Oct 2026: Realized = the glossary's REALIZED for the period;
         Unrealized = paper P&L now (the same in both periods); Time value =
         what is left in the options he sold. */
      unrealized: r2(unrealized),
      time_value_sold: r2(tvSold),
      month: { from: monthStart, realized: realizedSince(monthStart),
        commission: r2(sum(monthStart, 'commissions') + commToday),
        interest: r2(sum(monthStart, 'interest_accrued')) },
      book: { from: BOOK_START, realized: realizedSince(BOOK_START),
        commission: r2(sum(BOOK_START, 'commissions') + commToday),
        interest: r2(sum(BOOK_START, 'interest_accrued')) },
      ibkr_close: { date: D, value: r2(navD), accounts: Number(anchor.accounts) },
      fills_since_close: nFills, unpriced_positions: unpriced,
    };
  }

  step('account');
  // ── Market: Today row, overnight, watchlist ──
  const mk = (s: string) => market.find((m) => m.symbol === s);
  const closeSeries = (t: string) => closes.filter((c) => c.ticker === t).map((c) => ({ d: String(c.date), c: Number(c.close_price) }));
  /* % moves for the shared range filter: today, then the close 5/10/15/20
     sessions back (Portfolio and Watchlist, block 10). */
  const ranges = (t: string, price: number | null, dayPct: number | null) => {
    const s = closeSeries(t).filter((x) => x.d < today);
    const back = (n: number) => (s.length >= n ? s[s.length - n].c : null);
    const pct = (b: number | null) => (price != null && b ? r2((price / b - 1) * 100) : null);
    return { d: dayPct != null ? r2(dayPct) : pct(back(1)), w1: pct(back(5)), w2: pct(back(10)), w3: pct(back(15)), w4: pct(back(20)) };
  };
  const tape = (m: Row | undefined) => m && ({
    symbol: m.symbol, label: m.label, state: m.market_state, price: num(m.price), prev_close: num(m.prev_close),
    change_pct: num(m.regular_change_pct), change: num(m.regular_change),
    pre: num(m.pre_price), pre_pct: num(m.pre_change_pct), post: num(m.post_price), post_pct: num(m.post_change_pct),
    /* The last regular close: before the open it is the 16:00 close the
       morning's moves run from (prev_close is then the day before). */
    regular: num(m.regular_price), regular_at: m.regular_time ?? null,
    at: m.captured_at,
  });
  const indices = ['SPY', 'QQQ', 'IWM', '^VIX'].map((s) => tape(mk(s))).filter(Boolean);
  const overnight = ['^N225', '^GDAXI', '^NSEI', '000001.SS'].map((s) => tape(mk(s))).filter(Boolean);
  /* Futures for the 7:00-9:30 cards (handoff 24, block 09): each card's 16:00
     close times (future now / its 16:00 price). The base is the future's last
     stored 16:00 before today; the app judges staleness from `at` (Yahoo runs
     ~10 min behind; Nik allows 20). VIX has no future here (no VX on Yahoo). */
  const futures = [['SPY', 'ES=F', 'ES'], ['QQQ', 'NQ=F', 'NQ'], ['IWM', 'RTY=F', 'RTY']].map(([card, sym, pill]) => {
    const m = mk(sym);
    const b = closes.filter((c) => c.ticker === sym && String(c.date) < today).sort((x, y) => String(y.date).localeCompare(String(x.date)))[0];
    return { card, symbol: sym, pill, price: num(m?.price), at: m?.regular_time ?? null,
             base: b ? Number(b.close_price) : null, base_date: b ? String(b.date) : null };
  });
  const watchlist = WATCH.map((s) => {
    const m = mk(s); if (!m) return null;
    return { ticker: s, price: num(m.regular_price), ranges: ranges(s, num(m.regular_price), num(m.regular_change_pct)) };
  }).filter(Boolean);

  // ── Portfolio: exposure per name, moves per range ──
  const sharesNow = new Map<string, number>();
  const shareCost = new Map<string, number>();
  if (anchor) {
    const posD = posAll.filter((p) => String(p.report_date) === String(anchor.report_date) && p.asset_category === 'STK');
    for (const p of posD) {
      const t = String(p.symbol).toUpperCase();
      sharesNow.set(t, (sharesNow.get(t) ?? 0) + Number(p.position));
      shareCost.set(t, (shareCost.get(t) ?? 0) + Number(p.cost_basis_money ?? 0));
    }
  }
  const names = [...new Set([...book, ...sharesNow.keys()])].sort();
  const portfolio = names.map((t) => {
    const ls = legs.filter((l) => l.ticker === t);
    const spot = spotOf.get(t) ?? ls.find((l) => l.underlying)?.underlying ?? null;
    const shareValue = (sharesNow.get(t) ?? 0) * (spot ?? 0);
    const optValue = ls.reduce((s, l) => s + (l.side === 'sold' ? -1 : 1) * (l.mark ?? 0) * l.n * 100, 0);
    const q = quotes.find((x) => String(x.ticker).toUpperCase() === t);
    return { ticker: t, spot, exposure: r2(shareValue + optValue), share_value: r2(shareValue), option_value: r2(optValue),
             ranges: ranges(t, spot, num(q?.day_change_pct)) };
  });

  step('market+portfolio');
  // ── Risk: Theta and Delta now (history comes from the daily roll-up) ──
  const tick = new Map<string, { collect: number; lose: number; longD: number; soldD: number; hedgeD: number;
    scD: number; spD: number; shares: number }>();
  let thShort = 0, thLong = 0, dLong = 0, dSold = 0, dHedge = 0, dSC = 0, dSP = 0, shLong = 0;
  for (const l of legs) {
    const e = tick.get(l.ticker) ?? { collect: 0, lose: 0, longD: 0, soldD: 0, hedgeD: 0, scD: 0, spD: 0, shares: 0 };
    const th = Math.abs(l.theta ?? 0) * l.n * 100;
    if (l.side === 'sold') { thShort += th; e.collect += th; } else { thLong += th; e.lose += th; }
    /* Delta (Nik, 16 Oct 2026): short = everything sold, calls and puts, as
       sizes added; long = every call bought (LEAPs and the upside calls); the
       hedge puts bought are their own number. (Was calls only, 12 Oct.) */
    if (isLeap(l)) { shLong += l.n * 100; e.shares += l.n * 100; }
    /* Judged on next week (Nik, 16 Oct 2026): a leg expiring today is left
       out, so a Friday's expiring calls never read as "buy back". */
    if (l.delta != null && l.expiry > today) {
      const d = Math.abs(l.delta) * l.n * 100;
      if (l.side === 'sold') {
        dSold += d; e.soldD += d;
        if (l.type === 'call') { dSC += d; e.scD += d; } else { dSP += d; e.spD += d; }
      }
      else if (l.type === 'call') { dLong += d; e.longD += d; }
      else { dHedge += d; e.hedgeD += d; }
    }
    tick.set(l.ticker, e);
  }
  const risk = {
    theta: { short: r2(thShort), long: r2(thLong), ratio_now: thLong > 0 ? r2(thShort / thLong) : null,
      by: [...tick].map(([t, e]) => ({ ticker: t, collect: r2(e.collect), lose: r2(e.lose), net: r2(e.collect - e.lose) }))
        .sort((a, b) => Math.abs(b.net) - Math.abs(a.net)) },
    /* NET DELTA LEFT (Nik, 16 Oct 2026): calls bought - calls sold + puts sold
       - hedge puts, as a % of the shares the LEAPs control; the band is one
       for every name: under 15 red, 15-20 amber, 20-30 on target, over 30
       room to sell. Same base as the Planner's 20% cushion. */
    delta: { sold: Math.round(dSold), long: Math.round(dLong), hedge: Math.round(dHedge),
      sold_calls: Math.round(dSC), sold_puts: Math.round(dSP), net: Math.round(dLong - dSC + dSP - dHedge), shares: shLong,
      pct_now: shLong > 0 ? r2((dLong - dSC + dSP - dHedge) / shLong * 100) : null,
      ratio_now: dLong > 0 ? r2(dSold / dLong * 100) : null,
      by: [...tick].filter(([, e]) => e.longD > 0)
        .map(([t, e]) => {
          const net = e.longD - e.scD + e.spD - e.hedgeD, pct = e.shares > 0 ? net / e.shares * 100 : 0;
          /* The tag: Sell over 30, Fine 20-30, Watch 15-20, Buy back under 15;
             10 points higher the week the name reports (Nik, 16 Oct 2026). */
          const earnWeek = earn.some((x) => String(x.ticker).toUpperCase() === t
            && String(x.report_date) >= today && String(x.report_date) <= addDays(today, 7));
          const up = earnWeek ? DELTA_EARN_BUMP : 0;
          const tag = pct < 15 + up ? 'buy_back' : pct < 20 + up ? 'watch' : pct <= 30 + up ? 'fine' : 'sell';
          /* The alert (handoff 25, block 16): red when net short, orange under
             20% (30% the week it reports); nothing else is coloured. */
          const alert = pct < 0 ? 'red' : pct < 20 + up ? 'orange' : null;
          return { ticker: t, sold: Math.round(e.soldD), long: Math.round(e.longD), hedge: Math.round(e.hedgeD),
                   sold_calls: Math.round(e.scD), sold_puts: Math.round(e.spD), net: Math.round(net), shares: e.shares,
                   pct: r2(pct), tag, alert, earnings_week: earnWeek };
        })
        .sort((a, b) => b.pct - a.pct) },
  };

  step('risk');
  // ════════════════════════════════════════════════════════════════════════
  // THE CARDS' HISTORY: one point per trading day, from leg_marks_daily.
  // ════════════════════════════════════════════════════════════════════════
  const days: string[] = [];
  for (let d = winStart; d < today; d = addDays(d, 1)) if (isTrading(d)) days.push(d);
  const markDay = new Map<string, Map<string, Row>>();      // day -> trade id -> row
  for (const r of lmd) {
    const d = String(r.day);
    (markDay.get(d) ?? markDay.set(d, new Map()).get(d)!).set(String(r.option_trade_id), r);
  }
  const closeOn = (t: string, d: string): number | null => {
    let best: number | null = null;
    for (const c of closes) if (c.ticker === t && String(c.date) <= d) best = Number(c.close_price);
    return best;
  };
  type DayLeg = { key: string; ticker: string; type: string; short: boolean; strike: number; expiry: string; n: number; ids: string[] };
  /** The book as it stood at the close of `d`: pooled per contract. */
  const legsAt = (d: string): DayLeg[] => {
    const out: DayLeg[] = [];
    for (const [k, rows] of groups) {
      const f = rows[0];
      if (String(f.expiry) < d) continue;
      let n = 0; const ids: string[] = [];
      for (const t of rows) {
        if (String(t.trade_date) > d) continue;
        if (t.action === 'open') { n += Number(t.contracts); ids.push(String(t.id)); } else n -= Number(t.contracts);
      }
      if (n > 0.0001) out.push({ key: k, ticker: String(f.ticker).toUpperCase(), type: f.option_type,
        short: f.direction === 'short', strike: Number(f.strike), expiry: String(f.expiry), n, ids });
    }
    return out;
  };
  /* A leg's greeks on `d`: that day's last capture, else the latest before. */
  const greekOn = (ids: string[], d: string): Row | null => {
    for (let back = 0; back < 6; back++) {
      const m = markDay.get(addDays(d, -back)); if (!m) continue;
      for (const id of ids) { const r = m.get(id); if (r) return r; }
    }
    return null;
  };
  type Point = { d: string; thS: number; thL: number; dS: number; dL: number; dH: number; dSC: number; dSP: number; sh: number;
                 longMV: number; shortMV: number;
                 thLongBy: Record<string, number> };
  const pointOf = (d: string, live: boolean): Point => {
    const p: Point = { d, thS: 0, thL: 0, dS: 0, dL: 0, dH: 0, dSC: 0, dSP: 0, sh: 0, longMV: 0, shortMV: 0, thLongBy: {} };
    const ls = live
      ? legs.map((l) => ({ ticker: l.ticker, type: l.type, short: l.side === 'sold', n: l.n, expiry: l.expiry,
          g: { theta: l.theta, delta: l.delta, mark: l.mark } as Row, key: `${l.ticker}|${l.type}|${l.strike}|${l.expiry}` }))
      : legsAt(d).map((l) => ({ ticker: l.ticker, type: l.type, short: l.short, n: l.n, expiry: l.expiry, g: greekOn(l.ids, d) ?? {},
          key: `${l.ticker}|${l.type}|${l.strike}|${l.expiry}` }));
    for (const l of ls) {
      const th = Math.abs(Number(l.g.theta ?? 0)) * l.n * 100;
      const mv = Number(l.g.mark ?? 0) * l.n * 100;
      if (l.short) { p.thS += th; p.shortMV += mv; } else {
        p.thL += th; p.longMV += mv; p.thLongBy[l.key] = (p.thLongBy[l.key] ?? 0) + th;
      }
      if (!l.short && l.type === 'call' && !upKeys.has(l.key)) p.sh += l.n * 100;
      if (l.g.delta != null && l.expiry > d) {     // same split and basis as the live card above
        const dl = Math.abs(Number(l.g.delta)) * l.n * 100;
        if (l.short) { p.dS += dl; if (l.type === 'call') p.dSC += dl; else p.dSP += dl; }
        else if (l.type === 'call') p.dL += dl; else p.dH += dl;
      }
    }
    return p;
  };
  const series = days.map((d) => pointOf(d, false));
  /* ⚠ IBKR'S CLOSING VALUES WIN FOR THE VALUE SIDE. Our end-of-day option
     mids put single days of Sold vs Bought thousands off IBKR's (1 Oct: -6.1K
     against IBKR's -1.4K); IBKR's daily statement carries every position's
     closing value, so a day it covers takes those. Greeks have no IBKR twin. */
  const ibkrMV = new Map<string, { long: number; short: number }>();
  for (const r of posAll.filter((x) => String(x.report_date) >= winStart && x.asset_category === 'OPT')) {
    const d = String(r.report_date), e = ibkrMV.get(d) ?? { long: 0, short: 0 };
    if (Number(r.position) > 0) e.long += Number(r.position_value); else e.short -= Number(r.position_value);
    ibkrMV.set(d, e);
  }
  for (const p of series) {
    const e = ibkrMV.get(p.d);
    if (e) { p.longMV = e.long; p.shortMV = e.short; }
  }
  const livePoint = isTrading(today) ? pointOf(today, true) : null;
  const all = livePoint ? [...series, livePoint] : series;
  /* The 2-week average: the mean of the last ten daily ratios (block 15: it
     smooths the Monday-to-Friday sawtooth so only the trend shows). */
  const avg10 = (arr: (number | null)[], i: number) => {
    const xs = arr.slice(Math.max(0, i - 9), i + 1).filter((x): x is number => x != null && isFinite(x));
    return xs.length ? xs.reduce((s, x) => s + x, 0) / xs.length : null;
  };
  const thetaDaily = all.map((p) => (p.thL > 0 ? p.thS / p.thL : null));
  const deltaDaily = all.map((p) => (p.dL > 0 ? p.dS / p.dL * 100 : null));
  const trendOf = (arr: (number | null)[]) => {
    const now = arr.at(-1), then = arr.length > 5 ? arr[arr.length - 6] : null;
    if (now == null || then == null || then === 0) return 'steady';
    const ch = (now - then) / Math.abs(then);
    return ch < -0.05 ? 'downslope' : ch > 0.05 ? 'climbing' : 'steady';
  };
  const theta2w = all.map((_, i) => avg10(thetaDaily, i));
  const delta2w = all.map((_, i) => avg10(deltaDaily, i));
  const peakAt = theta2w.reduce<number>((b, v, i) => (v != null && (b < 0 || v > (theta2w[b] ?? -1)) ? i : b), -1);
  const history = {
    from: winStart, live_today: !!livePoint,
    days: all.map((p) => p.d),
    theta: { daily: thetaDaily.map((x) => (x == null ? null : r2(x))), avg2w: theta2w.map((x) => (x == null ? null : r2(x))),
      now: theta2w.at(-1) == null ? null : r2(theta2w.at(-1)!), trend: trendOf(theta2w),
      peak: peakAt >= 0 ? { d: all[peakAt].d, v: r2(theta2w[peakAt]!), at_right_edge: peakAt >= all.length * 0.9 } : null,
      short: all.map((p) => Math.round(p.thS)), long: all.map((p) => Math.round(p.thL)) },
    delta: { daily: deltaDaily.map((x) => (x == null ? null : Math.round(x))), avg2w: delta2w.map((x) => (x == null ? null : Math.round(x))),
      now: delta2w.at(-1) == null ? null : Math.round(delta2w.at(-1)!), trend: trendOf(delta2w),
      sold: all.map((p) => Math.round(p.dS)), long: all.map((p) => Math.round(p.dL)), hedge: all.map((p) => Math.round(p.dH)),
      /* Net delta left, % of LEAP shares, each day as it was (no averaging:
         the cushion is a now number). */
      net_pct: all.map((p) => (p.sh > 0 ? r2((p.dL - p.dSC + p.dSP - p.dH) / p.sh * 100) : null)),
      net: all.map((p) => Math.round(p.dL - p.dSC + p.dSP - p.dH)), shares: all.map((p) => p.sh) },
  };

  step('history');
  // ── Payback (block 18): what the LEAPs cost, split, and how it comes back ──
  const leapLots: { ticker: string; k: number; d: string; n: number; tv: number; intr: number }[] = [];
  for (const l of legs.filter(isLeap)) {
    const rows = groups.get(`${l.ticker}|call|long|${l.strike}|${l.expiry}`) ?? [];
    for (const t of rows.filter((r) => r.action === 'open').sort((a, b) => String(a.trade_date).localeCompare(String(b.trade_date)))) {
      const d = String(t.trade_date);
      const S = Number(markDay.get(d)?.get(String(t.id))?.underlying ?? NaN) || closeOn(l.ticker, d) || 0;
      const intr = Math.max(0, S - l.strike), prem = Number(t.premium);
      leapLots.push({ ticker: l.ticker, k: l.strike, d, n: Number(t.contracts), intr, tv: Math.max(0, prem - intr) });
    }
  }
  /* Only what is still held: a LEAP sold leaves both targets (block 18). A
     lot's share of a partly-sold leg is scaled to what remains. */
  for (const l of legs.filter(isLeap)) {
    const mine = leapLots.filter((x) => x.ticker === l.ticker && x.k === l.strike);
    const bought = mine.reduce((s, x) => s + x.n, 0);
    if (bought > l.n) { const f = l.n / bought; for (const x of mine) x.n *= f; }
  }
  const premiumBy = (t: string, from: string, to: string) => realized
    .filter((e) => e.ticker === t && (e.kind === 'calls sold' || e.kind === 'puts sold') && e.d >= from && e.d <= to)
    .reduce((s, e) => s + e.amt, 0);
  const paybackOn = (d: string, live: boolean) => {
    let tvT = 0, inT = 0, inPaid = 0;
    const firstBy = new Map<string, string>();
    for (const x of leapLots) {
      if (x.d > d) continue;
      tvT += x.tv * x.n * 100; inT += x.intr * x.n * 100;
      const S = live ? (spotOf.get(x.ticker) ?? closeOn(x.ticker, d) ?? 0) : (closeOn(x.ticker, d) ?? 0);
      inPaid += (Math.max(0, S - x.k) - x.intr) * x.n * 100;
      if (!firstBy.has(x.ticker) || x.d < firstBy.get(x.ticker)!) firstBy.set(x.ticker, x.d);
    }
    let tvPaid = 0;
    for (const [t, from] of firstBy) tvPaid += premiumBy(t, from, d);
    /* Combined Payback (Nik, 13 Oct 2026): everything made since the first LEAP,
       sold premium, puts and calls bought, shares, any close, book-wide; the card
       adds the intrinsic change and sets it against the whole LEAP cost. */
    const first = [...firstBy.values()].sort()[0];
    const allReal = first ? realized.filter((e) => e.d >= first && e.d <= d).reduce((s, e) => s + e.amt, 0) : 0;
    const held = first ? heldFlows.filter((e) => e.d >= first && e.d <= d).reduce((s, e) => s + e.amt, 0) : 0;
    return { d, tvT: Math.round(tvT), inT: Math.round(inT), tvPaid: Math.round(tvPaid), inPaid: Math.round(inPaid),
      allReal: Math.round(allReal), held: Math.round(held) };
  };
  const firstLeap = leapLots.map((x) => x.d).sort()[0] ?? null;
  const payDays = firstLeap ? [...days.filter((d) => d >= firstLeap)] : [];
  const paySeries = payDays.map((d) => paybackOn(d, false));
  if (firstLeap && isTrading(today)) paySeries.push(paybackOn(today, true));
  const paceOf = (f: 'tvPaid' | 'inPaid' | 'all' | 'made') => {
    if (paySeries.length < 2) return null;
    const v = (p: typeof paySeries[number]) => f === 'all' ? p.allReal + p.inPaid : f === 'made' ? p.allReal + p.held : p[f];
    const now = paySeries.at(-1)!, i0 = Math.max(0, paySeries.length - 1 - 25);
    const weeks = Math.max(1, (paySeries.length - 1 - i0) / 5);
    return Math.round((v(now) - v(paySeries[i0])) / weeks);
  };
  const payback = paySeries.length ? {
    now: paySeries.at(-1), pace_tv: paceOf('tvPaid'), pace_intr: paceOf('inPaid'), pace_all: paceOf('all'),
    pace_made: paceOf('made'),
    series: paySeries.map((p) => [p.d, p.tvT, p.tvPaid, p.inT, p.inPaid, p.allReal, p.held]),
    new_leap_days: [...new Set(leapLots.map((x) => x.d))].sort(),
  } : null;

  // ── Yield (block 17): every short credit, filed under the week it covers ──
  const weekStartOf = (iso: string) => { const d = new Date(iso + 'T12:00:00Z'); const wd = (d.getUTCDay() + 6) % 7; return addDays(iso, -wd); };
  /* Time value at a trade (Yield's third mode, block 17): the premium less
     what was intrinsic at that day's close. */
  const tvOf = (t: Row, call: boolean) => {
    const px = closeOn(String(t.ticker), String(t.trade_date)), k = Number(t.strike), prem = Number(t.premium);
    const intr = px == null ? 0 : call ? Math.max(0, px - k) : Math.max(0, k - px);
    return Math.max(0, prem - intr) * Number(t.contracts) * 100;
  };
  const yieldWeeks = new Map<string, { cs: number; cb: number; ps: number; pb: number; cst: number; cbt: number;
    pst: number; pbt: number; month: string }>();
  for (const [, rows] of groups) {
    const f = rows[0];
    if (f.direction !== 'short') continue;
    const firstOpen = rows.filter((r) => r.action === 'open').map((r) => String(r.trade_date)).sort()[0];
    if (!firstOpen || firstOpen < BOOK_START) continue;
    const exp = String(f.expiry), w = weekStartOf(exp);
    const e = yieldWeeks.get(w) ?? { cs: 0, cb: 0, ps: 0, pb: 0, cst: 0, cbt: 0, pst: 0, pbt: 0, month: exp.slice(0, 7) };
    for (const t of rows) {
      const c = Number(t.contracts) * Number(t.premium) * 100, call = f.option_type === 'call', tv = tvOf(t, call);
      if (call) { if (t.action === 'open') { e.cs += c; e.cst += tv; } else { e.cb += c; e.cbt += tv; } }
      else { if (t.action === 'open') { e.ps += c; e.pst += tv; } else { e.pb += c; e.pbt += tv; } }
    }
    yieldWeeks.set(w, e);
  }
  /* The divisor is what is invested in the long legs still held, as at the
     end of that week: the current app's rule, so both apps agree. */
  const investedAsOf = (end: string) => {
    let s = 0;
    for (const l of legs.filter((x) => x.side === 'bought')) {
      for (const t of groups.get(`${l.ticker}|${l.type}|long|${l.strike}|${l.expiry}`) ?? []) {
        if (String(t.trade_date) > end) continue;
        s += (t.action === 'open' ? 1 : -1) * Number(t.contracts) * Number(t.premium) * 100;
      }
    }
    return s;
  };
  const investedNow = investedAsOf(today);
  const yieldOut = [...yieldWeeks].sort((a, b) => a[0].localeCompare(b[0])).map(([w, e]) => {
    const inv = investedAsOf(addDays(w, 6)) || investedNow;
    return { week: w, fri: addDays(w, 4), month: e.month, calls_sold: Math.round(e.cs), calls_back: Math.round(e.cb),
             puts_sold: Math.round(e.ps), puts_back: Math.round(e.pb), invested: Math.round(inv),
             calls_sold_tv: Math.round(e.cst), calls_back_tv: Math.round(e.cbt),
             puts_sold_tv: Math.round(e.pst), puts_back_tv: Math.round(e.pbt) };
  });

  // ── Inventory (block 14): the shelf, now and per week covered ──
  const invNow = new Map<string, { cH: number; cS: number; pH: number; pS: number; credit: number }>();
  for (const l of legs) {
    const e = invNow.get(l.ticker) ?? { cH: 0, cS: 0, pH: 0, pS: 0, credit: 0 };
    if (l.type === 'call') { if (l.side === 'bought') { if (isLeap(l)) e.cH += l.n; } else e.cS += l.n; }
    else { if (l.side === 'bought') e.pH += l.n; else e.pS += l.n; }
    if (l.side === 'sold') e.credit += l.avg * l.n * 100;
    invNow.set(l.ticker, e);
  }
  /* A name with a research rule is full at its share of the LEAPs (WRITE_RULES). */
  const invRows = [...invNow].map(([t, e]) => ({ ticker: t, calls_max: coverOf(t, e.cH), calls_sold: e.cS, puts_max: e.pH,
    puts_sold: e.pS, credit_open: Math.round(e.credit) }));
  /* ROLLS (handoff 24, block 14): a short closed and a short opened on the same
     day, same ticker and type, the new expiry later. Rolled = the smaller side,
     per day; it stays in the week it left (a hatched top on that bar) and the
     new contracts count again in their own week. */
  type Roll = { t: string; type: string; from: string; to: string; n: number };
  const rolls: Roll[] = [];
  {
    const day = new Map<string, { closes: Map<string, number>; opens: Map<string, number> }>();
    for (const r of trades) {
      if (r.direction !== 'short') continue;
      const k = `${String(r.ticker).toUpperCase()}|${r.option_type}|${r.trade_date}`;
      const e = day.get(k) ?? { closes: new Map(), opens: new Map() };
      const side = r.action === 'close' ? e.closes : r.action === 'open' ? e.opens : null;
      if (side) side.set(String(r.expiry), (side.get(String(r.expiry)) ?? 0) + Number(r.contracts));
      day.set(k, e);
    }
    for (const [k, e] of day) {
      const [t, type] = k.split('|');
      const opens = [...e.opens].sort((a, b) => a[0].localeCompare(b[0])).map(([x, n]) => ({ x, n }));
      for (const [from, n0] of [...e.closes].sort((a, b) => a[0].localeCompare(b[0]))) {
        let left = n0;
        for (const o of opens) {
          if (left <= 0) break;
          if (o.x <= from || o.n <= 0) continue;
          const n = Math.min(left, o.n);
          rolls.push({ t, type, from, to: o.x, n }); left -= n; o.n -= n;
        }
      }
    }
  }
  const rolledOut = (w: string, type: string) => rolls.filter((r) => r.type === type && weekStartOf(r.from) === w);
  /* The week the shelf is on now: this Friday's, or the coming one at the weekend. */
  const shelfWeek = (() => { const d = new Date(today + 'T12:00:00Z'), wd = d.getUTCDay();
    return weekStartOf(addDays(today, wd === 6 ? 2 : wd === 0 ? 1 : 0)); })();
  /* Per week covered, the most contracts that were ON at once: a roll closes
     one strike and opens another, so counting every sale would put a fully
     covered week over its own max. Fills replay in order, closes first on a
     tie, and the peak of the running count is the week's bar. */
  const invWeeks = [...yieldWeeks.keys()].sort().map((w) => {
    const peak = (type: string) => {
      const fills: Row[] = [];
      for (const [, rows] of groups) {
        const f = rows[0];
        if (f.direction === 'short' && f.option_type === type && weekStartOf(String(f.expiry)) === w) fills.push(...rows);
      }
      fills.sort((a, b) => String(a.trade_date).localeCompare(String(b.trade_date))
        || String(a.executed_at ?? '').localeCompare(String(b.executed_at ?? ''))
        || (a.action === 'close' ? -1 : 1));
      let on = 0, max = 0;
      for (const t of fills) { on += (t.action === 'open' ? 1 : -1) * Number(t.contracts); max = Math.max(max, on); }
      return max;
    };
    const rc = rolledOut(w, 'call'), rp = rolledOut(w, 'put');
    const out = [...rc, ...rp];
    return { week: w, fri: addDays(w, 4), calls: peak('call'), puts: peak('put'),
             calls_rolled: rc.reduce((s, r) => s + r.n, 0), puts_rolled: rp.reduce((s, r) => s + r.n, 0),
             rolled_to: out.length ? out.map((r) => r.to).sort().slice(-1)[0] : null,
             rolled_names: [...new Set(out.map((r) => r.t))].sort() };
  });
  const inventory = {
    calls_max: invRows.reduce((s, r) => s + r.calls_max, 0), calls_sold: invRows.reduce((s, r) => s + r.calls_sold, 0),
    puts_max: invRows.reduce((s, r) => s + r.puts_max, 0), puts_sold: invRows.reduce((s, r) => s + r.puts_sold, 0),
    credit_open: invRows.reduce((s, r) => s + r.credit_open, 0),
    by: invRows.filter((r) => r.calls_max + r.puts_max > 0)
      .map((r) => ({ ...r, rolled: rolls.filter((x) => x.t === r.ticker && weekStartOf(x.from) === shelfWeek).reduce((s, x) => s + x.n, 0) }))
      .sort((a, b) => (a.calls_max ? a.calls_sold / a.calls_max : 1) - (b.calls_max ? b.calls_sold / b.calls_max : 1)),
    weeks: invWeeks,
  };

  // ── Sold vs Bought (block 19): per trading day, so any period adds up ──
  /* Longs: the change in value of everything bought, plus its cash (a buy is
     not a gain, a sale is not a loss). Shorts: REALIZED premium on calls and
     puts sold, on the day it settled. Each side keeps its own bar. */
  const longCash = new Map<string, number>();
  for (const [, rows] of groups) {
    const f = rows[0];
    /* Every bought leg, whenever opened: the value side counts every long
       held, so its cash must too (an Aug put sold on 1 Oct read -$12K). */
    if (f.direction === 'short') continue;
    for (const t of rows) {
      const d = String(t.trade_date);
      const c = t.net_cash != null ? Number(t.net_cash)
        : (t.action === 'open' ? -1 : 1) * Number(t.contracts) * Number(t.premium) * 100;
      longCash.set(d, (longCash.get(d) ?? 0) + c);
    }
  }
  const sbDays = all.map((p, i) => {
    const prev = i > 0 ? all[i - 1].longMV : null;
    const longs = prev == null ? null : p.longMV - prev + (longCash.get(p.d) ?? 0);
    const shorts = realized.filter((e) => e.d === p.d && (e.kind === 'calls sold' || e.kind === 'puts sold'))
      .reduce((s, e) => s + e.amt, 0);
    return [p.d, longs == null ? null : Math.round(longs), Math.round(shorts)];
  });
  const soldVsBought = {
    days: sbDays,
    open_credit: Math.round(legs.filter((l) => l.side === 'sold').reduce((s, l) => s + l.avg * l.n * 100, 0)),
  };

  // ── Performance (block 20): realized by month, name and kind; open by name ──
  const perfMap = new Map<string, number>();
  for (const e of realized) {
    const k = `${e.d.slice(0, 7)}|${e.ticker}|${e.kind}`;
    perfMap.set(k, (perfMap.get(k) ?? 0) + e.amt);
  }
  const unrealBy = new Map<string, number>();
  for (const l of legs) {
    const m = l.mark ?? 0;
    const u = l.side === 'bought' ? (m - l.avg) * l.n * 100 : (l.avg - m) * l.n * 100;
    const kind = `${l.type === 'call' ? 'calls' : 'puts'} ${l.side}`;
    const k = `${l.opened.slice(0, 7)}|${l.ticker}|${kind}`;
    unrealBy.set(k, (unrealBy.get(k) ?? 0) + u);
  }
  const performance = {
    realized: [...perfMap].map(([k, v]) => [...k.split('|'), Math.round(v)]),
    /* Open P&L by the month each leg was opened (Unrealized filter). Here a
       sold leg counts its credit against its mark, as on the Positions card. */
    unrealized: [...unrealBy].map(([k, v]) => [...k.split('|'), Math.round(v)]),
  };

  // ── Allocation (block 21): one holding per company, plus Cash ──
  const holdings = names.map((t) => {
    const ls = legs.filter((l) => l.ticker === t);
    const sh = sharesNow.get(t) ?? 0;
    const spot = spotOf.get(t) ?? 0;
    const now = sh * spot + ls.reduce((s, l) => s + (l.side === 'sold' ? -1 : 1) * (l.mark ?? 0) * l.n * 100, 0);
    /* Invested nets the credit of open sold legs against the cost of the
       bought ones, so Now minus Invested is the name's open P&L. */
    const invested = ls.reduce((s, l) => s + (l.side === 'sold' ? -1 : 1) * l.avg * l.n * 100, 0) + (shareCost.get(t) ?? 0);
    return { ticker: t, now: Math.round(now), invested: Math.round(invested) };
  }).sort((a, b) => b.now - a.now);
  const allocation = { holdings, cash: account.ok ? Math.round(Number(account.cash)) : null };

  step('cards');
  // ── Deck inputs ──
  const upcomingEarn = new Map<string, Row>();
  for (const e of earn) {
    const t = String(e.ticker).toUpperCase();
    if (!book.includes(t) && !sharesNow.has(t)) continue;
    const cur = upcomingEarn.get(t);
    /* A confirmed date beats an estimate on the same name. */
    if (!cur || (cur.date_estimated && !e.date_estimated) || String(e.report_date) < String(cur.report_date)) upcomingEarn.set(t, e);
  }
  const next1 = nextTrading(today);
  const earnings = await Promise.all([...upcomingEarn.values()].map(async (e) => {
    const t = String(e.ticker).toUpperCase(), d = String(e.report_date);
    const ls = legs.filter((l) => l.ticker === t);
    /* The card comes one trading day ahead (block 04), so only those get a
       priced move; the rest are dates for the season card and the report. */
    const due = (d === today && e.report_time === 'amc') || (d === next1 && e.report_time !== 'amc')
      || (d === today && !e.report_time);
    return {
      ticker: t, date: d, time: e.report_time ?? null, estimated: !!e.date_estimated,
      calls_on: ls.filter((l) => l.type === 'call').reduce((s, l) => s + l.n, 0),
      puts_on: ls.filter((l) => l.type === 'put').reduce((s, l) => s + l.n, 0),
      shares: sharesNow.get(t) ?? 0,
      exposure: portfolio.find((p) => p.ticker === t)?.exposure ?? 0,
      priced_move_pct: due ? await pricedMove(t, d, e.report_time ?? null).catch(() => null) : null,
    };
  }));
  earnings.sort((a, b) => a.date.localeCompare(b.date) || Math.abs(b.exposure) - Math.abs(a.exposure));
  const season = seasons.find((s) => String(s.starts) <= today && today <= String(s.ends))
    ?? seasons.find((s) => String(s.starts) > today && String(s.starts) <= addDays(today, 7)) ?? null;
  let seasonOut: Row | null = null;
  if (season) {
    const inside = earnings.filter((e) => e.date >= String(season.starts) && e.date <= String(season.ends));
    let fifth = String(season.starts); for (let i = 0; i < 4; i++) fifth = nextTrading(fifth);
    seasonOut = { quarter: season.quarter, starts: season.starts, ends: season.ends, show_through: fifth,
      names: inside.length, last: inside.map((e) => e.date).sort().at(-1) ?? null,
      only: inside.length === 1 ? { ticker: inside[0].ticker, date: inside[0].date } : null };
  }

  // ── Freshness, for the Updated pill and the live glow ──
  const maxAt = (rows: Row[], f = 'captured_at') => rows.reduce((m, r) => (String(r[f] ?? '') > m ? String(r[f]) : m), '');
  const fresh = { marks: maxAt(greeks) || null, quotes: maxAt(quotes) || null, market: maxAt(market) || null,
                  trades: runs[0]?.finished_at ?? null, account_close: anchor?.report_date ?? null };

  step('deck');
  // ════════════════════════════════════════════════════════════════════════
  // REPORTS (block 06): weekly every Monday for the week before, monthly on
  // the 1st for the month before; a Monday the 1st brings the monthly only.
  // Built once, when IBKR's statement for the period's last day is in, and
  // saved, so history can come later. Shown all day on its day.
  // ════════════════════════════════════════════════════════════════════════
  const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  const MONTH = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October',
    'November', 'December'];
  const shortDate = (iso: string) => `${MON[Number(iso.slice(5, 7)) - 1]} ${Number(iso.slice(8, 10))}`;
  const isoWeek = (iso: string) => {
    const d = new Date(iso + 'T12:00:00Z'); const wd = (d.getUTCDay() + 6) % 7;
    d.setUTCDate(d.getUTCDate() - wd + 3);
    const y0 = new Date(Date.UTC(d.getUTCFullYear(), 0, 4));
    return 1 + Math.round(((d.getTime() - y0.getTime()) / 864e5 - 3 + ((y0.getUTCDay() + 6) % 7)) / 7);
  };
  const lastTradingOnOrBefore = (d: string) => { let x = d; while (!isTrading(x)) x = addDays(x, -1); return x; };
  const due: { kind: 'weekly' | 'monthly'; from: string; to: string; label: string; mark: string }[] = [];
  if (today.endsWith('-01')) {
    const to = addDays(today, -1), from = to.slice(0, 8) + '01';
    due.push({ kind: 'monthly', from, to, label: `${MONTH[Number(from.slice(5, 7)) - 1]} ${from.slice(0, 4)}`,
               mark: MON[Number(from.slice(5, 7)) - 1] });
  } else if (new Date(today + 'T12:00:00Z').getUTCDay() === 1) {
    const from = addDays(today, -7), to = addDays(today, -3);
    due.push({ kind: 'weekly', from, to, label: `Week ${isoWeek(from)} · ${shortDate(from)} - ${shortDate(lastTradingOnOrBefore(to))}`,
               mark: String(isoWeek(from)) });
  }
  const reportsOut: Row[] = [];
  /* What was borrowed at the period's last close, for the receipt's
     interest note ("margin on 21K borrowed"). */
  const borrowedAt = (d: string) => {
    const h = savedHistory.filter((x) => String(x.day) <= d).at(-1);
    return h && Number(h.cash) < 0 ? Math.round(-Number(h.cash)) : 0;
  };
  for (const r of due) {
    const have = savedReports.find((x) => x.kind === r.kind && String(x.period_start) === r.from);
    if (have) { reportsOut.push({ kind: r.kind, label: r.label, mark: r.mark, borrowed: borrowedAt(r.to), ...have.payload }); continue; }
    const lastDay = lastTradingOnOrBefore(r.to);
    if (!acctDays.some((d) => String(d.report_date) >= lastDay && Number(d.accounts) >= 2)) {
      reportsOut.push({ kind: r.kind, label: r.label, mark: r.mark, pending: 'waiting for IBKR statement' });
      continue;
    }
    const ev = realized.filter((e) => e.d >= r.from && e.d <= r.to);
    const byLeg = new Map<string, { leg: string; how: string; exp: string | null; amt: number; basis: number; kind: string }>();
    for (const e of ev) {
      const k = `${e.leg}|${e.how}|${e.exp ?? ''}`;
      const x = byLeg.get(k) ?? { leg: e.leg, how: e.how, exp: e.exp ?? null, amt: 0, basis: 0, kind: e.kind };
      x.amt += e.amt; x.basis += e.basis; byLeg.set(k, x);
    }
    const lines = [...byLeg.values()].sort((a, b) => b.amt - a.amt)
      .map((x) => ({ leg: x.leg, how: x.how, exp: x.exp, amount: r2(x.amt), kind: x.kind }));
    const realizedTotal = r2(ev.reduce((s, e) => s + e.amt, 0));
    const inP = acctDays.filter((d) => String(d.report_date) >= r.from && String(d.report_date) <= r.to);
    const commission = r2(inP.reduce((s, d) => s + Number(d.commissions ?? 0), 0));
    const interest = r2(inP.reduce((s, d) => s + Number(d.interest_accrued ?? 0), 0));
    const fills = trades.filter((t) => String(t.trade_date) >= r.from && String(t.trade_date) <= r.to
      && !/lifecycle/.test(String(t.note ?? ''))).length;
    const best = [...byLeg.values()].filter((x) => x.kind === 'calls sold' || x.kind === 'puts sold')
      .sort((a, b) => b.amt - a.amt)[0];
    const horizon = addDays(today, r.kind === 'weekly' ? 7 : 14);
    const payloadR = {
      period: { from: r.from, to: r.to },
      /* Kept: realized after commission and interest, in IBKR's sign. */
      kept: r2(realizedTotal + commission + interest),
      realized: realizedTotal, lines,
      commission, trades: fills, commission_each: fills ? r2(commission / fills) : null,
      interest,
      unrealized_now: account.ok ? account.unrealized : null,
      best: best ? { leg: best.leg, amount: r2(best.amt), how: best.how, exp: best.exp,
                     kept_pct: best.basis > 0 ? Math.round(best.amt / best.basis * 100) : null } : null,
      coming_up: {
        earnings: earnings.filter((e) => e.date >= today && e.date <= horizon)
          .map((e) => ({ date: e.date, ticker: e.ticker, time: e.time })),
        market: cal.filter((c) => String(c.date) >= today && String(c.date) <= horizon)
          .map((c) => ({ date: c.date, kind: c.kind, name: c.name, closes: c.closes })),
        macro: macro.filter((m) => String(m.event_date) <= horizon)
          .map((m) => ({ date: m.event_date, time: m.event_time, name: m.name })),
        /* Ex-dividend on a name with calls sold: early assignment gets likely
           the day before. */
        ex_dividend: divs.filter((d) => String(d.ex_date) <= horizon && book.includes(String(d.ticker)))
          .map((d) => ({ date: d.ex_date, ticker: d.ticker, amount: num(d.cash_amount),
            calls_sold: legs.filter((l) => l.ticker === d.ticker && l.side === 'sold' && l.type === 'call')
              .reduce((s, l) => s + l.n, 0) })),
        longs: legs.filter((l) => l.side === 'bought').map((l) => ({
          leg: `${l.ticker} ${l.expiry.slice(0, 7)} ${l.strike}${l.type === 'call' ? 'C' : 'P'}`, expiry: l.expiry,
          months: Math.max(0, Math.round((Date.parse(l.expiry) - Date.parse(today)) / (30.44 * 864e5))),
          since_bought_pct: l.mark != null && l.avg > 0 ? Math.round((l.mark / l.avg - 1) * 100) : null })),
      },
      built_from: { ibkr_close: lastDay },
    };
    await fetch(`${URL_}/rest/v1/reports?on_conflict=kind,period_start`, {
      method: 'POST', headers: { ...H, Prefer: 'resolution=ignore-duplicates,return=minimal' },
      body: JSON.stringify([{ kind: r.kind, period_start: r.from, period_end: r.to, shown_on: today, payload: payloadR }]),
    });
    reportsOut.push({ kind: r.kind, label: r.label, mark: r.mark, borrowed: borrowedAt(r.to), ...payloadR });
  }

  step('reports');
  // ════════════════════════════════════════════════════════════════════════
  // WRITES SHEET (block 14): next Friday's write on every name, by TODAY'S
  // roll-sheet rule, not the design's (Nik, 12 Oct 2026: "stays as we have it
  // today"). Calls: a third at the money, the rest at 0.6 SD, the rest at 1 SD
  // after a 15%+ month, 20% at the money when a report falls on or before the
  // expiry. Puts: the nearest strike at or below spot (overlay names: 2% below,
  // capped at the long put strike, half the puts bought; PUT_RULES). Sized on every LEAP
  // (calls); puts at about 30% of the puts bought (Nik, 13 Oct 2026: "around
  // 30%", the put programme's smaller weekly quantity); what is already sold for that
  // Friday counts toward the strike it sits nearer, and only the rest is
  // suggested (partial fills). Chains: option_chain_next, every 15 min.
  // ════════════════════════════════════════════════════════════════════════
  /* Next Friday: Monday to Friday the Friday after this week's; on a weekend
     the coming one. A holiday Friday moves it to that week's last session. */
  const nextFri = (() => { const d = new Date(today + 'T12:00:00Z'), wd = d.getUTCDay();
    d.setUTCDate(d.getUTCDate() + (5 - wd + 7) % 7 + (wd === 6 || wd === 0 ? 0 : 7));
    return d.toISOString().slice(0, 10); })();
  const targetExp = lastTradingOnOrBefore(nextFri);
  const dte = Math.max(1, Math.round((Date.parse(targetExp) - Date.parse(today)) / 864e5));
  type CS = { k: number; mid: number; delta: number | null; iv: number | null; oi: number | null };
  const nearestK = (xs: CS[], target: number) => xs.length
    ? xs.reduce((a, b) => (Math.abs(b.k - target) < Math.abs(a.k - target) ? b : a)) : null;
  /* The latest reads per read-rule name (ticker-technicals, every 15 min in the session). */
  const readsOf = new Map<string, Row>();
  if (Object.keys(READ_RULES).length) {
    for (const r of await get(`ticker_technicals?ticker=in.(${Object.keys(READ_RULES).join(',')})&reads=not.is.null`
      + `&day=gte.${addDays(today, -READS_STALE_DAYS)}&select=ticker,day,reads&order=ticker.asc,day.desc`)) {
      if (!readsOf.has(String(r.ticker))) readsOf.set(String(r.ticker), r);
    }
  }
  const writes = [];
  for (const t of book) {
    const ls = legs.filter((l) => l.ticker === t);
    const leapN = ls.filter(isLeap).reduce((s, l) => s + l.n, 0);
    const putsN = ls.filter((l) => l.side === 'bought' && l.type === 'put').reduce((s, l) => s + l.n, 0);
    if (!leapN && !putsN) continue;
    const rows = chainRows.filter((r) => r.ticker === t && String(r.expiry) === targetExp);
    if (!rows.length) { writes.push({ ticker: t, expiry: targetExp, error: 'no chain cached for this Friday' }); continue; }
    const cs = (side: string): CS[] => rows.filter((r) => r.side === side).map((r) => ({ k: Number(r.strike),
      mid: Number(r.mid ?? 0), delta: num(r.delta), iv: num(r.iv), oi: num(r.oi) }));
    const calls = cs('call'), puts = cs('put');
    const spot = spotOf.get(t) ?? Number(rows.find((r) => r.spot)?.spot ?? 0);
    /* One SD from the chain's own IV at the strike nearest spot. */
    const ivRow = [...calls, ...puts].filter((x) => x.iv).sort((a, b) => Math.abs(a.k - spot) - Math.abs(b.k - spot))[0];
    const sd = ivRow?.iv ? spot * ivRow.iv * Math.sqrt(dte / 365) : null;
    /* The month: today against 20 sessions back (21 once today's close is in). */
    const mo = closeSeries(t).reverse();
    const back = mo.length && mo[0].d === today ? 21 : 20;
    const move21 = mo.length > back && spot > 0 ? (spot / mo[back].c - 1) * 100 : null;
    const earnRow = upcomingEarn.get(t);
    const earnIn = !!earnRow && String(earnRow.report_date) >= today && String(earnRow.report_date) <= targetExp;
    const rule = WRITE_RULES[t];
    const coverKs = ls.filter((l) => l.side === 'bought' && l.type === 'put' && l.expiry >= targetExp).map((l) => l.strike);
    const coverK = coverKs.length ? Math.min(...coverKs) : null;
    /* ── THE READ RULE (READ_RULES; NKE only): the week's pick from the reads ── */
    const rr = READ_RULES[t] ? readsOf.get(t) : undefined;
    type Pick = { label: string; why: string; share: number; z: number | null; calls: number; puts: number; pz: number | null;
                  atm: CS | null; out: CS | null; put: CS | null; outNote: string;
                  steps: { read: string; label: string; step: string }[] };
    let pick: Pick | null = null;
    if (rr && sd && spot > 0) {
      const R = rr.reads as Record<string, Row & { read: string; fact: string }>;
      const inp = (R.inputs ?? {}) as Row;
      const live = calls.filter((x) => x.mid > 0).sort((a, b) => a.k - b.k);
      const cAt = (x: number) => live.find((c) => c.k >= x) ?? live.at(-1) ?? null;      // first strike at or above
      const pAt = (x: number) => coverK == null ? null                                    // highest at or below, covered
        : puts.filter((p) => p.mid > 0 && p.k <= x && p.k <= coverK).sort((a, b) => b.k - a.k)[0] ?? null;
      const full = Math.floor(leapN * READ_RULES[t].cover + 0.5);
      const halfPuts = Math.floor(putsN * 0.5 + 0.5);
      /* An after-the-close report on the expiry day lands after it. */
      const earnWk = earnIn && !(String(earnRow!.report_date) === targetExp && earnRow!.report_time === 'amc');
      const exd = inp.ex_div ? String(inp.ex_div) : null, exIn = !!exd && exd > today && exd <= targetExp;
      const none = { atm: null, out: null, put: null, pz: null };
      if (R.iv?.read === 'skip') {
        pick = { label: 'Skip the week', why: `IV: ${R.iv.fact}`, share: 0, z: null, calls: 0, puts: 0, outNote: '', ...none,
                 steps: [{ read: 'iv', label: `IV · ${R.iv.fact}`, step: 'skip' }] };
      } else if (earnWk) {
        pick = { label: 'Earnings week: every call at 1 SD, no puts', why: `Earnings ${earnRow!.report_date} before the expiry`,
                 share: 0, z: 1, calls: full, puts: 0, ...none, out: cAt(spot + sd), outNote: 'at 1 SD',
                 steps: [{ read: 'events', label: `Events · earnings ${earnRow!.report_date} before expiry`, step: '1 SD' }] };
      } else {
        let idx = R.momentum?.read === 'bullish' ? 2 : 1;
        const why: string[] = [`momentum ${R.momentum?.read}`];
        /* Our thesis (handoff 26, 14c), on the TESTED rule (Nik, 19 Oct 2026): each menu step is 0.2 SD
           (0.6 -> 0.8 -> 1.0); a step closer from 0.6 is 20% at the money + 0.6. Bearish momentum is not a step. */
        const steps: { read: string; label: string; step: string }[] = [];
        if (R.momentum?.read === 'bullish') steps.push({ read: 'momentum', label: 'Momentum · bullish', step: '+0.2' });
        if (R.fundamentals?.read === 'bearish') { idx--; why.push('fundamentals bearish: closer'); steps.push({ read: 'fundamentals', label: 'Fundamentals · bearish', step: 'closer' }); }
        if (R.history?.read === 'stretched up') { idx++; why.push('stretched up: wider'); steps.push({ read: 'history', label: 'History · stretched up', step: '+0.2' }); }
        if (R.history?.read === 'stretched down') { idx--; why.push('stretched down: closer'); steps.push({ read: 'history', label: 'History · stretched down', step: 'closer' }); }
        if (R.momentum?.read === 'bullish' && R.technicals?.read === 'bullish') { idx++; why.push('momentum and technicals bullish: wider'); steps.push({ read: 'technicals', label: 'Technicals · bullish with momentum', step: '+0.2' }); }
        idx = Math.max(0, Math.min(3, idx));
        const [share, z] = READ_MENU[idx];
        let out = cAt(spot + z * sd), outNote = `at ${z} SD`;
        const hi5 = Number(inp.high5 ?? 0);
        if (R.breakout?.read === 'yes' && out && hi5 > 0 && out.k <= hi5) {
          out = cAt(hi5 + 0.01); outNote = 'above the 5-day high'; why.push(`breakout week: above $${hi5.toFixed(2)}`);
          steps.push({ read: 'breakout', label: `Breakout week · above the 5-day high $${hi5.toFixed(2)}`, step: 'strike' });
        }
        const atm = share ? cAt(spot) : null;
        const near = Math.min(atm?.k ?? Infinity, out?.k ?? Infinity) <= spot * 1.02;
        const n = exIn && near ? Math.round(full * 2 / 3) : full;
        if (exIn && near) { why.push(`ex-dividend ${exd} with calls within 2%: two thirds`); steps.push({ read: 'events', label: `Events · ex-dividend ${exd}`, step: 'two thirds' }); }
        const pz = R.momentum?.read === 'bearish' ? 0.8 : 0.6;
        const stretchedDn = R.history?.read === 'stretched down';
        pick = { label: (share ? `${Math.round(share * 100)}% at the money + ${z} SD` : `${z} SD`) + (outNote === 'above the 5-day high' ? ', above the 5-day high' : ''),
                 why: why.join('; '), share, z, calls: n, puts: stretchedDn ? 0 : halfPuts, pz,
                 atm, out, put: stretchedDn ? null : pAt(spot - pz * sd), outNote, steps };
      }
    }
    const share = pick ? pick.share : rule ? 0 : earnIn ? 0.2 : 1 / 3, out = pick ? (pick.z ?? 0.6) : move21 != null && move21 >= 15 ? 1.0 : 0.6;
    const callTarget = pick ? pick.calls : coverOf(t, leapN);
    const atmN = pick ? Math.round(pick.calls * pick.share) : Math.floor(leapN * share + 0.5);
    /* A research name: one strike, the first at least otmPct% above spot. */
    const ruleK = rule ? calls.filter((x) => x.k >= spot * (1 + rule.otmPct / 100) && x.mid > 0).sort((a, b) => a.k - b.k)[0] ?? null : null;
    const atm = pick ? pick.atm : rule ? ruleK : calls.filter((x) => x.k >= spot && x.mid > 0).sort((a, b) => a.k - b.k)[0] ?? null;
    let otm = pick ? pick.out : sd ? nearestK(calls.filter((x) => x.k > spot && x.mid > 0), spot + out * sd) : null;
    if (atm && otm && otm.k <= atm.k) otm = calls.filter((x) => x.k > atm.k && x.mid > 0).sort((a, b) => a.k - b.k)[0] ?? null;
    const sd1 = sd ? nearestK(calls.filter((x) => x.k > spot), spot + sd) : null;
    /* Overlay names: the highest strike at least otmPct% below spot, capped at the lowest
       long put still open on that Friday; no covering long put, no suggestion. */
    const pRule = PUT_RULES[t];
    const put = pick ? pick.put : pRule
      ? (coverK == null ? null : puts.filter((x) => x.k <= spot * (1 - pRule.otmPct / 100) && x.k <= coverK && x.mid > 0)
          .sort((a, b) => b.k - a.k)[0] ?? null)
      : puts.filter((x) => x.k <= spot && x.mid > 0).sort((a, b) => b.k - a.k)[0] ?? null;
    /* Already sold for that Friday: each counts toward the nearer strike. */
    const sold = ls.filter((l) => l.side === 'sold' && l.expiry === targetExp);
    let doneAtm = 0, doneOtm = 0;
    for (const l of sold.filter((x) => x.type === 'call')) {
      if (!otm || !atm || Math.abs(l.strike - atm.k) <= Math.abs(l.strike - otm.k)) doneAtm += l.n; else doneOtm += l.n;
    }
    const donePuts = sold.filter((x) => x.type === 'put').reduce((s, l) => s + l.n, 0);
    const left = Math.max(0, callTarget - doneAtm - doneOtm);
    const leftAtm = rule ? left : Math.min(left, Math.max(0, atmN - doneAtm)), leftOtm = left - leftAtm;
    /* Puts: about 30% of the puts bought, rounded half up (NKE 20 -> 6); overlay
       names half (NKE 30 -> 15, BABA 7 -> 4). */
    const putTarget = pick ? pick.puts : Math.floor(putsN * (pRule?.share ?? PUT_SHARE) + 0.5);
    const leftPuts = Math.max(0, putTarget - donePuts);
    const plan = [
      atm && leftAtm > 0 ? { type: 'call', n: leftAtm, strike: atm.k, mid: atm.mid, delta: atm.delta,
        note: rule ? `${rule.otmPct}% out of the money` : 'at the money' } : null,
      otm && leftOtm > 0 ? { type: 'call', n: leftOtm, strike: otm.k, mid: otm.mid, delta: otm.delta,
        note: pick ? pick.outNote : out === 1 ? 'at 1 SD' : 'at 0.6 SD' } : null,
      put && leftPuts > 0 ? { type: 'put', n: leftPuts, strike: put.k, mid: put.mid, delta: put.delta,
        note: pick ? `at ${pick.pz} SD` : pRule ? `${pRule.otmPct}% out of the money` : 'at the money' } : null,
    ].filter(Boolean) as { type: string; n: number; strike: number; mid: number; delta: number | null; note: string }[];
    /* Only what is still open on that Friday: this week's calls expire first,
       and counting them made a plan look delta negative (Nik, 15 Oct 2026). */
    const deltaNow = ls.filter((l) => l.expiry >= targetExp)
      .reduce((s, l) => s + (l.side === 'bought' ? 1 : -1) * (l.delta ?? 0) * l.n * 100, 0);
    const deltaAfter = deltaNow - plan.reduce((s, p) => s + (p.delta ?? 0) * p.n * 100, 0);
    const putK = put?.k ?? sold.find((x) => x.type === 'put')?.strike ?? null;
    /* ── THE PACKAGE (handoff 25, blocks 14b and 16): one model for the
       Planner and the Delta tile. Delta in share-equivalents, contracts × 100
       × delta: long adds, short takes away, and a put's delta is negative, so
       hedge puts take away and short puts add. NOW is the Delta tile's number
       to the share (legs past today, the next-week basis; Nik, 16 Oct 2026).
       AFTER is everything still on at the target Friday plus the suggestions
       left on; the app redoes it as chips switch off. Sells are OUR rule
       above (Nik: "keep ours"); the buys and the fix are the design's: a
       12-month call ~30% out held the year and a 3-month ~15% out rolled at
       expiry, 10% of LEAP value a year split by delta per dollar (the 3-month
       premium counted four times), each at least 1. Still under 20% (30% in
       the earnings week) with every suggestion on: N more 3-month or M
       12-month calls to land on 25% (35%). */
    const pkg = (() => {
      const base = leapN * 100;
      if (!base) return null;
      const tk = tick.get(t);
      const nowD = tk ? tk.longD - tk.scD + tk.spD - tk.hedgeD : 0;
      const e = earn.some((x) => String(x.ticker).toUpperCase() === t
        && String(x.report_date) >= today && String(x.report_date) <= addDays(today, 7)) ? DELTA_EARN_BUMP : 0;
      const dOf = (l: Leg) => (l.side === 'bought' ? 1 : -1) * (l.delta ?? 0) * l.n * 100;
      const tenorOf = (l: Leg) => ((Date.parse(l.expiry) - Date.parse(l.opened)) / (30.44 * 864e5) > 6 ? '12m' : '3m');
      const held = ls.filter((l) => l.expiry > today).map((l) => {
        const up = upside.has(l);
        const ty = l.type === 'call' ? (l.side === 'sold' ? 'sc' : up ? 'oc' : 'lc') : (l.side === 'sold' ? 'sp' : 'lp');
        return { ty, n: l.n, k: l.strike, exp: l.expiry, d: Math.round(dOf(l)), stays: l.expiry >= targetExp,
                 ...(up ? { tenor: tenorOf(l), roll: l.expiry } : {}) };
      });
      const heldTenor = new Set(held.filter((h) => h.ty === 'oc').map((h) => (h as { tenor?: string }).tenor));
      const sug: Row[] = plan.map((p, i) => ({ id: `s${i}`, ty: p.type === 'call' ? 'sc' : 'sp', act: 'Sell',
        n: p.n, k: p.strike, exp: targetExp, mid: r2(p.mid), d: Math.round(-(p.delta ?? 0) * p.n * 100) }));
      /* The upside quotes: the listed strike nearest 15% / 30% over today's price. */
      const q = (tenor: string, out: number) => {
        const xs = upQuotes.filter((r) => r.ticker === t && r.tenor === tenor && Number(r.mid) > 0 && r.delta != null);
        if (!xs.length || !(spot > 0)) return null;
        const r = xs.reduce((a, b) => (Math.abs(Number(b.strike) - spot * out) < Math.abs(Number(a.strike) - spot * out) ? b : a));
        return { k: Number(r.strike), exp: String(r.expiry), mid: Number(r.mid), dl: Number(r.delta) };
      };
      const q12 = q('12m', 1.3), q3 = q('3m', 1.15);
      const leapValue = ls.filter(isLeap).reduce((s2, l) => s2 + (l.mark ?? 0) * l.n * 100, 0);
      const budget = 0.1 * leapValue;
      const e12 = q12 ? q12.dl / q12.mid : 0, e3 = q3 ? q3.dl / (4 * q3.mid) : 0;
      const w = e12 + e3 > 0 ? e12 / (e12 + e3) : 0;
      const n12 = q12 ? Math.max(1, Math.round(budget * w / (100 * q12.mid))) : 0;
      const n3 = q3 ? Math.max(1, Math.round(budget * (1 - w) / 4 / (100 * q3.mid))) : 0;
      const buy = (id: string, tenor: string, x: { k: number; exp: string; mid: number; dl: number }, n: number) =>
        ({ id, ty: 'oc', act: 'Buy', tenor, n, k: x.k, exp: x.exp, mid: r2(x.mid), d: Math.round(x.dl * n * 100) });
      if (q12 && !heldTenor.has('12m')) sug.push(buy('b12', '12m', q12, n12));
      if (q3 && !heldTenor.has('3m')) sug.push(buy('b3', '3m', q3, n3));
      const after0 = held.filter((h) => h.stays).reduce((s2, h) => s2 + h.d, 0) + sug.reduce((s2, x) => s2 + Number(x.d), 0);
      const after0P = after0 / base * 100;
      const gap = (25 + e - after0P) / 100 * base;
      const fix = after0P < 20 + e ? [
        q3 ? buy('f3', '3m', q3, Math.ceil(gap / (100 * q3.dl))) : null,
        q12 ? buy('f12', '12m', q12, Math.ceil(gap / (100 * q12.dl))) : null,
      ].filter(Boolean) : [];
      return { base, e, now: Math.round(nowD), now_pct: r2(nowD / base * 100), held, sug, fix,
               after0: Math.round(after0), after0_pct: r2(after0P),
               leap_value: Math.round(leapValue), budget: Math.round(budget), w: r2(w),
               iv: ivRow?.iv ?? null };
    })();
    writes.push({
      ticker: t, expiry: targetExp, spot: r2(spot), sd: sd == null ? null : r2(sd),
      /* The Planner (block 14b) caps calls at the LEAPs held and puts at the
         puts bought, less what is already sold for that Friday, and names the
         next report even when it falls after the expiry. */
      leaps: leapN,
      next_earnings: earnRow ? { date: earnRow.report_date, time: earnRow.report_time ?? null } : null,
      move_21d_pct: move21 == null ? null : r2(move21),
      split: { atm_share: r2(share), out_sd: out, why: pick ? 'reads' : rule ? 'research' : earnIn ? 'earnings' : out === 1 ? 'up a lot' : 'flat' },
      /* The read rule's pick and the reads behind it (READ_RULES; null for other names). */
      read_rule: !READ_RULES[t] ? null : !pick
        ? { name: 'NKE weekly rule (trial)', error: rr ? 'no chain IV for this Friday' : `no reads in the last ${READS_STALE_DAYS} days: the roll-sheet rule is used` }
        : { name: 'NKE weekly rule (trial)', pick: pick.label, why: pick.why, calls: pick.calls, of: leapN, puts: pick.puts,
            /* Our thesis (14c): baseline 0.6 SD, the steps, the pick and the one strike every card uses. */
            baseline: 0.6, steps: pick.steps, pick_sd: pick.z, atm_share: pick.share, spot: r2(spot), sd: sd == null ? null : r2(sd),
            strike: pick.out?.k ?? null, strike_pct: pick.out ? r2((pick.out.k / spot - 1) * 100) : null,
            reads_day: rr!.day, reads: Object.fromEntries(['fundamentals', 'technicals', 'iv', 'history', 'momentum', 'events', 'breakout', 'thesis', 'inputs']
              .map((k) => [k, (rr!.reads as Row)[k] ?? null])) },
      earnings: earnIn ? { date: earnRow!.report_date, time: earnRow!.report_time ?? null } : null,
      ex_dividend: (() => { const d = divs.find((x) => x.ticker === t && String(x.ex_date) <= targetExp);
        return d ? { date: d.ex_date, amount: num(d.cash_amount) } : null; })(),
      plan: plan.map((p) => ({ ...p, mid: r2(p.mid), credit: Math.round(p.mid * p.n * 100) })),
      expected: Math.round(plan.reduce((s, p) => s + p.mid * p.n * 100, 0)),
      already: sold.map((l) => ({ type: l.type, n: l.n, strike: l.strike, credit: Math.round(l.avg * l.n * 100) })),
      collected: Math.round(sold.reduce((s, l) => s + l.avg * l.n * 100, 0)),
      calls: { sold: doneAtm + doneOtm, of: callTarget }, puts: { sold: donePuts, of: putTarget, bought: putsN },
      written: left === 0 && leftPuts === 0,
      delta: { now: Math.round(deltaNow), after: Math.round(deltaAfter) },
      pkg,
      /* The By Fri bar: put strike, price, the call strike, the 1 SD call. */
      bar: { put: putK, spot: r2(spot), call: (atm ?? otm)?.k ?? sold.find((x) => x.type === 'call')?.strike ?? null,
             sd1: sd1?.k ?? null, breakeven: (atm ?? otm) ? r2((atm ?? otm)!.k + (atm ?? otm)!.mid) : null,
             to_put_pct: putK ? r2((spot - putK) / spot * 100) : null,
             to_sd1_pct: sd1 ? r2((sd1.k - spot) / spot * 100) : null },
    });
  }
  /* Least filled first, as the chips run (block 14). */
  writes.sort((a: Row, b: Row) => ((a.calls?.of ? a.calls.sold / a.calls.of : 1) - (b.calls?.of ? b.calls.sold / b.calls.of : 1)));

  step('writes');
  // ════════════════════════════════════════════════════════════════════════
  // LAST WEEK (block 09): Friday 4:00 PM to Monday 4:00 AM, each index's week
  // against the move its weekly straddle priced in at the close before.
  // ════════════════════════════════════════════════════════════════════════
  /* mode 'last_week' (admin only) builds the week before this one on any
     day, so the priced-move pipeline can be checked away from a weekend. */
  const weekend = (now.wd === 'Fri' && now.mins >= 16 * 60) || now.wd === 'Sat' || now.wd === 'Sun'
    || (now.wd === 'Mon' && now.mins < 4 * 60) || mode === 'last_week';
  let lastWeek: Row | null = null;
  if (weekend) {
    const anchorDay = mode === 'last_week' ? addDays(today, -7) : now.wd === 'Mon' ? addDays(today, -3) : today;
    const wk = weekStartOf(anchorDay);
    const lastT = lastTradingOnOrBefore(addDays(wk, 4));
    const priorT = prevTrading(wk);
    const stored = await get(`index_weekly?week_start=eq.${wk}&select=*`);
    const rowsLW: Row[] = [];
    for (const sym of ['SPY', 'QQQ', 'IWM']) {
      let row = stored.find((x) => x.symbol === sym);
      if (!row) {
        const pc = closes.find((c) => c.ticker === sym && String(c.date) === priorT);
        const cl = closes.find((c) => c.ticker === sym && String(c.date) === lastT);
        const closeNow = cl ? Number(cl.close_price) : num(mk(sym)?.regular_price);
        if (!pc || closeNow == null) continue;
        const prior = Number(pc.close_price);
        let straddle: number | null = null, atmK: number | null = null;
        const q = await thetaJson(`/v3/option/history/eod?symbol=${sym}&expiration=${lastT.replaceAll('-', '')}`
          + `&start_date=${priorT.replaceAll('-', '')}&end_date=${priorT.replaceAll('-', '')}`).catch(() => []);
        const quotesLW = q.filter((x) => x.data?.[0]).map((x) => ({ side: String(x.contract.right).toLowerCase(),
          k: Number(x.contract.strike), bid: Number(x.data[0].bid), ask: Number(x.data[0].ask) }));
        for (const x of quotesLW) if (atmK == null || Math.abs(x.k - prior) < Math.abs(atmK - prior)) atmK = x.k;
        const c = quotesLW.find((x) => x.k === atmK && x.side === 'call'), p = quotesLW.find((x) => x.k === atmK && x.side === 'put');
        if (c && p && c.ask > 0 && p.ask > 0) straddle = (c.bid + c.ask) / 2 + (p.bid + p.ask) / 2;
        row = { week_start: wk, symbol: sym, prior_close_date: priorT, close_date: lastT, prior_close: prior,
          close: closeNow, change_pct: r2((closeNow / prior - 1) * 100), expiry: lastT, atm_strike: atmK,
          straddle: straddle == null ? null : r2(straddle),
          priced_move_pct: straddle == null ? null : r2(straddle / prior * 100) };
        /* Kept only once the week's close is final; a Friday evening before the
           17:30 close capture uses the tape and tries again. */
        if (cl && straddle != null) {
          await fetch(`${URL_}/rest/v1/index_weekly?on_conflict=week_start,symbol`, {
            method: 'POST', headers: { ...H, Prefer: 'resolution=merge-duplicates,return=minimal' },
            body: JSON.stringify([row]) });
        }
      }
      rowsLW.push({ symbol: sym, change_pct: num(row.change_pct), priced_move_pct: num(row.priced_move_pct),
                    close: num(row.close) });
    }
    const vix = closeSeries('^VIX');
    const vEnd = vix.find((x) => x.d === lastT)?.c ?? num(mk('^VIX')?.regular_price);
    const vPrior = vix.find((x) => x.d === priorT)?.c ?? null;
    lastWeek = { week_start: wk, from: wk, to: lastT, rows: rowsLW,
      vix: vEnd == null ? null : { close: vEnd, change_pct: vPrior ? r2((vEnd / vPrior - 1) * 100) : null } };
  }

  // ════════════════════════════════════════════════════════════════════════
  // THETA CHECK (block 07), mode 'theta_check', after every close. Asleep
  // until a LEAP drags: its theta a day up 50% or more on a month ago, or it
  // alone pulls the book's 2-week ratio under 3× (Nik took both proposals; the
  // line moved from 2× to 3× on 13 Oct 2026 after the risk-bands backtest).
  // A finding carries its fix: the roll to the next January a year further
  // out at 70 to 75 delta (Nik, 12 Oct 2026: "around 70 to 75 delta, not
  // 90"; 0.9 put NKE into a $47,550 debit, new capital, not a roll).
  // ════════════════════════════════════════════════════════════════════════
  step('last_week');
  /* Once per trading day, after the close. pg_cron speaks UTC, so it fires at
     20:25 and 21:25 to cover EDT and EST; whichever lands after 4:15 New York
     runs, and only once (the heartbeat says whether today already ran). */
  const ranToday = mode === 'theta_check'
    ? (await get("sync_heartbeat?feed=eq.theta-check&select=ran_at"))[0]?.ran_at : null;
  const dry = mode === 'theta_check' && !!opts.dry;
  const checkDue = dry || (mode === 'theta_check' && isTrading(today) && now.mins >= 16 * 60 + 15
    && !(ranToday && ny(new Date(String(ranToday))).date === today));
  if (mode === 'theta_check' && !checkDue) checkSummary = [{ skipped: 'not after the close, or already ran today' }];
  if (checkDue) {
    const THETA_LINE = 3;   // the Theta card's warning line (block 15), same number in the app
    const ratioNow = history.theta.now;
    const thL = livePoint?.thL ?? all.at(-1)?.thL ?? 0;
    /* ⚠ ONE BASIS (audit, 13 Oct 2026). The ratio trigger compared the 2-week
       ratio against a single-day "without": the daily ratio swings through the
       week as the weeklies near Friday, so under 3x a strong day would have
       flagged every LEAP and a weak one none, and the receipt said KR "alone"
       moved theta 8.05x to 7.76x when its share was 0.03x. Without-this-LEAP
       and after-the-roll are now the 2-week ratio too: the last ten points with
       the leg's theta removed or swapped (today's swap held across the ten). */
    const last10 = all.slice(-10);
    const ratio2w = (key: string, swap: (old: number) => number) => {
      const xs = last10.map((p) => {
        const L = p.thL - (p.thLongBy[key] ?? 0) + swap(p.thLongBy[key] ?? 0);
        return L > 0 ? p.thS / L : null;
      }).filter((x): x is number => x != null && isFinite(x));
      return xs.length ? xs.reduce((a, b) => a + b, 0) / xs.length : null;
    };
    const monthAgo = days.length > 21 ? days[days.length - 21] : days[0];
    const commPerContract = (() => {
      const c = trades.filter((t) => t.commission != null);
      const n = c.reduce((s, t) => s + Number(t.contracts), 0);
      return n ? Math.abs(c.reduce((s, t) => s + Number(t.commission), 0)) / n : 0.7;
    })();
    /* ⚠ SMOOTHED AND SIZED (Nik, 13 Oct 2026). KR's one LEAP flagged on
       noise: $0.27 a day on 14 Sep against $0.72 now (+167%), while its theta
       bounced between $0.18 and $0.78 day to day on a thin deep-ITM quote, and
       it was 0.4% of the book's long decay. Growth now compares 5-session
       averages, not two single days, and only a LEAP carrying 10% or more of
       the book's long decay can flag on growth. The ratio trigger is as before. */
    const GROWTH_MIN_SHARE = 0.10;
    const monthIdx = days.indexOf(monthAgo);
    const avgTh = (vals: (number | null)[]) => {
      const xs = vals.filter((v): v is number => v != null);
      return xs.length >= 3 ? xs.reduce((s, v) => s + v, 0) / xs.length : null;
    };
    const found: Row[] = [];
    for (const l of legs.filter((x) => x.side === 'bought' && x.type === 'call')) {
      const ids = (groups.get(`${l.ticker}|call|long|${l.strike}|${l.expiry}`) ?? [])
        .filter((t) => t.action === 'open').map((t) => String(t.id));
      const thOn = (d: string | undefined) => {
        const g = d ? greekOn(ids, d) : null;
        return g && g.theta != null ? Math.abs(Number(g.theta)) * l.n * 100 : null;
      };
      const liveTh = Math.abs(l.theta ?? 0) * l.n * 100;
      // Today live plus the four sessions before it; then the five ending a month ago.
      const nowTh = avgTh([liveTh, ...days.slice(-4).map(thOn)]) ?? liveTh;
      const thenTh = monthIdx >= 0 ? avgTh(days.slice(Math.max(0, monthIdx - 4), monthIdx + 1).map(thOn)) : null;
      const thenDay = thenTh != null ? monthAgo : null;
      const growth = thenTh && thenTh > 0 ? nowTh / thenTh - 1 : null;
      const share = thL > 0 ? nowTh / thL : 0;
      const key = `${l.ticker}|call|${l.strike}|${l.expiry}`;
      const without = ratio2w(key, () => 0);
      const trigger = growth != null && growth >= 0.5 && share >= GROWTH_MIN_SHARE ? 'growth'
        : (ratioNow != null && ratioNow < THETA_LINE && without != null && without >= THETA_LINE) ? 'ratio' : null;
      found.push({ l, key, nowTh, liveTh, thenTh, thenDay, growth, share, without, trigger });
    }
    const existing = openChecks;
    for (const c of existing) {
      const f = found.find((x) => x.l.ticker === c.ticker && x.l.strike === Number(c.strike) && x.l.expiry === String(c.expiry));
      const why = !f ? 'closed or rolled' : !f.trigger ? 'back under the trigger' : null;
      const body = why ? { status: 'resolved', resolved_on: today, resolved_why: why, last_checked: today }
        /* Comes back to Home only a step worse: another 0.25× off the book. */
        : { last_checked: today, theta_now: r2(f!.nowTh), ratio_now: ratioNow, ratio_without: f!.without && r2(f!.without),
            ...(ratioNow != null && c.ratio_at_card != null && ratioNow <= Number(c.ratio_at_card) - 0.25
              ? { card_on: today, ratio_at_card: ratioNow } : {}) };
      if (!dry) await fetch(`${URL_}/rest/v1/theta_checks?id=eq.${c.id}`, { method: 'PATCH', headers: H, body: JSON.stringify(body) });
    }
    const priced: Row[] = [];
    for (const f of found.filter((x) => x.trigger || (dry && (opts.price === '*' || opts.price === x.l.ticker)))) {
      const l = f.l as Leg;
      if (!dry && existing.some((c) => c.ticker === l.ticker && Number(c.strike) === l.strike && String(c.expiry) === l.expiry)) continue;
      const roll = await rollFor(l, f.liveTh, ratioNow, (newTh) => ratio2w(f.key, () => newTh), commPerContract,
        spotOf.get(l.ticker) ?? null).catch((e) => ({ error: String(e).slice(0, 120) }));
      if (dry) { priced.push({ leg: `${l.ticker} ${l.strike}C ${l.expiry}`, roll }); continue; }
      await fetch(`${URL_}/rest/v1/theta_checks`, {
        method: 'POST', headers: { ...H, Prefer: 'return=minimal' },
        body: JSON.stringify([{ ticker: l.ticker, option_type: 'call', strike: l.strike, expiry: l.expiry, contracts: l.n,
          trigger: f.trigger, found_on: today, card_on: today, theta_now: r2(f.nowTh), theta_then: f.thenTh && r2(f.thenTh),
          then_date: f.thenDay, growth_pct: f.growth == null ? null : Math.round(f.growth * 100),
          ratio_now: ratioNow, ratio_without: f.without && r2(f.without), ratio_at_card: ratioNow, roll, last_checked: today }]),
      });
    }
    if (!dry) await fetch(`${URL_}/rest/v1/sync_heartbeat?on_conflict=feed`, {
      method: 'POST', headers: { ...H, Prefer: 'resolution=merge-duplicates,return=minimal' },
      body: JSON.stringify([{ feed: 'theta-check', ran_at: new Date().toISOString(),
        rows_written: found.filter((x) => x.trigger).length,
        detail: `${found.length} LEAPs · ${found.filter((x) => x.trigger).length} dragging` }]),
    });
    checkSummary = found.map((f) => ({ leg: `${f.l.ticker} ${f.l.strike}C ${f.l.expiry}`, theta: r2(f.nowTh),
      then: f.thenTh && r2(f.thenTh), growth_pct: f.growth == null ? null : Math.round(f.growth * 100),
      share_pct: Math.round(f.share * 1000) / 10, without: f.without && r2(f.without), trigger: f.trigger }));
    if (dry) checkSummary = [{ dry: true, ratio_now: ratioNow, priced }, ...checkSummary];
  }

  // ── Theta check (block 07): what the after-close run found ──
  const checksNow = mode === 'theta_check' ? await get('theta_checks?status=eq.open&select=*&order=found_on.asc') : openChecks;
  const thetaChecks = checksNow.map((c) => ({
    ticker: c.ticker, leg: `${c.ticker} ${String(c.expiry).slice(0, 7)} ${Number(c.strike)}${c.option_type === 'call' ? 'C' : 'P'}`,
    trigger: c.trigger, found_on: c.found_on, card_today: String(c.card_on) === today,
    theta_now: num(c.theta_now), theta_then: num(c.theta_then), growth_pct: num(c.growth_pct),
    ratio_now: num(c.ratio_now), ratio_without: num(c.ratio_without), roll: c.roll,
  }));

  // ════════════════════════════════════════════════════════════════════════
  // ACCOUNT CHART (block 02b, handoff 19). One point per trading day since
  // 1 Sep 2026, from IBKR's closes (both accounts) and IBKR's closing position
  // values; mode 'history' rebuilds the stored rows each morning, every tick
  // reads them and adds today's live point. Nik's rulings, 13 Oct 2026:
  //   Margin = account value + net borrowed (both accounts' cash netted)
  //   Unrealized and Time value are levels at the day, not changes
  //   Sold and Bought return on capital divide by the money in long options
  //     (the Yield card's divisor); Shares and Dividends by the shares' value
  //   Kept full credit = a position that expired or closed at $0.00
  //   TLT's shares count from 1 Sep
  // A group's line is its P&L since the close before 1 Sep: the change in
  // value of what it holds plus the cash its trades moved. Only differences
  // are ever shown, so the base cancels out of every range.
  // ════════════════════════════════════════════════════════════════════════
  const CHART_START = '2026-09-01';
  type GK = 'cs' | 'ps' | 'cb' | 'pb' | 'sh';
  const GK_LIST: GK[] = ['cs', 'ps', 'cb', 'pb', 'sh'];
  const zero = (): Record<GK, number> => ({ cs: 0, ps: 0, cb: 0, pb: 0, sh: 0 });
  const gOf = (type: string, short: boolean): GK => (type === 'call' ? (short ? 'cs' : 'cb') : (short ? 'ps' : 'pb'));
  const kindG: Record<string, GK> = { 'calls sold': 'cs', 'puts sold': 'ps', 'calls bought': 'cb', 'puts bought': 'pb', shares: 'sh' };
  /* Cash each group's trades moved, by day, after the base close. */
  const cashBy = new Map<string, Record<GK, number>>();
  const addCash = (d: string, g: GK, c: number) => { const e = cashBy.get(d) ?? zero(); e[g] += c; cashBy.set(d, e); };
  /* ⚠ SEPTEMBER'S FILLS CARRY NO COMMISSION OF THEIR OWN (IBKR's per-fill
     commission is stored from 12 Oct on). IBKR's daily statement has each
     day's total, so the part no fill carries is spread over that day's
     uncommissioned fills by contracts (a share trade counts as one), and every
     day's lines then match IBKR's account change less interest and fees. */
  const isLife = (t: Row) => /lifecycle/.test(String(t.note ?? ''));
  const dayComm = new Map(acctDays.map((d) => [String(d.report_date), Number(d.commissions ?? 0)]));
  const carried = new Map<string, number>(), units = new Map<string, number>();
  for (const t of trades) {
    const d = String(t.trade_date); if (d <= BOOK_START || isLife(t)) continue;
    if (t.commission != null) carried.set(d, (carried.get(d) ?? 0) + Number(t.commission));
    else units.set(d, (units.get(d) ?? 0) + Number(t.contracts));
  }
  for (const l of lots) if (String(l.acquired_date) > BOOK_START) units.set(String(l.acquired_date), (units.get(String(l.acquired_date)) ?? 0) + 1);
  for (const s of sells) if (String(s.trade_date) > BOOK_START) units.set(String(s.trade_date), (units.get(String(s.trade_date)) ?? 0) + 1);
  const commPerUnit = (d: string) => {
    const u = units.get(d) ?? 0; if (!u || !dayComm.has(d)) return 0;
    return Math.min(0, dayComm.get(d)! - (carried.get(d) ?? 0)) / u;
  };
  for (const t of trades) {
    const d = String(t.trade_date); if (d <= BOOK_START) continue;
    const short = t.direction === 'short', sells = short === (t.action === 'open');
    const cash = t.net_cash != null ? Number(t.net_cash)
      : (sells ? 1 : -1) * Number(t.premium) * Number(t.contracts) * 100
        + (t.commission == null && !isLife(t) ? commPerUnit(d) * Number(t.contracts) : Number(t.commission ?? 0));
    addCash(d, gOf(t.option_type, short), cash);
  }
  for (const l of lots) if (String(l.acquired_date) > BOOK_START) addCash(String(l.acquired_date), 'sh', -Number(l.qty_original ?? 0) * Number(l.cost_per_share ?? 0) + commPerUnit(String(l.acquired_date)));
  for (const s of sells) if (String(s.trade_date) > BOOK_START) addCash(String(s.trade_date), 'sh', Number(s.quantity ?? 0) * Number(s.price ?? 0) + commPerUnit(String(s.trade_date)));
  const cashBetween = (a: string, b: string) => {        // (a, b]
    const out = zero();
    for (const [d, e] of cashBy) if (d > a && d <= b) for (const g of GK_LIST) out[g] += e[g];
    return out;
  };
  const realBy = (upTo: string) => {
    const out = zero();
    for (const e of realized) if (e.d <= upTo && e.d > BOOK_START) out[kindG[e.kind]] += e.amt;
    return out;
  };
  const posByDay = new Map<string, Row[]>();
  for (const p of posAll) (posByDay.get(String(p.report_date)) ?? posByDay.set(String(p.report_date), []).get(String(p.report_date))!).push(p);
  /* What each group held at a close, at IBKR's marks and cost. */
  const snapOf = (d: string) => {
    const mv = zero(), un = zero(), tv = zero(); let capLong = 0, shVal = 0; const tick = new Set<string>();
    for (const p of posByDay.get(d) ?? []) {
      const q = Number(p.position), m = Number(p.multiplier ?? 1), v = Number(p.position_value ?? 0), cb = Number(p.cost_basis_money ?? 0);
      if (p.asset_category === 'OPT') {
        const type = p.put_call === 'C' ? 'call' : 'put', g = gOf(type, q < 0);
        mv[g] += v; un[g] += q < 0 ? v : v - cb;
        const S = closeOn(String(p.underlying).toUpperCase(), d) ?? 0, K = Number(p.strike);
        const intr = type === 'call' ? Math.max(0, S - K) : Math.max(0, K - S);
        tv[g] += Math.abs(q) * m * Math.max(0, Number(p.mark_price ?? 0) - intr);
        if (q > 0) capLong += cb;
      } else if (p.asset_category === 'STK' && q !== 0) {
        mv.sh += v; un.sh += v - cb; shVal += v; tick.add(String(p.symbol));
      }
    }
    return { mv, un, tv, capLong, shVal, tickers: tick.size, has: posByDay.has(d) };
  };
  const navDays = acctDays.filter((d) => Number(d.accounts) >= 2).map((d) => String(d.report_date)).sort();
  const lastClose = navDays.at(-1) ?? null;
  const baseDay = [...navDays].reverse().find((d) => d < CHART_START) ?? null;
  const base = baseDay ? snapOf(baseDay) : null;
  const navOf = new Map(acctDays.map((d) => [String(d.report_date), d]));
  const cum = (f: string, upTo: string) => acctDays
    .filter((d) => String(d.report_date) > BOOK_START && String(d.report_date) <= upTo)
    .reduce((s, d) => s + Number(d[f] ?? 0), 0);
  const rowFor = (d: string) => {
    const a = navOf.get(d)!, sn = snapOf(d), cash = Number(a.cash ?? 0), nav = Number(a.nav);
    const cashSum = cashBetween(baseDay ?? BOOK_START, d), rl = realBy(d);
    const groups: Record<string, Record<string, number>> = {};
    for (const g of GK_LIST) {
      groups[g] = { line: r2(sn.mv[g] - (base?.mv[g] ?? 0) + cashSum[g]), real: r2(rl[g]), unreal: r2(sn.un[g]),
                    tv: r2(sn.tv[g]), mv: r2(sn.mv[g]) };
    }
    groups.sh.tickers = sn.tickers;
    return { day: d, nav: r2(nav), cash: r2(cash), margin: r2(nav + Math.max(0, -cash)),
      interest_cum: r2(cum('interest_accrued', d)), commission_cum: r2(cum('commissions', d)),
      dividends_cum: r2(cum('dividends', d)), realized_cum: r2(GK_LIST.reduce((s, g) => s + rl[g], 0)),
      unrealized: r2(GK_LIST.reduce((s, g) => s + sn.un[g], 0)),
      time_value: r2(sn.tv.cs + sn.tv.ps), capital_long: r2(sn.capLong), shares_value: r2(sn.shVal), groups };
  };
  let chartRows: Row[] = savedHistory;
  if (mode === 'history') {
    const built = navDays.filter((d) => d >= CHART_START && isTrading(d) && posByDay.has(d)).map(rowFor);
    if (built.length) {
      const w = await fetch(`${URL_}/rest/v1/account_history?on_conflict=day`, {
        method: 'POST', headers: { ...H, Prefer: 'resolution=merge-duplicates,return=minimal' },
        body: JSON.stringify(built.map((b) => ({ ...b, built_at: new Date().toISOString() }))) });
      if (!w.ok) throw new Error(`account_history ${w.status} ${(await w.text()).slice(0, 160)}`);
    }
    chartRows = built;
    checkSummary = [{ history_days: built.length, from: built[0]?.day ?? null, to: built.at(-1)?.day ?? null }];
    await fetch(`${URL_}/rest/v1/sync_heartbeat?on_conflict=feed`, {
      method: 'POST', headers: { ...H, Prefer: 'resolution=merge-duplicates,return=minimal' },
      body: JSON.stringify([{ feed: 'account-history', ran_at: new Date().toISOString(), rows_written: built.length,
        detail: `${built.length} days to ${built.at(-1)?.day ?? 'none'}` }]) });
  }
  /* Today's point, live until IBKR's statement replaces it next morning. */
  let livePt: Row | null = null;
  const lastRow = chartRows.at(-1);
  if (account.ok && isTrading(today) && lastRow && String(lastRow.day) < today) {
    const mv = zero(), un = zero(), tv = zero();
    for (const l of legs) {
      const g = gOf(l.type, l.side === 'sold'), m = l.mark ?? 0, sgn = l.side === 'sold' ? -1 : 1;
      mv[g] += sgn * m * l.n * 100;
      un[g] += l.side === 'sold' ? -m * l.n * 100 : (m - l.avg) * l.n * 100;
      const S = spotOf.get(l.ticker) ?? l.underlying ?? 0;
      tv[g] += Math.max(0, m - (l.type === 'call' ? Math.max(0, S - l.strike) : Math.max(0, l.strike - S))) * l.n * 100;
    }
    let shVal = 0, shCost = 0;
    for (const [t, q] of sharesNow) { shVal += q * (spotOf.get(t) ?? 0); shCost += shareCost.get(t) ?? 0; }
    mv.sh = shVal; un.sh = shVal - shCost;
    const since = cashBetween(String(lastRow.day), today), rl = realBy(today);
    const groups: Record<string, Record<string, number>> = {};
    for (const g of GK_LIST) {
      const prev = (lastRow.groups as Record<string, Record<string, number>>)[g];
      groups[g] = { line: r2(Number(prev.line) + (mv[g] - Number(prev.mv)) + since[g]), real: r2(rl[g]),
                    unreal: r2(un[g]), tv: r2(tv[g]), mv: r2(mv[g]) };
    }
    groups.sh.tickers = sharesNow.size;
    const commToday = trades.filter((t) => String(t.trade_date) > String(lastRow.day)).reduce((s, t) => s + Number(t.commission ?? 0), 0);
    livePt = { day: today, nav: account.value, cash: account.cash,
      margin: r2(Number(account.value) + Math.max(0, -Number(account.cash))),
      interest_cum: lastRow.interest_cum, commission_cum: r2(Number(lastRow.commission_cum) + commToday),
      dividends_cum: lastRow.dividends_cum, realized_cum: r2(GK_LIST.reduce((s, g) => s + rl[g], 0)),
      unrealized: account.unrealized, time_value: account.time_value_sold,
      capital_long: r2(legs.filter((l) => l.side === 'bought').reduce((s, l) => s + l.avg * l.n * 100, 0)),
      shares_value: r2(shVal), groups };
  }
  const pts = livePt ? [...chartRows, livePt] : chartRows;
  /* Closed positions, for Kept full credit (sold) and Closed in profit
     (bought): one per position, dated when it went flat or expired. */
  const closedPos: (string | number)[][] = [];
  for (const [, rows] of groups) {
    const f = rows[0], short = f.direction === 'short';
    const firstOpen = rows.filter((r) => r.action === 'open').map((r) => String(r.trade_date)).sort()[0];
    if (!firstOpen || firstOpen < BOOK_START) continue;
    const net = rows.reduce((s, r) => s + (r.action === 'open' ? 1 : -1) * Number(r.contracts), 0);
    const closes = rows.filter((r) => r.action === 'close');
    let when: string | null = null;
    if (net <= 0 && closes.length) when = closes.map((r) => String(r.trade_date)).sort().at(-1)!;
    else if (net > 0 && String(f.expiry) < today) when = String(f.expiry);
    if (!when) continue;
    const leg = `${String(f.ticker).toUpperCase()} ${r2(Number(f.strike))}${f.option_type === 'call' ? 'C' : 'P'}`;
    const amt = realized.filter((e) => e.leg === leg && e.exp === String(f.expiry) && e.kind === `${f.option_type === 'call' ? 'calls' : 'puts'} ${short ? 'sold' : 'bought'}`)
      .reduce((s, e) => s + e.amt, 0);
    const flag = short ? (closes.every((r) => Number(r.premium) === 0) ? 1 : 0) : (amt > 0 ? 1 : 0);
    closedPos.push([when, gOf(f.option_type, short), flag, Math.round(amt)]);
  }
  closedPos.sort((a, b) => String(a[0]).localeCompare(String(b[0])));
  /* Dividends: paid days from IBKR, trailing-year yield on the shares held,
     and the next declared payment on a held name. */
  const paidDays = acctDays.filter((d) => Number(d.dividends ?? 0) > 0 && String(d.report_date) > BOOK_START)
    .map((d) => [String(d.report_date), r2(Number(d.dividends))]);
  const yearPaid = acctDays.filter((d) => String(d.report_date) > addDays(today, -365)).reduce((s, d) => s + Number(d.dividends ?? 0), 0);
  const shNow = Number(livePt?.shares_value ?? lastRow?.shares_value ?? 0);
  /* Who paid (02b "Payers"): IBKR's daily cash has no ticker, so a payment
     counts for a name that held shares at the close before its ex-date. */
  const stkDays = [...new Set(posAll.filter((p) => p.asset_category === 'STK').map((p) => String(p.report_date)))].sort();
  const posDays = [...new Set(posAll.map((p) => String(p.report_date)))].sort();
  const payers = divPast.filter((d) => {
    const before = posDays.filter((x) => x < String(d.ex_date)).at(-1);
    return !!before && stkDays.length > 0 && posAll.some((p) => String(p.report_date) === before && p.asset_category === 'STK'
      && String(p.symbol).toUpperCase() === String(d.ticker) && Number(p.position) > 0);
  }).map((d) => [String(d.pay_date), String(d.ticker)]);
  const nextDiv = divs.filter((d) => sharesNow.has(String(d.ticker))).sort((a, b) => String(a.pay_date ?? a.ex_date).localeCompare(String(b.pay_date ?? b.ex_date)))[0];
  const col = (f: string) => pts.map((p) => (p[f] == null ? null : Number(p[f])));
  const gcol = (g: GK, f: string) => pts.map((p) => Number((p.groups as Record<string, Record<string, number>>)[g]?.[f] ?? 0));
  const chart = pts.length ? {
    from: String(pts[0].day), to: String(pts.at(-1)!.day), last_close: lastClose, live_last: !!livePt,
    days: pts.map((p) => String(p.day)),
    nav: col('nav'), margin: col('margin'), realized_cum: col('realized_cum'), unrealized: col('unrealized'),
    time_value: col('time_value'), interest_cum: col('interest_cum'), commission_cum: col('commission_cum'),
    dividends_cum: col('dividends_cum'), capital_long: col('capital_long'), shares_value: col('shares_value'),
    groups: Object.fromEntries(GK_LIST.map((g) => [g, { line: gcol(g, 'line'), real: gcol(g, 'real'),
      unreal: gcol(g, 'unreal'), tv: gcol(g, 'tv') }])),
    shares_tickers: pts.map((p) => Number((p.groups as Record<string, Record<string, number>>).sh?.tickers ?? 0)),
    closed: closedPos,
    dividends: { paid: paidDays, payers, yield_pct: shNow > 0 ? r2(yearPaid / shNow * 100) : null,
      next: nextDiv ? { ticker: nextDiv.ticker, ex_date: nextDiv.ex_date, pay_date: nextDiv.pay_date ?? null,
                        amount: num(nextDiv.cash_amount) } : null },
  } : null;

  step('theta_check');
  const hours = await hoursP;
  /* Each leg's mark at the close before the Chart cards' first session, so a
     card's line colours by the week it shows (Nik, 14 Oct 2026: a LEAP whose
     price rose all week drew red because it is still down since bought). A leg
     opened inside the week starts from what it was opened at. */
  {
    const before = prevTrading(sessions[0]);
    for (const l of legs) {
      const ids = (groups.get(`${l.ticker}|${l.type}|${l.side === 'sold' ? 'short' : 'long'}|${l.strike}|${l.expiry}`) ?? [])
        .filter((t) => t.action === 'open').map((t) => String(t.id));
      const g = l.opened > before ? null : greekOn(ids, before);
      l.mark_wk = g?.last_mark != null ? r2(Number(g.last_mark) * 100) / 100 : g?.mark != null ? r2(Number(g.mark) * 100) / 100 : l.avg;
    }
  }
  step('hours');
  // ── AFTERSHOCK (handoff 26, blocks 26 and 03b) and each name's strategy (13b) ──
  /* The page and the deck card read the last scans and the crashes of the last two weeks; the app
     works out the state (waiting, countdown, scanning, results, Day 2) from the New York clock.
     Day 2 moves come with the next scan (Nik, 19 Oct 2026: option 1; our Polygon plan has no live
     prices for names not held). */
  const [aUni, aScans, aEvents, aTaken] = await Promise.all([
    get('crash_universe?select=ticker'),
    get('crash_scans?order=day.desc&limit=3&select=day,scanned_at,universe,crashes'),
    get(`crash_events?day=gte.${addDays(today, -14)}&order=day.desc,drop_pct.asc&select=ticker,day,prev_close,close,drop_pct,entry_day,day2_close,day2_pct`),
    get('crash_events?taken=eq.true&select=ticker,entry_day&order=entry_day.desc'),
  ]);
  const aftershock = {
    universe: aUni.length,
    scans: aScans.map((x) => ({ day: x.day, crashes: Number(x.crashes), scanned_at: x.scanned_at })),
    events: aEvents.map((e) => ({ ticker: e.ticker, day: e.day, prev_close: num(e.prev_close), close: num(e.close),
      drop_pct: num(e.drop_pct), day2: e.entry_day, day2_close: num(e.day2_close), day2_pct: num(e.day2_pct) })),
    /* Today until today's scan is in, then the next trading day. */
    next_scan_day: isTrading(today) && String(aScans[0]?.day ?? '') !== today ? today : nextTrading(today),
  };
  /* By name (Nik, 19 Oct 2026): TSLA is Ladder; a name whose crash trade was taken (puts sold on its
     Day 2, seen by crash-scan) is Aftershock; every other held name is Rebound. */
  const LADDER = ['TSLA'];
  const takenOn = new Map<string, string>();
  for (const e of aTaken) if (!takenOn.has(String(e.ticker))) takenOn.set(String(e.ticker), String(e.entry_day));
  const strategies: Record<string, string> = {};
  for (const l of legs) {
    if (strategies[l.ticker]) continue;
    const tk = takenOn.get(l.ticker);
    strategies[l.ticker] = LADDER.includes(l.ticker) ? 'ladder'
      : tk && legs.some((x) => x.ticker === l.ticker && x.opened >= tk) ? 'aftershock' : 'rebound';
  }
  step('aftershock');
  const payload = {
    build: BUILD, built_at: new Date().toISOString(), today, trading_today: isTrading(today),
    calendar: cal.filter((c) => String(c.date) >= today)
      .map((c) => ({ date: c.date, kind: c.kind, closes: c.closes, name: c.name })),
    trade_to_415: TRADE_TO_415.filter((t) => book.includes(t)),
    fresh, account, indices, overnight, futures, watchlist, portfolio, legs, hours, risk,
    chart, history, payback, yield: yieldOut, inventory, sold_vs_bought: soldVsBought, performance, allocation,
    deck: { earnings, season: seasonOut, reports: reportsOut, theta_checks: thetaChecks.filter((c) => c.card_today) },
    /* A name with no chain cached for that Friday is listed apart, so one
       missing chain can never break the payload's shape. */
    writes: { expiry: targetExp, names: writes.filter((w: Row) => !w.error),
              missing: writes.filter((w: Row) => w.error).map((w: Row) => w.ticker) },
    theta_checks: thetaChecks, last_week: lastWeek, ...(checkSummary ? { theta_check_run: checkSummary } : {}),
    aftershock, strategies,
  };
  return { payload, ms: Date.now() - t0, steps };
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
  let body: { passes?: number; mode?: 'theta_check' | 'history' | 'last_week'; dry?: boolean; price?: string } = {};
  try { if (req.method === 'POST') body = await req.json(); } catch { /* cron sends {} */ }
  try {
    const n = ny();
    const live = !['Sat', 'Sun'].includes(n.wd) && n.mins >= 4 * 60 && n.mins < 20 * 60;
    /* ⚠ EVERY 15 S IN THE REGULAR SESSION (Nik, 14 Oct 2026): mp-refresh
       prices at :00 :15 :30 :45 from 9:30 to 16:00 New York, so four builds,
       each just after a price pass; every 30 s otherwise. */
    const regular = live && n.mins >= 9 * 60 + 30 && n.mins < 16 * 60;
    const passes = body.mode ? 1 : body.passes ?? (regular ? 4 : live ? 2 : (n.mins % 10 === 0 ? 1 : 0));
    const out: Row[] = [];
    for (let i = 0; i < passes; i++) {
      /* mp-refresh writes on its pass and takes 2-4 s; build just after. */
      if (live && !body.passes && !body.mode) {
        const at = 6_000 + i * (passes === 4 ? 15_000 : 30_000);
        const wait = (at - (Date.now() % 60_000) + 60_000) % 60_000;
        if (wait < (passes === 4 ? 16_000 : 40_000)) await new Promise((r) => setTimeout(r, wait));
      }
      const { payload, ms, steps } = await build(body.mode ?? 'tick', { dry: body.dry, price: body.price });
      const w = await fetch(`${URL_}/rest/v1/home_snapshot?on_conflict=id`, {
        method: 'POST', headers: { ...H, Prefer: 'resolution=merge-duplicates,return=minimal' },
        body: JSON.stringify([{ id: 1, payload, built_at: payload.built_at, build: BUILD, ms }]),
      });
      if (!w.ok) throw new Error(`home_snapshot ${w.status} ${(await w.text()).slice(0, 160)}`);
      out.push({ ms, steps, legs: (payload.legs as unknown[]).length, value: (payload.account as Row).value ?? null });
    }
    if (out.length) {
      await fetch(`${URL_}/rest/v1/sync_heartbeat?on_conflict=feed`, {
        method: 'POST', headers: { ...H, Prefer: 'resolution=merge-duplicates,return=minimal' },
        body: JSON.stringify([{ feed: 'sunny-home', ran_at: new Date().toISOString(), rows_written: out.length,
          detail: out.map((o) => `${o.ms}ms`).join(' / ') }]),
      });
    }
    /* Timings only: the payload leaves through home_snapshot, never here. */
    return new Response(JSON.stringify({ ok: true, build: BUILD, passes: out.map((o) => ({ ms: o.ms, steps: o.steps, legs: o.legs })) }),
      { headers: { 'Content-Type': 'application/json' } });
  } catch (e) {
    return new Response(JSON.stringify({ ok: false, build: BUILD, error: String(e).slice(0, 300) }),
      { status: 500, headers: { 'Content-Type': 'application/json' } });
  }
});
