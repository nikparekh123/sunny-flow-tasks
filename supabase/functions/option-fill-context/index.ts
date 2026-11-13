/**
 * option-fill-context: where each sold option leg sat when it was sold (handoff 2026-11-13-positions §3.3, Nik A4,
 * 13 Nov 2026). The Positions page's Sold, in SD card draws a hollow dot at the strike's SD on the day it was sold;
 * this saves what that needs, one row per opening sale, in option_fill_context. Written once, never overwritten.
 *
 * Every open sold leg in EVERY book (pooled FIFO per contract within each book, as sunny-home and mp-refresh) that has
 * no row gets one:
 *   sold today     underlying = the 15-second quote nearest the execution time (ticker_quotes, within 10 minutes),
 *                  else the latest quote; iv = option_chain_next's mid IV for that expiry, strike and side, else the
 *                  leg's own live mark IV (option_greeks_live), else the 30-day ATM IV (ticker_technicals).
 *                  approx = false only with the strike's own IV from the chain. source 'fill'.
 *   sold earlier   leg_marks_daily on the trade date (that trade's row, else another trade of the same contract that
 *                  day): underlying and iv, approx = true, source 'backfill'. Else daily_closes on the trade date and
 *                  ticker_technicals.atm_iv that day, approx = true, source 'backfill-close'.
 *   td  trading days after the trade date through the expiry (weekends and market_calendar closed days left out), as
 *       sunny-sd counts them from today; cd calendar days.
 *   z0  ln(K / underlying) / (iv x sqrt(td / 252)), signed. Sold on the expiry day (td 0): the part of the session left
 *       at the fill, at least a quarter hour, over 6.5 x 252.
 *
 * Run by pg_cron (option-fill-context-5min, every 5 minutes 13-21 UTC weekdays). POST {} ; { dry_run: true } shows
 * what it would write. ⚠ WHO MAY CALL: the scheduler (x-cron-key), an admin call, or the service role.
 * The IBKR sync is not touched. No em dashes in any words here (Nik).
 */

const BUILD = '2026-11-13.1';
const URL_ = Deno.env.get('SUPABASE_URL')!;
const KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const H = { apikey: KEY, Authorization: `Bearer ${KEY}`, 'Content-Type': 'application/json' };
type Row = Record<string, any>;
const json = (s: number, b: unknown) => new Response(JSON.stringify(b), { status: s, headers: { 'Content-Type': 'application/json' } });

async function get(q: string): Promise<Row[]> {
  const r = await fetch(`${URL_}/rest/v1/${q}`, { headers: H });
  if (!r.ok) throw new Error(`${q.split('?')[0]}: ${r.status} ${(await r.text()).slice(0, 200)}`);
  return await r.json();
}
/** Every row of a growing table: PostgREST stops at 1,000 rows, so read in Range pages (the query must carry an order). */
async function page(q: string): Promise<Row[]> {
  const out: Row[] = [];
  for (let from = 0; ; from += 1000) {
    const r = await fetch(`${URL_}/rest/v1/${q}`, { headers: { ...H, Range: `${from}-${from + 999}` } });
    if (!r.ok) throw new Error(`${q.split('?')[0]}: ${r.status} ${(await r.text()).slice(0, 200)}`);
    const rows = await r.json() as Row[];
    out.push(...rows);
    if (rows.length < 1000) return out;
  }
}
const chunks = <T>(xs: T[], n: number): T[][] => Array.from({ length: Math.ceil(xs.length / n) }, (_, i) => xs.slice(i * n, i * n + n));

const nyParts = (d = new Date()) => {
  const p = Object.fromEntries(new Intl.DateTimeFormat('en-CA', { timeZone: 'America/New_York', year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', hour12: false })
    .formatToParts(d).map((x) => [x.type, x.value]));
  return { day: `${p.year}-${p.month}-${p.day}`, mins: (Number(p.hour) % 24) * 60 + Number(p.minute) };
};
const addDays = (d: string, n: number) => { const x = new Date(d + 'T12:00:00Z'); x.setUTCDate(x.getUTCDate() + n); return x.toISOString().slice(0, 10); };
const num = (v: unknown) => (v == null || v === '' || !Number.isFinite(Number(v)) ? null : Number(v));
const r6 = (v: number) => Math.round(v * 1e6) / 1e6;

async function callerOk(req: Request): Promise<boolean> {
  const cron = Deno.env.get('CRON_SECRET');
  if (cron && (req.headers.get('x-cron-key') === cron || req.headers.get('x-admin-key') === cron)) return true;
  return (req.headers.get('authorization') ?? '') === `Bearer ${KEY}`;
}

Deno.serve(async (req) => {
  if (!(await callerOk(req))) return json(401, { ok: false, error: 'not allowed' });
  const body = await req.json().catch(() => ({})) as Row;
  const dry = body.dry_run === true;
  const t0 = Date.now(), { day: today } = nyParts();
  try {
    // ── Open sold lots: pooled FIFO per contract inside each book (opens by id, as sunny-home) ──
    const trades = await page(`option_trades?voided_at=is.null&expiry=gte.${today}&order=id.asc`
      + '&select=id,book_id,ticker,trade_date,executed_at,action,option_type,direction,contracts,strike,expiry');
    const groups = new Map<string, Row[]>();
    for (const t of trades) {
      const k = [t.book_id, String(t.ticker).toUpperCase(), t.option_type, t.direction, Number(t.strike), t.expiry].join('|');
      (groups.get(k) ?? groups.set(k, []).get(k)!).push(t);
    }
    const lots: Row[] = [];
    for (const rows of groups.values()) {
      if (rows[0].direction !== 'short') continue;
      const opens = rows.filter((r) => r.action === 'open').sort((a, b) => (a.id < b.id ? -1 : 1));
      let closeQty = rows.filter((r) => r.action === 'close').reduce((s, r) => s + Number(r.contracts), 0);
      for (const o of opens) {
        const take = Math.min(closeQty, Number(o.contracts));
        closeQty -= take;
        if (Number(o.contracts) - take > 0) lots.push(o);
      }
    }
    if (!lots.length) return json(200, { ok: true, build: BUILD, today, open: 0, written: 0, ms: Date.now() - t0 });

    // ── Which already have a row ──
    const have = new Set<string>();
    for (const c of chunks(lots.map((l) => String(l.id)), 80)) {
      for (const r of await get(`option_fill_context?option_trade_id=in.(${c.join(',')})&select=option_trade_id`)) have.add(String(r.option_trade_id));
    }
    const todo = lots.filter((l) => !have.has(String(l.id)));
    if (!todo.length) return json(200, { ok: true, build: BUILD, today, open: lots.length, written: 0, ms: Date.now() - t0 });

    // ── The inputs, read once ──
    const tickers = [...new Set(todo.map((l) => String(l.ticker).toUpperCase()))].sort();
    const tIn = `in.(${tickers.join(',')})`;
    const minDay = todo.map((l) => String(l.trade_date)).sort()[0];
    const maxEx = todo.map((l) => String(l.expiry)).sort().at(-1)!;
    const days = [...new Set(todo.map((l) => String(l.trade_date)))];
    const [cal, quotes, chain, techs, closes, lmdOwn] = await Promise.all([
      get(`market_calendar?kind=eq.closed&date=gte.${minDay}&date=lte.${maxEx}&select=date`),
      get(`ticker_quotes_latest?ticker=${tIn}&select=ticker,spot,captured_at`),
      page(`option_chain_next?ticker=${tIn}&iv=gt.0&order=ticker.asc,expiry.asc,side.asc,strike.asc&select=ticker,expiry,side,strike,iv,spot`),
      page(`ticker_technicals?ticker=${tIn}&day=gte.${addDays(minDay, -7)}&order=ticker.asc,day.asc&select=ticker,day,atm_iv,close`),
      page(`daily_closes?ticker=${tIn}&date=gte.${addDays(minDay, -7)}&order=ticker.asc,date.asc&select=ticker,date,close_price`),
      page(`leg_marks_daily?day=in.(${days.join(',')})&order=day.asc,option_trade_id.asc&select=option_trade_id,day,underlying,iv`),
    ]);
    const closed = new Set(cal.map((x) => String(x.date)));
    const tradingDays = (from: string, to: string) => {
      let n = 0;
      for (let d = addDays(from, 1); d <= to; d = addDays(d, 1)) { const w = new Date(d + 'T12:00:00Z').getUTCDay(); if (w !== 0 && w !== 6 && !closed.has(d)) n++; }
      return n;
    };
    const calDays = (from: string, to: string) => Math.round((Date.parse(to + 'T12:00:00Z') - Date.parse(from + 'T12:00:00Z')) / 864e5);
    const quoteBy = new Map(quotes.map((q) => [String(q.ticker), q]));
    const chainBy = new Map(chain.map((c) => [`${c.ticker}|${c.expiry}|${c.side}|${Number(c.strike)}`, Number(c.iv)]));
    // A leg_marks_daily row of any trade of the same contract that day (market data, the same for every book).
    const tradeById = new Map(trades.map((t) => [String(t.id), t]));
    const contract = (t: Row) => `${String(t.ticker).toUpperCase()}|${t.option_type}|${Number(t.strike)}|${t.expiry}`;
    const lmdBy = new Map<string, Row>(), lmdContract = new Map<string, Row>();
    for (const m of lmdOwn) {
      if (num(m.iv) == null || !(Number(m.iv) > 0)) continue;
      lmdBy.set(`${m.option_trade_id}|${m.day}`, m);
      const t = tradeById.get(String(m.option_trade_id));
      if (t && num(m.underlying) != null) { const k = `${contract(t)}|${m.day}`; if (!lmdContract.has(k)) lmdContract.set(k, m); }
    }
    const techOn = (t: string, d: string) => techs.filter((x) => x.ticker === t && String(x.day) <= d).at(-1) ?? null;
    const closeOn = (t: string, d: string) => closes.find((x) => x.ticker === t && String(x.date) === d) ?? null;
    const lastTech = (t: string) => techs.filter((x) => x.ticker === t && num(x.atm_iv) != null).at(-1) ?? null;

    const out: Row[] = [], miss: Row[] = [];
    for (const l of todo) {
      const t = String(l.ticker).toUpperCase(), side = String(l.option_type), K = Number(l.strike), ex = String(l.expiry), d = String(l.trade_date);
      let S: number | null = null, iv: number | null = null, approx = true, source = '';
      if (d === today) {
        source = 'fill';
        if (l.executed_at) {
          const at = Date.parse(String(l.executed_at));
          const qs = await get(`ticker_quotes?ticker=eq.${t}&captured_at=gte.${new Date(at - 600_000).toISOString()}&captured_at=lte.${new Date(at + 600_000).toISOString()}&order=captured_at.asc&select=spot,captured_at`);
          const best = qs.filter((q) => Number(q.spot) > 0).sort((a, b) => Math.abs(Date.parse(a.captured_at) - at) - Math.abs(Date.parse(b.captured_at) - at))[0];
          if (best) S = Number(best.spot);
        }
        const q = quoteBy.get(t);
        if (S == null && q && Number(q.spot) > 0 && nyParts(new Date(String(q.captured_at))).day === today) S = Number(q.spot);
        const civ = chainBy.get(`${t}|${ex}|${side}|${K}`);
        if (civ && civ > 0) { iv = civ; approx = false; }
        if (iv == null) {
          const g = (await get(`option_greeks_live?option_trade_id=eq.${l.id}&iv=gt.0&order=captured_at.desc&limit=1&select=iv,underlying,captured_at`))[0];
          if (g) iv = Number(g.iv);
        }
        if (iv == null) { const tt = lastTech(t); if (tt) iv = Number(tt.atm_iv); }
        if (S == null || iv == null) approx = true;
      } else {
        const m = lmdBy.get(`${l.id}|${d}`) ?? lmdContract.get(`${contract(l)}|${d}`) ?? null;
        if (m) {
          source = 'backfill';
          iv = Number(m.iv);
          S = num(m.underlying) ?? num(closeOn(t, d)?.close_price);
        }
        if (S == null || iv == null) {
          const c = closeOn(t, d), tt = techOn(t, d);
          if (c && tt && num(tt.atm_iv) != null) { source = 'backfill-close'; S = Number(c.close_price); iv = Number(tt.atm_iv); }
        }
        approx = true;
      }
      if (S == null || iv == null || !(S > 0) || !(iv > 0)) { miss.push({ id: l.id, book: l.book_id, t, side, K, ex, d, why: S == null ? 'no price' : 'no IV' }); continue; }
      const td = tradingDays(d, ex), cd = calDays(d, ex);
      let yrs = td / 252;
      if (td <= 0) {
        // Sold on the expiry day: the part of the session left at the fill.
        const mins = l.executed_at ? nyParts(new Date(String(l.executed_at))).mins : 9 * 60 + 30;
        yrs = Math.max(0.25, (16 * 60 - mins) / 60) / (6.5 * 252);
      }
      const z0 = Math.log(K / S) / (iv * Math.sqrt(yrs));
      out.push({ option_trade_id: l.id, ticker: t, side, underlying: r6(S), iv: r6(iv), td, cd, z0: Number.isFinite(z0) ? r6(z0) : null, approx, source });
    }

    if (!dry && out.length) {
      const r = await fetch(`${URL_}/rest/v1/option_fill_context?on_conflict=option_trade_id`, {
        method: 'POST', headers: { ...H, Prefer: 'resolution=ignore-duplicates,return=minimal' }, body: JSON.stringify(out) });
      if (!r.ok) throw new Error(`option_fill_context: ${r.status} ${(await r.text()).slice(0, 200)}`);
    }
    return json(200, { ok: true, build: BUILD, today, dry, open: lots.length, had: have.size, written: dry ? 0 : out.length,
      rows: dry || body.verbose ? out : undefined, missing: miss, ms: Date.now() - t0 });
  } catch (e) {
    return json(502, { ok: false, build: BUILD, error: String((e as Error)?.message ?? e) });
  }
});
