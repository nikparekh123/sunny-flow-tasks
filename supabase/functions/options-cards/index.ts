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

const BUILD = '2026-09-09.2';
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

    const [legs, allShorts, allPuts, quotes, greeks, greeksHist, names, closes] = await Promise.all([
      D.get(`option_trades?voided_at=is.null&expiry=gte.${today}`
        + '&select=id,ticker,option_type,direction,action,contracts,strike,expiry,premium,trade_date'),
      /* ⚠ SHORT PUTS COUNT HERE TOO. Nik, 2026-09-08: "short calls only shuold
         also include short puts as well." The weekly bars were calls-only
         while Roll check's footer summed both, so the same week read 2.7% on
         one card and 2.8% on the other, the $235 gap being an NFLX short put.
         The weekly yield is what the book earned that week, and a sold put
         earned it. It is also still the numerator of the put cover ring, and
         that is not double counting: the ring asks how much of the hedge is
         paid off, this asks what the week returned on capital. The rule the
         ring does keep is the one that matters, that CALL premium never
         funds the puts. */
      D.get('option_trades?voided_at=is.null&direction=eq.short'
        + '&select=ticker,option_type,action,contracts,premium,trade_date,expiry&order=trade_date.asc'),
      /* ⚠ SHORT PUTS ARE A SEPARATE SERIES AND MUST STAY SEPARATE. They fund the
         long puts and nothing else. Nik, 2026-09-06, on whether the cover ring
         should count call premium: it must not, because call premium is already
         the numerator of Yield progress, and one dollar cannot discharge two
         obligations on two cards. */
      /* ⚠ NO EXPIRY FILTER, BOTH DIRECTIONS. The cover ring is cumulative and
         never resets, so a put that has already expired still spent its money
         and its funding week still counted. Filtering to live legs the way the
         `legs` query does would quietly shrink the cost every time a tranche
         ran off, and the ring would climb for no reason. */
      D.get('option_trades?voided_at=is.null&option_type=eq.put'
        + '&select=ticker,direction,action,contracts,strike,premium,trade_date,expiry&order=trade_date.asc'),
      D.get('ticker_quotes_latest?select=ticker,spot'),
      D.get('option_greeks_latest?select=option_trade_id,delta,last_mark'),
      D.get(`option_greeks?captured_at=gte.${ago(12)}`
        + '&select=option_trade_id,delta,last_mark,captured_at&order=captured_at.desc'),
      D.get('ticker_names?select=ticker,name'),
      /* ⚠ SIXTY CALENDAR DAYS, NOT TWENTY-ONE ROWS. The furthest window is
         four TRADING weeks, which is 21 sessions, and 21 sessions spans more
         than 21 days across two holidays. Fetching by date and counting rows
         client-side is the only way the count stays a count of sessions. */
      D.get(`daily_closes?date=gte.${ago(60)}&select=ticker,date,close_price`
        + '&order=date.desc'),
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
    for (const t of allShorts) {
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
    /* ⚠ THE TRADING WEEK ENDS AT FRIDAY'S CLOSE, NOT SUNDAY MIDNIGHT. An ISO
       week runs Mon-Sun, so on a Saturday or Sunday `weekStart(today)` returns
       the week that has ALREADY EXPIRED — and every leg still open covers the
       week ahead. On Sunday 2026-09-06 that had the roll card showing $5,267
       of credit for legs expiring Friday the 11th while the weekly-yield card
       called this week $4,243, whose legs were gone. Both were right and the
       pair was useless.

       Nik: "Numbers shuold change on Friday night on Saturday morning for next
       week." So the weekend belongs to the week AHEAD. Bucketing is untouched
       — a call expiring Fri 11 Sep still files under Mon 7 Sep — it is only
       the question "which week is now" that moves. */
    const dow = new Date(today + 'T00:00:00Z').getUTCDay();   // 0 Sun, 6 Sat
    const thisWeek = (dow === 0 || dow === 6)
      ? new Date(Date.parse(weekStart(today) + 'T00:00:00Z') + 7 * 86_400_000)
          .toISOString().slice(0, 10)
      : weekStart(today);
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

    /* Per name, for the ticker page's own yield progress. */
    const putCostBy = new Map<string, number>();
    for (const e of open) {
      if (e.dir !== 'long' || e.type !== 'put') continue;
      putCostBy.set(e.ticker, (putCostBy.get(e.ticker) ?? 0) + e.cash);
    }

    const positions = open
      .filter((e) => e.dir === 'long' && e.type === 'call')
      .map((leap) => {
        const t = leap.ticker;
        const S = spot.get(t) ?? 0;
        const paid = leap.cash;
        const md = leap.ids.map((i) => mark.get(i)).filter(Boolean) as { d: number; m: number }[];
        const dLong = md.length ? md.reduce((s, x) => s + x.d, 0) / md.length : 0;
        /* ⚠ AN UNPRICED LEAP IS NOT A WORTHLESS ONE. This fell back to 0,
           so a LEAP bought minutes ago reported mark = $0 and the Long calls
           card showed LULU at -100.0% on the day it was opened. Same mistake
           as the short legs' captured = 100%, one side over. `leapPriced`
           says whether a price exists, and until one does the mark equals
           what was paid, so the gain reads 0.0% rather than a total loss. */
        const leapPriced = md.length > 0;
        const m = leapPriced
          ? md.reduce((s, x) => s + x.m, 0) / md.length
          : (leap.n > 0 ? paid / (leap.n * 100) : 0);
        const wa = leap.ids.map((i) => weekAgo.get(i)).filter((x) => x !== undefined) as number[];
        const prev = wa.length ? wa.reduce((s, x) => s + x, 0) / wa.length : 0;

        const shorts = open.filter((e) =>
          /* Sold PUTS join sold calls here. Roll check answers "what did I
             sell", and after 2026-09 that is both. */
          e.ticker === t && e.dir === 'short').map((s) => {
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
              /* ⚠ MONEYNESS INVERTS ON A PUT. A call is in the money ABOVE its
                 strike, a put BELOW it. The card colours every row and counts
                 ROLLING off this flag, so hard-coding the call rule would have
                 painted every sold put backwards — green when it was about to
                 be assigned. */
              type: s.type,
              value: Math.round(value), priced,
              itm: s.type === 'put' ? S < s.k && S > 0 : S > s.k,
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
          paid: Math.round(paid), mark: Math.round(m * leap.n * 100), leapPriced,
          /* Capital to earn back on this name: the LEAP plus any long puts.
             `paid` stays the LEAP alone because `mark - paid` is its gain. */
          invested: Math.round(paid + (putCostBy.get(t) ?? 0)),
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
    /* ⚠ EACH WEEK DIVIDES BY THE PREMIUM PAID AS OF THAT WEEK, NOT TODAY'S.
       Nik, 2026-09-08: "why does it rebalance and change the % of the previous
       weeks it shouldnt. When a new positions is added and % changes it cant
       change weeks that have passed." He is right and it was a real defect.
       The denominator was `paidTotal`, so buying a LEAP on a Tuesday rewrote
       every bar back to July. A week that has closed is a fact.

       The ledger is the LEAPs CURRENTLY HELD, dated by their own fills, not
       every long call ever traded. That keeps the last bar and Yield progress
       dividing by the same number, which is the reason this whole function
       exists, and it stops a closed position's realized gain from shrinking a
       past week's denominator. */
    /* ⚠ INVESTED IS CALLS PLUS PUTS. Nik, 2026-09-08: "does it calculate the
       put cost or not? if not it shuold consider the total investment of the
       account not just calls." It did not, and once short puts became income
       this morning the omission was incoherent: the premium counted but the
       capital it was earned on did not. This supersedes ruling 2 of 2026-09-06
       ("put cost does not join Yield progress's denominator"), and he chose to
       move BOTH cards so `paid` never means two things on one page.

       ⚠ BUT A POSITION'S OWN `paid` STAYS LEAP-ONLY. The Long calls card reads
       `mark - paid` as the LEAP's gain; folding put cost into that would report
       a loss the LEAP did not have. Capital-to-earn-back and cost-basis-of-the-
       mark are two different quantities that happened to share a field. */
    const investedKeys = new Set(
      open.filter((e) => e.dir === 'long')
          .map((e) => `${e.ticker}|${e.type}|long|${e.k}|${e.exp}`));
    const paidByDay = new Map<string, number>();
    for (const t of legs) {
      if (String(t.direction) !== 'long') continue;
      const key = `${t.ticker}|${t.option_type}|${t.direction}|${N(t.strike)}`
        + `|${String(t.expiry).slice(0, 10)}`;
      if (!investedKeys.has(key)) continue;
      const d = String(t.trade_date).slice(0, 10);
      const c = (String(t.action) === 'open' ? 1 : -1) * N(t.contracts) * N(t.premium) * 100;
      paidByDay.set(d, (paidByDay.get(d) ?? 0) + c);
    }
    const paidDates = [...paidByDay.keys()].sort();
    /* ⚠ THE PROGRAMME BEGINS AT THE FIRST LEAP, AND THAT IS THE FALLBACK TEST.
       Testing `dated > 0` looked equivalent and was not: a single FIS put
       bought on 26 Aug, at a strike later re-bought, put $1,750 of capital into
       the week of 24 Aug. That week collected $6,085 against shares he no
       longer holds, so the bar read 347.71% — arithmetically correct and
       meaningless. A week that ENDS before the first LEAP was bought predates
       the programme entirely, whatever stray capital existed, and takes today's
       total by Nik's ruling. */
    const leapKeys = new Set(
      open.filter((e) => e.dir === 'long' && e.type === 'call')
          .map((e) => `${e.ticker}|call|long|${e.k}|${e.exp}`));
    /* From the FILLS, not from a leg's `opened` — that field takes whichever
       row the unordered query returned first, which is not necessarily the
       earliest of a multi-fill LEAP. */
    const firstLeap = legs
      .filter((t) => String(t.option_type) === 'call' && String(t.direction) === 'long'
        && leapKeys.has(`${t.ticker}|call|long|${N(t.strike)}`
          + `|${String(t.expiry).slice(0, 10)}`))
      .map((t) => String(t.trade_date).slice(0, 10))
      .sort()[0] ?? '9999-12-31';
    /** Everything invested — LEAPs and long puts — as at the END of a week. */
    const paidAsOf = (weekMonday: string) => {
      const end = new Date(Date.parse(weekMonday + 'T00:00:00Z') + 6 * 86_400_000)
        .toISOString().slice(0, 10);
      let sum = 0;
      for (const d of paidDates) { if (d > end) break; sum += paidByDay.get(d)!; }
      return sum;
    };

    /* Summed from the ledger, not from `positions`, so a long put on a name
       with no LEAP still counts as money at work rather than vanishing. */
    const investedTotal = Math.round(
      [...paidByDay.values()].reduce((a, b) => a + b, 0));

    const bookWeekly = weeks.map((w) => {
      let c = 0;
      for (const p of positions) c += (creditByWeek.get(p.t)?.get(w) ?? 0);
      /* ⚠ THE FALLBACK IS A RULING, NOT A GUARD. Before 31 Aug there were no
         LEAPs at all — the book was still in shares — so those weeks have
         nothing to divide by. Nik chose to keep them on today's total rather
         than show them blank. They are therefore the ONLY bars that still
         drift, and they roll out of the eight-week window by late September,
         taking the drift with them. Do not "fix" this into a zero. */
      const weekEnd = new Date(Date.parse(w + 'T00:00:00Z') + 6 * 86_400_000)
        .toISOString().slice(0, 10);
      const dated = paidAsOf(w);
      const denom = (weekEnd >= firstLeap && dated > 0) ? dated : investedTotal;
      /* ⚠ WHICH BAR IS "NOW" IS NO LONGER THE LAST ONE. The window reaches
         forward, so the final column can be a week already sold but not yet
         begun — and the card was painting THAT one as the live week. The
         server says which is current; the client must not infer it from a
         position in the array. */
      return { week: w, credit: Math.round(c), current: w === thisWeek,
               pct: denom > 0 ? r2(c / denom * 100) : 0 };
    });
    const legCount = positions.reduce((s, p) => s + p.shorts.length, 0);
    /* ⚠ THE ROLL CHECK FOOTER IS COMPUTED HERE, NOT ON THE CLIENT, for the
       reason this whole function exists: two cards that derive the same figure
       separately will disagree eventually. Both divide by the same premium
       paid, always.

       ⚠ BUT THE NUMERATORS ARE NOT THE SAME QUESTION, and they part company
       the moment a leg is closed inside its own week. `openCredit` is the
       credit on the legs STILL OPEN; the weekly bar is what the week EARNED,
       closed legs included. On 8 Sep Nik bought back the NFLX 83 call for
       0.05 after selling it at 0.65, so the week reads 6,126 and Roll check
       reads 5,826 — the 300 is that call, kept and gone. Both are right. Do
       not "reconcile" them by dropping closed legs from the week; that would
       delete realized income from the yield. */
    const openCredit = positions.reduce((s, p) =>
      s + p.shorts.reduce((a, x) => a + x.credit, 0), 0);
    const openValue = positions.reduce((s, p) =>
      s + p.shorts.reduce((a, x) => a + (x.priced ? x.value : x.credit), 0), 0);
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
    /* ⚠ AND A WEEK THAT HAS NOT HAPPENED IS NOT A WEEK THAT RAN. The window
       reaches forward now, so a call written today for next Friday puts a real
       credit in a future column — $120 of it — and that column was landing in
       the average as a complete week at 0.05%, dragging the book rate from
       2.5% to 1.85% and Yearly from 133% to 96%. The forward bar still DRAWS,
       because the credit is banked and hiding it would understate the week; it
       just cannot be averaged as though it were finished. */
    const liveWeeks = bookWeekly.filter((w) => w.credit !== 0 && w.week <= thisWeek);
    const avgPct = liveWeeks.length
      ? liveWeeks.reduce((s, w) => s + w.pct, 0) / liveWeeks.length : 0;

    /* ── inventory ─────────────────────────────────────────────────────────
       handoff/cards/inventory.md. ONE MARK IS ONE CONTRACT — the card draws a
       circle per contract, so the server ships COUNTS and never a percentage or
       a ratio. `held - sold` is the only derived figure and the client does it,
       exactly as the sheet requires: a corrected count then fixes every mark,
       both footer figures and the header in one edit.

       ⚠ HELD AND SOLD ARE BOTH *CURRENTLY OPEN*. A short call that already
       expired is not written against anything any more, so it must not grey out
       a LEAP that is free to sell again. This is an inventory, not a history. */
    const inv = new Map<string, { ch: number; cs: number; ph: number; ps: number }>();
    for (const e of open) {
      const row = inv.get(e.ticker) ?? { ch: 0, cs: 0, ph: 0, ps: 0 };
      const n = Math.round(Math.abs(e.n));
      if (e.type === 'call') { if (e.dir === 'long') row.ch += n; else row.cs += n; }
      else { if (e.dir === 'long') row.ph += n; else row.ps += n; }
      inv.set(e.ticker, row);
    }
    const inventory = [...inv.entries()]
      /* A name with nothing held has nothing to draw. A name fully SOLD still
         gets a row — "NKE is fully worked" is a fact the card owes him. */
      .filter(([, r]) => r.ch + r.ph > 0)
      .map(([t, r]) => ({ t, callsHeld: r.ch, callsSold: r.cs,
                          putsHeld: r.ph, putsSold: r.ps }))
      .sort((a, b) => a.t.localeCompare(b.t));

    /* ── average credit per share ──────────────────────────────────────────
       handoff/cards/average-credit.md. Four weeks including this one, per side.

       ⚠ PER SHARE, NEVER PER CONTRACT: credit / contracts / 100, the number
       quoted when the trade is placed. The sheet's rule 0.1.

       ⚠ BUCKETED BY THE WEEK THE LEG COVERS, not the day it was sold. Nik,
       2026-09-03: "Which week it's sold for not the day it is sold", confirmed
       again for this card on 2026-09-08. Every other card on the page already
       buckets this way, so a week reads the same figure everywhere.

       ⚠ OPENS ONLY. Nik, 2026-09-08. The card asks what a contract SELLS for,
       and buying the NFLX 83 back at 0.05 does not change that it was sold at
       0.65. Weekly yield carries the net; this carries the rate.

       ⚠ A WEEK WITH NO TRADE ON A SIDE SHIPS null, NOT 0. The client draws no
       bar and keeps the key. Zero would say "sold at nothing" and, because the
       sheet's plot scale divides by the window's RANGE, it would drag the floor
       down and flatten the weeks that did trade. */
    const CREDIT_WEEKS = 4;
    const creditWeeks: string[] = [];
    for (let i = CREDIT_WEEKS - 1; i >= 0; i--) {
      creditWeeks.push(new Date(Date.parse(thisWeek + 'T00:00:00Z') - i * 7 * 86_400_000)
        .toISOString().slice(0, 10));
    }
    const bucket = new Map<string, { n: number; cash: number }>();  // `${side}|${week}`
    for (const t of allShorts) {
      if (String(t.action) !== 'open') continue;
      const w = weekStart(String(t.expiry).slice(0, 10));
      const k = `${t.option_type}|${w}`;
      const e = bucket.get(k) ?? { n: 0, cash: 0 };
      e.n += N(t.contracts);
      e.cash += N(t.contracts) * N(t.premium) * 100;
      bucket.set(k, e);
    }
    const sideWeeks = (side: string) => creditWeeks.map((w) => {
      const e = bucket.get(`${side}|${w}`);
      return {
        week: w,
        contracts: e ? Math.round(e.n) : 0,
        /* Two decimals, because this is a price and it is quoted in cents. */
        perShare: e && e.n > 0 ? Math.round(e.cash / e.n) / 100 : null,
      };
    });
    const credit = { week: thisWeek, calls: sideWeeks('call'), puts: sideWeeks('put') };

    /* ── stock price, five windows ─────────────────────────────────────────
       Nik, 2026-09-08: "Just like a roll check card can we do one for stock
       price. Same layout as Roll check the only added thing I want is adding
       1 week, 2 weeks, 3 weeks and 4 weeks filter", then "also need one for
       today" and "remove ref lines".

       ⚠ THE WINDOWS COUNT SESSIONS, NOT DAYS. A week is five trading days;
       counting calendar days would silently shorten every window that spans a
       holiday and would make "1 week" mean something different in July than in
       December. Offset 0 is the latest close, so `today` is spot against it and
       `w1` is spot against five sessions before that.

       ⚠ AND THE BOOK FIGURE IS WEIGHTED BY COST. The rows already say what each
       name did; an unweighted mean would only restate them and would call a 1%
       KR position the equal of a 24% BABA one. Weighting by `paid` makes the
       hero the one thing the rows cannot say — what his money did — and it uses
       the same cost basis the ticker strip's weights do, so the two can never
       disagree. */
    const closeRows = new Map<string, number[]>();   // ticker -> closes, newest first
    for (const r of closes) {
      /* ⚠ TODAY'S OWN CLOSE IS NOT IN THE SERIES. Once it lands (21:30 UTC) the
         anchor shifted onto it and `today` compared spot against ITSELF: every
         name read 0.0% and the card said "0 of 7 up" on a day the book moved.
         Offset 0 must always be the last close BEFORE today, which makes
         `today` genuinely today's move and keeps the week offsets from jumping
         a day when the close arrives. */
      if (String(r.date).slice(0, 10) >= today) continue;
      const t = String(r.ticker);
      if (!closeRows.has(t)) closeRows.set(t, []);
      closeRows.get(t)!.push(N(r.close_price));
    }
    const WINDOWS: [string, number][] =
      [['today', 0], ['w1', 5], ['w2', 10], ['w3', 15], ['w4', 20]];
    const moveFor = (t: string): Record<string, number | null> => {
      const S0 = spot.get(t) ?? 0;
      const cs = closeRows.get(t) ?? [];
      const out: Record<string, number | null> = {};
      for (const [key, back] of WINDOWS) {
        const base = cs[back];
        /* Null, never 0. A name with too little history has no move to report,
           and 0% would draw a flat bar that reads as "it did not move". */
        out[key] = (base && base > 0 && S0 > 0) ? r2((S0 / base - 1) * 100) : null;
      }
      return out;
    };
    const priceRows = positions.map((p) => ({
      ticker: p.t, weight: p.paid, pct: moveFor(p.t),
      /* The card swaps its value column to this on a tap. Nik, 2026-09-09:
         "When I tap on % can we show the stock price for each ticker". */
      spot: r2(spot.get(p.t) ?? 0),
    }));
    const bookMove: Record<string, number | null> = {};
    for (const [key] of WINDOWS) {
      let num = 0, den = 0;
      for (const r of priceRows) {
        const v = r.pct[key];
        if (v === null || r.weight <= 0) continue;
        num += v * r.weight; den += r.weight;
      }
      bookMove[key] = den > 0 ? r2(num / den) : null;
    }

    /* ── put cover ────────────────────────────────────────────────────────
       The long puts are the hedge; the short puts pay for them. The ring is
       one against the other, for the whole book.

       ⚠ IT NEVER RESETS. Nik, 2026-09-06: "It's a continous process when new
       stock is added new puts are added so not it never resets its
       continuous." So `cost` is every dollar ever spent NET on long puts and
       `collected` is every short-put credit ever. That is not a ratchet that
       ends life stuck at 100%: buying a tranche RAISES the cost and drops the
       ring, and the weeklies climb it back. Every purchase re-opens the gap,
       which is what makes a cumulative ring keep saying something.

       ⚠ AND CALL PREMIUM IS NOT IN IT. Yield progress already divides by call
       credits; counting them here would let one dollar discharge two different
       obligations on two cards that sit one above the other. */
    /* ⚠ THE PROGRAMME STARTS 1 SEP 2026 AND BOTH SIDES COUNT FROM THERE.
       Nik, 2026-09-08, seeing $105,892 of "put cost": "I havent bought puts
       worth 100K." He had not. The ring summed cash across every long put he
       had ever traded, so a June META put bought at 8.80 and sold at 2.00
       arrived here as $6,800 of COST. That is realized loss on a different
       programme, on names no longer in the book: $84,092 of the $105,892.

       "Never resets" was right and I read it too widely. It means a tranche
       running off does not wipe the number. It does not mean two eras of
       unrelated closed trades are the cost of this one.

       ⚠ MEMBERSHIP IS THE POSITION'S FIRST OPEN, NOT THE TRADE'S DATE. On
       1 Sep Nik closed ten August tranches. A `trade_date >= start` filter
       would have taken those closes without their opens, and the ring would
       have read −$3,035 collected against a negative cost. A position is in
       the programme when it was OPENED into it. */
    const PUT_START = '2026-09-01';
    const putKey = (t: Record<string, unknown>) =>
      `${t.ticker}|${t.direction}|${N(t.strike)}|${t.expiry}`;
    const firstOpen = new Map<string, string>();
    for (const t of allPuts) {
      if (String(t.action) !== 'open') continue;
      const k = putKey(t), d = String(t.trade_date).slice(0, 10);
      if (!firstOpen.has(k) || d < firstOpen.get(k)!) firstOpen.set(k, d);
    }
    /* A key with no open at all is pre-history, not a programme position. */
    const inProgramme = (t: Record<string, unknown>) => (firstOpen.get(putKey(t)) ?? '0000-00-00') >= PUT_START;

    const netLongPuts = new Map<string, number>();   // ticker -> contracts held
    let putCost = 0;
    for (const t of allPuts) {
      if (String(t.direction) !== 'long' || !inProgramme(t)) continue;
      const sign = String(t.action) === 'open' ? 1 : -1;
      const tk = String(t.ticker);
      netLongPuts.set(tk, (netLongPuts.get(tk) ?? 0) + sign * N(t.contracts));
      /* Net of any sold back, so rolling one does not inflate the cost. */
      putCost += sign * N(t.contracts) * N(t.premium) * 100;
    }
    const putNames = [...netLongPuts.entries()].filter(([, n]) => n > 0.0001);
    const putContracts = putNames.reduce((a, [, n]) => a + n, 0);

    /* Short-put credits, bucketed by the week they COVER, same rule the call
       side uses. */
    const putWeek = new Map<string, number>();
    for (const t of allPuts) {
      if (String(t.direction) !== 'short' || !inProgramme(t)) continue;
      const c = (String(t.action) === 'open' ? 1 : -1) * N(t.contracts) * N(t.premium) * 100;
      const w = weekStart(String(t.expiry).slice(0, 10));
      putWeek.set(w, (putWeek.get(w) ?? 0) + c);
    }
    const putCollected = [...putWeek.values()].reduce((a, b) => a + b, 0);
    /* Pace is the realised rate over the weeks that actually ran, never over
       the calendar — the same divisor Nik ruled on for the weekly yield. */
    const putLive = [...putWeek.values()].filter((v) => v !== 0);
    const putPace = putLive.length
      ? putLive.reduce((a, b) => a + b, 0) / putLive.length : 0;
    const putLeft = Math.round(putCost - putCollected);

    /* ⚠ THE HEDGE HAS A DEADLINE, AND A PROJECTION PAST IT IS NOT A PLAN.
       Nik, 2026-09-09: "the suggestion cannot be post expiry. We need to say
       that 2200 to be made to cover in 32 weeks."

       The card was dividing what is left by the realised pace and printing
       "full cover in 45 weeks". Every put in the book expires 19 Mar 2027,
       which is 27 weeks out, so 45 weeks describes a world in which the thing
       being paid off still exists. It does not. The question is the other way
       round: how much a week does it take to cover BEFORE they expire.

       The EARLIEST expiry sets the clock, not the furthest. When the first
       tranche lapses the cover it provided is gone, whatever the later ones
       are still doing. */
    const putExpiries = open
      .filter((e) => e.dir === 'long' && e.type === 'put')
      .map((e) => e.exp).sort();
    const putExpiry = putExpiries[0] ?? null;
    const putWeeksLeft = putExpiry
      ? Math.max(0, Math.ceil(
          (Date.parse(putExpiry + 'T00:00:00Z') - Date.parse(today + 'T00:00:00Z'))
          / (7 * 86_400_000)))
      : 0;
    /* What it takes per week to clear the remaining cost in the time left. */
    const putNeed = putWeeksLeft > 0 && putLeft > 0
      ? Math.ceil(putLeft / putWeeksLeft) : 0;

    return json(200, {
      ok: true, build: BUILD, date: today,
      /* Null when nothing is held: a ring at 0% of $0 is not an empty state,
         it is a card with no subject. The client drops it entirely. */
      putCover: putContracts > 0 && putCost > 0
        ? {
          names: putNames.length,
          puts: Math.round(putContracts),
          cost: Math.round(putCost),
          collected: Math.round(putCollected),
          left: putLeft,
          pace: Math.round(putPace),
          pct: r2(putCollected / putCost * 100),
          weeksToCover: putLeft > 0 && putPace > 0 ? Math.ceil(putLeft / putPace) : 0,
          /* The deadline, and the rate that meets it. */
          expiry: putExpiry,
          weeksLeft: putWeeksLeft,
          need: putNeed,
        }
        : null,
      /* `asOf` is the close the windows are measured FROM, so the card can
         say what "today" is against without the client guessing. */
      inventory,
      credit,
      prices: { rows: priceRows, book: bookMove,
                /* The close the windows are anchored to, which is the last one
                   BEFORE today, not the newest row in the table. */
                asOf: closes.map((r) => String(r.date).slice(0, 10))
                        .filter((d) => d < today).sort().pop() ?? today },
      book: {
        /* ⚠ `paid` IS NOW TOTAL INVESTED, and the label on the card says so.
           Every yield on this page divides by it. */
        paid: investedTotal,
        leapPaid: paidTotal,
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
        openCredit: Math.round(openCredit),
        openValue: Math.round(openValue),
        /* Gross: what the sold calls yield on the capital, before buying them
           back. The hero already carries the net as `kept`. */
        openYield: investedTotal > 0 ? r2(openCredit / investedTotal * 100) : 0,
        /* ⚠ THE OPEN LEGS DO NOT ALWAYS COVER "THIS WEEK", and the roll card
           said they did. An ISO week runs Mon-Sun, so on a SATURDAY OR SUNDAY
           the current week is the one that just ENDED and whose legs have
           already expired, while everything still open covers the week ahead.
           On Sunday 2026-09-06 that had the card printing "kept this week"
           over $5,267 of credit for legs expiring Friday the 11th, while the
           weekly-yield card correctly showed this week as $4,243. Both were
           right; the sentence was wrong.

           The server says which week the open legs actually cover, so the
           phrase follows the legs instead of asserting a week. */
        openWhen: (() => {
          const exps = positions.flatMap((p) => p.shorts.map((x) => weekStart(x.exp)));
          if (!exps.length) return 'this week';
          const w = exps.sort()[0];
          const d = Math.round((Date.parse(w) - Date.parse(thisWeek)) / (7 * 86_400_000));
          return d <= 0 ? 'this week' : d === 1 ? 'next week' : `in ${d} weeks`;
        })(),
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
