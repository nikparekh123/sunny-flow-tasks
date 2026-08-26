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

const BUILD = '2026-08-26.2';
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

async function companyName(t: string, k: string): Promise<string> {
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
    const [lots, divs, rates, shorts, closes, allShorts, quotes] = await Promise.all([
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
    ]);

    const facts: Array<{ key: string; spans: Span[]; projected?: boolean }> = [];

    const invested = lots.reduce((s, l) => s + N(l.qty_remaining) * N(l.cost_per_share), 0);

    /* One row per name that still holds shares, largest first. A name with no
       lots is absent rather than shown at 0% — the shell hides a heading with
       no card under it anyway, and a 0% row would claim a position he closed. */
    const byTicker = new Map<string, number>();
    for (const l of lots) {
      const t = String(l.ticker);
      byTicker.set(t, (byTicker.get(t) ?? 0) + N(l.qty_remaining) * N(l.cost_per_share));
    }
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
        days,
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

    return json(200, {
      ok: true, build: BUILD, asof: ymd(today),
      facts,
      book,
      rates_asof: r0 ? String(r0.date).slice(0, 10) : null,
      open_premium: Math.round(openPremium),
      omitted: [],
    });
  } catch (e) { return json(500, { ok: false, error: String(e) }); }
});
