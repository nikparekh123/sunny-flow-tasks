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

const BUILD = '2026-08-18.3';

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
const MARKET_DAY_SHARE = 0.25;
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

/** The coming Friday: the expiry the sleeve actually writes. */
function comingFriday(from: Date): string {
  const d = new Date(from.getTime());
  do { d.setUTCDate(d.getUTCDate() + 1); } while (d.getUTCDay() !== 5);
  return ymd(d);
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

    let body: { asof?: string; dry_run?: boolean; tickers?: string[] } = {};
    try { if (req.method === 'POST') body = await req.json(); } catch { /* no body is normal */ }
    const today = parseISO(body.asof ?? nyToday());
    const todayISO = ymd(today);
    const expiry = comingFriday(today);
    const D = db(url, key);

    const [uniRows, heldRows] = await Promise.all([
      D.get('income_scanner_universe?active=is.true&select=ticker'),
      D.get('income_sleeve_names?active=is.true&select=ticker'),
    ]);
    const held = heldRows.map((r) => String(r.ticker));
    const universe = (body.tickers ?? uniRows.map((r) => String(r.ticker)));
    if (!universe.length) return json(200, { ok: true, empty: true, note: 'universe is empty' });

    // ── prices for everything, including the held names for correlation ──────
    const need = Array.from(new Set([...universe, ...held]));
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
          bars[t] = await dailyCloses(t, polyKey, ymd(addDays(today, -600)), todayISO);
        } catch { bars[t] = []; }
      }));
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
    const marketDays = new Set(
      Object.entries(moves)
        .filter(([, ms]) => ms.length >= 60
          && ms.filter((m) => m > MARKET_DAY_MOVE).length / ms.length > MARKET_DAY_SHARE)
        .map(([d]) => d),
    );

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
        else if (edge <= G.edgeMin) fails.push(`edge ${edge.toFixed(1)}`);
        else if (edge > G.edgeMax) fails.push(`edge ${edge.toFixed(1)}, an event is priced`);
        if (oi < G.oiMin) fails.push(`no market: ${oi} open interest around the money`);

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
      'edge', 'option_oi', 'option_volume', 'weeklies', 'liquidity',
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

    const passed = out.filter((r) => r.passes);
    const heldRes = out.filter((r) => held.includes(r.ticker));
    return json(200, {
      // Written, or why not. A silent cache miss cost a day.
      cached: body.dry_run ? 'dry_run' : (cacheError ?? 'ok'),
      ok: true, build: BUILD, asof: todayISO, expiry,
      checked: out.length,
      passed: passed.length,
      market_days: marketDays.size,
      // Whether the book is still clean is the highest-value thing here, so it
      // comes back first rather than buried in the full list.
      held: heldRes.map((r) => ({ ticker: r.ticker, passes: r.passes, fails: r.fails })),
      names: passed.sort((a, b) => (a.pos_52w ?? 99) - (b.pos_52w ?? 99)),
      // Liquidity is the gate that cannot be proxied, so say plainly whether the
      // feed actually returned it rather than letting a zero read as "illiquid".
      liquidity_seen: out.filter((r) => (r.option_oi ?? 0) > 0).length,
    });
  } catch (e) {
    return json(500, { ok: false, error: String(e) });
  }
});
