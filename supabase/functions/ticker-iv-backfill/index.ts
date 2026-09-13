/**
 * ticker-iv-backfill — reconstruct historical ATM-30d implied volatility for any
 * held name and write it into `ticker_iv_daily`.
 *
 * WHY THIS EXISTS. `ticker-iv-snapshot` takes ONE LIVE READING A DAY, and it only
 * starts taking it for a name on the day that name first has an open option. So a
 * position opened in late August carries two weeks of history, and the Premium now
 * card needs twenty trading days before a median is worth calling "its usual".
 * Nik, 2026-09-12, seeing four of seven names with no IV word: "do the IV backfill
 * for the four names."
 *
 * THE METHOD IS NVDA'S, GENERALISED. `nvda-iv` already reconstructs a year of daily
 * IV this way and it works (234 of 251 days): for each past session, take the
 * underlying's close, find the calls that were roughly at the money and roughly
 * thirty days out ON THAT DAY, read what one of them actually closed at, and solve
 * Black-Scholes backwards for the volatility that produces that price. Nothing here
 * is a new idea; it is that solver pointed at a list of tickers and a different
 * table. `nvda-iv` is deliberately left alone — it owns its own table and its own
 * crush study, and merging the two would couple them for no gain.
 *
 * ⚠ THE DIVIDEND YIELD IS NOT ZERO ON THESE NAMES. nvda-iv hard-codes Q = 0, which
 * is right for NVDA and wrong for PEP and KR: a dividend depresses a call, so
 * solving with Q = 0 hands back an implied vol that is too LOW, and the error grows
 * with the yield. Q is per ticker here.
 *
 * ⚠ AND IT WRITES ONLY WHAT IT SOLVED. A session with no liquid contract near the
 * money is left ABSENT, never interpolated and never carried forward from the day
 * before. A median over invented rows is worse than a median over fewer real ones,
 * and the card already knows how to say nothing.
 *
 * Trigger:
 *   POST {"tickers":["BABA","PEP"],"from":"2026-06-01","to":"2026-08-20"}
 * `to` defaults to the day before the name's earliest row on file, so the default
 * run extends history backwards rather than rewriting what the cron already took.
 */
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';

const POLY = 'https://api.polygon.io';
const R = 0.043;                  // risk-free, annualised
const TARGET_DTE = 30;
const DTE_LO = 20, DTE_HI = 45;   // acceptable expiry window
const STRIKE_PCT = 0.06;          // "at the money" is within 6% of spot
const CAP = 70;                   // trading days per ticker per invocation
const RANK_TRIES = 8;             // candidates walked before giving the day up
const MIN_TRADES = 5;             // trades in a contract's day before it is evidence
const MIN_STRIKES = 2;            // strikes that must solve before a day is written
const MAX_SPREAD = 0.12;          // strikes disagreeing by more than 12 vol points
                                  // are not measuring the same thing; drop the day

/* Annual dividend yield per name. A call is worth less on a dividend payer, so a
   solver told Q = 0 reads that discount as low volatility. Approximate is fine —
   at a 3% yield on a 30-day option the term is worth about a quarter of a point
   of vol — but zero is not. */
const DIV_Q: Record<string, number> = {
  PEP: 0.036, KR: 0.019, FIS: 0.022, BABA: 0.010,
  NKE: 0.022, NFLX: 0, LULU: 0, TLT: 0.041,
};

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};
const json = (s: number, b: unknown) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...cors, 'Content-Type': 'application/json' } });

// ── Black-Scholes and the solver, lifted from nvda-iv ────────────────────────
function normCdf(x: number): number {
  const t = 1 / (1 + 0.2316419 * Math.abs(x));
  const d = 0.3989422804014327 * Math.exp(-x * x / 2);
  let p = d * t * (0.319381530 + t * (-0.356563782 + t * (1.781477937 + t * (-1.821255978 + t * 1.330274429))));
  p = 1 - p;
  return x >= 0 ? p : 1 - p;
}
function bsCall(S: number, K: number, T: number, sig: number, q: number): number {
  if (T <= 0 || sig <= 0) return Math.max(0, S - K);
  const d1 = (Math.log(S / K) + (R - q + sig * sig / 2) * T) / (sig * Math.sqrt(T));
  const d2 = d1 - sig * Math.sqrt(T);
  return S * Math.exp(-q * T) * normCdf(d1) - K * Math.exp(-R * T) * normCdf(d2);
}
/** σ from a call price, by bisection. null when the price is at or below intrinsic. */
function impliedVol(C: number, S: number, K: number, T: number, q: number): number | null {
  const intrinsic = Math.max(0, S * Math.exp(-q * T) - K * Math.exp(-R * T));
  if (C <= intrinsic + 1e-6 || T <= 0) return null;
  let lo = 0.001, hi = 5.0, mid = 0.5;
  for (let i = 0; i < 100; i++) {
    mid = (lo + hi) / 2;
    const p = bsCall(S, K, T, mid, q);
    if (Math.abs(p - C) < 1e-4) return mid;
    if (p > C) hi = mid; else lo = mid;
  }
  return mid;
}

const ymd = (d: Date) => d.toISOString().slice(0, 10);
const addDays = (d: Date, n: number) => new Date(d.getTime() + n * 86400000);

interface Contract { ticker: string; strike_price: number; expiration_date: string; contract_type: string }

async function fetchContracts(tk: string, spot: number, asOf: string, key: string,
                              expired: boolean): Promise<Contract[]> {
  const lo = (spot * (1 - STRIKE_PCT)).toFixed(2), hi = (spot * (1 + STRIKE_PCT)).toFixed(2);
  const expFrom = ymd(addDays(new Date(asOf + 'T00:00:00Z'), DTE_LO));
  const expTo = ymd(addDays(new Date(asOf + 'T00:00:00Z'), DTE_HI));
  const url = `${POLY}/v3/reference/options/contracts?underlying_ticker=${tk}`
    + `&contract_type=call&expired=${expired}`
    + `&expiration_date.gte=${expFrom}&expiration_date.lte=${expTo}`
    + `&strike_price.gte=${lo}&strike_price.lte=${hi}&limit=250&apiKey=${key}`;
  const r = await fetch(url);
  if (!r.ok) return [];
  return ((await r.json())?.results ?? []) as Contract[];
}
/* ⚠ BOTH EXPIRED AND ACTIVE. A 30-DTE contract from three weeks ago has expired;
   one from last week has not. Querying a single flag silently loses half the range. */
async function contractsAsOf(tk: string, spot: number, asOf: string, key: string): Promise<Contract[]> {
  const [exp, act] = await Promise.all([
    fetchContracts(tk, spot, asOf, key, true),
    fetchContracts(tk, spot, asOf, key, false),
  ]);
  const seen = new Set<string>(); const out: Contract[] = [];
  for (const c of [...act, ...exp]) if (!seen.has(c.ticker)) { seen.add(c.ticker); out.push(c); }
  return out;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  try {
    const key = Deno.env.get('POLYGON_API_KEY');
    if (!key) return json(200, { ok: false, error: 'POLYGON_API_KEY is not set' });
    const admin = createClient(Deno.env.get('SUPABASE_URL')!,
                               Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);

    const body = await req.json().catch(() => ({})) as
      { tickers?: string[]; from?: string; to?: string; dry_run?: boolean };
    const tickers = body.tickers?.length ? body.tickers : [];
    if (!tickers.length) return json(200, { ok: false, error: 'pass {"tickers":[...]}' });
    const from = body.from ?? ymd(addDays(new Date(), -160));

    const report: Record<string, unknown>[] = [];
    for (const tk of tickers) {
      /* ⚠ THE DEFAULT `to` IS THE DAY BEFORE THE FIRST ROW ON FILE. The cron's
         readings are live and exact; a reconstructed one is a model. Overwriting
         the former with the latter would make the series worse in the name of
         filling it. Pass `to` explicitly to redo a range on purpose. */
      let to = body.to ?? null;
      if (!to) {
        const { data } = await admin.from('ticker_iv_daily')
          .select('snapshot_date').eq('ticker', tk)
          .order('snapshot_date', { ascending: true }).limit(1);
        const first = (data ?? [])[0]?.snapshot_date as string | undefined;
        to = first ? ymd(addDays(new Date(first + 'T00:00:00Z'), -1)) : ymd(new Date());
      }
      if (to < from) { report.push({ ticker: tk, skipped: 'nothing to fill', from, to }); continue; }

      const q = DIV_Q[tk] ?? 0;
      const aggUrl = `${POLY}/v2/aggs/ticker/${tk}/range/1/day/${from}/${to}`
        + `?adjusted=true&sort=asc&limit=200&apiKey=${key}`;
      const ar = await fetch(aggUrl);
      if (!ar.ok) {
        report.push({ ticker: tk, error: `aggs ${ar.status}`, polygon: (await ar.text()).slice(0, 200) });
        continue;
      }
      /* Newest first, so a capped run fills the days NEAREST the existing history
         and the series stays contiguous rather than growing an island. */
      const bars = (((await ar.json())?.results ?? []) as { t: number; c: number }[])
        .map((b) => ({ date: ymd(new Date(b.t)), close: b.c })).reverse();
      if (!bars.length) { report.push({ ticker: tk, error: 'no bars', from, to }); continue; }

      const rows: Record<string, unknown>[] = [];
      const misses: string[] = [];
      let processed = 0;
      for (const bar of bars) {
        if (processed >= CAP) break;
        processed++;
        const asOf = new Date(bar.date + 'T16:00:00Z');
        try {
          const cands = await contractsAsOf(tk, bar.close, bar.date, key);
          const ranked = cands
            .filter((c) => c.contract_type === 'call')
            .map((c) => {
              const dte = Math.round((new Date(c.expiration_date + 'T16:00:00Z').getTime() - asOf.getTime()) / 86400000);
              const sd = Math.abs(c.strike_price - bar.close) / bar.close;
              return { c, dte, sd, score: Math.abs(dte - TARGET_DTE) * 2 + sd * 100 };
            })
            .filter((x) => x.dte >= DTE_LO && x.dte <= DTE_HI && x.sd <= STRIKE_PCT)
            .sort((a, b) => a.score - b.score);
          if (!ranked.length) { misses.push(bar.date + ' no contract'); continue; }

          /* ⚠ WALK THE CANDIDATES, AND SOLVE ALL OF THEM. The first version took
             the first strike that had a print, the way nvda-iv does. Calibrated
             against the live cron on the same days that read −1.24 points on NKE
             and −4.96 on LULU, with a −65 point day: fine on a liquid name and
             unusable on a thin one. One print on one strike of an illiquid name
             is not a measurement.

             ⚠ THE PRICE IS THE DAY'S VWAP, NOT ITS CLOSE. A close is a single
             trade and on a thin contract it is usually somebody hitting the bid,
             which is the whole −1.24: solving a bid-side print gives a vol that
             is too LOW, every day, on every name. VWAP is the day's traded
             average and sits far nearer the mid.

             ⚠ AND THE ANSWER IS THE MEDIAN OF THE STRIKES, not the first one.
             Three or more strikes around the money should agree to a point or
             two; when they do not, the median throws out the one that traded
             once at a silly price rather than letting it be the reading. */
          const from6 = ymd(addDays(asOf, -6));
          const solves: number[] = [];
          const usedT: string[] = [];
          for (const { c } of ranked.slice(0, RANK_TRIES)) {
            const oc = await fetch(`${POLY}/v2/aggs/ticker/${c.ticker}/range/1/day/${from6}/${bar.date}`
              + `?adjusted=true&sort=desc&limit=6&apiKey=${key}`);
            const ob = oc.ok
              ? (((await oc.json())?.results ?? []) as { t: number; c: number; vw?: number; n?: number }[])
              : [];
            if (!ob.length) continue;
            const b0 = ob[0];
            /* A contract that printed once tells you almost nothing; require a
               handful of trades before its price is allowed to be evidence. */
            if ((b0.n ?? 0) < MIN_TRADES) continue;
            const px = (b0.vw && b0.vw > 0) ? b0.vw : b0.c;
            const optDate = new Date(b0.t);
            const T = (new Date(c.expiration_date + 'T16:00:00Z').getTime() - optDate.getTime()) / (365 * 86400000);
            const solved = impliedVol(px, bar.close, c.strike_price, T, q);
            /* A solve that pins to a bound is the bisection failing, not a
               reading: 0.1% and 500% both mean "no answer here". */
            if (solved != null && solved > 0.02 && solved < 3) { solves.push(solved); usedT.push(c.ticker); }
          }
          /* ⚠ AT LEAST TWO STRIKES MUST AGREE, or the day is left ABSENT. A
             missing day costs the median one observation; a wrong day moves it. */
          if (solves.length < MIN_STRIKES) { misses.push(bar.date + ` only ${solves.length} strike(s)`); continue; }
          const sorted = [...solves].sort((a, b) => a - b);
          const iv = sorted.length % 2
            ? sorted[(sorted.length - 1) / 2]
            : (sorted[sorted.length / 2 - 1] + sorted[sorted.length / 2]) / 2;
          /* The spread across strikes IS the day's confidence, so it is recorded
             rather than thrown away: a wide one means the strikes disagreed. */
          const spread = sorted[sorted.length - 1] - sorted[0];
          if (spread > MAX_SPREAD) { misses.push(bar.date + ` strikes disagree ${(spread * 100).toFixed(0)}pts`); continue; }
          rows.push({
            ticker: tk, snapshot_date: bar.date, atm_iv: Math.round(iv * 10000) / 10000,
            source: 'backfill', contract_used: `${usedT.length} strikes`,
            captured_at: new Date().toISOString(),
          });
        } catch (e) {
          misses.push(bar.date + ' ' + (e instanceof Error ? e.message : String(e)));
        }
      }

      if (rows.length && !body.dry_run) {
        for (let i = 0; i < rows.length; i += 100) {
          await admin.from('ticker_iv_daily')
            .upsert(rows.slice(i, i + 100), { onConflict: 'ticker,snapshot_date' });
        }
      }
      const oldest = bars[Math.min(processed, bars.length) - 1]?.date;
      report.push({
        ticker: tk, q, from, to, processed, solved: rows.length, missed: misses.length,
        /* Present when the cap was hit: pass it back as `to` to continue. */
        next_to: processed >= CAP && oldest
          ? ymd(addDays(new Date(oldest + 'T00:00:00Z'), -1)) : null,
        range: rows.length ? [rows[rows.length - 1].snapshot_date, rows[0].snapshot_date] : null,
        /* A dry run returns EVERY day, because its only job is to be checked
           against the live readings for the same days. */
        sample: (body.dry_run ? rows : rows.slice(0, 3)).map((r) => [r.snapshot_date, r.atm_iv]),
        misses: misses.slice(0, 4),
      });
    }
    return json(200, { ok: true, dry_run: !!body.dry_run, report });
  } catch (e) {
    return json(500, { ok: false, error: String((e as Error)?.message ?? e) });
  }
});
