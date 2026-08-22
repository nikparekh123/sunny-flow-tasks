/**
 * tlt-live — TLT's own card, on TLT's own rules.
 *
 * ⚠ THIS IS A SEPARATE FUNCTION ON PURPOSE. position-live is built on the
 * income sleeve: a block, one call and one put per 100 shares, a floor sized to
 * shares plus puts sold. TLT works NONE of those ways, and rendering it through
 * that card produced "sell -27 puts" and "your floor needs 49 contracts" in
 * Nik's real book. Two strategies, two functions, no shared branch to drift.
 *
 * docs/STRATEGIES.md, verbatim:
 *
 *   No block. No conviction. Sell puts on the second red day of a slide,
 *   nearest Friday, nearest strike, flat size. Assignment is how you buy it.
 *   The put IS the trade. There is no block underneath and nothing to protect.
 *
 * So the card asks three questions and no others:
 *   is the gate open      the second red day of a slide, or later
 *   what is out there     open puts, what they commit, what is assigned
 *   what moves it         RATES, not analysts. TLT rises when yields fall.
 *
 * There is deliberately NO floor section, NO covered-call section and NO
 * analyst block. Those belong to a strategy this book does not run.
 */
import { corsHeaders, json, db, ymd, parseISO, addDays, nyToday, daysBetween } from
  'https://raw.githubusercontent.com/nikparekh123/sunny-flow-tasks/dd3c85a56102451ae439016d6a90460c4d41dab0/supabase/functions/_shared/planner.ts';

const BUILD = '2026-08-22.1';
const POLY = 'https://api.polygon.io';
const T = 'TLT';
const N = (v: unknown, d = 0) => (v === null || v === undefined || v === '' ? d : Number(v));
const usd = (v: number) => `$${Math.round(v).toLocaleString('en-US')}`;
const MON = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
const day = (iso: string) => { const [, m, d] = String(iso).slice(0, 10).split('-'); return `${Number(d)} ${MON[Number(m) - 1]}`; };

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  try {
    const url = Deno.env.get('SUPABASE_URL')!;
    const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const pk = Deno.env.get('POLYGON_API_KEY')!;
    const D = db(url, key);
    const today = parseISO(nyToday());
    const todayISO = ymd(today);

    const [lots, trades, quote, closes, rates, macro, divs] = await Promise.all([
      D.get(`share_lots?ticker=eq.${T}&voided_at=is.null&qty_remaining=gt.0&select=qty_remaining,cost_per_share`),
      D.get(`option_trades?ticker=eq.${T}&voided_at=is.null&select=action,option_type,direction,contracts,strike,premium,expiry`),
      D.get(`ticker_quotes_latest?ticker=eq.${T}&select=spot,day_change_pct`),
      D.get(`scanner_closes?ticker=eq.${T}&select=date,close&order=date.desc&limit=300`),
      D.get(`rates_daily?select=series,date,value&order=date.desc&limit=400`),
      D.get(`macro_events?event_date=gte.${todayISO}&select=name,event_date,importance&order=event_date.asc&limit=6`),
      D.get(`dividends?ticker=eq.${T}&select=ex_date,pay_date,cash_amount,frequency&order=ex_date.desc&limit=3`),
    ]);

    const spot = N(quote[0]?.spot);
    const shares = lots.reduce((s, l) => s + N(l.qty_remaining), 0);
    const paid = lots.reduce((s, l) => s + N(l.qty_remaining) * N(l.cost_per_share), 0);
    const avg = shares ? paid / shares : 0;

    // net the legs
    const leg = new Map<string, { t: string; d: string; k: number; e: string; n: number }>();
    let credit = 0;
    for (const x of trades) {
      const k = `${x.option_type}|${x.direction}|${N(x.strike)}|${String(x.expiry).slice(0, 10)}`;
      const e = leg.get(k) ?? { t: String(x.option_type), d: String(x.direction), k: N(x.strike), e: String(x.expiry).slice(0, 10), n: 0 };
      e.n += (x.action === 'open' ? 1 : -1) * N(x.contracts);
      leg.set(k, e);
      if (x.direction === 'short') credit += N(x.contracts) * N(x.premium) * 100 * (x.action === 'open' ? 1 : -1);
    }
    const live = [...leg.values()].filter((l) => l.n > 0.0001 && l.e >= todayISO);
    const shortPuts = live.filter((l) => l.t === 'put' && l.d === 'short');
    const nShort = shortPuts.reduce((s, l) => s + l.n, 0);
    const committed = shortPuts.reduce((s, l) => s + l.n * 100 * l.k, 0);
    const longPuts = live.filter((l) => l.t === 'put' && l.d === 'long');

    /* THE DIP GATE. "Sell puts on the second red day of a slide, onward."
       Count consecutive lower closes ending at the latest session. One red day
       is not a slide; the rule starts at two. */
    const px = closes.map((r) => ({ d: String(r.date).slice(0, 10), c: N(r.close) })).reverse();
    let red = 0;
    for (let i = px.length - 1; i > 0; i--) {
      if (px[i].c < px[i - 1].c) red++; else break;
    }
    const gateOpen = red >= 2;

    /* RATES ARE TLT'S SITUATION. Analysts do not cover a Treasury ETF in any
       way that matters, and TLT moves on yields: when the long end sells off,
       TLT falls. That inversion is why a rising 10-year is BEARISH here. */
    const seriesAt = (s: string, back = 0) => {
      const rows = rates.filter((r) => String(r.series) === s);
      return rows.length > back ? N(rows[back].value) : null;
    };
    const chg = (s: string, back: number) => {
      const a = seriesAt(s, 0), b = seriesAt(s, back);
      return (a !== null && b !== null) ? (a - b) * 100 : null;   // basis points
    };

    const bear: string[] = [], bull: string[] = [], cat: string[] = [];
    const y10 = seriesAt('DGS10'), y2 = seriesAt('DGS2'), y30 = seriesAt('DGS30');
    const real10 = seriesAt('DFII10'), be10 = seriesAt('T10YIE');
    const d10w = chg('DGS10', 5), d10m = chg('DGS10', 20);
    if (y10 !== null) {
      const line = `10-year at ${y10.toFixed(2)}%`
        + (d10w !== null ? `, ${d10w >= 0 ? '+' : ''}${d10w.toFixed(0)}bp on the week` : '')
        + (d10m !== null ? `, ${d10m >= 0 ? '+' : ''}${d10m.toFixed(0)}bp on the month` : '');
      // Yields up is TLT down.
      ((d10m ?? 0) > 0 ? bear : bull).push(line);
    }
    if (y30 !== null) ((chg('DGS30', 20) ?? 0) > 0 ? bear : bull).push(`30-year at ${y30.toFixed(2)}%, the end TLT actually tracks`);
    if (y10 !== null && y2 !== null) {
      const sp = (y10 - y2) * 100;
      cat.push(`Curve ${sp >= 0 ? '+' : ''}${sp.toFixed(0)}bp, 2s10s${sp < 0 ? ', still inverted' : ''}`);
    }
    if (real10 !== null) cat.push(`Real 10-year ${real10.toFixed(2)}%, the part that is not inflation`);
    if (be10 !== null) cat.push(`Breakeven inflation ${be10.toFixed(2)}%`);
    for (const m of macro.slice(0, 3)) {
      cat.push(`${m.name} on ${day(String(m.event_date))}, ${daysBetween(today, parseISO(String(m.event_date)))} days out`);
    }
    const dv = divs[0];
    if (dv) {
      const y = N(dv.cash_amount) * (N(dv.frequency) || 12) / spot * 100;
      bull.push(`Distribution about ${y.toFixed(1)}% a year, paid monthly, last ex-date ${day(String(dv.ex_date))}`);
    }
    const stance = bear.length > bull.length ? 'Yields against you'
                 : bull.length > bear.length ? 'Yields with you' : 'Balanced';

    /* Nearest Friday, nearest strike. TLT writes EVERY available expiry, unlike
       NVDA which is Friday-only, so the nearest one is the right one. */
    const nextFri = (() => { const d = new Date(today.getTime());
      do { d.setUTCDate(d.getUTCDate() + 1); } while (d.getUTCDay() !== 5); return ymd(d); })();
    let quoteLine: string | null = null;
    if (gateOpen && spot) {
      try {
        const u = new URL(`${POLY}/v3/snapshot/options/${T}`);
        u.searchParams.set('expiration_date', nextFri);
        u.searchParams.set('contract_type', 'put');
        u.searchParams.set('strike_price.gte', String(Math.floor(spot * 0.94)));
        u.searchParams.set('strike_price.lte', String(Math.ceil(spot * 1.02)));
        u.searchParams.set('limit', '100');
        u.searchParams.set('apiKey', pk);
        const r = await fetch(u.toString());
        if (r.ok) {
          const cs = ((await r.json())?.results ?? []).map((c: Record<string, any>) => ({
            k: Number(c.details?.strike_price),
            mid: (c.last_quote?.bid > 0 && c.last_quote?.ask > 0) ? (c.last_quote.bid + c.last_quote.ask) / 2 : Number(c.day?.close ?? 0),
          })).filter((c: { k: number; mid: number }) => c.k > 0 && c.mid > 0);
          if (cs.length) {
            const near = cs.reduce((b: { k: number; mid: number }, c: { k: number; mid: number }) =>
              Math.abs(c.k - spot) < Math.abs(b.k - spot) ? c : b);
            quoteLine = `nearest strike ${near.k}, ${day(nextFri)}, about ${near.mid.toFixed(2)} each`;
          }
        }
      } catch { /* quote is a convenience */ }
    }

    const doList: string[] = [];
    if (gateOpen) {
      doList.push(`The gate is OPEN: ${red} red days in a row.`);
      doList.push(`Sell puts at your flat size${quoteLine ? `, ${quoteLine}` : `, nearest Friday, nearest strike`}.`);
    } else if (red === 1) {
      doList.push(`One red day. The rule starts on the second, so nothing today.`);
    } else {
      doList.push(`Not a slide. TLT last closed ${px.length > 1 && px[px.length - 1].c >= px[px.length - 2].c ? 'up' : 'flat'}, so the gate is shut.`);
    }
    if (nShort) doList.push(`${nShort} puts already out, ${usd(committed)} committed if every one is assigned.`);

    return json(200, {
      ok: true, build: BUILD, ticker: T, asof: todayISO, spot,
      stance, bearish: bear, supportive: bull, catalyst: cat,
      gate: { red_days: red, open: gateOpen, rule: 'second red day of a slide, onward' },
      stand: [
        `Spot ${spot.toFixed(2)}`,
        shares ? `${shares.toLocaleString('en-US')} shares at ${avg.toFixed(2)}, from assignment` : `No shares`,
        `${nShort} short puts out, ${usd(committed)} committed`,
        `${usd(credit)} credit taken on what is open`,
        longPuts.length ? `${longPuts.reduce((s, l) => s + l.n, 0)} long puts held` : `No long puts`,
      ],
      legs: live.map((l) => ({ type: l.t, dir: l.d, strike: l.k, expiry: l.e, contracts: l.n })),
      do: doList,
    });
  } catch (e) { return json(500, { ok: false, error: String(e) }); }
});
