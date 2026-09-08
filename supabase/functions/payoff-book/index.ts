/**
 * payoff-book — the whole contract for the payoff planner page.
 *
 * Handoff: design_handoff_payoff_planner/README.md. One call returns every
 * name in the book with its live legs, closed legs, price context and option
 * chain, because the page's numbers must agree with the Options page and two
 * endpoints would let them drift.
 *
 * ⚠ ENTRY MARK IS NET CASH OVER CONTRACTS. A leg built from several fills —
 * NKE's 60 LEAPs came in at 12.60 and 12.70 — gets ONE number, which is the
 * same "paid" figure the option cards already use. Two definitions of the
 * cost basis on two pages is how the Options page and this one would disagree.
 *
 * ⚠ "UNREALIZED" IS THE BROKER MARK, NOT THE MODEL. Nik, 2026-09-08: "what
 * the current value is, not anything else." So every live leg ships its
 * last_mark from option_greeks, and the client anchors today's curve to it.
 * Black-Scholes takes over only when the date is scrubbed forward.
 *
 * ⚠ CLOSED-LEG OUTCOMES ARE ONLY WHAT IBKR ACTUALLY SAID. Assigned, Exercised
 * and Expired come from lifecycle codes. Anything else closed for money is
 * "Bought back" (a short) or "Sold" (a long). There is NO "Rolled": it is an
 * inference dressed as a fact, and Nik ruled it out.
 */
import { corsHeaders, json, db, nyToday, POLY } from
  'https://raw.githubusercontent.com/nikparekh123/sunny-flow-tasks/dd3c85a56102451ae439016d6a90460c4d41dab0/supabase/functions/_shared/planner.ts';

const BUILD = '2026-09-08.1';
const N = (v: unknown) => (v === null || v === undefined || v === '' ? 0 : Number(v));
const r2 = (v: number) => Math.round(v * 100) / 100;
const MON = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];

/** "18 Mar 2026" — the history line's date, as the design writes it. */
const dayLabel = (iso: string) => {
  const p = iso.slice(0, 10).split('-');
  return `${Number(p[2])} ${MON[Number(p[1]) - 1]} ${p[0]}`;
};
/** "Jan '27" / "Mar 19" — the design's fmtExp, with the year only off-year. */
const expLabel = (iso: string, year: number) => {
  const p = iso.split('-');
  const y = Number(p[0]);
  return `${MON[Number(p[1]) - 1]} ${Number(p[2])}` + (y !== year ? ` ’${String(y).slice(2)}` : '');
};
const fmtK = (k: number) => (k % 1 === 0 ? String(k) : k.toFixed(2));

/** Exponential moving average of an ascending close series. */
function ema(closes: number[], n: number): number | null {
  if (closes.length < n) return null;
  const k = 2 / (n + 1);
  let e = closes.slice(0, n).reduce((a, b) => a + b, 0) / n;
  for (let i = n; i < closes.length; i++) e = closes[i] * k + e * (1 - k);
  return r2(e);
}

type Trade = Record<string, unknown>;

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  try {
    const D = db(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    const polygonKey = Deno.env.get('POLYGON_API_KEY') ?? '';
    const today = nyToday();
    const year = Number(today.slice(0, 4));
    const ago = (d: number) => new Date(Date.parse(today + 'T00:00:00Z') - d * 86_400_000)
      .toISOString().slice(0, 10);

    const [trades, lots, quotes, greeks, names, ivs, acts, levels] = await Promise.all([
      D.get('option_trades?voided_at=is.null'
        + '&select=id,ticker,option_type,direction,action,contracts,strike,expiry,premium,trade_date,note,source'
        + '&order=trade_date.asc'),
      D.get('share_lots?voided_at=is.null&qty_remaining=gt.0&select=ticker,qty_remaining,cost_per_share'),
      D.get('ticker_quotes_latest?select=ticker,spot'),
      D.get('option_greeks_latest?select=option_trade_id,delta,iv,last_mark'),
      D.get('ticker_names?select=ticker,name'),
      D.get('ticker_iv_daily?select=ticker,atm_iv,snapshot_date&order=snapshot_date.desc'),
      D.get(`analyst_insights?date=gte.${ago(90)}&select=ticker,date,price_target`),
      D.get('ticker_levels?select=ticker,kind,price'),
    ]);

    const spot = new Map<string, number>();
    for (const q of quotes) spot.set(String(q.ticker), N(q.spot));
    const co = new Map<string, string>();
    for (const n of names) co.set(String(n.ticker), String(n.name));
    const mark = new Map<string, { d: number; iv: number; m: number }>();
    for (const g of greeks) mark.set(String(g.option_trade_id), { d: N(g.delta), iv: N(g.iv), m: N(g.last_mark) });
    const tickIV = new Map<string, number>();
    for (const r of ivs) if (!tickIV.has(String(r.ticker))) tickIV.set(String(r.ticker), N(r.atm_iv));

    /* ── net every leg on its contract key ─────────────────────────────── */
    type Key = { ticker: string; type: string; k: number; exp: string;
      net: number; cash: number; ids: string[]; trades: Trade[] };
    const byKey = new Map<string, Key>();
    for (const t of trades as Trade[]) {
      const key = `${t.ticker}|${t.option_type}|${N(t.strike)}|${t.expiry}`;
      const e = byKey.get(key) ?? {
        ticker: String(t.ticker), type: String(t.option_type), k: N(t.strike),
        exp: String(t.expiry), net: 0, cash: 0, ids: [], trades: [],
      };
      const sign = (String(t.action) === 'open' ? 1 : -1) * (String(t.direction) === 'long' ? 1 : -1);
      e.net += sign * N(t.contracts);
      /* Signed cash from Nik's side: a credit is positive, a debit negative.
         Opening a short or closing a long brings cash IN. */
      const cashIn = (String(t.direction) === 'short') === (String(t.action) === 'open');
      e.cash += (cashIn ? 1 : -1) * N(t.contracts) * N(t.premium) * 100;
      e.ids.push(String(t.id));
      e.trades.push(t);
      byKey.set(key, e);
    }

    const legDescr = (t: Trade, k: Key) => {
      const side = String(t.direction) === 'long'
        ? (String(t.action) === 'open' ? 'Bought' : 'Sold')
        : (String(t.action) === 'open' ? 'Sold' : 'Bought back');
      const note = String(t.note ?? '');
      if (note.startsWith('IBKR A ')) return `Assigned on ${N(t.contracts)} × ${fmtK(k.k)} ${k.type === 'call' ? 'C' : 'P'}`;
      if (note.startsWith('IBKR Ex ')) return `Exercised ${N(t.contracts)} × ${fmtK(k.k)} ${k.type === 'call' ? 'C' : 'P'}`;
      if (note.startsWith('IBKR Ep ') || String(t.source) === 'expiry') return `Expired worthless`;
      return `${side} ${N(t.contracts)} × ${expLabel(k.exp, year)} ${fmtK(k.k)} ${k.type === 'call' ? 'C' : 'P'} @ ${N(t.premium).toFixed(2)}`;
    };
    const cashOf = (t: Trade) => {
      const cashIn = (String(t.direction) === 'short') === (String(t.action) === 'open');
      return (cashIn ? 1 : -1) * N(t.contracts) * N(t.premium) * 100;
    };

    /* ── the universe: any name with a live option leg or shares ────────── */
    const held = new Set<string>();
    for (const e of byKey.values()) if (Math.abs(e.net) > 0.0001 && e.exp >= today) held.add(e.ticker);
    for (const l of lots) held.add(String(l.ticker));

    const tickers = [...held].sort();

    /* ── expiries per name from Polygon, in parallel ────────────────────── */
    const chains = new Map<string, string[]>();
    await Promise.all(tickers.map(async (t) => {
      try {
        const u = new URL(`${POLY}/v3/reference/options/contracts`);
        u.searchParams.set('underlying_ticker', t);
        u.searchParams.set('expired', 'false');
        u.searchParams.set('limit', '1000');
        u.searchParams.set('apiKey', polygonKey);
        const r = await fetch(u);
        if (!r.ok) throw new Error(String(r.status));
        const j = await r.json() as { results?: { expiration_date?: string }[] };
        const set = new Set<string>();
        for (const c of (j.results ?? [])) if (c.expiration_date) set.add(c.expiration_date);
        chains.set(t, [...set].sort());
      } catch { chains.set(t, []); }
    }));

    /* ── daily closes per name, ascending, for the EMAs and ranges ──────── */
    const closesBy = new Map<string, { d: string; c: number }[]>();
    await Promise.all(tickers.map(async (t) => {
      const rows = await D.get(`daily_closes?ticker=eq.${t}&date=gte.${ago(400)}&select=date,close_price&order=date.asc`);
      closesBy.set(t, rows.map((r: Trade) => ({ d: String(r.date), c: N(r.close_price) })));
    }));

    const book = tickers.map((t) => {
      const S = spot.get(t) ?? 0;
      const closes = closesBy.get(t) ?? [];
      const cs = closes.map((x) => x.c);
      const last = cs.length ? cs[cs.length - 1] : S;
      const prev = cs.length > 1 ? cs[cs.length - 2] : last;
      /* Day change against the prior close; if the spot is stale to the
         close, the change is the close's own move. */
      const ref = S > 0 && S !== last ? last : prev;
      const chg = ref > 0 ? r2(((S || last) / ref - 1) * 100) : 0;

      const wk = cs.slice(-252);
      const d5 = cs.slice(-5);

      /* ── live legs ────────────────────────────────────────────────────── */
      const legs = [...byKey.values()]
        .filter((e) => e.ticker === t && Math.abs(e.net) > 0.0001 && e.exp >= today)
        .map((e) => {
          const md = e.ids.map((i) => mark.get(i)).filter(Boolean) as { d: number; iv: number; m: number }[];
          const mk = md.length ? md.reduce((s, x) => s + x.m, 0) / md.length : null;
          const iv = md.length ? md.reduce((s, x) => s + x.iv, 0) / md.length : null;
          /* Entry mark: net cash over contracts, per share. Sign-free — the
             leg's qty carries the side. */
          const premium = Math.abs(e.cash) / (Math.abs(e.net) * 100);
          return {
            id: `${t}-${e.type[0]}-${e.k}-${e.exp}`,
            kind: e.type, qty: Math.round(e.net), strike: e.k, expiry: e.exp,
            premium: r2(premium),
            mark: mk === null ? null : r2(mk),
            iv: iv && iv > 0 ? r2(iv) : null,
            history: e.trades.map((tr) => [dayLabel(String(tr.trade_date)), legDescr(tr, e), Math.round(cashOf(tr))]),
          };
        })
        .sort((a, b) => a.expiry.localeCompare(b.expiry) || a.strike - b.strike);

      for (const l of lots) {
        if (String(l.ticker) !== t) continue;
        const qty = N(l.qty_remaining), basis = N(l.cost_per_share);
        legs.unshift({
          id: `${t}-stock`, kind: 'stock', qty, strike: 0, expiry: '', premium: 0,
          mark: null, iv: null,
          basis,
          history: [[dayLabel(today), `Holding ${qty} sh @ ${basis.toFixed(2)}`, -Math.round(qty * basis)]],
        } as unknown as typeof legs[number]);
      }

      /* ── closed legs: fully flat, or expired ──────────────────────────── */
      const closed = [...byKey.values()]
        .filter((e) => e.ticker === t && (Math.abs(e.net) < 0.0001 || e.exp < today))
        .map((e) => {
          const opens = e.trades.filter((x) => String(x.action) === 'open');
          const short = opens.length ? String(opens[0].direction) === 'short' : e.net < 0;
          const n = opens.reduce((s, x) => s + N(x.contracts), 0);
          const notes = e.trades.map((x) => String(x.note ?? ''));
          const outcome =
            notes.some((s) => s.startsWith('IBKR A ')) ? 'Assigned'
            : notes.some((s) => s.startsWith('IBKR Ex ')) ? 'Exercised'
            : (notes.some((s) => s.startsWith('IBKR Ep ')) || e.trades.some((x) => String(x.source) === 'expiry') || e.exp < today && Math.abs(e.net) > 0.0001) ? 'Expired worthless'
            : short ? 'Bought back' : 'Sold';
          const first = String(opens[0]?.trade_date ?? e.trades[0].trade_date).slice(0, 10);
          const lastT = String(e.trades[e.trades.length - 1].trade_date).slice(0, 10);
          const when = outcome === 'Expired worthless'
            ? `opened ${dayLabel(first).slice(0, -5)} · expired ${dayLabel(e.exp)}`
            : outcome === 'Assigned' || outcome === 'Exercised'
            ? `${n * 100} sh ${e.type === 'call' ? 'called away' : 'put to you'} ${dayLabel(lastT)}`
            : `opened ${dayLabel(first).slice(0, -5)} · closed ${dayLabel(lastT)}`;
          return {
            title: `${n} × ${expLabel(e.exp, year)} ${fmtK(e.k)} ${e.type === 'call' ? 'C' : 'P'}`,
            side: short ? 'sold' : 'bought',
            outcome, pnl: Math.round(e.cash), when, expiry: e.exp, closedOn: lastT,
          };
        })
        .sort((a, b) => b.closedOn.localeCompare(a.closedOn));

      /* ── analyst target, same rule as the New page ───────────────────── */
      const tg = (acts as Trade[])
        .filter((a) => String(a.ticker) === t && N(a.price_target) > 0)
        .map((a) => N(a.price_target)).sort((x, y) => x - y);
      const target = tg.length
        ? { low: tg[0], median: tg[Math.floor(tg.length / 2)], high: tg[tg.length - 1], n: tg.length }
        : null;

      const lv = (levels as Trade[]).filter((l) => String(l.ticker) === t)
        .map((l) => [String(l.kind).toUpperCase(), N(l.price)] as [string, number]);

      const legIV = legs.map((l) => (l as { iv: number | null }).iv).filter((v): v is number => !!v);
      const iv = tickIV.get(t) ?? (legIV.length ? legIV.reduce((a, b) => a + b, 0) / legIV.length : 0.35);

      return {
        ticker: t, name: co.get(t) ?? t, spot: r2(S || last), chg, iv: r2(iv),
        emas: [['EMA 200', ema(cs, 200)], ['EMA 50', ema(cs, 50)], ['EMA 20', ema(cs, 20)]]
          .filter((e) => e[1] !== null),
        levels: lv,
        wk52: wk.length ? [Math.min(...wk), Math.max(...wk)] : null,
        /* The time-at-price histogram bins these; the page has no other
           source for a year of closes. */
        closes: wk,
        d5: d5.length ? [Math.min(...d5), Math.max(...d5)] : null,
        target,
        chain: chains.get(t) ?? [],
        legs, closed,
      };
    });

    return json(200, { ok: true, build: BUILD, date: today, book });
  } catch (e) {
    return json(500, { ok: false, build: BUILD, error: String((e as Error)?.message ?? e) });
  }
});
