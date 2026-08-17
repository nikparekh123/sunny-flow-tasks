/**
 * income-sleeve — several names, ONE rule.
 *
 * Spec: docs/INCOME_SLEEVE_SPEC.md
 *
 * Own a block. Sell an at-the-money call and an at-the-money put on it every week.
 * Hold a long-dated out-of-the-money put as a floor, which the weekly premium pays
 * for. The share count lands where it lands.
 *
 * This is NOT nvda-accumulate or tlt-planner with more tickers. Those answer "how
 * much do I write today", which needs bands, budgets, chase rates and dip gates
 * because the size is genuinely uncertain. Here the size is fixed by the block, so
 * the only question left is:
 *
 *     should I write at all this week, on this name?
 *
 * Two answers: WRITE or SKIP, plus a one-phrase verdict on how the week prices.
 * (A third state, CAREFUL, was removed on 2026-08-16: it never blocked anything
 * and read as alarm rather than information. See the state block below.)
 *
 * Positions come from the LEGACY option_trades / share_lots / share_sells, which
 * already carry a ticker column and are already filled by ibkr-flex-sync for any
 * symbol traded. NVDA and TLT needed mirrored per-ticker stores; this does not, and
 * adding a fourth name is a row in income_sleeve_names rather than a new table.
 *
 * Body (all optional): {"asof":"2026-08-17"}
 */
// The shared core is fetched over https, pinned to a commit, NOT imported from
// ../_shared/. The dashboard bundles only this folder, so a sibling import fails at
// deploy with 'Module not found'. Same URL and SHA as nvda-accumulate and tlt-planner.
import {
  corsHeaders, json, db, dailyCloses, spotOf, chain, Quote, Row,
  ncdf, d1of, ymd, parseISO, addDays, daysBetween, nyToday, marketNow, marketState,
  sd, fmtDay,
} from 'https://raw.githubusercontent.com/nikparekh123/sunny-flow-tasks/dd3c85a56102451ae439016d6a90460c4d41dab0/supabase/functions/_shared/planner.ts';

/* Bumped by hand on every meaningful change. Six deploys on 2026-08-16 went in
   with no error and several of them changed nothing (the dashboard's Save is not
   its Deploy), and each one cost a round of "is it live?" guessing. The response
   carries this, so one call answers it. */
const BUILD = '2026-08-17.4';

// ── the rules, all of them ──────────────────────────────────────────────────
const REALISED_DAYS = 20;      // the window the edge is measured against
const HIGH_IN_RANGE = 75;      // above this much of the 52w range the verdict softens
const FLOOR_MIN_WEEKS = 3;     // a floor with less left than this must be rolled first

/**
 * EDGE, and why the horizon matters.
 *
 * edge = 7-day at-the-money implied  −  20-day realised
 *
 * Positive means the option is priced above what the stock has actually been doing.
 * Negative means selling volatility cheaper than it is arriving, which is a losing
 * trade however good the yield looks.
 *
 * On 2026-08-14, 15 of 20 names screened NEGATIVE. A planner that simply said "write
 * every Friday" would have walked into most of them: SHOP -37%, MU -43%, PLTR -64%.
 *
 * The window is 20 days ON PURPOSE. Comparing a 7-day option to a YEAR of realised
 * vol made almost everything look like a bad sale, because a year contains regimes
 * the next seven days will not. It is a filter, not a forecast.
 */
function realisedVol(closes: number[], n: number): number | null {
  if (closes.length < n + 2) return null;
  const w = closes.slice(-(n + 1));
  const lr: number[] = [];
  for (let i = 0; i < w.length - 1; i++) lr.push(Math.log(w[i + 1] / w[i]));
  return sd(lr) * Math.sqrt(252);
}

/** Implied vol backed out of one option price. Bisection: fast enough, no derivative. */
function impliedVol(price: number, S: number, K: number, T: number, put: boolean): number | null {
  if (!(price > 0) || !(S > 0) || !(K > 0) || T <= 0) return null;
  const val = (v: number) => {
    const a = d1of(S, K, T, v), b = a - v * Math.sqrt(T);
    const c = S * ncdf(a) - K * Math.exp(-0.045 * T) * ncdf(b);
    return put ? c - S + K * Math.exp(-0.045 * T) : c;
  };
  let lo = 0.02, hi = 5.0;
  if (val(hi) < price) return null;                 // price above anything sane
  for (let i = 0; i < 100; i++) {
    const m = (lo + hi) / 2;
    if (val(m) > price) hi = m; else lo = m;
  }
  return (lo + hi) / 2;
}

/** The nearest listed strike to a target, among quotes that are actually tradeable. */
function nearest(qs: Quote[], target: number): Quote | null {
  const live = qs.filter((q) => q.mid > 0);
  if (!live.length) return null;
  return live.reduce((a, b) => (Math.abs(a.strike - target) <= Math.abs(b.strike - target) ? a : b));
}

/** The coming Friday. Weekly is the whole cadence here; there is no tenor decision. */
function comingFriday(from: Date): string {
  const d = new Date(from.getTime());
  do { d.setUTCDate(d.getUTCDate() + 1); } while (d.getUTCDay() !== 5);
  return ymd(d);
}

/**
 * TREND, deliberately three plain facts and no verdict.
 *
 * Nik asked for "a little technical analysis" because a lot is moving on it and the
 * prints are close. The screen states where the price sits against its 50-day, what
 * RSI reads, and what the last week did. It does NOT turn those into a buy or a
 * sell: the write decision is made by edge and earnings, not by an oscillator.
 *
 * RSI is the plain 14-period simple average of gains and losses, not Wilder's
 * smoothing. Over 14 bars the two differ by a point or two and this is context, not
 * a trigger.
 */
function rsi14(cl: number[]): number | null {
  if (cl.length < 15) return null;
  let g = 0, l = 0;
  for (let i = cl.length - 14; i < cl.length; i++) {
    const ch = cl[i] - cl[i - 1];
    if (ch > 0) g += ch; else l -= ch;
  }
  if (l === 0) return 100;
  return 100 - 100 / (1 + (g / 14) / (l / 14));
}

function meanOf(cl: number[], n: number): number | null {
  if (cl.length < n) return null;
  return cl.slice(-n).reduce((s, x) => s + x, 0) / n;
}

/* ── the card contract ────────────────────────────────────────────────────────
   Claude Design's Income screen (docs/INCOME_SCREEN_DESIGN_BRIEF.md, returned
   2026-08-16) sets one rule: EVERY DISPLAYED STRING IS EMITTED HERE. The client
   formats nothing. The only number crossing the boundary is foot.pct, which sets
   the width of the 52-week range track.

   That is why the helpers below exist rather than living in Swift. Two clients
   formatting the same figure two ways is exactly how the covered-call card ended
   up reading $499 against a summary saying $249. */
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const DAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

/** "2026-08-21" -> "Fri 21 Aug". The expiry has to read at a glance, so weekday first. */
function dayShort(iso?: string | null): string {
  if (!iso || iso.length < 10) return '';
  const d = parseISO(String(iso).slice(0, 10));
  return `${DAYS[d.getUTCDay()]} ${d.getUTCDate()} ${MONTHS[d.getUTCMonth()]}`;
}

/** "2027-01-15" -> "Jan". The floor is named by its month, never its full date. */
function monShort(iso?: string | null): string {
  if (!iso || iso.length < 7) return '';
  return MONTHS[parseISO(String(iso).slice(0, 10)).getUTCMonth()] ?? '';
}

/** "$24,652". Whole dollars, grouped. No k/m compaction: the design shows the figure. */
function usd(v: number): string {
  return '$' + Math.round(v).toLocaleString('en-US');
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  try {
    const url = Deno.env.get('SUPABASE_URL')!;
    const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const polyKey = Deno.env.get('POLYGON_API_KEY')!;
    if (!polyKey) return json(500, { ok: false, error: 'POLYGON_API_KEY is not set' });

    let body: { asof?: string } = {};
    try { if (req.method === 'POST') body = await req.json(); } catch { /* no body is normal */ }
    const today = parseISO(body.asof ?? nyToday());
    const todayISO = ymd(today);
    const expiry = comingFriday(today);
    const D = db(url, key);

    const [names, mkt, setRows] = await Promise.all([
      D.get('income_sleeve_names?active=is.true&select=*&order=sort.asc'),
      marketNow(polyKey),
      D.get('income_sleeve_settings?id=eq.1&select=*'),
    ]);
    const cfg = setRows[0] ?? {};
    if (!names.length) return json(200, { ok: true, empty: true, note: 'no active names' });

    const tickers = names.map((n) => String(n.ticker));
    const inList = `(${tickers.join(',')})`;
    const [earnRows, tradeRows, lotRows, sellRows] = await Promise.all([
      // report_date, NOT earnings_date or event_date. Two migrations and two other
      // functions each use a different name for this column and only report_date
      // exists. db.get() swallows the 400 and returns [], so the wrong name fails
      // silently rather than loudly, which is how nvda-accumulate's earnings brake
      // sat dead without anyone noticing.
      D.get(`earnings_events?ticker=in.${inList}&report_date=gte.${todayISO}`
            + `&select=ticker,report_date&order=report_date.asc`),
      D.get(`option_trades?ticker=in.${inList}&voided_at=is.null`
            + `&select=ticker,trade_date,action,option_type,direction,contracts,strike,premium,expiry`),
      D.get(`share_lots?ticker=in.${inList}&voided_at=is.null&select=ticker,acquired_date,qty_remaining,cost_per_share`),
      D.get(`share_sells?ticker=in.${inList}&voided_at=is.null&select=ticker,trade_date,realized_pl`),
    ]);

    // Deliberately permissive: the rank pass below writes rank/rank_line back onto
    // each row after they are all built, and the no-price early return is a much
    // narrower shape than a full row. A union type here buys nothing and costs a
    // cast at every read.
    const rows: Array<Record<string, any>> = await Promise.all(names.map(async (n) => {
      const t = String(n.ticker);

      const [spot, closes] = await Promise.all([
        spotOf(t, polyKey),
        dailyCloses(t, polyKey, ymd(addDays(today, -400)), todayISO),
      ]);
      if (spot == null || !closes.length) {
        return {
          ticker: t, state: 'SKIP', why: ['no price'], verdict: 'no read',
          spot, blocked: true, floor_line: 'none yet', write: null,
        };
      }
      const cl = closes.map((c) => c.c);

      // ── the book, from the legacy tables filtered by ticker AND start date ──
      // started_on exists because the legacy tables hold positions Nik USED to have.
      // On 2026-08-16 they showed 200 INTU, 48 NKE and 500 LULU that he no longer
      // holds. Rather than void real history, the sleeve simply does not look before
      // its own start. Everything earlier still belongs to the ledger, just not here.
      const since = n.started_on ? String(n.started_on) : '1900-01-01';
      const lots = lotRows.filter((r) => r.ticker === t && String(r.acquired_date ?? '') >= since);
      const shares = lots.reduce((s, l) => s + Number(l.qty_remaining ?? 0), 0);
      const paid = lots.reduce((s, l) => s + Number(l.qty_remaining ?? 0) * Number(l.cost_per_share ?? 0), 0);
      const avgBuy = shares > 0 ? paid / shares : 0;

      const legs = tradeRows.filter((r) => r.ticker === t && String(r.trade_date ?? '') >= since);
      // PREMIUM COUNTS ON COLLECTION HERE, not on expiry. Decided 2026-08-15.
      // This DIFFERS from NVDA and TLT, which follow docs/PNL_GLOSSARY.md and only
      // book a short option's premium once it has expired or closed. The book turns
      // over weekly, so the gap is days rather than months, and the whole point of
      // the screen is watching the average grind down. Do NOT "fix" this.
      //
      // SPLIT BY LEG, because the card shows which side is doing the work. A name
      // whose average is grinding down entirely on call premium is a different
      // position from one carried by the puts, and the totals hide that.
      const premOf = (kind: string | null) => legs
        .filter((l) => l.direction === 'short' && (kind == null || l.option_type === kind))
        .reduce((s, l) => s + (l.action === 'open' ? 1 : -1)
                            * Number(l.premium ?? 0) * Number(l.contracts ?? 0) * 100, 0);
      const premCalls = premOf('call'), premPuts = premOf('put');
      const premCollected = premOf(null);
      const realisedShares = sellRows.filter((r) => r.ticker === t && String(r.trade_date ?? '') >= since)
        .reduce((s, r) => s + Number(r.realized_pl ?? 0), 0);

      // CURRENT AVERAGE — the number Nik actually watches. Bought at 100, collected
      // $1 on the call and $2 on the put, current average is 97. It walks down every
      // week you write.
      const currentAvg = shares > 0 ? avgBuy - premCollected / shares : 0;

      const netOpen = (kind: string) => {
        let n = 0;
        for (const l of legs) {
          if (l.option_type !== kind || l.direction !== 'short') continue;
          if (String(l.expiry ?? '') < todayISO) continue;       // already gone
          n += (l.action === 'open' ? 1 : -1) * Number(l.contracts ?? 0);
        }
        return Math.max(0, n);
      };
      const openCalls = netOpen('call'), openPuts = netOpen('put');
      const putCommit = legs
        .filter((l) => l.option_type === 'put' && l.direction === 'short'
                    && String(l.expiry ?? '') >= todayISO && l.action === 'open')
        .reduce((s, l) => s + Number(l.strike ?? 0) * 100 * Number(l.contracts ?? 0), 0);

      // ── the two numbers neither other engine has ───────────────────────────
      const rv = realisedVol(cl, REALISED_DAYS);
      /* TIME TO EXPIRY IS MEASURED FROM THE QUOTE'S OWN SESSION, not from now.
         Polygon returns the last session's close while the market is shut. Read
         on a Sunday, a Friday-close price for the coming Friday was being divided
         by 5 days of life when it was bought with 7, so implied vol came out high
         and every name read "good week to sell". INTU showed 60% on the Sunday
         against 44% measured on the Friday: not a small distortion, and it lands
         on the one number the whole screen is disciplined by.

         The fix is not a weekend special case. Any time the market is shut the
         quote is older than the clock, so the clock is the wrong reference. */
      const quoteDay = (mkt?.open ?? marketState(new Date()).open)
        ? todayISO
        : (closes[closes.length - 1]?.d ?? todayISO);
      const T = Math.max(daysBetween(parseISO(String(quoteDay)), parseISO(expiry)), 1) / 365;
      const [puts, calls] = await Promise.all([
        chain(t, 'put', expiry, Math.floor(spot * 0.90), Math.ceil(spot * 1.06), polyKey),
        chain(t, 'call', expiry, Math.floor(spot * 0.94), Math.ceil(spot * 1.10), polyKey),
      ]);
      const atmPut = nearest(puts, spot), atmCall = nearest(calls, spot);
      const iv = atmPut ? impliedVol(atmPut.mid, spot, atmPut.strike, T, true) : null;
      const edge = (iv != null && rv != null) ? iv - rv : null;

      const win = cl.slice(-252);
      const lo52 = Math.min(...win), hi52 = Math.max(...win);
      const pos52 = hi52 > lo52 ? 100 * (spot - lo52) / (hi52 - lo52) : 50;
      // A NEW LOW is the thing Nik wants surfaced, not the range position alone: a
      // name printing fresh lows while you sell puts on it is refilling into a fall.
      const newLow = spot <= lo52 * 1.005;

      const ma50 = meanOf(cl, 50), ma200 = meanOf(cl, 200), rsi = rsi14(cl);
      const chg5 = cl.length >= 6 ? 100 * (spot / cl[cl.length - 6] - 1) : null;

      // ── the rank, and what it is measured on ───────────────────────────────
      // Premium collected per week, against the value of the block it was written
      // on. Both halves move with assignment, which is the point: a name that gets
      // called away and rebuilt smaller has less capital working AND collects less,
      // so the ratio still says how hard the money worked.
      //
      // Per WEEK, not cumulative: a name added in October must not rank last for
      // three months purely for being young.
      const weeksIn = n.started_on
        ? Math.max(1, daysBetween(parseISO(String(n.started_on)), today) / 7)
        : 0;
      const capitalBase = shares * spot;
      // premCollected > 0 matters, and the first live run is what showed why. On
      // day one started_on is today, so weeksIn floors to 1 and this evaluated to
      // a real 0.00 rather than null. Every name scored zero, "any name has earned
      // something" came out true, and the rank fell through to input order while
      // printing "0.00% a week" as though it had measured something. Nothing
      // collected means there is nothing to rank on, so: null, and the quoted-yield
      // fallback takes over as intended.
      const earnedPerWeek = (weeksIn > 0 && capitalBase > 0 && premCollected > 0)
        ? 100 * (premCollected / weeksIn) / capitalBase
        : null;

      /* ── EARNINGS, AND THE SILENCE WHEN THERE ARE NONE ─────────────────────
         earnings_events holds hand-entered dates. When a name runs out of them
         the query simply returns nothing, nextEarn is undefined, earnInside is
         false, and the sleeve writes straight through the print without a word.

         That is not hypothetical: on 2026-08-17 the table held exactly three
         future dates (INTU 25 Aug, LULU 27 Aug, NKE 24 Sep). After 24 Sep every
         name would have been flying blind, and the card would have said nothing
         at all about it. It is the same failure that left nvda-accumulate's brake
         dead for months — a guard that cannot fire looks identical to a guard
         with nothing to catch.

         So a missing date is now a STATE, not an absence. The card says so, and
         `earnings_missing` is on the row for anything that wants to alert. */
      const nextEarn = earnRows.find((e) => e.ticker === t)?.report_date as string | undefined;
      const earnMissing = !nextEarn;
      const earnInside = !!(nextEarn && nextEarn <= expiry);
      /* MARGIN RISES BEFORE THE PRINT, not on the day of it. Nik's rule, added
         2026-08-17: come down a week early rather than carry full size into the
         margin increase. So the brake reaches one expiry FURTHER than the write —
         an earnings date inside the week AFTER this one already stops new puts. */
      const earnSoon = !!(nextEarn && nextEarn <= ymd(addDays(parseISO(expiry), 7)));

      // ── the floor ──────────────────────────────────────────────────────────
      const fStrike = n.floor_strike != null ? Number(n.floor_strike) : null;
      const fExpiry = n.floor_expiry ? String(n.floor_expiry) : null;
      const fCt = Number(n.floor_contracts ?? 0);
      const fCost = Number(n.floor_cost ?? 0);
      const fWeeksLeft = fExpiry ? Math.floor(daysBetween(today, parseISO(fExpiry)) / 7) : null;
      // FUNDED: has the premium collected since the floor was bought paid for it?
      // Once this crosses 100% the protection is free for the rest of its life. On
      // AVGO that took about 21 days of a 154-day life.
      const boughtOn = n.floor_bought_on ? String(n.floor_bought_on) : null;
      const premSinceFloor = boughtOn
        ? legs.filter((l) => l.direction === 'short' && l.action === 'open'
                          && String(l.trade_date ?? '') >= boughtOn)
              .reduce((s, l) => s + Number(l.premium ?? 0) * Number(l.contracts ?? 0) * 100, 0)
        : 0;
      const fundedPct = fCost > 0 ? 100 * premSinceFloor / fCost : null;

      /* HOW MANY FLOOR CONTRACTS THE POSITION ACTUALLY NEEDS.
         Nik's rule, 2026-08-17: shares held PLUS puts sold, never a future or
         intended size. A short put is a promise to buy more shares at the strike,
         so in a fall it loses alongside the block rather than instead of it. A
         floor sized to the shares alone leaves exactly half the exposure bare.

         Priced on the week-one package it is decisive. Covering shares only, a
         40% fall left $62,402 of put assignment unhedged. Covering shares plus
         puts, the net result is FLAT from -10% through -40%. The floor doubles in
         cost, from 15% to 29% of the income, and that is what it buys.

         It is deliberately current, not forward: nothing here pre-buys protection
         for shares that have not arrived. */
      const floorNeed = Math.floor(shares / 100) + openPuts;
      const floorShort = Math.max(0, floorNeed - fCt);

      // ── how many to write ──────────────────────────────────────────────────
      // Calls are limited by shares actually HELD. Pending assignment is not cover:
      // write against shares that have not arrived and a rally leaves you naked.
      const callCt = Math.max(0, Math.floor(shares / 100) - openCalls);
      // Puts match the block too, 1:1, exactly as the calls do.
      //
      // NO TARGET. Until 2026-08-16 this refilled toward a target_shares figure,
      // which sized the first write at 6 INTU + 50 NKE + 16 LULU: $604,000 of
      // commitment in one Friday. Nik removed targets outright: the sleeve reads
      // what IBKR says he holds and reports each name as a share of the whole.
      //
      // It is also the correct structure, not just the requested one. The wheel is
      // self-balancing: the call takes shares out at the same rate the put brings
      // them back, so a block written 1:1 on both legs oscillates around its own
      // size and needs nothing to aim at. target_shares stays on the table as dead
      // weight rather than being dropped mid-week; nothing reads it now.
      const putCt = Math.max(0, Math.floor(shares / 100) - openPuts);

      // ── write or skip. There is no CAREFUL any more. ───────────────────────
      //
      // CAREFUL was dropped on 2026-08-16. It fired on negative edge, on a high
      // range position, and on a missing floor, and printed lines like "CAREFUL —
      // no floor set" against a sleeve that had not opened yet. Nik's words: it
      // reads as fear-mongering. It was also lying by omission, since a state that
      // never blocks anything is not a state, it is a tone of voice.
      //
      // The same information survives, stated as fact rather than alarm:
      //   negative edge      -> the verdict reads "poor week to sell"
      //   high in the range  -> the position line already says "82% up the range"
      //   no floor           -> the floor line reads "none yet"
      //
      // SKIP is unchanged and still blocks. Earnings inside the expiry, nothing to
      // write against, and a floor about to expire are real stops, not warnings.
      let state = 'WRITE';
      const why: string[] = [];
      if (earnInside) {
        state = 'SKIP';
        why.push(`earnings ${dayShort(nextEarn)} is inside this expiry`);
      } else if (earnSoon) {
        state = 'SKIP';
        why.push(`earnings ${dayShort(nextEarn)} is the week after, margin rises first`);
      } else if (earnMissing) {
        // Not a warning about the market. A warning about the DATA: nothing is
        // protecting this name, and saying nothing would imply something is.
        state = 'SKIP';
        why.push('no earnings date on file, so nothing is guarding the print');
      } else if (shares <= 0) {
        state = 'SKIP';
        why.push('no shares yet, nothing to write against');
      } else if (callCt <= 0 && putCt <= 0) {
        state = 'SKIP';
        why.push('nothing left to write, calls and puts both full');
      } else if (fStrike != null && fWeeksLeft != null && fWeeksLeft < FLOOR_MIN_WEEKS) {
        // The structure is only sound while the protection is on. A floor about to
        // expire gets rolled BEFORE more premium is written against it, otherwise
        // this is a naked short straddle wearing a hedge's name.
        state = 'SKIP';
        why.push(`floor expires in ${fWeeksLeft} week${fWeeksLeft === 1 ? '' : 's'}, roll it first`);
      }

      // The verdict: one phrase, right-aligned on the card, replacing the two
      // percentages that used to sit in the row body. iv and rv still ship in the
      // payload for the detail view, so the working is a tap away rather than gone.
      /* ELIGIBLE TO BUY is not the same question as eligible to write.
         "No shares yet" is precisely what the ramp exists to fix, so it must not
         exclude a name from the buy plan — otherwise the sleeve can never start.
         A print inside the next two expiries, or no date on file, does exclude
         it: buying stock a week before the margin rises is the thing Nik's own
         rule is there to prevent. */
      const canBuy = !earnInside && !earnSoon && !earnMissing;

      const verdict = edge == null ? 'no read'
        : edge < 0 ? 'poor week to sell'
        : pos52 > HIGH_IN_RANGE ? 'rich, but near the high'
        : 'good week to sell';

      return {
        ticker: t, state, why, verdict,
        spot, expiry,
        trend: {
          ma50: ma50 != null ? Math.round(ma50 * 100) / 100 : null,
          ma50_pct: ma50 != null ? Math.round(1000 * (spot / ma50 - 1)) / 10 : null,
          ma200: ma200 != null ? Math.round(ma200 * 100) / 100 : null,
          ma200_pct: ma200 != null ? Math.round(1000 * (spot / ma200 - 1)) / 10 : null,
          rsi: rsi != null ? Math.round(rsi) : null,
          chg5: chg5 != null ? Math.round(chg5 * 10) / 10 : null,
        },
        trend_line: [
          ma50 != null ? `${spot >= ma50 ? 'above' : 'below'} the 50 day` : null,
          rsi != null ? `RSI ${Math.round(rsi)}` : null,
          chg5 != null ? `5d ${chg5 >= 0 ? '+' : ''}${(Math.round(chg5 * 10) / 10).toFixed(1)}%` : null,
        ].filter(Boolean).join(' · '),
        new_low: newLow,
        // The ATM straddle, on EVERY row including a skipped one. The quoted-yield
        // fallback used to read these out of `write`, which is null on SKIP — so
        // the moment all three names skipped (no shares held, opening week) the
        // rank had nothing to sort on and fell back to input order while claiming
        // "no price to rank on". The prices were never missing, only unreachable.
        atm_call_mid: atmCall?.mid ?? null,
        atm_put_mid: atmPut?.mid ?? null,
        atm_straddle: (atmCall?.mid != null && atmPut?.mid != null)
          ? Math.round((atmCall.mid + atmPut.mid) * 100) / 100 : null,
        where_line: (newLow ? 'at the 52w low' : `${Math.round(pos52)}% up the 52w range`),
        earned_per_week: earnedPerWeek != null ? Math.round(earnedPerWeek * 100) / 100 : null,
        weeks_in: weeksIn > 0 ? Math.round(weeksIn * 10) / 10 : null,
        capital_base: Math.round(capitalBase),
        edge: edge != null ? Math.round(edge * 1000) / 10 : null,
        iv: iv != null ? Math.round(iv * 100) : null,
        rv: rv != null ? Math.round(rv * 100) : null,
        vol_line: (iv != null && rv != null) ? `sells ${Math.round(iv * 100)}%, moves ${Math.round(rv * 100)}%` : null,
        pos52: Math.round(pos52),
        low52: Math.round(lo52 * 100) / 100, high52: Math.round(hi52 * 100) / 100,
        earnings: nextEarn ?? null,
        earnings_missing: earnMissing,
        can_buy: canBuy,
        atm_pair_strike: atmPut?.strike ?? null,
        earnings_soon: earnSoon,
        earnings_in_days: nextEarn ? daysBetween(today, parseISO(nextEarn)) : null,
        started_on: n.started_on ?? null,
        shares,
        avg_buy: Math.round(avgBuy * 100) / 100,
        current_avg: Math.round(currentAvg * 100) / 100,
        avg_line: shares > 0
          ? `avg ${(Math.round(currentAvg * 100) / 100).toFixed(2)} from ${(Math.round(avgBuy * 100) / 100).toFixed(2)}`
          : null,
        // What each LEG took off the average, per share. Confirmed with Nik
        // 2026-08-16: this is the split of the credit, not the average that would
        // result if the calls carried the shares away.
        avg_split: shares > 0 ? {
          calls: Math.round(100 * premCalls / shares) / 100,
          puts: Math.round(100 * premPuts / shares) / 100,
        } : null,
        avg_split_line: shares > 0
          ? `calls gave ${(Math.round(100 * premCalls / shares) / 100).toFixed(2)}, `
            + `puts gave ${(Math.round(100 * premPuts / shares) / 100).toFixed(2)}`
          : null,
        premium_collected: Math.round(premCollected),
        premium_calls: Math.round(premCalls),
        premium_puts: Math.round(premPuts),
        realised_shares: Math.round(realisedShares),
        open_calls: openCalls, open_puts: openPuts,
        put_commitment: Math.round(putCommit),
        stock_value: Math.round(shares * spot),
        write: state === 'SKIP' ? null : {
          calls: callCt, call_strike: atmCall?.strike ?? null, call_mid: atmCall?.mid ?? null,
          puts: putCt, put_strike: atmPut?.strike ?? null, put_mid: atmPut?.mid ?? null,
          credit: Math.round((atmCall?.mid ?? 0) * 100 * callCt + (atmPut?.mid ?? 0) * 100 * putCt),
        },
        floor: fStrike == null ? null : {
          strike: fStrike, expiry: fExpiry, contracts: fCt, cost: fCost,
          weeks_left: fWeeksLeft,
          funded_pct: fundedPct != null ? Math.round(fundedPct) : null,
          funded: fundedPct != null && fundedPct >= 100,
          // How far the stock sits ABOVE the floor. This is the hole the floor does
          // NOT cover: everything between here and the strike is still yours to lose.
          gap_pct: Math.round(1000 * (spot - fStrike) / spot) / 10,
        },
        // "floor 310 Jan · 10% below the price · paid for", or "none yet". Never a
        // warning: a sleeve in its first week has nothing to protect.
        floor_needed: floorNeed,
        floor_short: floorShort,
        floor_line: fStrike == null
          ? (floorNeed > 0 ? `none yet · ${floorNeed} contracts needed` : 'none yet')
          : `${fStrike} ${monShort(fExpiry)} · `
            + `${(Math.round(1000 * (spot - fStrike) / spot) / 10).toFixed(0)}% below the price · `
            + (fundedPct == null ? 'cost unknown'
               : fundedPct >= 100 ? 'paid for'
               : `${Math.round(fundedPct)}% paid for`)
            + (floorShort > 0 ? ` · ${fCt} of ${floorNeed}, ${floorShort} short` : ''),
        floor_cost: fCost,
        floor_prem_since: Math.round(premSinceFloor),
      };
    }));

    /* ── THE RANK ────────────────────────────────────────────────────────────
       Ordered on premium earned per week per dollar of capital the name is meant
       to consume. That is a scoreboard, not a forecast: it re-sorts itself when a
       name skips an earnings week or simply goes quiet, and Nik sees the order
       change without doing the arithmetic.

       Week one nothing has been earned, so it falls back to the QUOTED straddle
       yield and the card says so rather than pretending the rank is history.
       `ranked_on` carries which of the two produced the order. */
    const quotedYield = (r: Record<string, any>) => {
      if (!r.spot || r.atm_straddle == null) return null;
      const straddle = Number(r.atm_straddle);
      return straddle > 0 ? 100 * straddle / Number(r.spot) : null;
    };
    const anyEarned = rows.some((r) => r.earned_per_week != null);
    for (const r of rows) {
      r.quoted_yield = quotedYield(r) != null ? Math.round(quotedYield(r)! * 100) / 100 : null;
      r.ranked_on = anyEarned ? 'earned' : 'quoted';
      r.rank_value = anyEarned ? (r.earned_per_week ?? -1) : (r.quoted_yield ?? -1);
    }
    [...rows].sort((a, b) => Number(b.rank_value ?? -1) - Number(a.rank_value ?? -1))
      .forEach((r, i) => { r.rank = i + 1; });
    for (const r of rows) {
      r.rank_line = r.ranked_on === 'earned'
        ? `${(r.earned_per_week as number).toFixed(2)}% a week · `
          + `$${Math.round(r.premium_collected as number).toLocaleString('en-US')} since `
          + fmtDay(String(r.started_on))
        : r.quoted_yield == null
          ? 'nothing yet · no price to rank on'
          : `nothing yet · ranked on this week's ${(r.quoted_yield as number).toFixed(1)}%`;
    }

    const stock = rows.reduce((s, r) => s + (r.stock_value ?? 0), 0);
    // THE BALANCE, which is what replaced "0 of 600 shares". Each name as a share
    // of the sleeve by value: INTU 32%, NKE 46%, LULU 22%. A target said how far
    // off some intended size you were; this says how the money actually sits.
    for (const r of rows) {
      const v = r.stock_value ?? 0;
      r.share_of_sleeve = stock > 0 ? Math.round(1000 * v / stock) / 10 : null;
      r.balance_line = stock > 0 && v > 0
        ? `${Math.round(r.shares ?? 0).toLocaleString('en-US')} shares · `
          + `$${Math.round(v).toLocaleString('en-US')} · `
          + `${(Math.round(1000 * v / stock) / 10).toFixed(0)}% of the sleeve`
        : 'no shares yet';
    }
    /* ── THE RAMP: turn a weekly income target into a share purchase ─────────
       Nik's rule: $5,000 of income a week, plus $5,000 each week, toward
       $30,000. Slow on purpose, one rung at a time, stoppable at any point.

       Writing both legs on a block earns the straddle premium every week, so the
       stock needed for a given income is target / straddle-yield. That is all
       this is. The shortfall is split evenly across the names that CAN buy
       today, then rounded to whole contracts, because a block that is not a
       multiple of 100 cannot be fully written against.

       Names skipped for EARNINGS are excluded from the buy as well as the write:
       buying a week before the margin rises is exactly what Nik's rule exists to
       prevent. Names skipped only for having no shares are the whole point. */
    const rampOn = String(cfg.ramp_start_on ?? '2026-08-17');
    const rampWk = Math.max(0, Math.floor(daysBetween(parseISO(rampOn), today) / 7));
    const rampStart = Number(cfg.ramp_start ?? 5000);
    const rampStep = Number(cfg.ramp_step ?? 5000);
    const rampCap = Number(cfg.ramp_cap ?? 30000);
    const paused = cfg.ramp_paused === true;
    const target = Math.min(rampCap, rampStart + (paused ? 0 : rampStep * rampWk));

    // What the blocks already held will pay this week, before any buying.
    const running = rows.reduce((s, r) => s + ((r.write?.credit) ?? 0), 0);
    const shortfall = Math.max(0, target - running);
    const buyers = rows.filter((r) => r.can_buy && r.atm_straddle && r.spot);
    const per = buyers.length ? shortfall / buyers.length : 0;

    for (const r of rows) {
      const eligible = r.can_buy && r.atm_straddle && r.spot;
      if (!eligible || per <= 0) { r.buy = null; continue; }
      const ct = Math.round(per / (Number(r.atm_straddle) * 100));
      if (ct < 1) { r.buy = null; continue; }
      r.buy = {
        contracts: ct,
        shares: ct * 100,
        cost: Math.round(ct * 100 * Number(r.spot)),
        adds: Math.round(Number(r.atm_straddle) * 100 * ct),
        strike: r.atm_pair_strike,
        line: `Buy ${(ct * 100).toLocaleString('en-US')} shares, ${usd(ct * 100 * Number(r.spot))}`
              + `, to add ${usd(Number(r.atm_straddle) * 100 * ct)} a week.`,
      };
    }

    /* ── THE CARD, exactly as Claude Design specified it ─────────────────────
       Anatomy per position: numbered eyebrow + state chip · hero figure + unit
       line · two bullets (the trade, the floor) · open space · next earnings ·
       a band of three (collected, commits, effective cost) · a foot carrying the
       one graphic on the screen, the 52-week range · freshness stamp.

       The vertical list I built first was replaced by the design's horizontal
       snap rail. I had argued a rail hides the third-ranked name; the design
       answers that by putting the rank in the eyebrow as 01/02/03 and stating
       the basis above the rail, so the ordering survives being scrolled.

       `forecast` is the field that keeps a projection from being mistaken for a
       record: it dashes the hero underline and hollows the stamp dot. Do not
       drop it because "the text already says forecast" — the text is the part
       nobody reads twice. */
    for (const r of rows) {
      const fc = r.ranked_on !== 'earned';
      const w = r.write as Record<string, any> | null;
      const f = r.floor as Record<string, any> | null;
      const noShares = (r.shares ?? 0) <= 0;

      const chip = r.verdict === 'poor week to sell' ? { chip: 'Poor week', fill: true }
        : r.verdict === 'rich, but near the high' ? { chip: 'Near the high', fill: true }
        : r.verdict === 'no read' ? { chip: 'No read', fill: false }
        : { chip: 'Good week', fill: false };

      const trade = w
        ? 'Write ' + [
            (w.puts ?? 0) > 0 ? `${w.puts} puts ${w.put_strike}` : null,
            (w.calls ?? 0) > 0 ? `${w.calls} calls ${w.call_strike}` : null,
          ].filter(Boolean).join(' · ')
          + ` · ${dayShort(r.expiry)} for ${usd(w.credit ?? 0)}.`
        : (r.buy?.line)
          ? String(r.buy.line)
          /* A HARD BLOCK OUTRANKS "no shares yet".
             LULU came back reading "No shares yet, nothing to write against" when
             the actual reason it had nothing to do was its 27 Aug print landing
             inside the margin week. Both were true; only one explains why there
             is no buy line under it either. Having no shares is the condition the
             ramp exists to fix, so it is never the interesting half. */
          : (r.why ?? []).find((w) => !String(w).startsWith('no shares'))
            ? `Skipping · ${(r.why ?? []).find((w) => !String(w).startsWith('no shares'))}.`
            : 'No shares yet, nothing to write against.';

      const floorBullet = f
        ? `Floor ${f.strike} ${monShort(f.expiry)} · ${Math.round(f.gap_pct ?? 0)}% below the price · `
          + (f.funded ? 'paid for.' : `${Math.round(f.funded_pct ?? 0)}% paid for.`)
        : 'No floor yet.';

      const prem = r.premium_collected ?? 0, commits = r.put_commitment ?? 0;
      r.card = {
        n: String(r.rank ?? 0).padStart(2, '0'),
        sym: r.ticker,
        price: r.spot != null ? Number(r.spot).toFixed(2) : '',
        ...chip,
        forecast: fc,
        hero: fc
          ? (r.quoted_yield != null ? `${Number(r.quoted_yield).toFixed(1)}%` : '—')
          : `${Number(r.earned_per_week).toFixed(2)}%`,
        unit: fc
          ? (noShares ? 'forecast for this week · no shares yet' : 'forecast for this week')
          : `cash a week per dollar · ${Math.round(r.share_of_sleeve ?? 0)}% of the group`,
        bullets: [trade, floorBullet],
        earn: r.earnings
          ? `${dayShort(r.earnings)} · ${r.earnings_in_days} days`
            + (String(r.earnings) <= String(r.expiry) ? ' · inside this expiry'
               : r.earnings_soon ? ' · the week after' : '')
          : 'no date on file',
        band: [
          { k: 'Collected', v: prem > 0 ? usd(prem) : 'nothing yet', text: prem <= 0 },
          { k: 'Commits', v: commits > 0 ? usd(commits) : 'nothing', text: commits <= 0, mark: commits > 0 },
          { k: 'Eff. cost', v: noShares ? 'nothing yet' : Number(r.current_avg).toFixed(2), text: noShares },
        ],
        foot: {
          lab: 'Where it sits · 52w range',
          fig: r.new_low ? 'At the low' : `${Math.round(r.pos52 ?? 0)}%`,
          sub: r.new_low ? '52-week low' : 'up the range',
          pct: Math.max(0, Math.min(100, Math.round(r.pos52 ?? 0))),
          line: [
            r.trend?.ma50 != null
              ? `${Number(r.spot) >= Number(r.trend.ma50) ? '▲ above' : '▼ below'} the 50 day` : null,
            r.trend?.rsi != null ? `RSI ${r.trend.rsi}` : null,
          ].filter(Boolean).join(' · '),
        },
        stamp: {
          text: fc ? 'forecast · nothing collected yet' : 'updated now · cash collected',
          forecast: fc,
        },
      };
    }

    const commit = rows.reduce((s, r) => s + (r.put_commitment ?? 0), 0);
    // The floors are shown as a NEGATIVE line. Selling ATM puts on a block you
    // already own roughly DOUBLES what you are liable for, and one "committed"
    // figure hid that. The floor truncates the bottom; it does not remove it.
    const floors = rows.reduce((s, r) => {
      const f = r.floor;
      return s + (f ? Number(f.strike) * 100 * Number(f.contracts ?? 0) : 0);
    }, 0);

    return json(200, {
      ok: true,
      build: BUILD,
      asof: todayISO,
      expiry,
      market: mkt ?? marketState(new Date()),
      /* ── THE HEADER ──────────────────────────────────────────────────────────
         Changed 2026-08-16 from an exposure header to a standing header. It used
         to lead with stock, put commitment and NET AT RISK. Nik removed the net
         figure: put commitment is on every row, so the doubling is still visible
         name by name, and a $1.02m headline on a screen he checks daily was noise
         rather than information.

         What it answers now: what went in, what came back, what the shares really
         cost after all that premium, and whether the protection has paid for
         itself yet. */
      portfolio: {
        invested: Math.round(rows.reduce((s, r) => s + (r.shares ?? 0) * (r.avg_buy ?? 0), 0)),
        collected: Math.round(rows.reduce((s, r) => s + (r.premium_collected ?? 0), 0)),
        // The blended average, as a percent BELOW what the shares cost. One number
        // across the sleeve, weighted by shares, so a big block cannot be flattered
        // by a small one that happens to be doing well.
        average_below_pct: (() => {
          const cost = rows.reduce((s, r) => s + (r.shares ?? 0) * (r.avg_buy ?? 0), 0);
          const prem = rows.reduce((s, r) => s + (r.premium_collected ?? 0), 0);
          return cost > 0 ? Math.round(1000 * prem / cost) / 10 : null;
        })(),
        floor_cost: Math.round(rows.reduce((s, r) => s + (r.floor_cost ?? 0), 0)),
        // What the protection costs as a SHARE OF INCOME, and how many weeks of
        // writing pay for it. On AVGO that was about 7% of the premium buying a
        // third off the worst case, which is the whole argument for the floor.
        floor_pct_of_premium: (() => {
          const fc = rows.reduce((s, r) => s + (r.floor_cost ?? 0), 0);
          const prem = rows.reduce((s, r) => s + (r.premium_collected ?? 0), 0);
          return prem > 0 && fc > 0 ? Math.round(100 * fc / prem) : null;
        })(),
        floor_weeks_to_pay: (() => {
          const fc = rows.reduce((s, r) => s + (r.floor_cost ?? 0), 0);
          const wk = rows.reduce((s, r) => s + ((r.write?.credit) ?? 0), 0);
          return fc > 0 && wk > 0 ? Math.ceil(fc / wk) : null;
        })(),
        stock, put_commitment: commit,
        premium_this_week: rows.reduce((s, r) => s + ((r.write?.credit) ?? 0), 0),
        ramp_week: rampWk + 1,
        ramp_target: target,
        ramp_paused: paused,
        ramp_shortfall: Math.round(shortfall),
        buy_cost: Math.round(rows.reduce((s, r) => s + (r.buy?.cost ?? 0), 0)),
        expiring_friday: rows.reduce((s, r) => s + (r.open_calls ?? 0) + (r.open_puts ?? 0), 0),
      },
      /* ── THE SLEEVE CARD, the design's wide header ───────────────────────────
         Same anatomy as a position card, full width, no foot: eyebrow, hero,
         two bullets, band of three, stamp. It answers what is collectable this
         week, how the money is split across the names, and whether the floors
         have paid for themselves.

         The bullets carry the balance INTU 34% · NKE 33% · LULU 30%, which is
         what replaced target_shares. Note it is a share of money invested, not
         of some intended size: there is no intended size any more. */
      head: (() => {
        const invested = Math.round(rows.reduce((s, r) => s + (r.shares ?? 0) * (r.avg_buy ?? 0), 0));
        const prem = Math.round(rows.reduce((s, r) => s + (r.premium_collected ?? 0), 0));
        const fc = Math.round(rows.reduce((s, r) => s + (r.floor_cost ?? 0), 0));
        // The hero is what this week collects IF the screen is followed, so it
        // counts the buys it is telling him to make. On an empty book the
        // existing blocks pay nothing, and a $0 headline over three cards each
        // saying "buy" would be the screen arguing with itself.
        const planned = rows.reduce((s, r) => s + (r.buy?.adds ?? 0), 0);
        const week = rows.reduce((s, r) => s + ((r.write?.credit) ?? 0), 0) + planned;
        const below = invested > 0 ? Math.round(1000 * prem / invested) / 10 : null;
        const weeks = fc > 0 && week > 0 ? Math.ceil(fc / week) : null;
        const held = rows.filter((r) => (r.shares ?? 0) > 0);
        return {
          n: 'Sleeve', sym: `${rows.length} names`, chip: dayShort(expiry),
          hero: usd(week),
          unit: `to collect this week · writes ${dayShort(expiry)}`,
          bullets: [
            // The rung, always first: it is the instruction the rest follows from.
            `Week ${rampWk + 1} of the ramp · target ${usd(target)}`
              + (paused ? ' · held here' : '')
              + (planned > 0 ? ` · ${usd(planned)} of it from buying.` : '.'),
            held.length
              ? held.map((r) => `${r.ticker} ${Math.round(r.share_of_sleeve ?? 0)}%`).join(' · ')
                + ' of the money invested.'
              : 'No shares yet, so nothing is invested.',
            fc > 0
              ? `Floors ${usd(fc)} · ${Math.round(100 * fc / Math.max(prem, 1))}% of the cash · `
                + `${weeks} week${weeks === 1 ? '' : 's'} pays for them.`
              : 'No floors yet, nothing to pay back.',
          ].slice(0, held.length ? 3 : 2),
          band: [
            { k: 'Invested', v: usd(invested) },
            { k: 'Collected', v: usd(prem), mark: prem > 0 },
            { k: 'Below cost', v: below != null ? `${below.toFixed(1)}%` : 'none yet', text: below == null },
          ],
          stamp: `updated now · ${dayShort(todayISO)}`,
        };
      })(),
      // The label above the rail, and the sentence under it saying which of the
      // two bases produced the order. A forecast and a track record must never be
      // mistakable for one another.
      grp: rows.some((r) => r.ranked_on === 'earned') ? 'Ranked on cash collected' : 'Ranked on forecast',
      basis: rows.some((r) => r.ranked_on === 'earned')
        ? `Cash a week per dollar invested, since ${dayShort(rows.find((r) => r.started_on)?.started_on)}.`
        : "Nothing collected yet, so the order is this week's forecast.",
      // The footer. A note, not a total: these blocks are the tool, not the holding.
      note: 'These are trading positions. Every put here is a promise to buy at the '
          + 'strike, and the calls can take the shares away.',
      names: rows,
    });
  } catch (e) {
    return json(500, { ok: false, error: String(e) });
  }
});
