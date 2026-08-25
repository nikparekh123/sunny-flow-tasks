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

const BUILD = '2026-08-25.1';
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

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  try {
    const D = db(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    const todayISO = nyToday();

    const [lots, trades, marks, quotes] = await Promise.all([
      D.get('share_lots?voided_at=is.null&qty_remaining=gt.0'
        + '&select=ticker,qty_remaining,cost_per_share'),
      D.get(`option_trades?voided_at=is.null&expiry=gte.${todayISO}`
        + '&select=id,ticker,option_type,direction,strike,expiry,action,contracts,premium'),
      D.get('option_greeks_latest?select=option_trade_id,last_mark,captured_at'),
      D.get('ticker_quotes_latest?select=*'),
    ]);

    const markBy = new Map<string, number>();
    for (const m of marks) markBy.set(String(m.option_trade_id), N(m.last_mark));

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

    const out: Record<string, unknown>[] = [];
    for (const [ticker, sh] of shareBy) {
      const spot = spotBy.get(ticker) ?? 0;
      if (!(spot > 0) || !(sh.qty > 0)) continue;
      const avg = sh.cost / sh.qty;

      const shares = {
        code: 'SH', label: 'SHARES',
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
      }>();
      for (const leg of (legBy.get(ticker) ?? new Map<string, Leg>()).values()) {
        if (Math.abs(leg.contracts) < 0.0001) continue;
        if (!(leg.mark > 0)) continue;
        const e = rolled.get(leg.code) ?? { contracts: 0, cash: 0, value: 0, parts: [], dte: 0 };
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
        return {
          code: c, label: LABEL[c], short,
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
    return json(200, { ok: true, build: BUILD, asof: todayISO, positions: out });
  } catch (e) { return json(500, { ok: false, error: String(e) }); }
});
