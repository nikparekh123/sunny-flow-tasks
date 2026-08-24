/**
 * open-premium — every short option still open, across the whole book.
 *
 * Four figures, in the order Claude Design's drawer shows them:
 *
 *   CREDIT COLLECTED   what came in when these legs were sold
 *   COMMITTED          what assignment would cost, if every short put were put to him
 *   TIME VALUE LEFT    the extrinsic still in them, which is what decays
 *   TOTAL VALUE LEFT   what it would cost to buy the whole lot back right now
 *
 * Collected minus total-value-left is the position's profit so far. Time value is
 * the part of what remains that goes away on its own.
 *
 * ── Why this is one function and not three ──────────────────────────────────
 * The drawer sits above every tab, NVDA and TLT and Income alike, because Nik's
 * problem is that no screen shows the whole book at once. Marks live in three
 * separate per-ticker stores (nvda_option_marks and friends), so reading those
 * would rebuild the same fragmentation the drawer exists to fix. It reads the
 * LEGACY option_trades instead, which ibkr-flex-sync fills for every symbol
 * traded, and marks the legs live off Polygon.
 *
 * Body (all optional): {"asof":"2026-08-17"}
 */
// Pinned https import, NOT ../_shared/ — the dashboard bundles only this folder.
import {
  corsHeaders, json, db, spotOf, ymd, parseISO, nyToday, marketNow, marketState,
} from 'https://raw.githubusercontent.com/nikparekh123/sunny-flow-tasks/dd3c85a56102451ae439016d6a90460c4d41dab0/supabase/functions/_shared/planner.ts';

const BUILD = '2026-08-17.1';
const POLY = 'https://api.polygon.io';

/* SPEC 05: the minus sits OUTSIDE the currency and is U+2212, not a hyphen.
   toLocaleString gives "-3,726", which renders as "$-3,726". */
const usd = (v: number) => (v < 0 ? '\u2212' : '')
  + '$' + Math.abs(Math.round(v)).toLocaleString('en-US');

/** Every contract at one expiry for one underlying, keyed strike|type. */
async function marks(ticker: string, expiry: string, key: string) {
  const out = new Map<string, number>();
  try {
    const u = new URL(`${POLY}/v3/snapshot/options/${ticker}`);
    u.searchParams.set('expiration_date', expiry);
    u.searchParams.set('limit', '250');
    u.searchParams.set('apiKey', key);
    const r = await fetch(u.toString());
    if (!r.ok) return out;
    const j = await r.json();
    for (const c of (j?.results ?? [])) {
      const k = c.details?.strike_price, t = c.details?.contract_type;
      if (k == null || !t) continue;
      const bid = c.last_quote?.bid, ask = c.last_quote?.ask;
      const mid = (bid > 0 && ask > 0) ? (bid + ask) / 2 : (c.day?.close ?? 0);
      if (mid > 0) out.set(`${k}|${t}`, mid);
    }
  } catch { /* a missing mark must not fail the drawer */ }
  return out;
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
    const D = db(url, key);

    const legs = await D.get('option_trades?voided_at=is.null'
      + `&expiry=gte.${todayISO}&direction=eq.short`
      + '&select=ticker,option_type,direction,action,contracts,strike,premium,expiry');

    /* NET the opens against the closes. A leg bought back is not open premium,
       and counting it would show credit against a position that no longer
       exists. Keyed by the contract itself, not by trade. */
    type Leg = { ticker: string; type: string; strike: number; expiry: string;
                 ct: number; credit: number };
    const open = new Map<string, Leg>();
    for (const l of legs) {
      const t = String(l.ticker), ty = String(l.option_type);
      const k = String(l.strike), e = String(l.expiry).slice(0, 10);
      const id = `${t}|${ty}|${k}|${e}`;
      const sign = l.action === 'open' ? 1 : -1;
      const ct = sign * Number(l.contracts ?? 0);
      const cur = open.get(id) ?? { ticker: t, type: ty, strike: Number(k), expiry: e, ct: 0, credit: 0 };
      cur.ct += ct;
      cur.credit += sign * Number(l.premium ?? 0) * Number(l.contracts ?? 0) * 100;
      open.set(id, cur);
    }
    const live = [...open.values()].filter((l) => l.ct > 0);

    if (!live.length) {
      return json(200, {
        ok: true, build: BUILD, asof: todayISO, any_open: false,
        market: (await marketNow(polyKey)) ?? marketState(new Date()),
        tape: {
          lab: 'Open premium', mini: 'nothing open',
          cells: [
            { k: 'Credit collected', v: '$0' },
            { k: 'Committed', v: 'nothing', text: true },
            { k: 'Time value left', v: 'nothing open', text: true },
            { k: 'Total value left', v: 'nothing open', text: true },
          ],
        },
      });
    }

    // one spot per underlying, one snapshot per (underlying, expiry)
    const tickers = [...new Set(live.map((l) => l.ticker))];
    const pairs = [...new Set(live.map((l) => `${l.ticker}|${l.expiry}`))];
    const [spots, chains] = await Promise.all([
      Promise.all(tickers.map(async (t) => [t, await spotOf(t, polyKey)] as const)),
      Promise.all(pairs.map(async (p) => {
        const [t, e] = p.split('|');
        return [p, await marks(t, e, polyKey)] as const;
      })),
    ]);
    const spot = new Map(spots), chain = new Map(chains);

    let credit = 0, committed = 0, value = 0, intrinsic = 0, unpriced = 0;
    const perTicker = new Map<string, { credit: number; value: number; ct: number }>();

    for (const l of live) {
      credit += l.credit;
      if (l.type === 'put') committed += l.strike * 100 * l.ct;

      const S = spot.get(l.ticker) ?? null;
      const mid = chain.get(`${l.ticker}|${l.expiry}`)?.get(`${l.strike}|${l.type}`) ?? null;
      /* An unpriced leg is COUNTED and SAID, not silently dropped. A drawer that
         quietly omits a leg it could not mark understates what buying the book
         back costs, which is the one number Nik reads when he is lost. */
      if (mid == null) { unpriced += l.ct; continue; }

      value += mid * 100 * l.ct;
      if (S != null) {
        const iv = l.type === 'put' ? Math.max(0, l.strike - S) : Math.max(0, S - l.strike);
        intrinsic += iv * 100 * l.ct;
      }
      const p = perTicker.get(l.ticker) ?? { credit: 0, value: 0, ct: 0 };
      p.credit += l.credit; p.value += mid * 100 * l.ct; p.ct += l.ct;
      perTicker.set(l.ticker, p);
    }
    const timeValue = Math.max(0, value - intrinsic);

    return json(200, {
      ok: true, build: BUILD, asof: todayISO, any_open: true,
      market: (await marketNow(polyKey)) ?? marketState(new Date()),
      contracts: live.reduce((s, l) => s + l.ct, 0),
      tickers: tickers.length,
      unpriced,
      // The drawer's own shape: a label, the closed-state figure, four cells.
      tape: {
        lab: 'Open premium',
        mini: `${usd(value)} left`,
        cells: [
          { k: 'Credit collected', v: usd(credit) },
          { k: 'Committed', v: committed > 0 ? usd(committed) : 'nothing', text: committed <= 0 },
          { k: 'Time value left', v: usd(timeValue) },
          { k: 'Total value left', v: usd(value), mark: true },
        ],
        note: unpriced > 0 ? `${unpriced} contracts could not be marked` : null,
      },
      raw: {
        credit_collected: Math.round(credit),
        committed: Math.round(committed),
        time_value_left: Math.round(timeValue),
        total_value_left: Math.round(value),
        // Collected minus what it costs to close: the open position's profit so far.
        ahead_by: Math.round(credit - value),
        by_ticker: [...perTicker.entries()]
          .map(([t, p]) => ({ ticker: t, contracts: p.ct,
                              credit: Math.round(p.credit), value: Math.round(p.value) }))
          .sort((a, b) => b.credit - a.credit),
      },
    });
  } catch (e) {
    return json(500, { ok: false, error: String(e) });
  }
});
