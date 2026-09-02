/**
 * sunny-rail — the facts on the always-on dock.
 *
 * Chrome, not feed. CHROME.md §2 and handoff/cards/text-rail.md.
 *
 * ⚠ THE SPEC'S FIGURES ARE THE DESIGN'S, NOT NIK'S. The build sheet ships
 * "Invested $400k at 4.5%", "TLT div in 2d $1,240 .33/sh", "US 10y 4.42%".
 * Those are the reference card's numbers. Hard-coding them would put four false
 * figures on the dock of a real book, so every one is sourced:
 *
 *   invested   sum(qty_remaining x cost_per_share) over every open lot
 *   TLT div    last ex-date and per-share from `dividends`, shares from the
 *              lots, next date projected forward at its own frequency
 *   US 10y     DGS10 from `rates_daily`
 *
 * ⚠ THE YIELD IS OPEN PREMIUM, AND ONLY OPEN. Nik: "it should always be current
 * not past so open." So the numerator is the premium collected on short legs
 * that are STILL OPEN and not yet expired, never a trailing window.
 *
 * That rule also dodges a real trap. Premium over a fixed past window computed
 * as opens minus closes reads NEGATIVE — 28 days came out at −$48,428 — because
 * closes landing inside the window mostly belong to positions opened before it,
 * so the money going out is counted without the money that came in. Any
 * windowed premium figure has to be opens-only or it lies. Open legs have no
 * window at all, so the question does not arise.
 *
 * Long puts are excluded: `direction=short` only. The floor is bought, not sold,
 * and Nik's instruction was to ignore it here.
 *
 * The spec's own "4.5%" was an example, not a target. On this book the figure
 * is ~2.4%. Do not tune toward 4.5.
 */
import { corsHeaders, json, db, ymd, parseISO, addDays, nyToday } from
  'https://raw.githubusercontent.com/nikparekh123/sunny-flow-tasks/dd3c85a56102451ae439016d6a90460c4d41dab0/supabase/functions/_shared/planner.ts';

const BUILD = '2026-08-27.1';
const N = (v: unknown, d = 0) => (v === null || v === undefined || v === '' ? d : Number(v));

/** The rail abbreviates money: $400k, never $400,000. */
function money(v: number): string {
  const a = Math.abs(Math.round(v));
  if (a >= 1_000_000) return `$${(a / 1_000_000).toFixed(1)}m`;
  if (a >= 1_000) return `$${Math.round(a / 1000)}k`;
  return `$${a.toLocaleString('en-US')}`;
}

/* ── the book, for the shell's section headings ────────────────────────────
   SHELL.md §7: a name heading is ticker + full company name + weight, and the
   names run largest position first. That is chrome the shell cannot compute on
   its own — it holds cards, not lots — so it is served here, beside the rail
   facts it already fetches, rather than in a second call.

   ⚠ ADDITIVE ONLY. `book` is a new key. Nothing above it changed shape, because
   a build already on the phone decodes this response and a removed field throws
   keyNotFound there. That mistake has been made once.

   Weight is COST, not market value: the same basis the invested fact on the
   dock is drawn on, so a heading can never disagree with the number two rows
   below it. */
const NAMES = new Map<string, string>();

/* ⚠ POLYGON'S OWN CASING IS WRONG FOR SOME NAMES, and it is the heading on a
   whole page, so it gets corrected here rather than lived with. NFLX comes back
   as "NetFlix Inc" and the company writes itself Netflix.

   ⚠ AND IT HAS TO BE AN OVERRIDE, NOT A CASING RULE. Title-casing everything
   would break iShares, which Polygon gets RIGHT — a lowercase first letter is
   the brand. Any general normaliser has to know which is which, which is what
   this map is. Add a row when a name is wrong; do not write a rule. */
const NAME_FIX = new Map<string, string>([
  ['NFLX', 'Netflix, Inc.'],
]);

async function companyName(t: string, k: string): Promise<string> {
  const fix = NAME_FIX.get(t);
  if (fix) return fix;
  const hit = NAMES.get(t);
  if (hit !== undefined) return hit;
  try {
    // NOT /v3/reference/ticker-details, which 404s.
    const r = await fetch(`https://api.polygon.io/v3/reference/tickers/${t}?apiKey=${k}`);
    if (!r.ok) { NAMES.set(t, t); return t; }
    const j = await r.json();
    const n = String(j?.results?.name ?? '').trim();
    NAMES.set(t, n || t);
    return n || t;
  } catch { return t; }
}

type Span = { text: string; kind: 'word' | 'figure' | 'minor' };

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  try {
    /* `peek` skips the daily delta stamp. A probe should be able to read the
       book without writing a reading into its history. */
    let body: { peek?: boolean } = {};
    try { if (req.method === 'POST') body = await req.json(); } catch { /* none */ }
    const D = db(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    const today = parseISO(nyToday());

    const todayISO = ymd(today);
    /* Six closes, not five: five daily CHANGES need six levels, and the sixth is
       also the left end of the week range in the card's header. Ordered newest
       first here and kept that way all the way to the card, because
       five-day-price.md §0.2 puts the newest day on the LEFT. */
    const sinceISO = ymd(addDays(today, -21));   // 3 weeks covers holidays
    /* ⚠ EVERY SHORT LEG EVER, not just the open ones. The average card credits
       ALL premium written on a name, and a leg that has expired is exactly the
       premium that already came in. option_trades is past 680 rows and this
       project caps PostgREST at 1000 with no way to lift it, so page it. */
    async function getAll(path: string): Promise<Record<string, unknown>[]> {
      const out: Record<string, unknown>[] = [];
      for (let off = 0; ; off += 1000) {
        const page = await D.get(`${path}&limit=1000&offset=${off}`);
        out.push(...(page as Record<string, unknown>[]));
        if (page.length < 1000) return out;
      }
    }
    const [lots, divs, rates, shorts, closes, allShorts, quotes, openLegs, greeks,
           deltaPrior] = await Promise.all([
      D.get('share_lots?voided_at=is.null&qty_remaining=gt.0&select=ticker,qty_remaining,cost_per_share'),
      D.get('dividends?ticker=eq.TLT&select=ex_date,cash_amount,frequency&order=ex_date.desc&limit=1'),
      D.get('rates_daily?series=eq.DGS10&select=date,value&order=date.desc&limit=1'),
      D.get(`option_trades?voided_at=is.null&direction=eq.short&expiry=gte.${todayISO}`
        + '&select=ticker,option_type,strike,expiry,action,contracts,premium'),
      D.get(`daily_closes?date=gte.${sinceISO}&select=ticker,date,close_price`
        + '&order=date.desc'),
      getAll('option_trades?voided_at=is.null&direction=eq.short&order=id.asc'
        + '&select=ticker,action,contracts,premium'),
      D.get('ticker_quotes_latest?select=ticker,spot'),
      getAll(`option_trades?voided_at=is.null&expiry=gte.${todayISO}&order=id.asc`
        + '&select=id,ticker,direction,action,contracts,option_type,strike,expiry,premium'),
      D.get('option_greeks_latest?select=option_trade_id,delta,last_mark'),
      /* Every prior reading, newest first — the "since yesterday" support line
         compares against the most recent day BEFORE today, which is not
         necessarily yesterday if he skipped a day. */
      D.get(`delta_history?snapshot_date=lt.${todayISO}`
        + '&select=ticker,snapshot_date,net_delta&order=snapshot_date.desc'),
    ]);

    const facts: Array<{ key: string; spans: Span[]; projected?: boolean }> = [];

    /* ⚠ CAPITAL COMMITTED, NOT SHARE COST. The book was share cost alone, so
       a name whose shares are sold and replaced by long calls DISAPPEARED
       from the strip: no circle, therefore no page, therefore no news. Five
       names went that way in one afternoon. Weight now counts what was
       actually paid — share cost plus net premium on open LONG legs — which
       is the meaning the label always had, extended to the instrument that
       now holds the position.

       `invested` moves with it deliberately. The header comment above
       promises a heading can never disagree with the dock fact two rows
       below it, and that only holds if both are drawn on the same basis. */
    const byTicker = new Map<string, number>();
    for (const l of lots) {
      const t = String(l.ticker);
      byTicker.set(t, (byTicker.get(t) ?? 0) + N(l.qty_remaining) * N(l.cost_per_share));
    }
    /* ⚠ NET ON THE CONTRACT KEY FIRST, then count only what is still open.
       Summing signed premium per TICKER instead put NVDA in the book at
       $71,489 with zero contracts outstanding: on a fully closed position the
       signed sum is not capital committed, it is realised P&L wearing its
       coat. Same trap the openPremium map below already avoids. */
    const longLeg = new Map<string, { net: number; paid: number; t: string }>();
    for (const t of openLegs) {
      if (String(t.direction) !== 'long') continue;
      const k = `${t.ticker}|${t.option_type}|${N(t.strike)}|${String(t.expiry).slice(0, 10)}`;
      const e = longLeg.get(k) ?? { net: 0, paid: 0, t: String(t.ticker) };
      const sign = String(t.action) === 'open' ? 1 : -1;
      e.net += sign * N(t.contracts);
      e.paid += sign * N(t.contracts) * N(t.premium) * 100;
      longLeg.set(k, e);
    }
    for (const e of longLeg.values()) {
      if (e.net <= 0.0001) continue;
      byTicker.set(e.t, (byTicker.get(e.t) ?? 0) + e.paid);
    }
    /* A name that nets to zero or below has been closed out, not held. */
    const invested = [...byTicker.values()].reduce((s, v) => s + Math.max(v, 0), 0);

    /* One row per name with capital in it, largest first. A name with no
       lots is absent rather than shown at 0% — the shell hides a heading with
       no card under it anyway, and a 0% row would claim a position he closed. */
    /* ── the five-day week, per name ──────────────────────────────────────
       The card charts daily CHANGE against a zero line, never price level: five
       price levels at this size are five identical bars, and the shape of the
       week is the whole point. So the server sends changes, and it sends both
       units because a tap swaps between them without refetching.

       Percent and dollar are both computed HERE. Deriving the dollar on the
       client from a rounded percent reproduces it wrong by a cent or two, and
       the card prints them side by side across a tap. */
    const byName = new Map<string, Array<{ date: string; close: number }>>();
    for (const r of closes) {
      const t = String(r.ticker);
      const c = N(r.close_price);
      if (!(c > 0)) continue;
      const a = byName.get(t) ?? [];
      if (a.length < 6) a.push({ date: String(r.date).slice(0, 10), close: c });
      byName.set(t, a);
    }
    const DOW = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    function week(t: string) {
      const a = byName.get(t) ?? [];
      if (a.length < 2) return null;
      const days = [];
      for (let i = 0; i < Math.min(5, a.length - 1); i++) {
        const c = a[i].close, p = a[i + 1].close;
        days.push({
          day: DOW[parseISO(a[i].date).getUTCDay()],
          date: a[i].date,
          pct: Math.round((c - p) / p * 10000) / 100,
          usd: Math.round((c - p) * 100) / 100,
        });
      }
      if (!days.length) return null;
      /* The header's two ends and the footer's "On the week" are ONE span, and
         it is the span the five bars actually cover: the close before the
         oldest bar, through the newest close. Quoting a 5-session range beside
         bars that show 5 changes would be off by one day. */
      const from = a[days.length].close, to = a[0].close;
      const pcts = days.map((d) => d.pct);
      return {
        /* Oldest first — see the note on the fetch above. */
        days: days.reverse(),
        from, to,
        week_pct: Math.round((to - from) / from * 10000) / 100,
        best: Math.max(...pcts),
        worst: Math.min(...pcts),
      };
    }

    /* ── the average price, one per name ──────────────────────────────────
       ⚠ PREMIUM, NOT REALIZED. Nik chose this on 26 Aug over the glossary's
       NEW AVERAGE, which subtracts REALIZED instead. The two disagree hard on
       this book — NKE reads 37.79 under spot one way and 44.41 over it the
       other, and five of nine cards change colour between them.

       This is the income sleeve's own number and the one he watches: what the
       block has cost after every dollar of premium written against the name.
       It walks down every week he writes, which is the thing the sleeve exists
       to show. The glossary's version answers a different question, and the
       page heading's Total already answers that one.

       ⚠ ALL-TIME PREMIUM, not premium since the current block opened. Those
       differ a lot — NKE's block is days old while its premium history runs to
       months — and all-time is what he approved.

       Known cost, accepted: it credits premium on shorts that are STILL OPEN,
       so an average can improve on paper and give some back when a leg is
       bought in. The glossary calls that flattering; here it is deliberate. */
    const premBy = new Map<string, number>();
    for (const t of allShorts) {
      const k = String(t.ticker);
      const sign = t.action === 'open' ? 1 : -1;
      premBy.set(k, (premBy.get(k) ?? 0) + sign * N(t.contracts) * N(t.premium) * 100);
    }
    const shareBy = new Map<string, { qty: number; cost: number; lots: number }>();
    for (const l of lots) {
      const t = String(l.ticker);
      const e = shareBy.get(t) ?? { qty: 0, cost: 0, lots: 0 };
      e.qty += N(l.qty_remaining);
      e.cost += N(l.qty_remaining) * N(l.cost_per_share);
      e.lots += 1;
      shareBy.set(t, e);
    }
    const spotBy = new Map<string, number>();
    for (const q of quotes) {
      const v = N(q.spot);
      if (v > 0) spotBy.set(String(q.ticker), v);
    }
    function average(ticker: string) {
      const sh = shareBy.get(ticker);
      if (!sh || !(sh.qty > 0)) return null;
      const paid = sh.cost / sh.qty;
      const avg = paid - (premBy.get(ticker) ?? 0) / sh.qty;
      const spot = spotBy.get(ticker) ?? 0;
      return {
        shares: Math.round(sh.qty),
        /* The S card's right-hand label says what the average covers. The
           handoff's specimen reads "Both lots"; generalised, it is the count. */
        lots: sh.lots,
        cost: Math.round(sh.cost),
        paid: Math.round(paid * 100) / 100,
        average: Math.round(avg * 100) / 100,
        spot: Math.round(spot * 100) / 100,
        /* Both percentages name their reference because they move
           independently: one is premium against what he paid, the other is the
           resulting basis against the market. Neither can be the silent
           default, which is why the card's reference line has two cells. */
        vs_paid: paid > 0 ? Math.round((avg / paid - 1) * 1000) / 10 : 0,
        vs_spot: spot > 0 ? Math.round((avg / spot - 1) * 1000) / 10 : 0,
      };
    }

    /* ── net delta, one per name ──────────────────────────────────────────
       The position's directional exposure expressed in SHARES: what he is
       actually long or short once the options are counted.

         net = shares + Σ (long ? +1 : −1) × contracts × 100 × delta

       Polygon's delta is already signed by option type, so a put arrives
       negative and the direction factor is the only thing this has to supply.
       Each of the four cases then falls out without a special case: a short call
       reduces exposure, a short put adds it, a long put reduces it.

       ⚠ A POSITIVE DELTA IS NOT A GAIN. It is a direction, and the cards carry
       no green anywhere for exactly that reason. Only a SHORT takes colour.

       ⚠ A LEG WITH NO DELTA SUPPRESSES THE WHOLE NAME. A missing greek is not a
       zero: NKE's 10 short 38.5 puts, filled minutes ago and not yet marked,
       are worth roughly +250 shares of exposure, and counting them as nothing
       would print 1,060 where the truth is nearer 1,310. Same rule the rest of
       the deck follows — no price, no week. The greeks cron fills it within the
       quarter hour, so the name comes back on its own. */
    const deltaById = new Map<string, number>();
    for (const g of greeks) {
      const v = g.delta;
      if (v !== null && v !== undefined) deltaById.set(String(g.option_trade_id), N(v));
    }
    const legDelta = new Map<string, { d: number; missing: number }>();
    for (const t of openLegs) {
      const tick = String(t.ticker);
      const e = legDelta.get(tick) ?? { d: 0, missing: 0 };
      const dl = deltaById.get(String(t.id));
      if (dl === undefined) { e.missing += 1; legDelta.set(tick, e); continue; }
      const dir = String(t.direction) === 'long' ? 1 : -1;
      const open = t.action === 'open' ? 1 : -1;
      e.d += dir * open * N(t.contracts) * 100 * dl;
      legDelta.set(tick, e);
    }
    function netDelta(ticker: string) {
      const sh = shareBy.get(ticker);
      if (!sh || !(sh.qty > 0)) return null;
      const e = legDelta.get(ticker);
      if (e && e.missing > 0) return null;          // see the note above
      const net = Math.round(sh.qty + (e?.d ?? 0));
      const spot = spotBy.get(ticker) ?? 0;
      const was = priorDelta.get(ticker);
      return {
        net,
        short: net < 0,
        /* The most recent reading BEFORE today, and its date. Null on a name
           whose first snapshot is today — the card then says "opened today"
           rather than inventing a change from nothing. */
        prior: was ? was.d : null,
        prior_on: was ? was.on : null,
        change: was ? net - was.d : null,
        /* The position's NOTIONAL, and the card names it `exposure` because a
           signed dollar figure in this deck otherwise reads as P&L. */
        exposure: Math.round(net * spot),
      };
    }

    /* ── the open short book, for the New page's three figures ────────────
       What he was paid to write the options still open, what it would cost to
       buy them back, and how much of that cost is time rather than moneyness.

         credit    Σ contracts × premium × 100        what he received
         value     Σ contracts × mark × 100           what it costs to close
         intrinsic Σ contracts × max(0, ITM) × 100    the part that will not decay
         time      value − intrinsic                  the part that will

       ⚠ TIME VALUE IS THE EXTRINSIC PART, confirmed by Nik 26 Aug. It is the
       only one of the three he actually earns by waiting; intrinsic is settled
       by where the stock is, not by the clock. On this book intrinsic is nearly
       four fifths of the cost to close — $9,188 of $11,830, almost all of it
       NKE's 40.5 puts and BABA — so the two figures are far apart and the gap is
       the interesting part.

       ⚠ NONE OF THE THREE IS A DIRECTION, so none takes gain or loss ink. The
       deck reserves colour for direction, and a balance is not one. */
    const markById = new Map<string, number>();
    /* ⚠ THE SPOT THE MARK WAS QUOTED AGAINST, when we have it. Polygon's option
       snapshot carries its own underlying price, and mp-refresh now stamps it
       beside the mark, so intrinsic is computed against the two halves of ONE
       quote rather than against a stock snapshot on a different clock. */
    const underById = new Map<string, number>();
    for (const g of greeks) {
      const v = g.last_mark;
      if (v !== null && v !== undefined) markById.set(String(g.option_trade_id), N(v));
      const u = (g as { underlying?: number | null }).underlying;
      if (u !== null && u !== undefined && N(u) > 0) underById.set(String(g.option_trade_id), N(u));
    }
    const shortLeg = new Map<string, {
      net: number; credit: number; mark: number; itm: number;
    }>();
    for (const t of openLegs) {
      if (String(t.direction) !== 'short') continue;
      const tick = String(t.ticker);
      const key = `${tick}|${t.option_type}|${N(t.strike)}|${String(t.expiry).slice(0, 10)}`;
      const e = shortLeg.get(key) ?? { net: 0, credit: 0, mark: 0, itm: 0 };
      const sign = t.action === 'open' ? 1 : -1;
      e.net += sign * N(t.contracts);
      /* ⚠ THE MARK AND ITS SPOT ARE TAKEN TOGETHER OR NOT AT ALL. A leg is
         several trade rows — an open, a partial buy-back — and only the rows
         mp-refresh still refreshes carry a mark. Reading the spot outside this
         guard let a later unmarked row overwrite the intrinsic, pairing one
         row's mark with another row's spot, which is the exact thing the stamp
         exists to prevent. */
      const mk = markById.get(String(t.id));
      if (mk !== undefined) {
        e.mark = mk;
        /* Fall back to the latest quote for rows captured before 27 Aug 2026
           and for any snapshot Polygon returned without an underlying price. */
        const spot = underById.get(String(t.id)) ?? spotBy.get(tick) ?? 0;
        e.itm = spot > 0
          ? Math.max(0, String(t.option_type) === 'put'
              ? N(t.strike) - spot : spot - N(t.strike))
          : 0;
      }
      shortLeg.set(key, e);
    }
    /* The credit comes from the same netted short rows the premium map is built
       from, so a leg bought back contributes nothing here either. */
    const creditBy = new Map<string, number>();
    for (const t of shorts) {
      const k = `${t.ticker}|${t.option_type}|${N(t.strike)}|${String(t.expiry).slice(0, 10)}`;
      creditBy.set(k, (creditBy.get(k) ?? 0) + N(t.contracts) * N(t.premium) * 100
        * (t.action === 'open' ? 1 : -1));
    }
    /* ⚠ TIME VALUE CANNOT BE NEGATIVE, AND IT IS CLAMPED PER LEG, NOT ON THE
       TOTAL. The mark and the spot come from two different feeds on two
       different clocks — option_greeks_latest is a 15-minute cron, ticker
       quotes have their own cadence — so on a deep-ITM leg, whose extrinsic is
       a few cents to begin with, a small drift between the two makes the
       computed intrinsic exceed the mark. Three legs did on 27 Aug (CEG 272.5
       −$14, NKE 40.5 −$110, PEP 144 −$140) and the book's time value came out
       $264 light at $2,537 instead of $2,801.

       Clamping the TOTAL would hide it; clamping each leg is the true statement,
       because the error is per leg and a leg that is all intrinsic has zero time
       value, never negative. Intrinsic takes the same clamp from the other side
       so the two still sum to the value exactly — an identity the card depends
       on, since it prints both.

       ⚠ IT IS A FLOOR, AND IT STAYS EVEN NOW THE SPOT IS STAMPED. The drift is
       addressed at the source — option_greeks.underlying carries the price
       Polygon quoted beside the mark, so intrinsic is now the two halves of one
       quote — but every row captured before 27 Aug 2026 has none, and Polygon
       can omit it. Those fall back to the latest quote and can still drift, so
       the invariant is kept here rather than assumed upstream. */
    let oCredit = 0, oValue = 0, oItm = 0, oCtr = 0;
    for (const [k, e] of shortLeg) {
      if (!(e.net > 0.0001)) continue;
      oCtr += e.net;
      oCredit += creditBy.get(k) ?? 0;
      const value = e.net * e.mark * 100;
      oValue += value;
      oItm += Math.min(e.net * e.itm * 100, value);
    }
    const openShorts = {
      contracts: Math.round(oCtr),
      credit: Math.round(oCredit),
      /* ⚠ TOTAL VALUE LEFT is the whole mark, intrinsic included — everything
         still standing in the open shorts. Time value is the subset of it that
         decays. Nik picked this reading on 26 Aug over "credit less cost to
         close", which is what has been captured rather than what is left. */
      value: Math.round(oValue),
      intrinsic: Math.round(oItm),
      time_value: Math.round(oValue - oItm),
    };

    /* ── the three option lists ───────────────────────────────────────────
       ONE ROW PER LEG, so a name with two strikes of the same kind appears
       twice — Nik, 27 Aug: "it will still be one row, but we'll just have to
       repeat that row". A row's figure IS the strike, so it can only carry one;
       NKE holds 40.5 and 38.5 puts sold, and TLT 75 and 80 puts bought.

       ⚠ MONEYNESS IS AGAINST SPOT, never against the strike. Both denominators
       are live and they differ; the sheet fixes spot (§0.6) and the M card
       prints spot beside the figure so the arithmetic is auditable.

       ⚠ THE EXCEPTION TEST IS DIRECTION-AWARE. A call sold is an exception when
       it is IN the money; a put sold when the cost to close has passed the
       credit taken; a put bought never — protection cannot be underwater the
       way a short can, which is why that list's header carries a count in grey
       rather than an exception in red. */
    type LegRow = {
      ticker: string; strike: number; expiry: string; contracts: number;
      itm: boolean; moneyness: number; opened: number; now: number;
      exception: boolean;
    };
    const legBy = new Map<string, {
      ticker: string; type: string; short: boolean; strike: number; expiry: string;
      net: number; cash: number; mark: number;
    }>();
    for (const t of openLegs) {
      const tick = String(t.ticker);
      const short = String(t.direction) === 'short';
      const type = String(t.option_type);
      const strike = N(t.strike);
      const expiry = String(t.expiry).slice(0, 10);
      const key = `${tick}|${type}|${strike}|${expiry}|${short}`;
      const e = legBy.get(key)
        ?? { ticker: tick, type, short, strike, expiry, net: 0, cash: 0, mark: 0 };
      const sign = t.action === 'open' ? 1 : -1;
      e.net += sign * N(t.contracts);
      const mk = markById.get(String(t.id));
      if (mk !== undefined) e.mark = mk;
      legBy.set(key, e);
    }
    /* What the leg took in or cost, netted over its own open and close rows, so
       a partial buy-back reduces it rather than being counted twice. The same
       fetch carries both directions, so a credit and a debit are one formula
       and only the label differs on the card. */
    const cashByKey = new Map<string, number>();
    for (const t of openLegs) {
      const tick = String(t.ticker);
      const short = String(t.direction) === 'short';
      const key = `${tick}|${t.option_type}|${N(t.strike)}|${String(t.expiry).slice(0, 10)}|${short}`;
      const sign = t.action === 'open' ? 1 : -1;
      cashByKey.set(key, (cashByKey.get(key) ?? 0) + sign * N(t.contracts) * N(t.premium) * 100);
    }
    const callsSold: LegRow[] = [], putsSold: LegRow[] = [], putsBought: LegRow[] = [];
    for (const [key, e] of legBy) {
      if (!(e.net > 0.0001)) continue;
      const spot = spotBy.get(e.ticker) ?? 0;
      if (!(spot > 0)) continue;
      const itm = e.type === 'call' ? spot > e.strike : spot < e.strike;
      const row: LegRow = {
        ticker: e.ticker, strike: e.strike, expiry: e.expiry,
        contracts: Math.round(e.net),
        itm,
        moneyness: Math.round(Math.abs(spot - e.strike) / spot * 1000) / 10,
        opened: Math.round(Math.abs(cashByKey.get(key) ?? 0)),
        now: Math.round(e.net * e.mark * 100),
        exception: false,
      };
      if (e.short && e.type === 'call') { row.exception = itm; callsSold.push(row); }
      else if (e.short) { row.exception = row.now > row.opened; putsSold.push(row); }
      else if (e.type === 'put') { putsBought.push(row); }
    }
    /* Exceptions first, then alphabetical, then by strike so a name that
       repeats keeps a stable order between its own rows. */
    const rank = (a: LegRow, b: LegRow) =>
      a.exception !== b.exception ? (a.exception ? -1 : 1)
        : a.ticker !== b.ticker ? a.ticker.localeCompare(b.ticker)
        : a.strike - b.strike;
    callsSold.sort(rank); putsSold.sort(rank); putsBought.sort(rank);

    /* ── if exercised, the ladder ─────────────────────────────────────────
       cards/exercise-ladder.md. A sold call and a sold put on ONE NAME CANNOT
       BOTH BE ASSIGNED — they are branches of one variable, where the price
       lands. So this is not a list of legs, it is a ladder of MUTUALLY
       EXCLUSIVE PRICE BANDS ordered high to low, and exactly one rung is true.

       The bands come from the distinct short strikes: n strikes make n+1 bands.
       Inside a band the outcome is constant, which is the whole reason the band
       is the unit — a short call at K is assigned for every price above K, a
       short put at K for every price below it, so a band whose floor is at or
       above K assigns that call and one whose ceiling is at or below K assigns
       that put. No representative price is ever picked.

       ⚠ THE BASIS USED IS `average`, NOT `paid`. Realized on a call assignment
       and the new average after a put both run off the premium-adjusted average
       the average price card prints, so the two cards can never tell him two
       different stories about the same block. It is not FIFO — the true lot
       basis differs — but the card that would disagree is the one on the same
       page, and this is the number that is on it. */
    function exercise(ticker: string) {
      const spot = spotBy.get(ticker) ?? 0;
      const a = average(ticker);
      if (!(spot > 0) || !a) return null;
      const shorts = [...legBy.values()]
        .filter((e) => e.ticker === ticker && e.short && e.net > 0.0001);
      if (!shorts.length) return null;

      const shares = a.shares, avg = a.average;
      const callLegs = shorts.filter((e) => e.type === 'call').length;
      const putLegs = shorts.length - callLegs;
      const strikes = [...new Set(shorts.map((e) => e.strike))].sort((x, y) => y - x);

      const rungs = strikes.concat([0]).map((_, i) => {
        /* hi = null above the top strike, lo = null below the bottom one. */
        const hi = i === 0 ? null : strikes[i - 1];
        const lo = i === strikes.length ? null : strikes[i];
        const on = shorts.filter((e) =>
          e.type === 'call' ? (lo !== null && lo >= e.strike)
                            : (hi !== null && hi <= e.strike));
        const calls = on.filter((e) => e.type === 'call');
        const puts = on.filter((e) => e.type === 'put');
        const out = calls.reduce((n, e) => n + Math.round(e.net) * 100, 0);
        const inn = puts.reduce((n, e) => n + Math.round(e.net) * 100, 0);
        const held = shares - out + inn;
        const cash = calls.reduce((n, e) => n + Math.round(e.net) * 100 * e.strike, 0)
                   - puts.reduce((n, e) => n + Math.round(e.net) * 100 * e.strike, 0);
        /* Shares sold leave at the average, so what stays behind keeps it and
           only the bought shares move the basis. */
        const kept = shares - out;
        const bought = puts.reduce((n, e) => n + Math.round(e.net) * 100 * e.strike, 0);
        const newAvg = held > 0 && inn > 0
          ? Math.round((kept * avg + bought) / held * 100) / 100 : null;
        const realized = out > 0
          ? Math.round(calls.reduce((n, e) =>
              n + Math.round(e.net) * 100 * (e.strike - avg), 0)) : null;

        /* ⚠ LIKELIHOOD IS A WORD AND IT COMES FROM MONEYNESS, NEVER FROM DELTA.
           Nik, 27 Aug: "the simpler the better, prefer OTM, ITM and ATM vs
           delta." Spot inside the band is the world we are in; a band whose
           nearest edge is within 5% of spot is one price move away; anything
           further is not. The threshold reproduces the handoff's own NKE
           ladder exactly — 2.8% Possible, 9.1% Unlikely. */
        const live = (lo === null || spot > lo) && (hi === null || spot <= hi);
        const edges = [lo, hi].filter((v): v is number => v !== null);
        const near = Math.min(...edges.map((v) => Math.abs(spot - v))) / spot * 100;
        const verdict = live ? 'likely' : near <= 5 ? 'possible' : 'unlikely';

        return {
          lo, hi, live, verdict,
          held, share_delta: held - shares, cash: Math.round(cash),
          calls: calls.length, puts: puts.length, call_legs: callLegs, put_legs: putLegs,
          /* Only the band where nothing is assigned prints a credit, and it
             credits EVERY leg that expires — crediting one set of two is the
             defect the sheet names. */
          credit: on.length === 0
            ? Math.round(shorts.reduce((n, e) => {
                const k = `${ticker}|${e.type}|${e.strike}|${e.expiry}|true`;
                return n + Math.abs(cashByKey.get(k) ?? 0);
              }, 0))
            : null,
          realized, new_avg: newAvg, old_avg: avg,
        };
      });
      return { legs: shorts.length, spot: Math.round(spot * 100) / 100, rungs };
    }

    /* ── net delta, day over day ──────────────────────────────────────────
       Written on every call, keyed on the day, so it is idempotent; a nightly
       cron covers a day he does not open the app. The support line compares
       against the most recent reading BEFORE today, which is not always
       yesterday. */
    const priorDelta = new Map<string, { d: number; on: string }>();
    for (const r of deltaPrior) {
      const t = String(r.ticker);
      if (priorDelta.has(t)) continue;          // ordered desc, first wins
      priorDelta.set(t, { d: N(r.net_delta), on: String(r.snapshot_date).slice(0, 10) });
    }

    const pk = Deno.env.get('POLYGON_API_KEY') ?? '';
    const book = await Promise.all(
      [...byTicker.entries()]
        .filter(([, v]) => v > 0)
        .sort((a, b) => b[1] - a[1])
        .map(async ([ticker, cost]) => ({
          ticker,
          name: pk ? await companyName(ticker, pk) : ticker,
          weight: invested > 0 ? Math.round(cost / invested * 100) : 0,
          cost: Math.round(cost),
          avg: average(ticker),
          delta: netDelta(ticker),
          exercise: exercise(ticker),
          week: week(ticker),
        })),
    );

    /* Net each leg by contract before counting it. A leg that has been bought
       back nets to zero and must not contribute its premium — netting on the
       FIFO key is what stopped alert-dispatcher reporting "40 short calls ITM"
       on a flat account. */
    const leg = new Map<string, { net: number; prem: number }>();
    for (const t of shorts) {
      const k = `${t.ticker}|${t.option_type}|${N(t.strike)}|${String(t.expiry).slice(0, 10)}`;
      const e = leg.get(k) ?? { net: 0, prem: 0 };
      const sign = t.action === 'open' ? 1 : -1;
      e.net += sign * N(t.contracts);
      e.prem += sign * N(t.contracts) * N(t.premium) * 100;
      leg.set(k, e);
    }
    const openPremium = [...leg.values()]
      .filter((e) => e.net > 0.0001)
      .reduce((s, e) => s + e.prem, 0);

    if (invested > 0) {
      /* ⚠ ONE FACT, NOT TWO. The yield means nothing without the balance it is
         drawn on, so they share a name, sit in one hit box, and take NO rule
         between them. The joining word is a real word, lowercase, in
         --rail-minor — never a dot and never a slash. */
      const spans: Span[] = [
        { text: 'Income invested', kind: 'word' },
        { text: money(invested), kind: 'figure' },
      ];
      if (openPremium > 0) {
        spans.push({ text: 'at', kind: 'minor' });
        spans.push({ text: `${(openPremium / invested * 100).toFixed(1)}%`, kind: 'figure' });
      }
      facts.push({ key: 'invested', spans });
    }

    /* The countdown lives IN THE NAME ("TLT div in 8d") — the rail has no
       right-hand slot, so "in 8d" is part of what the fact is called. The
       per-share figure is MINOR, not figure: one fact carries one loud number
       and the payment is the one that matters. */
    const d0 = divs[0];
    const tltShares = lots.filter((l) => String(l.ticker) === 'TLT')
      .reduce((s, l) => s + N(l.qty_remaining), 0);
    if (d0 && tltShares > 0) {
      const per = N(d0.cash_amount);
      const freq = N(d0.frequency) || 12;
      const step = Math.round(365 / freq);
      let next = parseISO(String(d0.ex_date).slice(0, 10));
      while (ymd(next) <= ymd(today)) next = addDays(next, step);
      const days = Math.max(0, Math.round((next.getTime() - today.getTime()) / 86_400_000));
      facts.push({ key: 'div', projected: true, spans: [
        { text: `TLT div in ${days}d`, kind: 'word' },
        { text: money(per * tltShares), kind: 'figure' },
        { text: `${per.toFixed(2).replace(/^0/, '')}/sh`, kind: 'minor' },
      ] });
    }

    /* NEUTRAL INK, deliberately. A yield is a level, not a direction, so it
       takes --rail-figure and never a direction ink. When a change comes back,
       the CHANGE earns the direction ink; the level never does. */
    const r0 = rates[0];
    if (r0) {
      facts.push({ key: 'us10y', spans: [
        { text: 'US 10y', kind: 'word' },
        { text: `${N(r0.value).toFixed(2)}%`, kind: 'figure' },
      ] });
    }

    /* ⚠ STAMP TODAY'S DELTA LAST, after the book is built, and keyed on the day
       so it is idempotent however many times the app is opened. A nightly cron
       calls this function too, so a day he never opens the app is still
       captured — otherwise "since yesterday" silently becomes "since whenever
       he last looked". */
    if (!body.peek) {
      const rows = book
        .filter((b) => b.delta)
        .map((b) => ({
          ticker: b.ticker, snapshot_date: todayISO,
          net_delta: b.delta!.net, exposure: b.delta!.exposure,
          captured_at: new Date().toISOString(),
        }));
      if (rows.length) await D.upsert('delta_history', rows, 'ticker,snapshot_date');
    }

    return json(200, {
      ok: true, build: BUILD, asof: ymd(today),
      facts,
      book,
      open_shorts: openShorts,
      calls_sold: callsSold,
      puts_sold: putsSold,
      puts_bought: putsBought,
      rates_asof: r0 ? String(r0.date).slice(0, 10) : null,
      open_premium: Math.round(openPremium),
      omitted: [],
    });
  } catch (e) { return json(500, { ok: false, error: String(e) }); }
});
