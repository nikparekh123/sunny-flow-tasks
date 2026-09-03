/**
 * options-cards — the whole contract for the six option cards.
 *
 * Build sheet: handoff/options/OPTIONS-CARDS.md. One call feeds both surfaces,
 * because 2k's last bar must equal 2b's "this week" figure and two endpoints
 * would let them drift.
 *
 *   book       roll check · yield progress · weekly yield     (the New page)
 *   positions  weekly credit · the pair · pace to cover        (a name's page)
 *
 * ⚠ COLLECTED IS EVERY SHORT-CALL CREDIT EVER ON THE NAME, Nik's ruling on
 * 2026-09-02: "how much is collected from all the calls sold, that's as simple
 * as that." It therefore predates the LEAP — credits run from 20 May and the
 * LEAPs opened 31 Aug — so `weeksRun` counts from the FIRST CREDIT, not from
 * the LEAP's open, and `leapOpened` ships beside it so the card can say so.
 *
 * ⚠ EVERY LEG IS NETTED ON ITS CONTRACT KEY BEFORE IT COUNTS. A raw
 * `expiry >= today` scan reports positions that were opened and closed in the
 * same week; it put NVDA in the book at $71,489 with zero contracts
 * outstanding, because on a closed position the signed premium sum is realised
 * P&L wearing capital's coat.
 */
import { corsHeaders, json, db, nyToday } from
  'https://raw.githubusercontent.com/nikparekh123/sunny-flow-tasks/dd3c85a56102451ae439016d6a90460c4d41dab0/supabase/functions/_shared/planner.ts';

const BUILD = '2026-09-02.1';
const N = (v: unknown) => (v === null || v === undefined || v === '' ? 0 : Number(v));
const r2 = (v: number) => Math.round(v * 100) / 100;
const MON = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];

/** "30 × 75 · Jan 2028" — the sheet's contract line. */
function contractLine(n: number, k: number, iso: string, longForm: boolean) {
  const p = iso.split('-');
  const when = longForm
    ? `${MON[Number(p[1]) - 1]} ${p[0]}`
    : `${['Sun','Mon','Tue','Wed','Thu','Fri','Sat'][new Date(iso + 'T12:00:00Z').getUTCDay()]}`
      + ` ${Number(p[2])} ${MON[Number(p[1]) - 1]}`;
  return `${n} × ${k % 1 === 0 ? k : k.toFixed(2)} · ${when}`;
}

/** Monday of the ISO week an date falls in. */
const weekStart = (iso: string) => {
  const d = new Date(iso + 'T00:00:00Z');
  const off = (d.getUTCDay() + 6) % 7;
  d.setUTCDate(d.getUTCDate() - off);
  return d.toISOString().slice(0, 10);
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  try {
    const D = db(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    const today = nyToday();
    const ago = (d: number) => new Date(Date.parse(today + 'T00:00:00Z') - d * 86_400_000)
      .toISOString().slice(0, 10);

    const [legs, allCalls, quotes, greeks, greeksHist, names] = await Promise.all([
      D.get(`option_trades?voided_at=is.null&expiry=gte.${today}`
        + '&select=id,ticker,option_type,direction,action,contracts,strike,expiry,premium,trade_date'),
      D.get('option_trades?voided_at=is.null&option_type=eq.call&direction=eq.short'
        + '&select=ticker,action,contracts,premium,trade_date,expiry&order=trade_date.asc'),
      D.get('ticker_quotes_latest?select=ticker,spot'),
      D.get('option_greeks_latest?select=option_trade_id,delta,last_mark'),
      D.get(`option_greeks?captured_at=gte.${ago(12)}`
        + '&select=option_trade_id,delta,last_mark,captured_at&order=captured_at.desc'),
      D.get('ticker_names?select=ticker,name'),
    ]);

    const spot = new Map<string, number>();
    for (const q of quotes) spot.set(String(q.ticker), N(q.spot));
    const co = new Map<string, string>();
    for (const n of names) co.set(String(n.ticker), String(n.name));
    const mark = new Map<string, { d: number; m: number }>();
    for (const g of greeks) mark.set(String(g.option_trade_id), { d: N(g.delta), m: N(g.last_mark) });
    /* The oldest reading inside the window, per leg — `markWeek` needs a week
       ago and the LEAPs are days old, so this is the furthest back available
       rather than exactly seven days. It reads 0 until a week of history
       exists, which is honest and self-healing. */
    const weekAgo = new Map<string, number>();
    for (const g of greeksHist) weekAgo.set(String(g.option_trade_id), N(g.last_mark));

    /* ── net every open leg on its contract key ─────────────────────────── */
    type Leg = {
      ticker: string; type: string; dir: string; k: number; exp: string;
      n: number; cash: number; ids: string[]; opened: string;
    };
    const byKey = new Map<string, Leg>();
    for (const t of legs) {
      const key = `${t.ticker}|${t.option_type}|${t.direction}|${N(t.strike)}`
        + `|${String(t.expiry).slice(0, 10)}`;
      const e: Leg = byKey.get(key) ?? {
        ticker: String(t.ticker), type: String(t.option_type), dir: String(t.direction),
        k: N(t.strike), exp: String(t.expiry).slice(0, 10), n: 0, cash: 0, ids: [],
        opened: String(t.trade_date).slice(0, 10),
      };
      const sign = String(t.action) === 'open' ? 1 : -1;
      e.n += sign * N(t.contracts);
      e.cash += sign * N(t.contracts) * N(t.premium) * 100;
      if (String(t.action) === 'open') {
        e.ids.push(String(t.id));
        const d = String(t.trade_date).slice(0, 10);
        if (d < e.opened) e.opened = d;
      }
      byKey.set(key, e);
    }
    const open = [...byKey.values()].filter((e) => e.n > 0.0001);

    /* ── every credit ever, bucketed by week ────────────────────────────── */
    const creditByWeek = new Map<string, Map<string, number>>();
    const firstCredit = new Map<string, string>();
    for (const t of allCalls) {
      const tk = String(t.ticker);
      const d = String(t.trade_date).slice(0, 10);
      const c = (String(t.action) === 'open' ? 1 : -1) * N(t.contracts) * N(t.premium) * 100;
      if (!creditByWeek.has(tk)) creditByWeek.set(tk, new Map());
      const m = creditByWeek.get(tk)!;
      /* ⚠ THE WEEK A CREDIT BELONGS TO IS THE WEEK IT COVERS, NOT THE DAY IT
         WAS SOLD. Nik, 2026-09-03, after selling a BABA 114 for 11 Sep on the
         3rd and finding it nowhere: "Which week it's sold for not the day it
         is sold." Bucketing by trade_date put that credit in the week of the
         SALE, so a call written a week ahead landed on top of the week it was
         written in and the week it actually covers showed nothing.

         This rewrites every historical bar, deliberately. The question the
         card answers is what each week of COVERAGE earned, which is the only
         reading under which "3 of 8 weeks" and the weekly rate mean anything.
         A credit is now filed under its expiry's Monday. */
      const w = weekStart(String(t.expiry).slice(0, 10));
      m.set(w, (m.get(w) ?? 0) + c);
      if (!firstCredit.has(tk) || d < firstCredit.get(tk)!) firstCredit.set(tk, d);
    }

    /* The eight weeks the cards chart, newest last. Real zeros are weeks with
       no sale, not missing data — the sheet's `weekly[]` must sum to
       `collected`, so a gap is a zero and never a dropped column. */
    const thisWeek = weekStart(today);
    /* ⚠ AND THE WINDOW HAS TO REACH FORWARD, or expiry-bucketing achieves
       nothing: a call sold today for next Friday files under NEXT week, which
       an eight-week window ending on THIS week cannot show. The window now ends
       at the furthest week that actually carries a credit.

       Capped four weeks out. The shorts are weeklies, so a credit further ahead
       than that is a typo or a one-off, and either way it must not drag six
       empty columns into a chart that only has three live weeks in it. */
    const FORWARD_CAP = 4;
    let lastWeek = thisWeek;
    const capWeek = new Date(Date.parse(thisWeek + 'T00:00:00Z')
      + FORWARD_CAP * 7 * 86_400_000).toISOString().slice(0, 10);
    for (const m of creditByWeek.values()) {
      for (const [w, c] of m) if (c !== 0 && w > lastWeek && w <= capWeek) lastWeek = w;
    }
    const weeks: string[] = [];
    for (let i = 7; i >= 0; i--) {
      weeks.push(new Date(Date.parse(lastWeek + 'T00:00:00Z') - i * 7 * 86_400_000)
        .toISOString().slice(0, 10));
    }

    /* ⚠ THE TARGET IS 25 WEEKS TO COVER, NOT THE LEAP'S EXPIRY. Nik's ruling
       2026-09-02: "the pace should be more like 25 weeks to cover the
       investment, anything below is danger anything above is good."

       The sheet ramped to the LEAP's expiry, which is 72 weeks out, so every
       position sat as a flat line in the bottom-left corner and would have for
       months — the sheet flags that as "honest, and hard to read" at 21 weeks
       in; we are at three. A 25-week target is a standard the position can
       actually be measured against today.

       He also said "avg should be 3% each week roughly", and those two do not
       agree: 25 weeks implies 4.0% a week, 3% implies 33. TARGET_WEEKS is the
       one that ships because he named it first and definitely; change this
       single constant to move the standard. The book currently runs 2.78%. */
    const TARGET_WEEKS = 25;

    const positions = open
      .filter((e) => e.dir === 'long' && e.type === 'call')
      .map((leap) => {
        const t = leap.ticker;
        const S = spot.get(t) ?? 0;
        const paid = leap.cash;
        const md = leap.ids.map((i) => mark.get(i)).filter(Boolean) as { d: number; m: number }[];
        const dLong = md.length ? md.reduce((s, x) => s + x.d, 0) / md.length : 0;
        const m = md.length ? md.reduce((s, x) => s + x.m, 0) / md.length : 0;
        const wa = leap.ids.map((i) => weekAgo.get(i)).filter((x) => x !== undefined) as number[];
        const prev = wa.length ? wa.reduce((s, x) => s + x, 0) / wa.length : 0;

        const shorts = open.filter((e) =>
          e.ticker === t && e.dir === 'short' && e.type === 'call').map((s) => {
            const sm = s.ids.map((i) => mark.get(i)).filter(Boolean) as { d: number; m: number }[];
            /* ⚠ AN UNPRICED LEG IS NOT A FULLY CAPTURED ONE. `value` used to
               fall back to 0 when no mark existed, which made captured
               (credit − 0) / credit = 100%. Nik caught it on a BABA 114 sold
               minutes earlier: "baba is not 100% and cannot be 100% with one
               day remaining". Every newly sold leg read as a perfect capture
               until the next mp-refresh, and it inflated `kept` by the whole
               credit besides.

               `priced` is the truth of it. The value and captured FIELDS stay
               numeric rather than going null, because a shipped build decodes
               them as Int and an optional Decodable still throws on a changed
               shape — it tolerates a missing key, not a null one. So an
               unpriced leg reports value = credit and captured = 0, which nets
               to zero contribution everywhere, and the new build reads
               `priced` to render it as unknown rather than as break-even. */
            const priced = sm.length > 0;
            const value = priced
              ? (sm.reduce((a, x) => a + x.m, 0) / sm.length) * s.n * 100
              : s.cash;
            const credit = s.cash;
            return {
              n: s.n, k: s.k, exp: s.exp, credit: Math.round(credit),
              value: Math.round(value), itm: S > s.k, priced,
              /* ⚠ CAPTURED IS OF THE CREDIT RECEIVED, never the option's own
                 price change and never a dollar. It is the MONEY; `itm` is the
                 ACTION, and they disagree often on purpose. */
              captured: (priced && credit > 0) ? Math.round((credit - value) / credit * 100) : 0,
              delta: sm.length ? r2(sm.reduce((a, x) => a + x.d, 0) / sm.length) : 0,
              contract: contractLine(s.n, s.k, s.exp, false),
            };
          });

        const wk = creditByWeek.get(t) ?? new Map();
        const collected = [...wk.values()].reduce((a, b) => a + b, 0);
        const weekly = weeks.map((w) => Math.round(wk.get(w) ?? 0));
        /* ⚠ THE CLOCK STARTS WHEN THE LEAP OPENED, not at the first credit.
           `collected` is every credit ever, Nik's ruling, and NKE's run back to
           20 May — so counting from there made the pace card ask NKE for
           $45,300 of its $75,500 by now, when the thing being paid off has
           existed for three weeks. Credits earned before the LEAP still COUNT
           toward paying it off; they just mean the position starts ahead. What
           they cannot do is start the clock on an obligation that did not
           exist. */
        const weeksRun = Math.max(1, Math.round(
          (Date.parse(today) - Date.parse(leap.opened)) / (7 * 86_400_000)));
        const weeksLeft = Math.max(0, Math.round(
          (Date.parse(leap.exp) - Date.parse(today)) / (7 * 86_400_000)));
        const dShort = shorts.length
          ? shorts.reduce((a, s) => a + s.delta * s.n, 0) / shorts.reduce((a, s) => a + s.n, 0) : 0;
        const shortN = shorts.reduce((a, s) => a + s.n, 0);

        return {
          t, co: co.get(t) ?? t,
          leap: contractLine(leap.n, leap.k, leap.exp, true),
          leapOpened: leap.opened,
          paid: Math.round(paid), mark: Math.round(m * leap.n * 100),
          /* ⚠ A CHANGE IN MARK, NOT CASH THAT MOVED. A LEAP held all week moves
             no cash and still gains or loses every week. Zero until a week of
             `option_greeks` exists for a leg opened days ago. */
          markWeek: prev > 0 ? Math.round((m - prev) * leap.n * 100) : 0,
          collected: Math.round(collected),
          /* ⚠ THE SHEET'S INVARIANT NEEDED SPLITTING, not breaking. It says
             `weekly[] must sum to collected, checked numerically`, which holds
             only while a name's whole history fits the eight-week window. It
             does not: NKE and NFLX have credits from 20 May, so their weekly[]
             sums 3,815 and 4,713 against collected of 4,620 and 5,902.
             `collected` is all time, per Nik's ruling; `windowCredit` is what
             the bars actually total, and THAT is the figure the invariant now
             governs. A card that charts eight weeks and prints an all-time
             total must label which is which. */
          windowCredit: weekly.reduce((a, b) => a + b, 0),
          /* Same correction per name: FIS and PEP have run two weeks of the
             eight, so an eight-week divisor understates them fourfold. */
          liveWeeks: weekly.filter((v) => v !== 0).length,
          week: Math.round(wk.get(thisWeek) ?? 0),
          weekly, weeksRun, weeksLeft,
          longN: leap.n, shortN,
          targetWeeks: TARGET_WEEKS,
          /* What a straight line to a 25-week payback needs by now. Capped at
             the full premium: past week 25 the target is "all of it", not more. */
          neededByNow: Math.round(paid * Math.min(weeksRun, TARGET_WEEKS) / TARGET_WEEKS),
          dLong: r2(dLong), dShort: r2(dShort),
          /* ⚠ SHARE EQUIVALENTS, AND THE TWO LEG COUNTS ARE WEIGHTED
             SEPARATELY. The sheet's `contracts × 100 × (dLong − dShort)`
             assumes one short per long; NFLX runs 15 long against 14 short
             because Nik goes long-heavier when he is bullish, and that is
             deliberate rather than a rounding. */
          netDelta: Math.round(dLong * leap.n * 100 - dShort * shortN * 100),
          shorts,
        };
      })
      .filter((p) => p.paid > 0)
      .sort((a, b) => b.paid - a.paid);

    const paidTotal = positions.reduce((s, p) => s + p.paid, 0);
    const bookWeekly = weeks.map((w) => {
      let c = 0;
      for (const p of positions) c += (creditByWeek.get(p.t)?.get(w) ?? 0);
      /* ⚠ WHICH BAR IS "NOW" IS NO LONGER THE LAST ONE. The window reaches
         forward, so the final column can be a week already sold but not yet
         begun — and the card was painting THAT one as the live week. The
         server says which is current; the client must not infer it from a
         position in the array. */
      return { week: w, credit: Math.round(c), current: w === thisWeek,
               pct: paidTotal > 0 ? r2(c / paidTotal * 100) : 0 };
    });
    const legCount = positions.reduce((s, p) => s + p.shorts.length, 0);
    const rolling = positions.reduce((s, p) => s + p.shorts.filter((x) => x.itm).length, 0);
    /* Unpriced legs contribute nothing rather than their whole credit: value
       equals credit for them, so the subtraction is already zero. Filtered
       explicitly anyway, so the intent survives a change to that fallback. */
    const kept = positions.reduce((s, p) =>
      s + p.shorts.reduce((a, x) => a + (x.priced ? x.credit - x.value : 0), 0), 0);
    /* ⚠ THE AVERAGE COUNTS ONLY WEEKS THE BOOK ACTUALLY RAN. Nik caught this:
       the eight-week window reaches back before the position existed, so five
       zeros dragged the book rate from 2.78% to 1.04% and "Yearly" from 144%
       to 54% — a 2.7x understatement of the real run rate. The sheet is silent
       on the averaging window because it was authored against a book with
       eight full weeks behind it.

       The bars still chart all eight, zeros included, because a zero week is a
       fact and hiding it would make a young programme look established. It is
       the DIVISOR that changes, not the series. Once eight live weeks exist
       the two definitions converge and this stops mattering. */
    const liveWeeks = bookWeekly.filter((w) => w.credit !== 0);
    const avgPct = liveWeeks.length
      ? liveWeeks.reduce((s, w) => s + w.pct, 0) / liveWeeks.length : 0;

    return json(200, {
      ok: true, build: BUILD, date: today,
      book: {
        paid: paidTotal,
        collected: positions.reduce((s, p) => s + p.collected, 0),
        windowCredit: bookWeekly.reduce((s, w) => s + w.credit, 0),
        weekly: bookWeekly,
        avgPct: r2(avgPct),
        liveWeeks: liveWeeks.length,
        /* ⚠ THE LAST BAR IS NO LONGER THIS WEEK. Once the window reaches
           forward, bookWeekly's final column can be a week that has not
           started, so reading the footer's THIS WEEK off the end of the array
           would report next week's credit under this week's label. Key it on
           the current Monday instead. */
        thisWeek: bookWeekly.find((w) => w.week === thisWeek)?.credit ?? 0,
        bestWeek: Math.max(...bookWeekly.map((w) => w.credit)),
        /* ⚠ NOT A FORECAST. The eight-week average × 52, and the sheet keeps
           the caveat the one-word label cannot. */
        yearly: Math.round(avgPct * 52 * 100) / 100,
        legs: legCount,
        targetWeeks: TARGET_WEEKS,
        /* The weekly rate the target implies, so the card never has to
           re-derive it and the two can never disagree. */
        targetPct: r2(100 / TARGET_WEEKS),
        /* The leg count picks the form and nothing else does: ≤5 bars,
           6–10 paged, 11+ rows. */
        form: legCount <= 5 ? 'bars' : legCount <= 10 ? 'paged' : 'rows',
        rolling, nextExpiry: legCount - rolling, kept: Math.round(kept),
      },
      positions,
    });
  } catch (e) { return json(500, { ok: false, error: String(e) }); }
});
