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
const BUILD = '2026-10-12.4';
const BOOK_START = '2026-08-31';          // PNL_GLOSSARY: the stock-replacement shift
const WATCH = ['INTU', 'ADBE', 'PYPL', 'VZ', 'TMUS'];
/* Options on these trade to 4:15 ET (block 01). One config; extend here. */
const TRADE_TO_415 = ['SPY', 'QQQ', 'IWM', 'DIA'];

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
/** PostgREST caps a read at 1,000 rows, silently: page anything that grows. */
async function page(q: string): Promise<Row[]> {
  const out: Row[] = [];
  for (let from = 0; from < 100_000; from += 1000) {
    const r = await fetch(`${URL_}/rest/v1/${q}`, { headers: { ...H, Range: `${from}-${from + 999}` } });
    if (!r.ok) throw new Error(`${q.split('?')[0]} ${r.status} ${(await r.text()).slice(0, 160)}`);
    const rows = await r.json() as Row[];
    out.push(...rows);
    if (rows.length < 1000) break;
  }
  return out;
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

async function build(): Promise<{ payload: Row; ms: number }> {
  const t0 = Date.now();
  const now = ny();
  const today = now.date;

  const [trades, greeks, quotes, market, acctDays, cal, earn, seasons, closes, runs, sells, lots] = await Promise.all([
    page('option_trades?voided_at=is.null&order=id.asc&select=id,ticker,trade_date,action,option_type,'
      + 'direction,contracts,strike,premium,expiry,executed_at,commission,net_cash,realized_pl,realized_pl_source'),
    get('option_greeks_live?select=option_trade_id,last_mark,iv,delta,gamma,theta,vega,underlying,captured_at'),
    get('ticker_quotes_live?select=ticker,spot,day_change_pct,captured_at'),
    get('market_live?select=*'),
    get(`account_value_daily?report_date=gte.${addDays(BOOK_START, -5)}&order=report_date.desc`),
    get(`market_calendar?date=gte.${addDays(BOOK_START, -40)}&date=lte.${addDays(today, 120)}&order=date.asc`),
    get(`earnings_events?report_date=gte.${addDays(today, -1)}&report_date=lte.${addDays(today, 70)}`
      + '&select=ticker,report_date,report_time,date_estimated,source&order=report_date.asc'),
    get('earnings_season?select=*&order=starts.desc&limit=6'),
    page(`daily_closes?date=gte.${[addDays(today, -45), addDays(BOOK_START, -7)].sort()[0]}&order=date.asc&select=ticker,date,close_price`),
    get('ibkr_sync_runs?status=eq.success&order=finished_at.desc&limit=1&select=finished_at'),
    get(`share_sells?voided_at=is.null&trade_date=gte.${BOOK_START}&select=ticker,trade_date,quantity,realized_pl`),
    get(`share_lots?voided_at=is.null&acquired_date=gte.${BOOK_START}&select=ticker,acquired_date`),
  ]);

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
    theta: number | null; gamma: number | null; vega: number | null; underlying: number | null; marked_at: string | null };
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

  /* ── REALIZED, per docs/PNL_GLOSSARY.md (Nik chose the glossary for the
     header, 12 Oct 2026). Only what closed: sold options bought back or
     expired, bought options sold or expired, and shares sold. IBKR's AVERAGE
     cost (28 Sep ruling), and IBKR's own realized_pl wherever the Daily Flex
     delivered it (it carries commissions and handles assignments: an assigned
     option books 0, its premium lives in the share sale). Booked on the close
     date, or the expiry date for a leg left to expire. A leg is in or out by
     when it was OPENED: nothing opened before 31 Aug 2026 counts. */
  type Ev = { d: string; ticker: string; kind: 'calls sold' | 'puts sold' | 'calls bought' | 'puts bought' | 'shares'; amt: number };
  const realized: Ev[] = [];
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
    let qty = 0, cost = 0;
    for (const t of fills) {
      const n = Number(t.contracts), px = Number(t.premium) * 100;
      if (t.action === 'open') { qty += n; cost += n * px; continue; }
      const avg = qty > 0 ? cost / qty : 0;
      const ib = t.realized_pl != null && t.realized_pl_source === 'ibkr' ? Number(t.realized_pl) : null;
      const amt = ib ?? (short ? n * (avg - px) : n * (px - avg));
      realized.push({ d: String(t.trade_date), ticker: String(f0.ticker).toUpperCase(), kind, amt });
      cost -= n * avg; qty -= n;
    }
    if (qty > 0.0001 && String(f0.expiry) < today) {
      realized.push({ d: String(f0.expiry), ticker: String(f0.ticker).toUpperCase(), kind, amt: short ? cost : -cost });
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
    realized.push({ d, ticker: t, kind: 'shares', amt: Number(s.realized_pl ?? 0) });
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

  // ── Account: IBKR's last close, moved by today's prices and fills ──
  const anchor = acctDays.find((d) => Number(d.accounts) >= 2) ?? null;
  let account: Row = { ok: false, why: 'no IBKR daily statement yet' };
  if (anchor) {
    const D = String(anchor.report_date);
    const posD = await get(`account_positions_daily?report_date=eq.${D}&select=*`);
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
    at: m.captured_at,
  });
  const indices = ['SPY', 'QQQ', 'IWM', '^VIX'].map((s) => tape(mk(s))).filter(Boolean);
  const overnight = ['^N225', '^GDAXI', '^NSEI', '000001.SS'].map((s) => tape(mk(s))).filter(Boolean);
  const watchlist = WATCH.map((s) => {
    const m = mk(s); if (!m) return null;
    return { ticker: s, price: num(m.regular_price), ranges: ranges(s, num(m.regular_price), num(m.regular_change_pct)) };
  }).filter(Boolean);

  // ── Portfolio: exposure per name, moves per range ──
  const sharesNow = new Map<string, number>();
  const shareCost = new Map<string, number>();
  if (anchor) {
    const posD = await get(`account_positions_daily?report_date=eq.${anchor.report_date}&asset_category=eq.STK&select=symbol,position,cost_basis_money`);
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

  // ── Risk: Theta and Delta now (history comes from the daily roll-up) ──
  const tick = new Map<string, { collect: number; lose: number; longD: number; soldD: number }>();
  let thShort = 0, thLong = 0, dLong = 0, dSold = 0;
  for (const l of legs) {
    const e = tick.get(l.ticker) ?? { collect: 0, lose: 0, longD: 0, soldD: 0 };
    const th = Math.abs(l.theta ?? 0) * l.n * 100;
    if (l.side === 'sold') { thShort += th; e.collect += th; } else { thLong += th; e.lose += th; }
    /* Delta is calls only (block 16, Nik accepted 12 Oct 2026). */
    if (l.type === 'call' && l.delta != null) {
      const d = Math.abs(l.delta) * l.n * 100;
      if (l.side === 'sold') { dSold += d; e.soldD += d; } else { dLong += d; e.longD += d; }
    }
    tick.set(l.ticker, e);
  }
  const risk = {
    theta: { short: r2(thShort), long: r2(thLong), ratio_now: thLong > 0 ? r2(thShort / thLong) : null,
      by: [...tick].map(([t, e]) => ({ ticker: t, collect: r2(e.collect), lose: r2(e.lose), net: r2(e.collect - e.lose) }))
        .sort((a, b) => Math.abs(b.net) - Math.abs(a.net)) },
    delta: { sold: Math.round(dSold), long: Math.round(dLong), ratio_now: dLong > 0 ? r2(dSold / dLong * 100) : null,
      by: [...tick].filter(([, e]) => e.longD > 0)
        .map(([t, e]) => ({ ticker: t, sold: Math.round(e.soldD), long: Math.round(e.longD), pct: r2(e.soldD / e.longD * 100) }))
        .sort((a, b) => b.pct - a.pct) },
  };

  // ════════════════════════════════════════════════════════════════════════
  // THE CARDS' HISTORY: one point per trading day, from leg_marks_daily.
  // ════════════════════════════════════════════════════════════════════════
  const monthsBack = (iso: string, m: number) => {
    const [y, mo] = iso.split('-').map(Number);
    const d = new Date(Date.UTC(y, mo - 1 - m, 1));
    return d.toISOString().slice(0, 10);
  };
  /* Rolling 3 calendar months (block 15), never before the book: Nik took the
     proposal to start the charts on 1 Sep 2026. */
  const winStart = [monthsBack(today, 2), '2026-09-01'].sort().at(-1)!;
  const days: string[] = [];
  for (let d = winStart; d < today; d = addDays(d, 1)) if (isTrading(d)) days.push(d);
  const marksFrom = [addDays(today, -45), addDays(winStart, -10), addDays(BOOK_START, -5)].sort()[0];
  const lmd = await page(`leg_marks_daily?day=gte.${marksFrom}&order=day.asc,option_trade_id.asc`
    + '&select=option_trade_id,day,mark,delta,theta,underlying');
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
  type Point = { d: string; thS: number; thL: number; dS: number; dL: number; longMV: number; shortMV: number;
                 thLongBy: Record<string, number> };
  const pointOf = (d: string, live: boolean): Point => {
    const p: Point = { d, thS: 0, thL: 0, dS: 0, dL: 0, longMV: 0, shortMV: 0, thLongBy: {} };
    const ls = live
      ? legs.map((l) => ({ ticker: l.ticker, type: l.type, short: l.side === 'sold', n: l.n,
          g: { theta: l.theta, delta: l.delta, mark: l.mark } as Row, key: `${l.ticker}|${l.type}|${l.strike}|${l.expiry}` }))
      : legsAt(d).map((l) => ({ ticker: l.ticker, type: l.type, short: l.short, n: l.n, g: greekOn(l.ids, d) ?? {},
          key: `${l.ticker}|${l.type}|${l.strike}|${l.expiry}` }));
    for (const l of ls) {
      const th = Math.abs(Number(l.g.theta ?? 0)) * l.n * 100;
      const mv = Number(l.g.mark ?? 0) * l.n * 100;
      if (l.short) { p.thS += th; p.shortMV += mv; } else {
        p.thL += th; p.longMV += mv; p.thLongBy[l.key] = (p.thLongBy[l.key] ?? 0) + th;
      }
      if (l.type === 'call' && l.g.delta != null) {
        const dl = Math.abs(Number(l.g.delta)) * l.n * 100;
        if (l.short) p.dS += dl; else p.dL += dl;
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
  for (const r of await page(`account_positions_daily?report_date=gte.${winStart}&asset_category=eq.OPT`
      + '&order=report_date.asc,account_id.asc,conid.asc&select=report_date,position,position_value')) {
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
  const peakAt = theta2w.reduce((b, v, i) => (v != null && (b < 0 || v > (theta2w[b] ?? -1)) ? i : b), -1);
  const history = {
    from: winStart, live_today: !!livePoint,
    days: all.map((p) => p.d),
    theta: { daily: thetaDaily.map((x) => (x == null ? null : r2(x))), avg2w: theta2w.map((x) => (x == null ? null : r2(x))),
      now: theta2w.at(-1) == null ? null : r2(theta2w.at(-1)!), trend: trendOf(theta2w),
      peak: peakAt >= 0 ? { d: all[peakAt].d, v: r2(theta2w[peakAt]!), at_right_edge: peakAt >= all.length * 0.9 } : null,
      short: all.map((p) => Math.round(p.thS)), long: all.map((p) => Math.round(p.thL)) },
    delta: { daily: deltaDaily.map((x) => (x == null ? null : Math.round(x))), avg2w: delta2w.map((x) => (x == null ? null : Math.round(x))),
      now: delta2w.at(-1) == null ? null : Math.round(delta2w.at(-1)!), trend: trendOf(delta2w),
      sold: all.map((p) => Math.round(p.dS)), long: all.map((p) => Math.round(p.dL)) },
  };

  // ── Payback (block 18): what the LEAPs cost, split, and how it comes back ──
  const leapLots: { ticker: string; k: number; d: string; n: number; tv: number; intr: number }[] = [];
  for (const l of legs.filter((x) => x.side === 'bought' && x.type === 'call')) {
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
  for (const l of legs.filter((x) => x.side === 'bought' && x.type === 'call')) {
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
    return { d, tvT: Math.round(tvT), inT: Math.round(inT), tvPaid: Math.round(tvPaid), inPaid: Math.round(inPaid) };
  };
  const firstLeap = leapLots.map((x) => x.d).sort()[0] ?? null;
  const payDays = firstLeap ? [...days.filter((d) => d >= firstLeap)] : [];
  const paySeries = payDays.map((d) => paybackOn(d, false));
  if (firstLeap && isTrading(today)) paySeries.push(paybackOn(today, true));
  const paceOf = (f: 'tvPaid' | 'inPaid') => {
    if (paySeries.length < 2) return null;
    const now = paySeries.at(-1)!, i0 = Math.max(0, paySeries.length - 1 - 25);
    const weeks = Math.max(1, (paySeries.length - 1 - i0) / 5);
    return Math.round((now[f] - paySeries[i0][f]) / weeks);
  };
  const payback = paySeries.length ? {
    now: paySeries.at(-1), pace_tv: paceOf('tvPaid'), pace_intr: paceOf('inPaid'),
    series: paySeries.map((p) => [p.d, p.tvT, p.tvPaid, p.inT, p.inPaid]),
    new_leap_days: [...new Set(leapLots.map((x) => x.d))].sort(),
  } : null;

  // ── Yield (block 17): every short credit, filed under the week it covers ──
  const weekStartOf = (iso: string) => { const d = new Date(iso + 'T12:00:00Z'); const wd = (d.getUTCDay() + 6) % 7; return addDays(iso, -wd); };
  const yieldWeeks = new Map<string, { cs: number; cb: number; ps: number; pb: number; month: string }>();
  for (const [, rows] of groups) {
    const f = rows[0];
    if (f.direction !== 'short') continue;
    const firstOpen = rows.filter((r) => r.action === 'open').map((r) => String(r.trade_date)).sort()[0];
    if (!firstOpen || firstOpen < BOOK_START) continue;
    const exp = String(f.expiry), w = weekStartOf(exp);
    const e = yieldWeeks.get(w) ?? { cs: 0, cb: 0, ps: 0, pb: 0, month: exp.slice(0, 7) };
    for (const t of rows) {
      const c = Number(t.contracts) * Number(t.premium) * 100;
      if (f.option_type === 'call') { if (t.action === 'open') e.cs += c; else e.cb += c; }
      else { if (t.action === 'open') e.ps += c; else e.pb += c; }
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
             puts_sold: Math.round(e.ps), puts_back: Math.round(e.pb), invested: Math.round(inv) };
  });

  // ── Inventory (block 14): the shelf, now and per week covered ──
  const invNow = new Map<string, { cH: number; cS: number; pH: number; pS: number; credit: number }>();
  for (const l of legs) {
    const e = invNow.get(l.ticker) ?? { cH: 0, cS: 0, pH: 0, pS: 0, credit: 0 };
    if (l.type === 'call') { if (l.side === 'bought') e.cH += l.n; else e.cS += l.n; }
    else { if (l.side === 'bought') e.pH += l.n; else e.pS += l.n; }
    if (l.side === 'sold') e.credit += l.avg * l.n * 100;
    invNow.set(l.ticker, e);
  }
  const invRows = [...invNow].map(([t, e]) => ({ ticker: t, calls_max: e.cH, calls_sold: e.cS, puts_max: e.pH,
    puts_sold: e.pS, credit_open: Math.round(e.credit) }));
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
    return { week: w, fri: addDays(w, 4), calls: peak('call'), puts: peak('put') };
  });
  const inventory = {
    calls_max: invRows.reduce((s, r) => s + r.calls_max, 0), calls_sold: invRows.reduce((s, r) => s + r.calls_sold, 0),
    puts_max: invRows.reduce((s, r) => s + r.puts_max, 0), puts_sold: invRows.reduce((s, r) => s + r.puts_sold, 0),
    credit_open: invRows.reduce((s, r) => s + r.credit_open, 0),
    by: invRows.filter((r) => r.calls_max + r.puts_max > 0)
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

  const payload = {
    build: BUILD, built_at: new Date().toISOString(), today, trading_today: isTrading(today),
    calendar: cal.filter((c) => String(c.date) >= today)
      .map((c) => ({ date: c.date, kind: c.kind, closes: c.closes, name: c.name })),
    trade_to_415: TRADE_TO_415.filter((t) => book.includes(t)),
    fresh, account, indices, overnight, watchlist, portfolio, legs, risk,
    history, payback, yield: yieldOut, inventory, sold_vs_bought: soldVsBought, performance, allocation,
    deck: { earnings, season: seasonOut },
  };
  return { payload, ms: Date.now() - t0 };
}

Deno.serve(async (req) => {
  let body: { passes?: number } = {};
  try { if (req.method === 'POST') body = await req.json(); } catch { /* cron sends {} */ }
  try {
    const n = ny();
    const live = !['Sat', 'Sun'].includes(n.wd) && n.mins >= 4 * 60 && n.mins < 20 * 60;
    const passes = body.passes ?? (live ? 2 : (n.mins % 10 === 0 ? 1 : 0));
    const out: Row[] = [];
    for (let i = 0; i < passes; i++) {
      /* mp-refresh writes at :00 and :30 and takes 2-4 s; build just after. */
      if (live && !body.passes) {
        const wait = ((i === 0 ? 6_000 : 36_000) - (Date.now() % 60_000) + 60_000) % 60_000;
        if (wait < 40_000) await new Promise((r) => setTimeout(r, wait));
      }
      const { payload, ms } = await build();
      const w = await fetch(`${URL_}/rest/v1/home_snapshot?on_conflict=id`, {
        method: 'POST', headers: { ...H, Prefer: 'resolution=merge-duplicates,return=minimal' },
        body: JSON.stringify([{ id: 1, payload, built_at: payload.built_at, build: BUILD, ms }]),
      });
      if (!w.ok) throw new Error(`home_snapshot ${w.status} ${(await w.text()).slice(0, 160)}`);
      out.push({ ms, legs: (payload.legs as unknown[]).length, value: (payload.account as Row).value ?? null });
    }
    if (out.length) {
      await fetch(`${URL_}/rest/v1/sync_heartbeat?on_conflict=feed`, {
        method: 'POST', headers: { ...H, Prefer: 'resolution=merge-duplicates,return=minimal' },
        body: JSON.stringify([{ feed: 'sunny-home', ran_at: new Date().toISOString(), rows_written: out.length,
          detail: out.map((o) => `${o.ms}ms`).join(' / ') }]),
      });
    }
    /* Timings only: the payload leaves through home_snapshot, never here. */
    return new Response(JSON.stringify({ ok: true, build: BUILD, passes: out.map((o) => ({ ms: o.ms, legs: o.legs })) }),
      { headers: { 'Content-Type': 'application/json' } });
  } catch (e) {
    return new Response(JSON.stringify({ ok: false, build: BUILD, error: String(e).slice(0, 300) }),
      { status: 500, headers: { 'Content-Type': 'application/json' } });
  }
});
