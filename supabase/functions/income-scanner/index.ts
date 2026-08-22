/**
 * income-scanner — which names are ELIGIBLE for the income sleeve.
 *
 * Spec: docs/INCOME_SCANNER_SPEC.md
 *
 * A REPORT, not a recommender. It applies gates, records facts, and sorts. It
 * never proposes a trade and it emits no composite score: every attempt to
 * compress this into one number has moved the ranking by the next day.
 *
 * Runs on a cron and writes income_scanner_results. The Income screen reads the
 * last run rather than waiting on ~270 Polygon calls.
 *
 * Body (all optional): {"asof":"2026-08-17","dry_run":true,"tickers":["NKE"]}
 */
// Pinned https import, NOT ../_shared/ — the dashboard bundles only this folder
// and a sibling import fails at deploy with 'Module not found'.
import {
  corsHeaders, json, db, dailyCloses, ymd, parseISO, addDays, daysBetween,
  nyToday, sd, ncdf, d1of,
} from 'https://raw.githubusercontent.com/nikparekh123/sunny-flow-tasks/dd3c85a56102451ae439016d6a90460c4d41dab0/supabase/functions/_shared/planner.ts';

const BUILD = '2026-08-22.10';

// ── the gates, all of them, in one place ────────────────────────────────────
const G = {
  priceMin: 15, priceMax: 400,
  /* 12, and the number is Nik's: "no bizarre swings, no like 10% drop, 15% down."
     I had it at 9, which is inside his own tolerance, and it threw NFLX out at
     9.7% — a held name that had passed the run before. A threshold I invented
     rejecting a name he owns is the same mistake as the market-day gate, one
     notch smaller. */
  ownGapMax: 12,         // worst non-earnings, non-market day, %
  ret3moMax: 15,         // has it stopped falling, %
  vol60Max: 45,          // realised, annualised %
  edgeMin: 0,            // implied must beat realised
  edgeMax: 15,           // ...but a huge edge is a hidden event, not a bargain
  corrMax: 0.40,         // to anything already held
  pos52Max: 45,          // near the low, not the high
  /* Liquidity is measured across the STRIKES AROUND THE MONEY, not on the one
     nearest strike. A single strike's open interest is noise: the first dry run
     put NKE at 38 and LULU at 128, which would read as illiquid on two of the
     most heavily traded names in the market. Open interest concentrates on round
     strikes, so whichever one happens to sit nearest spot says nothing about
     whether there is a market to trade in.

     Deliberately loose to begin with. These are placeholders until a full run
     shows the distribution, and setting them from a guess is how the gap gate
     came to exclude the two names Nik holds. */
  oiBandPct: 5,          // ±% of spot that counts as "around the money"
  /* A FLOOR, NOT A BAR. Nik: "128 is not bad unless you see one or two then
     reject." The gate's job is to catch a name with no weekly market at all, and
     nothing beyond that. Judging how GOOD the market is would be a quality score
     smuggled in through a filter, which is the thing this whole screen refuses to
     do — it reports and Nik picks.

     50 across the band, both legs, is the level below which there is genuinely
     nothing to trade against. Anything above it passes and the actual figure is
     reported so he can see thin from deep himself.

     Volume is NOT gated at all. A quiet name with real open interest and no
     trades today is perfectly tradeable, and a scan running before the open sees
     zero volume on everything. */
  oiMin: 50,             // open interest across the band, both legs
  calmVol: 32,           // below this the name is 'calm', at or above it 'jumpy'
  /* At least this many distinct expiries in the next five weeks. A weekly name
     has four or five; a monthly name has one. The whole cadence is weekly, so a
     monthly-only name cannot run this strategy at all. */
  weekliesMin: 3,
};

/* MARKET DAYS. A day when more than this fraction of the universe moved more
   than 5% is the market moving, not the stock, and it must be removed before any
   per-stock statistic is computed.

   This gate exists because its absence quietly poisoned every other one. The
   first version excluded NKE, LULU, ORCL and AAL, and every one of their "gappy"
   days fell in the April 2025 macro week — when 79% of the universe moved more
   than 5% on a single session. NKE's worst own day drops from 16.9% to 5.0% once
   those are taken out, and the candidate list went from two names to nine.

   A universe fraction rather than an index return: no benchmark to fetch, and it
   scales with whatever list is being scanned. */
const MARKET_REF = 'SPY';
/* |SPY| daily move that makes a session THE MARKET rather than the stock.
   Tunable; the run reports how many days it finds so it can be calibrated. */
const MARKET_REF_MOVE = 2.0;
const MARKET_DAY_SHARE = 0.25;   // retained for the legacy path only
const MARKET_DAY_MOVE = 5;

const POLY = 'https://api.polygon.io';

function realisedVol(cl: number[], n: number): number | null {
  if (cl.length < n + 2) return null;
  const w = cl.slice(-(n + 1)); const lr: number[] = [];
  for (let i = 0; i < w.length - 1; i++) lr.push(Math.log(w[i + 1] / w[i]));
  return sd(lr) * Math.sqrt(252);
}

function impliedVol(price: number, S: number, K: number, T: number): number | null {
  if (!(price > 0) || !(S > 0) || !(K > 0) || T <= 0) return null;
  const val = (v: number) => {
    const a = d1of(S, K, T, v), b = a - v * Math.sqrt(T);
    const c = S * ncdf(a) - K * Math.exp(-0.045 * T) * ncdf(b);
    return c - S + K * Math.exp(-0.045 * T);          // put, via parity
  };
  let lo = 0.02, hi = 5.0;
  if (val(hi) < price) return null;
  for (let i = 0; i < 80; i++) { const m = (lo + hi) / 2; if (val(m) > price) hi = m; else lo = m; }
  return (lo + hi) / 2;
}

function corr(a: number[], b: number[]): number {
  const n = Math.min(a.length, b.length); if (n < 30) return 0;
  const x = a.slice(-n), y = b.slice(-n);
  const mx = x.reduce((s, v) => s + v, 0) / n, my = y.reduce((s, v) => s + v, 0) / n;
  let cov = 0, vx = 0, vy = 0;
  for (let i = 0; i < n; i++) { cov += (x[i] - mx) * (y[i] - my); vx += (x[i] - mx) ** 2; vy += (y[i] - my) ** 2; }
  return (vx && vy) ? cov / Math.sqrt(vx * vy) : 0;
}

/* WEEKLIES: how many distinct expiries exist over the next five weeks.
   A weekly name has four or five; a monthly name has one.

   This gate was in the spec from the start and was never actually implemented.
   The scanner only ever asked for the coming Friday, and 21 Aug 2026 happens to
   be the THIRD Friday — the monthly expiry — so every optionable name in the
   country has contracts that day. ZTS passed with 11,252 open interest and a
   4.23% straddle while having no weekly market at all: 17 strikes on 21 Aug and
   zero on 28 Aug, 4 Sep and 11 Sep.

   It would have waved monthly-only names through one week in four, and only in
   the other three weeks would anything have looked wrong.

   A deliberately tight strike band, because this call only counts dates. */
async function weeklyCount(ticker: string, from: string, to: string,
                           spot: number, key: string): Promise<number> {
  try {
    const u = new URL(`${POLY}/v3/snapshot/options/${ticker}`);
    u.searchParams.set('expiration_date.gte', from);
    u.searchParams.set('expiration_date.lte', to);
    u.searchParams.set('strike_price.gte', String(Math.floor(spot * 0.98)));
    u.searchParams.set('strike_price.lte', String(Math.ceil(spot * 1.02)));
    u.searchParams.set('contract_type', 'put');
    u.searchParams.set('limit', '250');
    u.searchParams.set('apiKey', key);
    const r = await fetch(u.toString());
    if (!r.ok) return -1;                       // unknown, not zero
    const j = await r.json();
    const days = new Set<string>();
    for (const c of (j?.results ?? [])) {
      const e = c.details?.expiration_date;
      if (e) days.add(String(e));
    }
    return days.size;
  } catch { return -1; }
}

/** The next Friday on the calendar. Not necessarily the one to price. */
function comingFriday(from: Date): string {
  const d = new Date(from.getTime());
  do { d.setUTCDate(d.getUTCDate() + 1); } while (d.getUTCDay() !== 5);
  return ymd(d);
}

/* The expiry the sleeve ACTUALLY writes, which always carries about a week.
   ─────────────────────────────────────────────────────────────────────────
   This used to price comingFriday() outright, so the scan measured a 5-day
   option on Monday and a ONE-day option on Thursday. Implied vol is the
   straddle price over the square root of time, and as time goes to zero that
   division amplifies every cent of spread into whole volatility points.

   The same book, three consecutive days, straddle price barely moving:

       MCD    1.83  1.54  1.36 % of spot     IV  25   21   36
       KMB    2.12  3.11  2.41               IV  33   34   78
       CPB    2.73  2.71  2.77               IV  35   41   17

   Not even a consistent inflation: KMB doubled while CPB halved, because at
   one day the error simply leans whichever way the quote happens to sit. The
   clear list fell from 10 names to 3 overnight on an unchanged book.

   Nik writes on Friday for the FOLLOWING Friday, so the contract he sells has
   roughly seven days in it and never one. Skipping to the next Friday inside
   five days prices the option he actually trades, and makes the reading mean
   the same thing on a Monday as on a Thursday. */
function writeFriday(from: Date): string {
  const f = parseISO(comingFriday(from));
  return ymd(daysBetween(from, f) < 5 ? addDays(f, 7) : f);
}

/** Every listed contract at one expiry, WITH open interest and volume. The
 *  option-chain function drops both; the liquidity gate is the one that cannot
 *  be faked, so this reads the snapshot directly rather than proxying it. */
async function snapshot(ticker: string, expiry: string, key: string, spot: number, tries = 3) {
  /* NARROWED BY STRIKE, the way option-chain does it. Asking for every strike at
     an expiry and capping at 250 was the bug behind LULU: the results come back
     from the lowest strike up, so on a name with hundreds of listings the 250
     returned are all far out of the money and nothing near the money is in them.
     The response is also large enough to fail outright, which is what LULU did
     twice, reading as "no market" when the market is plainly there — the sleeve
     prices the same expiry at a 4.62 straddle. */
  const u = new URL(`${POLY}/v3/snapshot/options/${ticker}`);
  u.searchParams.set('expiration_date', expiry);
  u.searchParams.set('strike_price.gte', String(Math.floor(spot * 0.88)));
  u.searchParams.set('strike_price.lte', String(Math.ceil(spot * 1.12)));
  u.searchParams.set('limit', '250');
  u.searchParams.set('apiKey', key);
  /* THE FETCH THROWS, IT DOES NOT RETURN A BAD STATUS.
     LULU failed four runs running while 124 of 143 names succeeded, and the real
     message was finally visible on build .4:

       error sending request from 10.32.181.208:59522 for api.polygon.io/v3/...

     That is a connection failure, not an HTTP error. Both my retry and my
     fallback tested `!r.ok`, and a fetch that throws never reaches that test, so
     neither had ever run. Three builds spent fixing the wrong thing because the
     guard was in the wrong place.

     It is not about LULU either. 143 names opening connections in parallel
     exhausts something and one of them loses; LULU is simply where it lands. So:
     catch the throw, back off, and try again. */
  const attempt = async (url: string) => {
    try { return await fetch(url); } catch { return null; }
  };
  let r = await attempt(u.toString());
  for (let i = 1; i < tries && (!r || !r.ok); i++) {
    await new Promise((res) => setTimeout(res, 300 * i));
    r = await attempt(u.toString());
  }
  /* Then the date-range form, which is what option-chain uses and what prices
     LULU's chain without trouble. Kept as a second line of defence now that the
     connection failure above is handled. */
  if (!r || !r.ok) {
    const v = new URL(u.toString());
    v.searchParams.delete('expiration_date');
    v.searchParams.set('expiration_date.gte', expiry);
    v.searchParams.set('expiration_date.lte', expiry);
    await new Promise((res) => setTimeout(res, 300));
    r = await attempt(v.toString());
  }
  if (!r) throw new Error(`no connection for ${ticker} ${expiry}`);
  if (!r.ok) throw new Error(`snapshot ${r.status} for ${ticker} ${expiry}`);
  const j = await r.json();
  return (j?.results ?? []).map((c: Record<string, any>) => ({
    strike: c.details?.strike_price,
    type: c.details?.contract_type,
    mid: (c.last_quote?.bid > 0 && c.last_quote?.ask > 0)
      ? (c.last_quote.bid + c.last_quote.ask) / 2
      : (c.day?.close ?? 0),
    oi: c.open_interest ?? 0,
    vol: c.day?.volume ?? 0,
  })).filter((c: Record<string, any>) => c.strike > 0);
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  try {
    const url = Deno.env.get('SUPABASE_URL')!;
    const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const polyKey = Deno.env.get('POLYGON_API_KEY')!;
    if (!polyKey) return json(500, { ok: false, error: 'POLYGON_API_KEY is not set' });

    let body: { asof?: string; dry_run?: boolean; tickers?: string[]; explain?: string[];
                store_history?: boolean; suggest_universe?: number; probe?: boolean } = {};
    try { if (req.method === 'POST') body = await req.json(); } catch { /* no body is normal */ }
    const today = parseISO(body.asof ?? nyToday());
    const todayISO = ymd(today);
    const expiry = writeFriday(today);
    const D = db(url, key);

    /* Does this Polygon plan carry earnings dates? 455 of 596 names fail for
       want of one, and the table is hand-maintained, so this is the ceiling on
       the whole universe. Ask rather than assume. */
    if (body.probe) {
      const tries: Record<string, string> = {
        financials: `${POLY}/vX/reference/financials?ticker=AAPL&limit=2&apiKey=${polyKey}`,
        benzinga_earnings: `${POLY}/benzinga/v1/earnings?ticker=AAPL&limit=2&apiKey=${polyKey}`,
        bz_by_date: `${POLY}/benzinga/v1/earnings?date.gte=2026-08-24&date.lte=2026-09-30`
          + `&limit=5&order=asc&sort=date&apiKey=${polyKey}`,
        bz_multi: `${POLY}/benzinga/v1/earnings?ticker.any_of=NKE,BABA,PG&date.gte=2026-08-01`
          + `&limit=5&apiKey=${polyKey}`,
        benzinga_consensus: `${POLY}/benzinga/v1/consensus-ratings?ticker=AAPL&limit=1&apiKey=${polyKey}`,
        dividends_control: `${POLY}/v3/reference/dividends?ticker=AAPL&limit=1&apiKey=${polyKey}`,
        ticker_details: `${POLY}/v3/reference/ticker-details/AAPL?apiKey=${polyKey}`,
      };
      const out: Record<string, unknown> = {};
      for (const [k, u] of Object.entries(tries)) {
        try {
          const r = await fetch(u);
          const t = await r.text();
          out[k] = { status: r.status, body: t.slice(0, 260) };
        } catch (e) { out[k] = { status: 'threw', body: String(e).slice(0, 160) }; }
      }
      return json(200, { ok: true, build: BUILD, probe: out });
    }

    /* Build a universe from what actually trades, not from index membership.
       ─────────────────────────────────────────────────────────────────────
       Nik asked for the S&P 500 and the Nasdaq 100. Constituent lists are
       licensed data and reconstructing them from memory is how SPCX, FIG and
       META got in and produced confident nonsense.

       Dollar volume is the better proxy anyway: this strategy needs a liquid
       WEEKLY OPTIONS market, and index membership does not guarantee one while
       heavy share turnover very nearly does. One grouped-bars call returns
       every US stock for a session, so the ranking costs a single request.

       Returns a suggestion and writes NOTHING. The universe stays Nik's. */
    if (body.suggest_universe) {
      const day = ymd(addDays(today, 1));
      let bar: Record<string, unknown>[] = [];
      for (let back = 1; back <= 6 && !bar.length; back++) {
        const d = ymd(addDays(today, -back));
        try {
          const r = await fetch(`${POLY}/v2/aggs/grouped/locale/us/market/stocks/${d}`
            + `?adjusted=true&apiKey=${polyKey}`);
          if (r.ok) {
            const j = await r.json();
            if ((j?.results ?? []).length) bar = j.results;
          }
        } catch { /* try the day before */ }
      }
      if (!bar.length) return json(502, { ok: false, error: 'no grouped bars from Polygon' });
      /* COMMON STOCK ONLY. Ranking raw dollar volume put IWM, SOXL, TQQQ,
         IBIT, GDX, HYG and LQD in the top 25: index ETFs, a leveraged
         semiconductor fund and two bond funds. A leveraged ETF cannot run this
         strategy at all, and TLT already has its own book with its own rule.
         Polygon classifies them, so ask rather than guess from the symbol. */
      const cs = new Set<string>();
      let next: string | null = `${POLY}/v3/reference/tickers?market=stocks&type=CS`
        + `&active=true&limit=1000&apiKey=${polyKey}`;
      for (let page = 0; page < 8 && next; page++) {
        try {
          const r: Response = await fetch(next);
          if (!r.ok) break;
          const j = await r.json();
          for (const x of (j?.results ?? [])) cs.add(String(x.ticker));
          next = j?.next_url ? `${j.next_url}&apiKey=${polyKey}` : null;
        } catch { break; }
      }

      const have = new Set((await D.get('income_scanner_universe?select=ticker'))
        .map((r) => String(r.ticker)));
      const ranked = bar
        .map((b) => ({
          ticker: String((b as { T: string }).T ?? ''),
          close: Number((b as { c: number }).c ?? 0),
          vol: Number((b as { v: number }).v ?? 0),
        }))
        // The price gate, applied up front: no point ranking what cannot pass.
        .filter((x) => x.ticker && !x.ticker.includes('.') && !x.ticker.includes(':')
          && (cs.size === 0 || cs.has(x.ticker))
          && x.close >= G.priceMin && x.close <= G.priceMax && x.vol > 0)
        .map((x) => ({ ...x, dollars: x.close * x.vol }))
        .sort((a, b) => b.dollars - a.dollars);
      const take = ranked.slice(0, body.suggest_universe);
      return json(200, {
        ok: true, build: BUILD, day,
        scanned: bar.length,
        common_stocks_known: cs.size,
        in_band: ranked.length,
        already_have: take.filter((x) => have.has(x.ticker)).length,
        suggest: take.map((x) => ({
          t: x.ticker,
          px: Math.round(x.close * 100) / 100,
          usd_m: Math.round(x.dollars / 1e6),
          new: !have.has(x.ticker),
        })),
      });
    }

    /* Settings and earnings come from the SAME rows the sleeve reads.
       ─────────────────────────────────────────────────────────────────────
       The edge floor and ceiling used to be hardcoded here at 0 and 15 while
       income_sleeve_settings held 3 and 15. So CPB at edge +1.3 passed the
       scanner ("clear to add") and failed the book ("under the floor") on the
       same screen, same second, same word. Nik: "why two different answers,
       when can I actually trust the app".

       A rule written in two places drifts by construction. Changing
       edge_floor in settings moved half the screen. Now there is one number
       in one row and both cards read it. */
    const [uniRows, persRows, heldRows, setRows, earnRows] = await Promise.all([
      D.get('income_scanner_universe?active=is.true&select=ticker,conviction'),
      D.get('scanner_persistence?select=ticker,persistence,measured&limit=2000'),
      D.get('income_sleeve_names?active=is.true&select=ticker'),
      D.get('income_sleeve_settings?id=eq.1&select=edge_floor,edge_ceiling'),
      D.get(`earnings_events?report_date=gte.${todayISO}`
            + `&select=ticker,report_date,report_time&order=report_date.asc`),
    ]);
    /* Persistence comes from SQL over scanner_closes, not from the bars held
       here. Computing it in-memory tied its measurement window to the fetch
       window, so cutting the fetch from 600 days to 420 quietly cut the
       measurement from ~158 sessions to ~30 and PEP read 100% where it had read
       29.4% that morning. `measured` under ~60 is noise, so it scores zero. */
    const persist = new Map<string, { p: number; n: number }>(
      persRows.map((r) => [String(r.ticker),
        { p: Number(r.persistence ?? 0), n: Number(r.measured ?? 0) }]));

    const cfg = setRows[0] ?? {};
    const edgeFloor = Number(cfg.edge_floor ?? G.edgeMin);
    const edgeCeiling = Number(cfg.edge_ceiling ?? G.edgeMax);

    /* The earnings blackout, which this spec has described since the first
       draft and which was never implemented. It runs a week PAST the expiry,
       not to it: an assigned put hands you the shares the Monday after, so
       the exposure is what the option TURNS INTO, not the option itself.
       PDD reporting Mon 24 Aug against a Fri 21 Aug expiry is clear on the
       option and holds you into the print. */
    const blackoutEnd = ymd(addDays(parseISO(expiry), 7));

    /* A print dated TODAY may already be behind you. earnings_events stores a
       date and no time, so BABA was blocked on 20 Aug by a report it had
       delivered before that morning's open, at an edge of +9.3, the best on
       the board. report_time settles it: 'bmo' clears once 09:30 ET has
       passed, 'amc' blocks the whole day, and NULL is treated as amc so not
       knowing never releases a name early. */
    const nyNow = new Intl.DateTimeFormat('en-US', {
      timeZone: 'America/New_York', hour: '2-digit', minute: '2-digit', hour12: false,
    }).formatToParts(new Date());
    const nyMins = Number(nyNow.find((p) => p.type === 'hour')?.value ?? '0') * 60
                 + Number(nyNow.find((p) => p.type === 'minute')?.value ?? '0');
    const afterOpen = nyMins >= (9 * 60 + 30);

    const earnBy = new Map<string, { d: string; done: boolean }>();
    for (const e of earnRows) {
      const tk = String(e.ticker);
      if (earnBy.has(tk)) continue;
      const d = String(e.report_date).slice(0, 10);
      // Already delivered: dated today, before the open, and the open has passed.
      const done = d === todayISO && String(e.report_time ?? 'amc') === 'bmo' && afterOpen;
      earnBy.set(tk, { d, done });
    }
    const held = heldRows.map((r) => String(r.ticker));
    const universe = (body.tickers ?? uniRows.map((r) => String(r.ticker)));
    // NULL reads as 5, neutral: an unrated name is neither rewarded nor punished.
    const conviction = new Map<string, number>(
      uniRows.map((r) => [String(r.ticker), r.conviction == null ? 5 : Number(r.conviction)]));
    if (!universe.length) return json(200, { ok: true, empty: true, note: 'universe is empty' });

    // ── prices for everything, including the held names for correlation ──────
    // SPY is fetched but never scanned: it is the market-day reference.
    const need = Array.from(new Set([...universe, ...held, MARKET_REF]));
    const bars: Record<string, { d: string; c: number }[]> = {};
    /* 8, not 12. The connection failures above are a concurrency problem, and
       widening the retry without narrowing the fan-out treats the symptom. The
       scan runs on a cron; a slower pass costs nothing. */
    const CHUNK = 8;
    for (let i = 0; i < need.length; i += CHUNK) {
      const part = need.slice(i, i + CHUNK);
      await Promise.all(part.map(async (t) => {
        try {
          /* 600 days, not 430. The metrics only need 252 trading days, but the
             MARKET-DAY detector needs to see the macro weeks, and at 430 the
             first run started on 13 Jun 2025 — after April 2025 entirely. It
             found 6 market days where a longer window finds 15, so NKE came back
             with a 15.2% "own gap" that is a macro session, which is the exact
             failure this gate exists to prevent. */
          /* 600 days for SPY, ~420 for everything else.
             ────────────────────────────────────────────────────────────────
             The 600-day window existed for ONE reason: the market-day detector
             needed to see the April 2025 macro weeks across the whole universe,
             and at 430 days the window started after them entirely. That
             detector now reads SPY alone, so only SPY needs the long history.

             Individual names need 252 sessions for the 52-week range and about
             the same again to measure persistence. 420 covers both. At 596
             names the difference is ~100,000 bar objects, and the run was dying
             with WORKER_RESOURCE_LIMIT holding history nothing was reading. */
          const days = t === MARKET_REF ? 600 : 420;
          bars[t] = await dailyCloses(t, polyKey, ymd(addDays(today, -days)), todayISO);
        } catch { bars[t] = []; }
      }));
    }

    /* Keep the history instead of discarding it. The 600-day pull above is
       already paid for; writing it costs one round trip and answers every
       question that needs a past, which none of them could before.

       Normal runs store the last 10 sessions, which is all that can be new.
       {"store_history":true} writes the whole 600 days, for the initial
       backfill or after a gap. Failure is non-fatal: this is research data and
       must never cost a scan. */
    let stored = 0, storeErr: string | null = null;
    if (!body.dry_run) {
      /* STREAMED, not accumulated. Building the whole set first meant 596
         names x 600 sessions = 357,000 objects alive at once, and the worker
         died with WORKER_RESOURCE_LIMIT. Flush as we go and the peak is one
         batch. */
      const keep = body.store_history ? 10_000 : 10;
      let buf: Array<{ ticker: string; date: string; close: number }> = [];
      const flush = async () => {
        if (!buf.length) return;
        const n = buf.length;
        try {
          const r = await fetch(`${url}/rest/v1/scanner_closes?on_conflict=ticker,date`, {
            method: 'POST',
            headers: {
              apikey: key, Authorization: `Bearer ${key}`,
              'Content-Type': 'application/json',
              Prefer: 'resolution=merge-duplicates,return=minimal',
            },
            body: JSON.stringify(buf),
          });
          if (r.ok) stored += n;
          else if (!storeErr) storeErr = `${r.status} ${(await r.text()).slice(0, 160)}`;
        } catch (e) { if (!storeErr) storeErr = String(e).slice(0, 160); }
        buf = [];
      };
      for (const [t, arr] of Object.entries(bars)) {
        for (const b of (arr ?? []).slice(-keep)) {
          if (!Number.isFinite(b.c)) continue;
          buf.push({ ticker: t, date: b.d, close: b.c });
          if (buf.length >= 2000) await flush();
        }
      }
      await flush();
    }

    const rets = (t: string) => {
      const c = (bars[t] ?? []).map((x) => x.c); const out: number[] = [];
      for (let i = 0; i < c.length - 1; i++) out.push(Math.log(c[i + 1] / c[i]));
      return out;
    };

    /* ── FIND THE MARKET DAYS, before any per-stock number is computed ────── */
    const moves: Record<string, number[]> = {};
    for (const t of universe) {
      const b = bars[t] ?? []; if (b.length < 200) continue;
      for (let i = 1; i < b.length; i++) {
        (moves[b[i].d] ??= []).push(Math.abs(100 * (b[i].c / b[i - 1].c - 1)));
      }
    }
    /* Market-day detection needs the WHOLE universe. On a six-name dry run no day
       reaches the 60-sample floor, so none are found and every stock's macro days
       count against it: NKE came back with a 15.2% "own gap" that is really the
       April 2025 week. The response reports market_days so a zero is visible
       rather than assumed. */
    /* ⚠ A FIXED REFERENCE, NOT A FRACTION OF THE UNIVERSE.
       ────────────────────────────────────────────────────────────────────────
       This used to call a session a market day when more than 25% of the names
       being scanned moved more than 5%. That reads as universe-independent and
       is the opposite: it measures the list, not the market.

       Growing the universe from 144 names to 596 by adding the S&P 500 cut
       detected market days from 13 to 5, because the index is far calmer than
       the original hand-picked list, so macro sessions stopped clearing the
       threshold. Nothing about April 2025 changed. What changed was who was
       standing next to NKE when its worst day was judged.

       That makes own_gap incomparable between runs, which is precisely the
       failure this gate exists to prevent. SPY's own move is the market's move
       whoever else is in the room. */
    const marketDays = new Set<string>();
    {
      const ref = bars[MARKET_REF] ?? [];
      for (let i = 1; i < ref.length; i++) {
        if (Math.abs(100 * (ref[i].c / ref[i - 1].c - 1)) >= MARKET_REF_MOVE) {
          marketDays.add(ref[i].d);
        }
      }
    }

    // ── the scan ────────────────────────────────────────────────────────────
    const heldRets = Object.fromEntries(held.map((h) => [h, rets(h)]));
    const T = Math.max(daysBetween(today, parseISO(expiry)), 1) / 365;
    const out: Record<string, any>[] = [];

    for (let i = 0; i < universe.length; i += CHUNK) {
      const part = universe.slice(i, i + CHUNK);
      const done = await Promise.all(part.map(async (t) => {
        const b = bars[t] ?? [];
        const fails: string[] = [];
        if (b.length < 260) return { ticker: t, asof: todayISO, passes: false, fails: ['too little history'] };

        const cl = b.map((x) => x.c); const lr = rets(t); const spot = cl[cl.length - 1];

        /* SANITY, before anything is scored. Of ~50 names screened on 2026-08-14,
           three had unusable history from ticker reuse and every one produced
           confident nonsense. */
        if (lr.some((x) => Math.abs(x) > Math.log(1.45))) {
          return { ticker: t, asof: todayISO, spot, passes: false, fails: ['a single day over 45%'] };
        }

        // earnings days: this stock's own outliers, whatever the market did
        const ev = new Set<number>();
        for (let k = 25; k < lr.length; k++) {
          const w = lr.slice(k - 22, k - 2);
          const s = sd(w) || 1e-9;
          if (Math.abs(lr[k]) > 3 * s && Math.abs(lr[k]) > 0.05) ev.add(k);
        }
        // the worst day that is the STOCK's own: not a print, not the market
        let ownGap = 0, ownGapOn: string | null = null;
        for (let k = 0; k < lr.length; k++) {
          if (ev.has(k) || marketDays.has(b[k + 1].d)) continue;
          const m = Math.abs(Math.exp(lr[k]) - 1) * 100;
          if (m > ownGap) { ownGap = m; ownGapOn = b[k + 1].d; }
        }

        const yr = cl.slice(-252);
        const lo = Math.min(...yr), hi = Math.max(...yr);
        const pos52 = hi > lo ? 100 * (spot - lo) / (hi - lo) : 50;
        const r12 = 100 * (spot / cl[cl.length - 252] - 1);
        const r3 = 100 * (spot / cl[cl.length - 60] - 1);
        const v60 = 100 * (realisedVol(cl, 60) ?? 0);
        const v20 = 100 * (realisedVol(cl, 20) ?? 0);
        const mx = held.length
          ? Math.max(...held.filter((h) => h !== t)
              .map((h) => Math.abs(corr(lr.slice(-250), (heldRets[h] ?? []).slice(-250)))))
          : 0;

        // ── the option side, read straight from the snapshot ────────────────
        let straddlePct: number | null = null, iv: number | null = null;
        let oi = 0, vol = 0;
        const weeks = await weeklyCount(t, todayISO, ymd(addDays(today, 35)), spot, polyKey);
        if (weeks === 0) fails.push('no options at all');
        else if (weeks > 0 && weeks < G.weekliesMin) {
          fails.push(`monthly only: ${weeks} expiry in the next 5 weeks`);
        }
        try {
          const chain = await snapshot(t, expiry, polyKey, spot);
          const puts = chain.filter((c: any) => c.type === 'put' && c.mid > 0);
          const calls = chain.filter((c: any) => c.type === 'call' && c.mid > 0);
          if (puts.length && calls.length) {
            const near = (xs: any[]) => xs.reduce((a, x) =>
              Math.abs(a.strike - spot) <= Math.abs(x.strike - spot) ? a : x);
            const p = near(puts), c = near(calls);
            straddlePct = 100 * (p.mid + c.mid) / spot;
            iv = impliedVol(p.mid, spot, p.strike, T);
            const lo = spot * (1 - G.oiBandPct / 100), hi = spot * (1 + G.oiBandPct / 100);
            const band = chain.filter((x: any) => x.strike >= lo && x.strike <= hi);
            oi = band.reduce((s: number, x: any) => s + (x.oi ?? 0), 0);
            vol = band.reduce((s: number, x: any) => s + (x.vol ?? 0), 0);
          } else fails.push('no weekly option at this expiry');
        } catch (e) {
          // The real message, not a generic one. "option snapshot failed" sent me
          // hunting a rate limit for three runs when the cause was the query.
          fails.push(`option snapshot: ${String((e as Error)?.message ?? e).slice(0, 90)}`);
        }

        const edge = (iv != null) ? 100 * iv - v20 : null;

        // ── gates ──────────────────────────────────────────────────────────
        if (spot < G.priceMin || spot > G.priceMax) fails.push(`price $${spot.toFixed(2)}`);
        if (ownGap >= G.ownGapMax) fails.push(`own gap ${ownGap.toFixed(1)}%`);
        if (Math.abs(r3) >= G.ret3moMax) fails.push(`still moving, ${r3.toFixed(0)}% in 3mo`);
        if (v60 >= G.vol60Max) fails.push(`vol ${v60.toFixed(0)}%`);
        if (pos52 >= G.pos52Max) fails.push(`${pos52.toFixed(0)}% up its range`);
        if (mx >= G.corrMax) fails.push(`correlates ${mx.toFixed(2)} to a held name`);
        if (edge == null) fails.push('no edge reading');
        else if (edge < edgeFloor) fails.push(`edge ${edge.toFixed(1)}, under the floor`);
        else if (edge > edgeCeiling) fails.push(`edge ${edge.toFixed(1)}, an event is priced`);
        if (oi < G.oiMin) fails.push(`no market: ${oi} open interest around the money`);
        // A name with no date on file is SKIPPED, not passed: a guard that
        // cannot fire looks exactly like a guard with nothing to catch.
        const rep = earnBy.get(t);
        if (!rep) fails.push('no earnings date on file');
        else if (!rep.done && rep.d <= blackoutEnd) {
          fails.push(`reports ${rep.d}, inside the blackout`);
        }

        // Thin evidence scores zero rather than flattering the name.
        const pr = persist.get(t);
        const pers = (pr && pr.n >= 60) ? pr.p : null;

        return {
          ticker: t, asof: todayISO, spot: Math.round(spot * 100) / 100,
          ret_12mo: Math.round(r12 * 10) / 10, ret_3mo: Math.round(r3 * 10) / 10,
          vol_60d: Math.round(v60), vol_20d: Math.round(v20),
          pos_52w: Math.round(pos52),
          own_gap: Math.round(ownGap * 10) / 10, own_gap_on: ownGapOn,
          atm_straddle_pct: straddlePct != null ? Math.round(straddlePct * 100) / 100 : null,
          implied_vol: iv != null ? Math.round(iv * 100) : null,
          edge: edge != null ? Math.round(edge * 10) / 10 : null,
          option_oi: oi, option_volume: vol,
          weeklies: weeks,
          persistence: pers,
          score: (() => {
            /* BANDED, not linear. A linear edge component scored INTU 74/100
               while it failed four gates, because +35 of edge and a 9.76%
               straddle were both the print three days away. Zero above the
               ceiling, or the score rewards what the ceiling rejects. */
            const band = edge == null ? 0
              : (edge <= 0 || edge >= G.edgeMax) ? 0
              : edge < 4 ? edge / 4
              : edge <= 10 ? 1
              : (G.edgeMax - edge) / 5;
            const cl = (x: number) => Math.max(0, Math.min(1, x));
            const parts =
                band                                    * 25
              + cl((pers ?? 0) / 60)                    * 25   // 60%+ of days is full marks
              + cl(((straddlePct ?? 0) - 1) / 5)        * 15   // 1%/wk -> 0, 6%/wk -> full
              + (conviction.get(t) ?? 5) / 10           * 15
              + cl((60 - pos52) / 60)                   * 10
              + cl(1 - Math.abs(r3) / 25)               * 10;
            return Math.round(parts * 10) / 10;
          })(),
          // Reported, never gated. Thin is a fact about the name, not a verdict.
          liquidity: oi >= 5000 ? 'deep' : oi >= 800 ? 'fine' : 'thin',
          max_correlation: Math.round(mx * 100) / 100,
          /* CALM or JUMPY, and it measures exactly one thing: 60-day realised
             volatility against calmVol. It is not a gate and it says nothing
             about the company.

             It used to read 'quiet' or 'broken'. Broken was coined when the
             sleeve held NKE, LULU and NFLX, which genuinely had fallen hard
             and then settled. Run across 143 names it started labelling
             anything merely volatile as broken: CCL is down 7% over the year
             and firming, and still read BROKEN purely because it realises 42%.
             That is a verdict the scanner is not entitled to make. */
          bucket: v60 < G.calmVol ? 'calm' : 'jumpy',
          passes: fails.length === 0,
          fails,
        };
      }));
      out.push(...done);
    }

    /* The shared db() exposes upsert(table, rows, onConflict), not a raw post.
       The write is deliberately non-fatal there: a failed cache write must not
       fail the run, and the response below carries the full result either way. */
    /* The write is done HERE rather than through D.upsert, for one reason: the
       shared helper only catches THROWN errors —

           try { await fetch(...) } catch { }

       — and a PostgREST 400 is a perfectly good Response, so it falls straight
       through. The table was created before the weeklies gate and the liquidity
       word existed, so every write since has been "column weeklies does not
       exist", discarded in silence. The run kept reporting "passed: 12" while
       storing nothing, income-sleeve read an empty table, emitted scanner:null,
       and the card never appeared on the screen.

       Still non-fatal — a failed cache write must not lose a 90-second scan —
       but the reason now travels back in the response. */
    /* One shape for every row, or PostgREST rejects the whole batch with
       PGRST102 "All object keys must match". A bulk insert is a single
       statement, so it needs one column list: the two early exits above
       (too little history, a single day over 45%) return four and five keys
       while a scored name returns twenty-one, and that alone was enough to
       throw away all 143 rows. Missing keys become null rather than absent. */
    const COLS = [
      'ticker', 'asof', 'spot', 'ret_12mo', 'ret_3mo', 'vol_60d', 'vol_20d',
      'pos_52w', 'own_gap', 'own_gap_on', 'atm_straddle_pct', 'implied_vol',
      'edge', 'option_oi', 'option_volume', 'weeklies', 'liquidity', 'persistence', 'score',
      'max_correlation', 'bucket', 'passes', 'fails',
    ] as const;
    const shaped = out.map((r) => {
      const o: Record<string, unknown> = {};
      for (const c of COLS) o[c] = (r as Record<string, unknown>)[c] ?? null;
      o.passes = (r as Record<string, unknown>).passes === true;
      return o;
    });

    let cacheError: string | null = null;
    if (!body.dry_run) {
      for (let i = 0; i < shaped.length; i += 50) {
        try {
          const r = await fetch(`${url}/rest/v1/income_scanner_results?on_conflict=ticker,asof`, {
            method: 'POST',
            headers: {
              apikey: key,
              Authorization: `Bearer ${key}`,
              'Content-Type': 'application/json',
              Prefer: 'resolution=merge-duplicates,return=minimal',
            },
            body: JSON.stringify(shaped.slice(i, i + 50)),
          });
          if (!r.ok && !cacheError) cacheError = `${r.status} ${(await r.text()).slice(0, 200)}`;
        } catch (e) {
          if (!cacheError) cacheError = String(e).slice(0, 200);
        }
      }
    }

    /* The option market's trend, from figures already in hand. The liquidity
       GATE reads today's number; this is so a draining market becomes visible
       before the spreads make it obvious. One row per name per scan date. */
    let optRows = 0;
    if (!body.dry_run) {
      const oh = out
        .filter((r) => (r as Record<string, unknown>).option_oi != null)
        .map((r) => {
          const x = r as Record<string, unknown>;
          return {
            ticker: x.ticker, asof: todayISO, expiry,
            spot: x.spot ?? null, option_oi: x.option_oi ?? null,
            option_vol: x.option_volume ?? null,
            straddle_pct: x.atm_straddle_pct ?? null,
            implied_vol: x.implied_vol ?? null,
          };
        });
      for (let i = 0; i < oh.length; i += 200) {
        try {
          const r = await fetch(`${url}/rest/v1/scanner_option_history?on_conflict=ticker,asof`, {
            method: 'POST',
            headers: {
              apikey: key, Authorization: `Bearer ${key}`,
              'Content-Type': 'application/json',
              Prefer: 'resolution=merge-duplicates,return=minimal',
            },
            body: JSON.stringify(oh.slice(i, i + 200)),
          });
          if (r.ok) optRows += Math.min(200, oh.length - i);
          else if (!storeErr) storeErr = `opt ${r.status} ${(await r.text()).slice(0, 140)}`;
        } catch (e) { if (!storeErr) storeErr = `opt ${String(e).slice(0, 140)}`; }
      }
    }

    const passed = out.filter((r) => r.passes);
    const heldRes = out.filter((r) => held.includes(r.ticker));
    return json(200, {
      // Written, or why not. A silent cache miss cost a day.
      cached: body.dry_run ? 'dry_run' : (cacheError ?? 'ok'),
      history_rows: stored, option_rows: optRows, history_error: storeErr,
      ok: true, build: BUILD, asof: todayISO, expiry,
      checked: out.length,
      passed: passed.length,
      market_days: marketDays.size,
      market_ref: `${MARKET_REF} >= ${MARKET_REF_MOVE}%`,
      // Whether the book is still clean is the highest-value thing here, so it
      // comes back first rather than buried in the full list.
      held: heldRes.map((r) => ({ ticker: r.ticker, passes: r.passes, fails: r.fails })),
      names: passed.sort((a, b) => (a.pos_52w ?? 99) - (b.pos_52w ?? 99)),
      /* Why a NAMED ticker did not clear. Only passers come back in `names`, so
         a rejected name was previously unanswerable without reading the table
         directly, and "no rows returned" is indistinguishable from "it passed".

         Deliberately NOT the same as body.tickers, which REPLACES the universe:
         a narrow run has too few samples for market-day detection, so no day
         reaches the 60-sample floor, none are found, and every stock wears the
         April 2025 macro week as its own gap. NKE came back at 15.2% that way.
         explain scans the whole universe and merely reports more of it. */
      explain: (body.explain ?? []).length
        ? out.filter((r) => (body.explain as string[])
            .map((t) => t.toUpperCase()).includes(String(r.ticker)))
        : undefined,
      // Liquidity is the gate that cannot be proxied, so say plainly whether the
      // feed actually returned it rather than letting a zero read as "illiquid".
      liquidity_seen: out.filter((r) => (r.option_oi ?? 0) > 0).length,
    });
  } catch (e) {
    return json(500, { ok: false, error: String(e) });
  }
});
