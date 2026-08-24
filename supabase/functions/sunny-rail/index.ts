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

const BUILD = '2026-08-24.2';
const N = (v: unknown, d = 0) => (v === null || v === undefined || v === '' ? d : Number(v));

/** The rail abbreviates money: $400k, never $400,000. */
function money(v: number): string {
  const a = Math.abs(Math.round(v));
  if (a >= 1_000_000) return `$${(a / 1_000_000).toFixed(1)}m`;
  if (a >= 1_000) return `$${Math.round(a / 1000)}k`;
  return `$${a.toLocaleString('en-US')}`;
}

type Span = { text: string; kind: 'word' | 'figure' | 'minor' };

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  try {
    const D = db(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    const today = parseISO(nyToday());

    const todayISO = ymd(today);
    const [lots, divs, rates, shorts] = await Promise.all([
      D.get('share_lots?voided_at=is.null&qty_remaining=gt.0&select=ticker,qty_remaining,cost_per_share'),
      D.get('dividends?ticker=eq.TLT&select=ex_date,cash_amount,frequency&order=ex_date.desc&limit=1'),
      D.get('rates_daily?series=eq.DGS10&select=date,value&order=date.desc&limit=1'),
      D.get(`option_trades?voided_at=is.null&direction=eq.short&expiry=gte.${todayISO}`
        + '&select=ticker,option_type,strike,expiry,action,contracts,premium'),
    ]);

    const facts: Array<{ key: string; spans: Span[]; projected?: boolean }> = [];

    const invested = lots.reduce((s, l) => s + N(l.qty_remaining) * N(l.cost_per_share), 0);

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
      rates_asof: r0 ? String(r0.date).slice(0, 10) : null,
      open_premium: Math.round(openPremium),
      omitted: [],
    });
  } catch (e) { return json(500, { ok: false, error: String(e) }); }
});
