/**
 * position-legs — the P&L legs widget's data. cards/position-legs.md is normative.
 *
 * ⚠ ONE KIND OF NUMBER ON EVERY CARD, and this is the whole reason the function
 * exists. The widget shipped once with three kinds of figure on four cards: P&L
 * on shares, CREDIT RECEIVED on the sold legs, DEBIT PAID on the bought ones.
 * The four never summed to the header, and a percentage could not be added
 * because every card's denominator was different. §0.2 settles it: mark to
 * market on every leg, and one percentage rule, P&L over cash committed.
 *
 * ⚠ THIS IS *NOT* THE SLEEVE'S "TOTAL MADE", AND THE TWO WILL DISAGREE ON
 * PURPOSE. docs/PNL_GLOSSARY.md keeps PREMIUM COLLECTED as cash, never marked;
 * the sleeve hero is built on that and must stay built on it. What this widget
 * shows is UNREALIZED, which the same glossary defines WITH the marks:
 * "− Current_Value_Of_Open_Short_Options + (Current_Value_Of_Open_Long_Options
 * − Long_Option_Cost_Basis)". Two metrics, two names, both correct. The sheet
 * even picks the word "captured" for a short leg rather than "collected", so
 * the card never claims the cash is in hand.
 *
 * Marks come from option_greeks_latest.last_mark, joined on option_trade_id.
 */
import { corsHeaders, json, db, nyToday } from
  'https://raw.githubusercontent.com/nikparekh123/sunny-flow-tasks/dd3c85a56102451ae439016d6a90460c4d41dab0/supabase/functions/_shared/planner.ts';

const BUILD = '2026-08-26.9';
const N = (v: unknown, d = 0) => (v === null || v === undefined || v === '' ? d : Number(v));

/** Reading order in the grid is tab order in the detail card (§1). Fixed. */
const ORDER = ['PS', 'CS', 'PB', 'CB'] as const;
type Code = typeof ORDER[number];

const legCode = (type: string, short: boolean): Code =>
  type === 'put' ? (short ? 'PS' : 'PB') : (short ? 'CS' : 'CB');

const LABEL: Record<Code, string> = {
  PS: 'PUTS SOLD', CS: 'CALLS SOLD', PB: 'PUTS BOUGHT', CB: 'CALLS BOUGHT',
};

const MONTH = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
               'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const expLabel = (iso: string) => {
  const [, m, d] = iso.slice(0, 10).split('-').map(Number);
  return `${MONTH[m - 1]} ${d}`;
};

/** The last N Monday starts, oldest first; the final one is the LIVE week. */
function mondaysBack(todayISO: string, n: number): string[] {
  const d = new Date(todayISO + 'T00:00:00Z');
  // getUTCDay: 0 Sun .. 6 Sat. Back up to this week's Monday.
  const back = (d.getUTCDay() + 6) % 7;
  d.setUTCDate(d.getUTCDate() - back);
  const out: string[] = [];
  for (let i = n - 1; i >= 0; i--) {
    const w = new Date(d);
    w.setUTCDate(w.getUTCDate() - i * 7);
    out.push(w.toISOString().slice(0, 10));
  }
  return out;
}

const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
             'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const weekLabel = (iso: string) => {
  const [, m, d] = iso.split('-').map(Number);
  return `${MON[m - 1]} ${d}`;
};

/** The last value at or before `on`, from a series sorted oldest first. */
function valueOn(series: Array<{ d: string; v: number }>, on: string): number | null {
  let out: number | null = null;
  for (const p of series) { if (p.d <= on) out = p.v; else break; }
  return out;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  try {
    const D = db(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    const todayISO = nyToday();

    /* Five week-starts back, so four full columns plus whatever the live week
       has so far. The bars are the week's CHANGE IN P&L, which is the one
       quantity that exists every week for every leg type — decay for a sold
       leg, mark for a bought one, price x quantity for shares. The old "cash
       that moved that week" rule fails on the commonest case: a sold put held
       to expiry moves cash ONCE, so three of four weeks would be empty. */
    const weekStarts = mondaysBack(todayISO, 4);
    const since = weekStarts[0];

    const [lots, trades, marks, quotes, closes] = await Promise.all([
      D.get('share_lots?voided_at=is.null&qty_remaining=gt.0'
        + '&select=ticker,qty_remaining,qty_original,cost_per_share,acquired_date'),
      D.get(`option_trades?voided_at=is.null&expiry=gte.${todayISO}`
        + '&select=id,ticker,option_type,direction,strike,expiry,action,contracts,premium'),
      D.get('option_greeks_latest?select=option_trade_id,last_mark,captured_at'),
      D.get('ticker_quotes_latest?select=*'),
      /* ⚠ TEN DAYS BEFORE THE FIRST WEEK, not from it. The weekly P&L values the
         position as it stood going IN, which needs the close on the day BEFORE
         the week opens. Fetching from the first Monday leaves that day missing,
         and the opening value silently fell to zero — NFLX printed +$7,286 for
         a week it actually sold 100 shares in, because "held 100, worth nothing"
         made the proceeds look like profit. Ten days clears a long weekend. */
      D.get(`daily_closes?date=gte.${
          new Date(Date.parse(since + 'T00:00:00Z') - 10 * 86_400_000)
            .toISOString().slice(0, 10)}`
        + '&select=ticker,date,close_price&order=date.asc&limit=5000'),
    ]);

    /* ── REALIZED, so a page heading can print a Total ────────────────────
       SHELL-PAGED.md §5 puts two figures over every name: Current, what the
       open position is worth against its basis right now, and Total, every
       dollar the name has made or lost all time. Current is the sum of the leg
       cards and is already computed below. Total is Current + REALIZED, and
       docs/PNL_GLOSSARY.md fixes what that word means:

         REALIZED = stock sold - stock bought
                  + premium collected on CLOSED positions
                  - cost on CLOSED positions
                  + dividends received on CLOSED positions

       ⚠ THE DIVIDEND TERM IS MISSING AND THAT IS KNOWN, NOT AN OVERSIGHT. The
       `dividends` table is Polygon's SCHEDULE — ex_date, cash_amount, frequency
       — not a record of cash received, and there is no receipts table to sum.
       TLT is the only name it would move. Do not synthesise it from the
       schedule and a share count: a payment is a fact, not an estimate.

       ⚠ PAGINATED ON PURPOSE. This project caps PostgREST at 1000 rows and
       `limit` cannot lift it; option_trades is at 681 and grows every week. A
       truncated response is indistinguishable from a complete one, and this
       file has already been burned by that once (see the per-leg mark fan-out
       below). Loop until a page comes back short. */
    async function getAll(path: string): Promise<Record<string, unknown>[]> {
      const out: Record<string, unknown>[] = [];
      for (let off = 0; ; off += 1000) {
        const page = await D.get(`${path}&limit=1000&offset=${off}`);
        out.push(...(page as Record<string, unknown>[]));
        if (page.length < 1000) return out;
      }
    }
    const [everyTrade, sells, allLots] = await Promise.all([
      getAll('option_trades?voided_at=is.null&order=id.asc'
        + '&select=id,ticker,trade_date,option_type,direction,strike,expiry,action,contracts,premium'),
      getAll('share_sells?voided_at=is.null&order=id.asc'
        + '&select=ticker,trade_date,quantity,price,realized_pl'),
      /* ⚠ EVERY LOT, INCLUDING THE FULLY SOLD ONES. The fetch above filters
         qty_remaining > 0 because it feeds the CURRENT position. The ledger
         below reconstructs the PAST, and a closed lot is exactly the history it
         needs: with only open lots and every sell, the share count ran deeply
         negative and NFLX printed −$105,778 for a week. */
      getAll('share_lots?voided_at=is.null&order=id.asc'
        + '&select=ticker,acquired_date,qty_original,cost_per_share'),
    ]);

    /* A leg is REALIZED when it has been closed out (contracts net to zero) or
       when its expiry has passed — an expired short keeps its whole credit, an
       expired long loses its whole debit, and an assignment is a close by the
       glossary's own rule. Either way the realized figure is simply the leg's
       net CASH FLOW, signed by what the trade did rather than by the leg's
       direction:

         short open  receive +      long open   pay      -
         short close pay     -      long close  receive  +

       Net that over the life of the leg and the sign is already the P&L, which
       is why nothing here needs a short/long branch at the end. */
    const realizedBy = new Map<string, number>();
    const legFlow = new Map<string, { net: number; cash: number; expiry: string; ticker: string }>();
    for (const t of everyTrade) {
      const tick = String(t.ticker);
      const short = String(t.direction) === 'short';
      const opening = t.action === 'open';
      const expiry = String(t.expiry ?? '').slice(0, 10);
      const key = `${tick}|${t.option_type}|${N(t.strike)}|${expiry}|${short}`;
      const e = legFlow.get(key) ?? { net: 0, cash: 0, expiry, ticker: tick };
      e.net += (opening ? 1 : -1) * N(t.contracts);
      e.cash += (opening ? 1 : -1) * (short ? 1 : -1) * N(t.contracts) * N(t.premium) * 100;
      legFlow.set(key, e);
    }
    for (const e of legFlow.values()) {
      const closed = Math.abs(e.net) < 0.0001 || (e.expiry !== '' && e.expiry < todayISO);
      if (!closed) continue;
      realizedBy.set(e.ticker, (realizedBy.get(e.ticker) ?? 0) + e.cash);
    }
    /* share_sells.realized_pl is IBKR's own fifoPnlRealized, imported rather
       than recomputed — the reconcile could not rebuild a sold lot's basis and
       left every sell at zero, which is what put Sunnyfi ~$5.9k under IBKR. */
    for (const r of sells) {
      const t = String(r.ticker);
      realizedBy.set(t, (realizedBy.get(t) ?? 0) + N(r.realized_pl));
    }

    const markBy = new Map<string, number>();
    for (const m of marks) markBy.set(String(m.option_trade_id), N(m.last_mark));

    /* ⚠ ONE REQUEST PER LEG, NOT ONE FOR THE WHOLE WINDOW. This project caps
       PostgREST at 1000 rows and `limit` cannot lift it — the window holds
       ~9,900 marks, so a bulk fetch silently returned the oldest Aug 3 slice
       and every option leg came back with no series at all. A truncated
       response and an empty one are indistinguishable from inside the function,
       which is why the row count had to be checked against the table.

       Per leg the series is a few hundred rows at most, so each request is
       comfortably inside the cap and the fan-out is one call per OPEN leg. */
    /* ⚠ EVERY LEG ALIVE IN THE WINDOW, not just the ones still open today.
       The weekly chart used to read marks for `expiry >= today` only, so a leg
       that expired inside the window contributed NOTHING to the week it lived
       and died in — which is the week its money was made. NKE's week of 17 Aug
       showed −$1,668: shares +$32 plus a long put's −$1,700 of decay, while the
       20 calls sold at 0.61 and the 20 puts sold at 0.60 that expired that
       Friday were invisible. The card's own subject is what the position did
       that week, and the two legs it dropped were most of it. */
    const openIds = [...new Set((everyTrade as Record<string, unknown>[])
      .filter((t) => t.action === 'open' && String(t.expiry ?? '') >= since)
      .map((t) => String(t.id)))];
    const markSeries = new Map<string, Array<{ d: string; v: number }>>();
    await Promise.all(openIds.map(async (id) => {
      const rows = await D.get(`option_greeks?option_trade_id=eq.${id}`
        + `&captured_at=gte.${since}T00:00:00Z`
        + '&select=last_mark,captured_at&order=captured_at.asc');
      const a: Array<{ d: string; v: number }> = [];
      for (const g of rows) {
        const v = N(g.last_mark);
        if (v > 0) a.push({ d: String(g.captured_at).slice(0, 10), v });
      }
      if (a.length) markSeries.set(id, a);
    }));
    const closeSeries = new Map<string, Array<{ d: string; v: number }>>();
    for (const c of closes) {
      const t = String(c.ticker), v = N(c.close_price);
      if (!(v > 0)) continue;
      const a = closeSeries.get(t) ?? [];
      a.push({ d: String(c.date).slice(0, 10), v });
      closeSeries.set(t, a);
    }
    /* Week i runs from its own Monday to the day before the next Monday; the
       last one runs to today and is the LIVE week — hatched on the card,
       because on a white ground a provisional signal cannot be lightness. */
    const weekEnds = weekStarts.map((w, i) =>
      i === weekStarts.length - 1 ? todayISO
        : new Date(Date.parse(weekStarts[i + 1] + 'T00:00:00Z') - 86_400_000)
            .toISOString().slice(0, 10));

    /* Spot, and it must come from the same place the 5-day card and the headings
       do or two cards on one screen disagree about the price. */
    const spotBy = new Map<string, number>();
    for (const q of quotes as Record<string, unknown>[]) {
      const t = String(q.ticker ?? '');
      const v = N(q.last ?? q.price ?? q.spot ?? q.close);
      if (t && v > 0) spotBy.set(t, v);
    }

    const shareBy = new Map<string, { qty: number; cost: number }>();
    for (const l of lots) {
      const t = String(l.ticker);
      const e = shareBy.get(t) ?? { qty: 0, cost: 0 };
      e.qty += N(l.qty_remaining);
      e.cost += N(l.qty_remaining) * N(l.cost_per_share);
      shareBy.set(t, e);
    }

    /* ⚠ NET THE LEG BEFORE PRICING IT. A leg bought back nets to zero and must
       not contribute its credit — netting on the strike/expiry key is what
       stopped alert-dispatcher reporting "40 short calls ITM" on a flat book. */
    type Leg = {
      code: Code; short: boolean; type: string; strike: number; expiry: string;
      contracts: number; cash: number; mark: number; tradeId: string;
    };
    const legBy = new Map<string, Map<string, Leg>>();
    for (const t of trades as Record<string, unknown>[]) {
      const tick = String(t.ticker);
      const short = String(t.direction) === 'short';
      const key = `${t.option_type}|${N(t.strike)}|${String(t.expiry).slice(0, 10)}|${short}`;
      const per = legBy.get(tick) ?? new Map<string, Leg>();
      const sign = t.action === 'open' ? 1 : -1;
      const e = per.get(key) ?? {
        code: legCode(String(t.option_type), short), short,
        type: String(t.option_type), strike: N(t.strike),
        expiry: String(t.expiry).slice(0, 10),
        contracts: 0, cash: 0, mark: 0, tradeId: String(t.id),
      };
      e.contracts += sign * N(t.contracts);
      e.cash += sign * N(t.contracts) * N(t.premium) * 100;
      const mk = markBy.get(String(t.id));
      if (mk !== undefined && mk > 0) e.mark = mk;
      per.set(key, e);
      legBy.set(tick, per);
    }

    /** The first date the name appears anywhere: a lot ever acquired, a sell, or
        an option trade. This is when the POSITION started, which is not the same
        as when its surviving lots were bought. */
    const firstSeen = new Map<string, string>();
    const sawOn = (t: string, d: string) => {
      if (!t || !d) return;
      const cur = firstSeen.get(t);
      if (!cur || d < cur) firstSeen.set(t, d);
    };
    for (const l of allLots) sawOn(String(l.ticker), String(l.acquired_date ?? '').slice(0, 10));
    for (const r of sells) sawOn(String(r.ticker), String(r.trade_date ?? '').slice(0, 10));
    for (const t of everyTrade) sawOn(String(t.ticker), String(t.trade_date ?? '').slice(0, 10));

    /** Days since the oldest open lot — the shares card's third footer stat. */
    const acquired = new Map<string, string>();
    for (const l of lots) {
      const t = String(l.ticker), d = String(l.acquired_date ?? '').slice(0, 10);
      if (!d) continue;
      const cur = acquired.get(t);
      if (!cur || d < cur) acquired.set(t, d);
    }
    const heldDays = (t: string) => {
      const d = acquired.get(t);
      if (!d) return 0;
      return Math.round((Date.parse(todayISO + 'T00:00:00Z') - Date.parse(d + 'T00:00:00Z')) / 86_400_000);
    };

    /* ── the share ledger, so a week he did not hold prints nothing ──────────
       ⚠ THIS MULTIPLIED THE WEEK'S PRICE MOVE BY TODAY'S SHARE COUNT, for every
       week in the window, with no reference to what he actually held. CEG, LEN
       and PEP were bought on 24 Aug and each showed four weeks of history: CEG
       printed −$382 for the week of 3 Aug, which is exactly
       (269.89 − 273.71) × 100 — what a hundred shares WOULD have done in a week
       he owned nothing. A hypothetical rendered as history, and the arithmetic
       was right, which is what made it convincing.

       ⚠ AND NULLING WEEKS BEFORE THE CURRENT BLOCK IS ALSO WRONG. NKE's block
       dates from 24 Aug, but he held NKE through every week in the window — a
       different, larger block that was called away. "You held nothing" would be
       as false as the fabricated bars.

       So the position is RECONSTRUCTED per week from the lots and the sells:

         weekly P&L = value(end) − value(start) − cash IN during the week

       where value is shares held on that day times the close, cash in is what
       the buys cost, and a sell is negative cash in. That identity is exact for
       every case that broke: a week with no shares gives 0 − 0 − 0 and prints
       nothing; the week he bought gives value(end) − cost, which is what the
       block has done since he actually bought it; a week he sold into books the
       proceeds; and a mid-week trade needs no special case at all.

       `qty_original`, not `qty_remaining`: remaining is what is left TODAY, so
       using it would erase every share he has since sold from the history. */
    type ShareEvent = { d: string; dq: number; cash: number };
    const ledger = new Map<string, ShareEvent[]>();
    const push = (t: string, e: ShareEvent) => {
      const a = ledger.get(t) ?? [];
      a.push(e);
      ledger.set(t, a);
    };
    for (const l of allLots) {
      const d = String(l.acquired_date ?? '').slice(0, 10);
      if (!d) continue;
      const q = N(l.qty_original);
      if (!(q > 0)) continue;
      push(String(l.ticker), { d, dq: q, cash: q * N(l.cost_per_share) });
    }
    for (const r of sells) {
      const d = String(r.trade_date ?? '').slice(0, 10);
      if (!d) continue;
      const q = N(r.quantity);
      push(String(r.ticker), { d, dq: -q, cash: -q * N(r.price) });
    }
    for (const a of ledger.values()) a.sort((x, y) => x.d.localeCompare(y.d));

    /** Shares held at the close of `on`, WALKED BACK from what he holds today.
     *
     * ⚠ BACKWARDS, NOT FORWARDS, AND THE REASON IS NKE. Summing lots forward
     * from the beginning assumes the lot history is complete, and NKE's is not:
     * it runs 500 → 0 → 500 → 148 and then a 600-share sell on 17 Jul takes it
     * to −452, ending at 1,500 against the 2,000 he actually holds. Roughly 500
     * shares were acquired and never wrote a lot row. A negative share count
     * times a price is what printed −$18,804 for a quiet week.
     *
     * Today's quantity is a known truth (`share_lots.qty_remaining`), so the
     * walk starts there and subtracts every event since. The result is exact at
     * today and degrades only as far back as the gap, instead of being wrong
     * everywhere. NFLX reconciles either way; NKE only this way.
     *
     * The gap is a real defect in the book and is reported as `share_history`
     * below rather than silently absorbed. */
    const qtyOn = (t: string, on: string, today: number) =>
      (ledger.get(t) ?? []).reduce((n, e) => (e.d > on ? n - e.dq : n), today);
    /** Cash paid in for shares over (after, on], sells counting negative. */
    const cashIn = (t: string, after: string, on: string) =>
      (ledger.get(t) ?? []).reduce((n, e) => (e.d > after && e.d <= on ? n + e.cash : n), 0);

    /* ── the option ledger, so a week counts every leg that lived in it ───────
       Same identity as the shares, and it has to be the same one or the two
       halves of a week cannot be added:

         weekly P&L = value(end) − value(start) − cash paid in during the week

       An option's VALUE is signed by direction — a long leg is an asset, a short
       leg is a liability — and CASH IN is money out of pocket, so buying is
       positive and selling is negative. Once a leg expires it holds no
       contracts, so its value is zero and the identity books the whole remaining
       credit or debit into that week without needing a settlement price.

       ⚠ AND AN ASSIGNMENT IS NOT DOUBLE COUNTED. A short call assigned on Friday
       leaves the option worth nothing here, while the shares it called away
       leave through the share ledger at the strike. Two ledgers, one event, no
       overlap. */
    type OptLeg = { long: boolean; expiry: string; openId: string;
                    events: Array<{ d: string; dq: number; cash: number }> };
    const optBy = new Map<string, Map<string, OptLeg>>();
    for (const t of everyTrade) {
      const tick = String(t.ticker);
      const expiry = String(t.expiry ?? '').slice(0, 10);
      if (expiry && expiry < since) continue;          // dead before the window
      const long = String(t.direction) !== 'short';
      const key = `${t.option_type}|${N(t.strike)}|${expiry}|${long}`;
      const per = optBy.get(tick) ?? new Map<string, OptLeg>();
      const e: OptLeg = per.get(key)
        ?? { long, expiry, openId: '', events: [] };
      const opening = t.action === 'open';
      if (opening && !e.openId) e.openId = String(t.id);
      const q = N(t.contracts);
      e.events.push({
        d: String(t.trade_date ?? '').slice(0, 10),
        dq: (opening ? 1 : -1) * q,
        cash: (opening ? 1 : -1) * (long ? 1 : -1) * q * N(t.premium) * 100,
      });
      per.set(key, e);
      optBy.set(tick, per);
    }
    /** The option book's mark-to-market value on `on`, longs positive. */
    const optValueOn = (t: string, on: string): number | null => {
      let v = 0;
      for (const leg of (optBy.get(t) ?? new Map<string, OptLeg>()).values()) {
        const held = leg.events.reduce((n, e) => (e.d <= on ? n + e.dq : n), 0);
        if (Math.abs(held) < 0.0001) continue;         // not open on that day
        if (leg.expiry && leg.expiry < on) continue;   // expired, worth nothing
        const m = valueOn(markSeries.get(leg.openId) ?? [], on);
        /* ⚠ ALIVE BUT UNPRICED IS NOT WORTHLESS. Returning 0 here would make a
           leg with no mark at a boundary read as a full gain or loss. No price,
           no week — the caller nulls it, exactly as the shares do. */
        if (m == null) return null;
        v += (leg.long ? 1 : -1) * held * m * 100;
      }
      return v;
    };
    /** Cash paid in for options over (after, on]. Selling is negative. */
    const optCashIn = (t: string, after: string, on: string) => {
      let c = 0;
      for (const leg of (optBy.get(t) ?? new Map<string, OptLeg>()).values()) {
        for (const e of leg.events) if (e.d > after && e.d <= on) c += e.cash;
      }
      return c;
    };

    const out: Record<string, unknown>[] = [];
    for (const [ticker, sh] of shareBy) {
      const spot = spotBy.get(ticker) ?? 0;
      if (!(spot > 0) || !(sh.qty > 0)) continue;
      const avg = sh.cost / sh.qty;

      /* ⚠ WEEKLY CHANGE, NEVER A LEVEL, AND NEVER CASH MOVED. Only change has
         a shape, and P&L change is the one quantity every leg type has every
         week. A week with no data on either end yields null and the card draws
         nothing there — distinct from a real zero. */
      const shClose = closeSeries.get(ticker) ?? [];
      const shareWeeks = weekStarts.map((w, i) => {
        const end = weekEnds[i];
        const live = i === weekStarts.length - 1;
        const label = live ? 'Live' : weekLabel(w);
        /* The day BEFORE the week opens: the position as it stood going in,
           priced on the last close before the week rather than on its first. */
        const prev = new Date(Date.parse(w + 'T00:00:00Z') - 86_400_000)
          .toISOString().slice(0, 10);
        /* ⚠ THE LIVE WEEK ENDS AT SPOT, not at the last close. The card prints
           the since-open figure right above this bar, and that figure is marked
           to spot — on a position opened this week the two ARE the same
           quantity, so a close-priced bar sat $2k away from the figure over it
           and neither was wrong. One price for one card. */
        const pOpen = valueOn(shClose, prev);
        const pEnd = live ? spot : valueOn(shClose, end);
        if (pEnd == null) return null;
        const qOpen = qtyOn(ticker, prev, sh.qty), qEnd = qtyOn(ticker, end, sh.qty);
        /* Held nothing at either end and traded nothing between: not a zero
           week, a week the position did not exist. The card draws nothing. */
        const flow = cashIn(ticker, prev, end);
        if (qOpen <= 0 && qEnd <= 0 && Math.abs(flow) < 0.005) return null;
        /* ⚠ HELD SHARES BUT NO PRICE TO VALUE THEM AT IS NOT ZERO. Treating a
           missing opening close as a zero opening value is what made a week's
           SALE PROCEEDS read as a week's profit. No price, no week. */
        if (qOpen > 0 && pOpen == null) return null;
        const vOpen = qOpen > 0 ? qOpen * (pOpen as number) : 0;
        return { label, live, pnl: Math.round(qEnd * pEnd - vOpen - flow) };
      });

      const shares = {
        code: 'SH', label: 'SHARES',
        weeks: shareWeeks,
        held: heldDays(ticker),
        pnl: Math.round((spot - avg) * sh.qty),
        pct: avg > 0 ? Math.round((spot / avg - 1) * 1000) / 10 : 0,
        basis: Math.round(sh.cost),
        contract: `${sh.qty.toLocaleString('en-US')} at ${avg.toFixed(2)} → ${spot.toFixed(2)}`,
        market: Math.round(spot * sh.qty),
      };

      /* One card per leg CODE, not per contract: four puts sold at three
         strikes is one "puts sold" card, because the grid is built from four
         slots and the tab strip from four tabs. Strikes roll up into the
         contract line. */
      const rolled = new Map<Code, {
        contracts: number; cash: number; value: number; parts: string[]; dte: number;
        ids: Array<{ id: string; contracts: number }>;
      }>();
      for (const leg of (legBy.get(ticker) ?? new Map<string, Leg>()).values()) {
        if (Math.abs(leg.contracts) < 0.0001) continue;
        if (!(leg.mark > 0)) continue;
        const e = rolled.get(leg.code)
          ?? { contracts: 0, cash: 0, value: 0, parts: [], dte: 0, ids: [] };
        e.ids.push({ id: leg.tradeId, contracts: Math.abs(leg.contracts) });
        /* The NEAREST expiry when a code rolls up several: the sub-label says
           how long you are exposed, and the leg that decides that is the one
           that resolves first. */
        const d = Math.round(
          (Date.parse(leg.expiry + 'T00:00:00Z') - Date.parse(todayISO + 'T00:00:00Z')) / 86_400_000);
        e.dte = e.dte === 0 ? d : Math.min(e.dte, d);
        e.contracts += Math.abs(leg.contracts);
        e.cash += Math.abs(leg.cash);
        e.value += Math.abs(leg.contracts) * leg.mark * 100;
        e.parts.push(`${Math.abs(leg.contracts)} × ${leg.strike} ${leg.type}`
          + ` · ${expLabel(leg.expiry)}`);
        rolled.set(leg.code, e);
      }

      const legs = ORDER.filter((c) => rolled.has(c)).map((c) => {
        const e = rolled.get(c)!;
        /* SHORT: the credit is the ceiling and the mark is what buying it back
           would cost, so P&L is credit minus value and the percentage is how
           much of the credit has been CAPTURED.
           LONG: the debit is sunk and the mark is what it is worth now. */
        const short = c === 'PS' || c === 'CS';
        const p = short ? e.cash - e.value : e.value - e.cash;
        /* SHORT: value falling is your gain, so the sign flips. LONG: value
           rising is your gain. Same arithmetic as the `pnl` above, taken across
           a week rather than across the life of the leg. */
        const weeks = weekStarts.map((wi, i) => {
          let d = 0, seen = false;
          for (const leg of e.ids) {
            const ser = markSeries.get(leg.id) ?? [];
            const a = valueOn(ser, wi), b = valueOn(ser, weekEnds[i]);
            if (a == null || b == null) continue;
            seen = true;
            d += (short ? a - b : b - a) * leg.contracts * 100;
          }
          if (!seen) return null;
          return { label: i === weekStarts.length - 1 ? 'Live' : weekLabel(wi),
                   live: i === weekStarts.length - 1,
                   pnl: Math.round(d) };
        });
        return {
          code: c, label: LABEL[c], short,
          weeks,
          pnl: Math.round(p),
          pct: e.cash > 0 ? Math.round(p / e.cash * 1000) / 10 : 0,
          committed: Math.round(e.cash),
          value: Math.round(e.value),
          contracts: e.contracts,
          contract: e.parts.join(' · '),
          dte: e.dte,
        };
      });

      /* ⚠ ONE CARD PER PUT POSITION, KEYED ON THE POSITION AND NOT THE TICKER.
         Five NKE puts at one strike are one card; two different NKE strikes are
         two cards, and they can disagree — that is correct, they are different
         insurance. So the floors do NOT come from the rolled-up PB leg, which
         folds every strike into one figure: TLT's December 75 and 80 are two
         separate pieces of cover with two separate bands.

         ⚠ AND THE TRIGGER READS DISTANCE, NEVER P&L. |spot − strike| / strike
         against the band. A put 12% in the money is up several hundred percent
         and still says roll, because it has stopped being insurance and become
         a position. Never gate the state on profit. */
      const floors = [...(legBy.get(ticker) ?? new Map<string, Leg>()).values()]
        .filter((l) => !l.short && l.type === 'put'
                    && Math.abs(l.contracts) > 0.0001 && l.mark > 0)
        .sort((a, b) => a.expiry.localeCompare(b.expiry) || a.strike - b.strike)
        .map((l) => {
          const n = Math.abs(l.contracts);
          const debit = Math.abs(l.cash);
          const value = n * l.mark * 100;
          const dist = (spot - l.strike) / l.strike * 100;
          return {
            strike: l.strike, expiry: l.expiry, contracts: n,
            dte: Math.round((Date.parse(l.expiry + 'T00:00:00Z')
                           - Date.parse(todayISO + 'T00:00:00Z')) / 86_400_000),
            debit: Math.round(debit),
            value: Math.round(value),
            pnl: Math.round(value - debit),
            pct: debit > 0 ? Math.round((value - debit) / debit * 1000) / 10 : 0,
            /* Raw, unrounded — the BREACH TEST uses this. The display guards
               its own rounding separately: 43.90 against 40 is exactly 9.75%,
               which lands at 9.7499…96 in binary and prints 9.7 under a plain
               toFixed(1). Guard the display only, so a true 10.0000001% still
               breaches even though it prints as 10.0%. */
            distance: dist,
          };
        });

      /* ── the position's week: REALIZED ONLY ──────────────────────────────
         ⚠ NOTHING UNREALIZED IN THIS CHART. Nik, 26 Aug: "this is unrealized
         you cannot count this — it's only realized that we need to count." The
         version before this marked every open leg to market, so the week he
         bought a Jan 15 hedge for $8,300 charged him its first four days of
         decay: his week of 17 Aug read +$1,952 against the +$2,452 he actually
         banked, and the $500 difference was a put he still holds.

         docs/PNL_GLOSSARY.md defines REALIZED as closed positions only, and
         that is exactly this: a leg books its whole lifetime cash flow in the
         week it closed or expired, and shares book IBKR's own fifoPnlRealized
         on the day of the sale. Nothing that is still open contributes.

         ⚠ AND THAT MEANS MOST WEEKS ARE EMPTY, which is correct rather than
         broken. A position opened this week has realized nothing, so its card
         draws no bars at all. Six of nine names read empty on 26 Aug. A blank
         chart on a young position is the honest answer to "what has this
         banked", not a missing feature.

         One good property falls out: the share side uses IBKR's realized figure
         rather than our own lot reconstruction, so a name whose lot history has
         a hole — NKE is short about 500 shares — still books the right number
         here, because IBKR did the FIFO. */
      const realizedWeek = (i: number) => {
        const w = weekStarts[i], end = weekEnds[i];
        let v = 0;
        let any = false;
        for (const r of sells) {
          if (String(r.ticker) !== ticker) continue;
          const d = String(r.trade_date ?? '').slice(0, 10);
          if (d < w || d > end) continue;
          v += N(r.realized_pl); any = true;
        }
        for (const leg of (optBy.get(ticker) ?? new Map<string, OptLeg>()).values()) {
          const net = leg.events.reduce((n, e) => n + e.dq, 0);
          const closes = leg.events.filter((e) => e.dq < 0).map((e) => e.d).sort();
          /* Closed out by a trade, or simply expired. An expired leg has no
             closing row on some paths, so the expiry IS the date it realized. */
          const on = Math.abs(net) < 0.0001 && closes.length
            ? closes[closes.length - 1]
            : (leg.expiry && leg.expiry < todayISO ? leg.expiry : '');
          if (!on || on < w || on > end) continue;
          /* cash is money OUT, so the realized P&L is its negative: a short leg
             opened for a credit and expiring worthless nets the credit. */
          v += -leg.events.reduce((n, e) => n + e.cash, 0);
          any = true;
        }
        return { any, v };
      };
      /* ⚠ A WEEK HE HELD THE NAME AND REALIZED NOTHING IS A ZERO, NOT A NULL.
         Null means "we do not know"; here we do. The card was returning null for
         every quiet week, so six of nine names drew no bars at all — Nik, 27
         Aug: "no bars are showing for any tickers." On a realized-only series a
         book whose legs all expire on the same future Friday is quiet by
         construction, and a flat zero is the true shape of that.

         ⚠ BEFORE HE OWNED IT, THE NULL IS STILL RIGHT. AIG and FIS are days
         old; a zero bar for the weeks before the first lot would claim a flat
         result on a position that did not exist.

         ⚠ AND THE CUT IS THE FIRST TIME HE HELD THE NAME AT ALL, not the oldest
         OPEN lot. `acquired` sees only surviving lots, so NKE dated from 24 Aug
         — a different, larger block had been called away — and four weeks he
         held it through came back null. The earliest of every lot ever, every
         sell and every option trade is the honest start of a position; the same
         mistake is already recorded a few lines above this one against the value
         series. */
      const since = firstSeen.get(ticker) ?? '';
      const posWeeks = weekStarts.map((_, i) => {
        const live = i === weekStarts.length - 1;
        const label = live ? 'Live' : weekLabel(weekStarts[i]);
        const { any, v } = realizedWeek(i);
        if (!any && (!since || weekEnds[i] < since)) return null;
        return { label, live, pnl: Math.round(v) };
      });

      out.push({
        ticker, spot,
        /* ⚠ THE CARD READS THIS, not the per-leg series summed. The per-leg
           arrays stay in the payload because they are still true statements
           about each leg, and because one backend serves two clients. */
        weeks: posWeeks,
        floors,
        shares,
        legs,
        /* The header is the sum of the VISIBLE legs, so it moves with the leg
           count exactly as §4 requires. */
        total: Math.round(shares.pnl + legs.reduce((s, l) => s + l.pnl, 0)),
        /* The page heading's two figures. `total` above is UNREALIZED and is
           what the heading calls CURRENT — it is the five leg cards summed, so
           the heading and the cards under it can never disagree. `allTime` adds
           everything already closed. They disagree with each other on purpose:
           that gap is what years of writing premium against a position that is
           currently underwater looks like. */
        /* ⚠ DOES THE LOT HISTORY ADD UP? Forward from the lots against what he
           holds today. Non-zero means rows are missing and the weekly bars are
           reconstructed across a gap — NKE is out by 500. Surfaced rather than
           swallowed: the fix belongs in the book, not in this arithmetic. */
        share_history: Math.round(
          (ledger.get(ticker) ?? []).reduce((n, e) => n + e.dq, 0) - sh.qty),
        realized: Math.round(realizedBy.get(ticker) ?? 0),
        allTime: Math.round(shares.pnl + legs.reduce((s, l) => s + l.pnl, 0)
                            + (realizedBy.get(ticker) ?? 0)),
        /* Parity of the OPTION-leg count picks the layout (§1): even puts
           shares on an M so the rows square off, odd makes shares an S and it
           joins the run. The client must not re-derive this. */
        layout: legs.length % 2 === 0 ? 'M' : 'S',
      });
    }

    out.sort((a, b) => String(a.ticker).localeCompare(String(b.ticker)));
    return json(200, { ok: true, build: BUILD, asof: todayISO, positions: out,
      debug: { legs: openIds.length, series: markSeries.size, closes: closes.length,
               weekStarts, weekEnds,
               sampleIds: [...markSeries.keys()].slice(0, 3) } });
  } catch (e) { return json(500, { ok: false, error: String(e) }); }
});
