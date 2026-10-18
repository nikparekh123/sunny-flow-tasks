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
 *
 * THE READS (step 2 of the NKE weekly rule, Nik 17 Oct 2026; docs/STRATEGIES.md
 * "NKE weekly rule (trial)"): fundamentals, technicals, IV, history, momentum,
 * events and the breakout week, one {read, fact} each, on the latest day's row
 * (ticker_technicals.reads). Same definitions as the tested replay
 * (research/target-study/playbook_replay.py). Step 3, the engine, turns them into
 * the week's pick. Portfolio delta is not here: it needs the book (sunny-home).
 *   ticker_fundamentals  one row a day: the Nasdaq analyst target, and Nik's
 *                        weekly model number carried until he gives a new one.
 */

const BUILD = '2026-10-17.2';
/* ⚠ ONE NAME FOR NOW (Nik, 16 Oct 2026: "do this only for one ticker for now
   to test it"). Widen to the book and the watchlist once he has seen NKE. */
const TICKERS = ['NKE'];
const KEEP_DAYS = 260;          // rows written each run (a year of trading days)
const PIVOT = 5;                // a turning point beats 5 sessions either side
const SWING_LOOKBACK = 126;     // about 6 months of sessions
const MERGE_PCT = 1.5;          // turning points within 1.5% are one wall
/* Nasdaq refuses requests without a browser's headers. This goes to Nasdaq
   only, never to Supabase (a browser UA on a secret key is refused there). */
const UA = {
  'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 '
    + '(KHTML, like Gecko) Version/17.0 Safari/605.1.15',
  Accept: 'application/json, text/plain, */*',
  'Accept-Language': 'en-US,en;q=0.9',
};

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
const addDays = (iso: string, n: number) => new Date(Date.parse(iso + 'T12:00:00Z') + n * 864e5).toISOString().slice(0, 10);
const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const dayName = (iso: string) => `${Number(iso.slice(8, 10))} ${MON[Number(iso.slice(5, 7)) - 1]}`;
const usd = (v: number) => `$${v.toFixed(2)}`;
const pc = (v: number) => `${Math.round(Math.abs(v) * 100)}%`;
async function nasdaq(path: string): Promise<any> {
  const r = await fetch(`https://api.nasdaq.com/api/${path}`, { headers: UA, signal: AbortSignal.timeout(10_000) });
  if (!r.ok) throw new Error(`nasdaq ${path.split('/')[1]} ${r.status}`);
  return (await r.json())?.data ?? null;
}

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
/* Realised volatility over the last n daily moves, LEAVING OUT earnings reaction
   sessions (a -15% report day otherwise sits in the 20-day number for a month and
   skips good weeks). `skip` holds each report day and the session after it, so a
   before-the-open or after-the-close report is covered either way. */
function hvEx(c: number[], days: string[], skip: Set<string>, n: number): (number | null)[] {
  return c.map((_, i) => {
    const r: number[] = [];
    for (let j = i; j > 0 && r.length < n; j--) if (!skip.has(days[j])) r.push(Math.log(c[j] / c[j - 1]));
    if (r.length < n) return null;
    const m = r.reduce((a, b) => a + b, 0) / n;
    return Math.sqrt(r.reduce((a, b) => a + (b - m) ** 2, 0) / (n - 1) * 252);
  });
}

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

/* ── fundamentals: the Nasdaq analyst target once a day; Nik's model number is
   carried from the last row that has one. Today's row is written only when
   Nasdaq answered, so a failed call retries on the next run. ── */
async function fundamentals(t: string, today: string): Promise<Row | null> {
  const have = (await get(`ticker_fundamentals?ticker=eq.${t}&order=day.desc&limit=1`))[0] ?? null;
  if (have && String(have.day) === today) return have;
  const model = (await get(`ticker_fundamentals?ticker=eq.${t}&model_value=not.is.null&select=model_value,model_day&order=day.desc&limit=1`))[0];
  try {
    const o = (await nasdaq(`analyst/${t}/targetprice`))?.consensusOverview;
    if (!o?.priceTarget) return have;
    const row: Row = { ticker: t, day: today, analyst_target: Number(o.priceTarget),
      analyst_low: o.lowPriceTarget ?? null, analyst_high: o.highPriceTarget ?? null,
      n_buy: o.buy ?? null, n_hold: o.hold ?? null, n_sell: o.sell ?? null,
      model_value: model?.model_value ?? null, model_day: model?.model_day ?? null, updated_at: new Date().toISOString() };
    await send('POST', 'ticker_fundamentals?on_conflict=ticker,day', [row], 'resolution=merge-duplicates,return=minimal');
    return row;
  } catch (_) { return have; }
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
      /* Earnings sessions left out of hv20_ex: Nasdaq's reported dates (last four
         quarters). The stored dates are the fallback only: they keep stale guesses
         (NKE has 24 Sep, 29 Sep and 1 Oct for one report) that would leave out
         ordinary days and move the number. */
      const repDates = new Set<string>();
      try {
        for (const x of (await nasdaq(`company/${t}/earnings-surprise`))?.earningsSurpriseTable?.rows ?? []) {
          const [m, d, y] = String(x.dateReported ?? '').split('/');
          if (y) repDates.add(`${y}-${m.padStart(2, '0')}-${d.padStart(2, '0')}`);
        }
      } catch (_) { /* the stored dates below still cover it */ }
      const earnRows = await get(`earnings_events?ticker=eq.${t}&select=report_date,report_time&order=report_date.asc`);
      if (!repDates.size) for (const e of earnRows) if (String(e.report_date) <= today) repDates.add(String(e.report_date));
      const skip = new Set<string>();
      days.forEach((d, i) => { if (repDates.has(d)) { skip.add(d); if (days[i + 1]) skip.add(days[i + 1]); } });
      const hx = hvEx(close, days, skip, 20);
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
          richness: r4(iv != null && h20[i] ? iv / h20[i]! : null), hv20_ex: r4(hx[i]),
          high5: r4(Math.max(...high.slice(Math.max(0, i - 4), i + 1))), updated_at: new Date().toISOString() });
      }
      await send('POST', 'ticker_technicals?on_conflict=ticker,day', rows, 'resolution=merge-duplicates,return=minimal');

      /* ── THE READS on the latest day (docs/STRATEGIES.md, NKE weekly rule) ── */
      let reads: Row | null = null;
      try {
        const n = close.length - 1, S = close[n];
        /* The Friday the Planner writes for (same as sunny-home): Monday to Friday
           the Friday after this week's, at the weekend the coming one; a holiday
           Friday moves to that week's last session. */
        const closed = new Set((await get(`market_calendar?kind=eq.closed&date=gte.${today}&date=lte.${addDays(today, 20)}&select=date`)).map((x) => String(x.date)));
        const wd = new Date(today + 'T12:00:00Z').getUTCDay();
        let exp = addDays(today, (5 - wd + 7) % 7 + (wd === 6 || wd === 0 ? 0 : 7));
        while (closed.has(exp)) exp = addDays(exp, -1);

        const fr = await fundamentals(t, today);
        const at = fr?.analyst_target != null ? Number(fr.analyst_target) : null;
        const mv = fr?.model_value != null ? Number(fr.model_value) : null;
        const value = at != null && mv != null ? (at + mv) / 2 : at ?? mv;
        const fund = value == null ? { read: 'neutral', fact: 'no analyst target yet' } : {
          read: value > S * 1.1 ? 'bullish' : value < S * 0.9 ? 'bearish' : 'neutral',
          fact: `${at != null && mv != null ? `value ${usd(value)} (analysts ${usd(at)}, model ${usd(mv)})` : mv != null ? `model ${usd(mv)}` : `analysts ${usd(value)}`}, ${pc(value / S - 1)} ${value >= S ? 'above' : 'below'} the price`,
          value: r4(value) };

        const up20 = S > e20[n]!, dn20 = S < e20[n]!, up50 = S > s50[n]!, dn50 = S < s50[n]!, r = rs[n]!;
        const tech = { read: up20 && up50 && r >= 50 && r <= 70 ? 'bullish' : dn20 && dn50 && r < 50 ? 'bearish' : 'mixed',
          fact: `${up20 && up50 ? 'above the 20 and 50-day lines' : dn20 && dn50 ? 'below the 20 and 50-day lines'
            : up20 ? 'above the 20-day line, below the 50-day' : 'below the 20-day line, above the 50-day'}, RSI ${Math.round(r)}` };

        const ivNow = ivSeries[n] ?? [...ivSeries].reverse().find((x) => x != null) ?? null;
        const yr = ivSeries.slice(Math.max(0, n - 251), n + 1).filter((x): x is number => x != null);
        const rank = ivNow != null && yr.length >= 120 && Math.max(...yr) > Math.min(...yr)
          ? (ivNow - Math.min(...yr)) / (Math.max(...yr) - Math.min(...yr)) * 100 : null;
        const rich = ivNow != null && hx[n] ? ivNow / hx[n]! : null;
        const lowRank = rank != null && rank < 25, under = rich != null && rich < 1;
        const ivR = ivNow == null ? { read: 'ok', fact: 'no IV stored yet' } : {
          read: lowRank || under ? 'skip' : rank != null && rank >= 50 && rich != null && rich >= 1.2 ? 'rich' : 'ok',
          fact: lowRank ? `IV rank ${Math.round(rank!)} is under 25` : under ? `IV ${pc(ivNow)} is below realised ${pc(hx[n]!)}`
            : `IV ${pc(ivNow)}, rank ${rank == null ? 'n/a' : Math.round(rank)}, ${rich == null ? 'n/a' : rich.toFixed(1) + 'x'} realised` };

        const m21 = close.slice(n - 21, n + 1), lo = Math.min(...m21), hi = Math.max(...m21);
        const pos = hi > lo ? (S - lo) / (hi - lo) : 0.5, w5 = S / close[n - 5] - 1, mo = S / close[n - 21] - 1;
        const hist = pos >= 0.9 && w5 >= 0.05 ? { read: 'stretched up', fact: `top of the month's range after +${pc(w5)} in 5 days` }
          : pos <= 0.1 && w5 <= -0.05 ? { read: 'stretched down', fact: `bottom of the month's range after -${pc(w5)} in 5 days` }
          : { read: mo > 0.05 ? 'up' : mo < -0.05 ? 'down' : 'flat', fact: `${mo >= 0 ? 'up' : 'down'} ${pc(mo)} in a month` };

        const rising = s200[n]! > s200[n - 21]!;
        const mom = { read: S > s200[n]! && rising ? 'bullish' : S < s200[n]! && !rising ? 'bearish' : 'mixed',
          fact: `${S > s200[n]! ? 'above' : 'below'} a ${rising ? 'rising' : 'falling'} 200-day line (${usd(s200[n]!)})` };

        const hi5 = Math.max(...high.slice(n - 4, n + 1));
        const breakout = w5 >= 0.05 ? { read: 'yes', fact: `up ${pc(w5)} in 5 days: sell above the 5-day high ${usd(hi5)}` }
          : { read: 'no', fact: `${w5 >= 0 ? 'up' : 'down'} ${pc(w5)} in 5 days` };

        /* Earnings: a report inside (today, expiry]; an after-the-close report on the
           expiry day itself lands after it. Ex-dividend: the declared date, else the
           last one plus a quarter (marked estimated). */
        const inWin = (e: Row) => String(e.report_date) > today && String(e.report_date) <= exp
          && !(String(e.report_date) === exp && e.report_time === 'amc');
        const earnIn = earnRows.find(inWin), earnNext = earnRows.find((e) => String(e.report_date) > today);
        const dv = (await get(`dividends?ticker=eq.${t}&select=ex_date,frequency&order=ex_date.desc&limit=1`))[0];
        let exd: string | null = dv ? String(dv.ex_date) : null, est = false;
        if (exd && exd <= today) {
          const step = Math.round(365 / (Number(dv.frequency) || 4));
          while (exd <= today) exd = addDays(exd, step);
          est = true;
        }
        const exTxt = exd ? `ex-dividend ${est ? 'about ' : ''}${dayName(exd)}` : null;
        const events = earnIn ? { read: 'earnings', fact: `earnings ${dayName(String(earnIn.report_date))} before the ${dayName(exp)} expiry` }
          : exd && exd > today && exd <= exp ? { read: 'ex-dividend', fact: `${exTxt} before the ${dayName(exp)} expiry` }
          : { read: 'clear', fact: `nothing before the ${dayName(exp)} expiry. ${[earnNext ? `Earnings ${dayName(String(earnNext.report_date))}` : null, exTxt].filter(Boolean).join(', ')}` };

        reads = { day: days[n], expiry: exp, price: r4(S), fundamentals: fund, technicals: tech, iv: ivR,
          history: hist, momentum: mom, events, breakout,
          inputs: { iv: r4(ivNow), iv_rank: r4(rank), hv20_ex: r4(hx[n]), rich: r4(rich), w5: r4(w5), high5: r4(hi5),
                    next_earnings: earnNext ? String(earnNext.report_date) : null, ex_div: exd, ex_div_estimated: est },
          build: BUILD };
        await send('PATCH', `ticker_technicals?ticker=eq.${t}&day=eq.${days[n]}`, { reads });
      } catch (e) {
        reads = { error: (e as Error).message };
      }

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
      out.push({ ticker: t, day: last.day, close: last.close, rsi14: last.rsi14, iv_rank: last.iv_rank, walls: walls.length,
        reads: reads?.error ? reads : Object.fromEntries(['fundamentals', 'technicals', 'iv', 'history', 'momentum', 'events', 'breakout']
          .map((k) => [k, `${(reads?.[k] as Row)?.read}: ${(reads?.[k] as Row)?.fact}`])) });
    } catch (e) {
      out.push({ ticker: t, error: (e as Error).message });
    }
  }
  return new Response(JSON.stringify({ ok: true, build: BUILD, today, out }), { headers: { 'Content-Type': 'application/json' } });
});
