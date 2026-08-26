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

const BUILD = '2026-08-25.3';
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
        + '&select=ticker,qty_remaining,cost_per_share,acquired_date'),
      D.get(`option_trades?voided_at=is.null&expiry=gte.${todayISO}`
        + '&select=id,ticker,option_type,direction,strike,expiry,action,contracts,premium'),
      D.get('option_greeks_latest?select=option_trade_id,last_mark,captured_at'),
      D.get('ticker_quotes_latest?select=*'),
      D.get(`daily_closes?date=gte.${since}&select=ticker,date,close_price`
        + '&order=date.asc&limit=5000'),
    ]);

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
    const openIds = [...new Set((trades as Record<string, unknown>[])
      .filter((t) => t.action === 'open')
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
        const a = valueOn(shClose, w), b = valueOn(shClose, weekEnds[i]);
        if (a == null || b == null) return null;
        return { label: i === weekStarts.length - 1 ? 'Live' : weekLabel(w),
                 live: i === weekStarts.length - 1,
                 pnl: Math.round((b - a) * sh.qty) };
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

      out.push({
        ticker, spot,
        shares,
        legs,
        /* The header is the sum of the VISIBLE legs, so it moves with the leg
           count exactly as §4 requires. */
        total: Math.round(shares.pnl + legs.reduce((s, l) => s + l.pnl, 0)),
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
