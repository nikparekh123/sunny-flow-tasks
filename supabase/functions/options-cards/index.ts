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

const BUILD = '2026-09-17.5';
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

/* ⚠ POSTGREST CAPS EVERY READ AT 1,000 ROWS AND SAYS NOTHING. Found
   2026-09-10 while costing a per-minute mark refresh, and it was already
   corrupting two cards:

     ticker_iv_daily  1,215 rows, ordered ASC, so the card got the OLDEST
                      thousand and its volatility history stopped on 28 Aug.
                      Every "x its usual" and the book IV were twelve days
                      behind the market.
     option_greeks    8,532 rows over the twelve-day window, ordered DESC, so
                      `weekAgo` reached back about ONE DAY. The LEAP's "change
                      this week" was a one-day change wearing a week's label,
                      and at a one-minute capture it would have been 23 MINUTES.

   `page` walks the whole result with Range headers instead. It pages until a
   short page comes back, so it costs one extra round trip only when the table
   is genuinely over the cap. Every paged query needs a DETERMINISTIC order or
   a row can be seen twice or missed at a page boundary, which is why each one
   below carries a tiebreaker. The shared `db.get` is left alone: it is pinned
   by SHA and read by a dozen other functions. */
const PAGE = 1000;
async function page(url: string, key: string, path: string): Promise<Record<string, unknown>[]> {
  const out: Record<string, unknown>[] = [];
  for (let from = 0; ; from += PAGE) {
    const r = await fetch(`${url}/rest/v1/${path}`, {
      headers: {
        apikey: key, Authorization: `Bearer ${key}`,
        'Range-Unit': 'items', Range: `${from}-${from + PAGE - 1}`,
      },
    });
    if (!r.ok) break;
    const rows = (await r.json()) as Record<string, unknown>[];
    out.push(...rows);
    if (rows.length < PAGE) break;
    /* A runaway table must not hang the page. 50k rows is far past anything
       these queries can legitimately return. */
    if (out.length >= 50 * PAGE) break;
  }
  return out;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  try {
    const SB_URL = Deno.env.get('SUPABASE_URL')!;
    const SB_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const D = db(SB_URL, SB_KEY);
    const P = (path: string) => page(SB_URL, SB_KEY, path);
    const today = nyToday();
    const ago = (d: number) => new Date(Date.parse(today + 'T00:00:00Z') - d * 86_400_000)
      .toISOString().slice(0, 10);

    /* ⚠ THE PAYLOAD CARRIES ITS OWN TIMINGS, and they stay. Added 14 Sep 2026
       when the page went from under a second to seven and the new loading
       screen made it visible; one call then named the culprit exactly, with no
       guessing and no deploy cycle. A query that quietly grows is the failure
       mode this function has had twice now — the 1,000-row cap was the first —
       so the measurement is cheap insurance, not scaffolding. */
    const T0 = Date.now();
    const timings: Record<string, number> = {};
    const time = async <X>(k: string, f: () => Promise<X>): Promise<X> => {
      const t = Date.now();
      const r = await f();
      timings[k] = Date.now() - t;
      return r;
    };

    /* ⚠ ONE DAY, ONE PAGE — NEVER A WINDOW. `mp-refresh` writes every leg every
       minute, so 1,000 rows of `option_greeks` ordered newest-first covers
       roughly ten minutes and therefore every leg many times over. Paging a
       WINDOW of the same table is what made this page take seven seconds:
       twelve days is 62,432 rows and 63 round trips to build a map of one
       number per leg, and the whole rest of the function measured 360 ms.

       Walks up to five days from `from` in `step` direction so a weekend or a
       holiday still answers rather than shipping an empty map. */
    const greeksOn = async (from: string, select: string, step = -1) => {
      for (let i = 0; i < 5; i++) {
        const d = new Date(Date.parse(from + 'T00:00:00Z') + i * step * 86_400_000)
          .toISOString().slice(0, 10);
        const nd = new Date(Date.parse(d + 'T00:00:00Z') + 86_400_000)
          .toISOString().slice(0, 10);
        const r = await fetch(`${SB_URL}/rest/v1/option_greeks`
          + `?captured_at=gte.${d}T00:00:00Z&captured_at=lt.${nd}T00:00:00Z`
          + `&select=${select}&order=captured_at.desc&limit=1000`, {
          headers: { apikey: SB_KEY, Authorization: `Bearer ${SB_KEY}` },
        });
        if (!r.ok) continue;
        const rows = (await r.json()) as Record<string, unknown>[];
        if (rows.length) return { day: d, rows };
      }
      return { day: from, rows: [] as Record<string, unknown>[] };
    };

    const [legs, allShorts, allPuts, quotes, greeks, names, closes, ivHist] = await Promise.all([
      time('legs', () => D.get(`option_trades?voided_at=is.null&expiry=gte.${today}`
        + '&select=id,ticker,option_type,direction,action,contracts,strike,expiry,premium,trade_date')),
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
      time('allShorts', () => P('option_trades?voided_at=is.null&direction=eq.short'
        + '&select=ticker,option_type,action,contracts,premium,strike,trade_date,expiry'
        + '&order=trade_date.asc,ticker.asc,expiry.asc')),
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
      time('allPuts', () => P('option_trades?voided_at=is.null&option_type=eq.put'
        + '&select=ticker,direction,action,contracts,strike,premium,trade_date,expiry'
        + '&order=trade_date.asc,ticker.asc,strike.asc')),
      time('quotes', () => D.get('ticker_quotes_latest?select=ticker,spot')),
      time('greeksLatest', () => D.get('option_greeks_latest?select=option_trade_id,delta,last_mark')),
      time('names', () => D.get('ticker_names?select=ticker,name')),
      /* ⚠ SIXTY CALENDAR DAYS, NOT TWENTY-ONE ROWS. The furthest window is
         four TRADING weeks, which is 21 sessions, and 21 sessions spans more
         than 21 days across two holidays. Fetching by date and counting rows
         client-side is the only way the count stays a count of sessions. */
      time('closes', () => P(`daily_closes?date=gte.${ago(60)}&select=ticker,date,close_price`
        + '&order=date.desc,ticker.asc')),
      /* ⚠ WHAT WE HAVE, NOT A YEAR. The Premium card's build sheet asks for a
         year of IV per name; `ticker_iv_daily` holds 67 days for NKE, LULU and
         NFLX and under two weeks for the rest. Nik, 2026-09-10, chose to ship
         on the history that exists and label it honestly, so the card says
         "its own past 3 months" and `days` tells it what to print. */
      time('ivHist', () => P('ticker_iv_daily?select=ticker,atm_iv,snapshot_date'
        + '&order=snapshot_date.asc,ticker.asc')),
    ]);
    timings.fetchAll = Date.now() - T0;

    /* ⚠ AN EMPTY GREEKS READ IS A FAILURE, NOT A BOOK WITH NO PRICES. The shared
       `db.get` swallows every error and returns [] — `if (!r.ok) return []` and a
       bare `catch { return [] }` — so a 5xx or a dropped connection on this one
       read reaches here as "nothing is priced". Every mark-derived figure then
       falls back and ships as fact: Roll check reports 0 legs asking because
       captured is 0 on an unpriced leg, Long legs reports +$0 because m = cost,
       Programme's mark is 0, the cover bars are empty. Nothing in the payload
       says so, and the app draws it. Caught 14 Sep 2026, on a day the project's
       REST layer was intermittently refusing connections.

       So: read it again, and if it is still empty while the book holds open
       legs, answer with an error. The client already handles that — it prints
       "The book did not answer" and keeps the last good figures — and a card
       that says nothing beats a card that says the wrong thing. */
    let greeksRows = greeks;
    if (!greeksRows.length) {
      greeksRows = await time('greeksRetry', () =>
        D.get('option_greeks_latest?select=option_trade_id,delta,last_mark'));
    }
    if (!greeksRows.length && legs.length) {
      return json(503, {
        ok: false, build: BUILD, date: today,
        error: 'option marks unavailable',
      });
    }

    const spot = new Map<string, number>();
    for (const q of quotes) spot.set(String(q.ticker), N(q.spot));
    const co = new Map<string, string>();
    for (const n of names) co.set(String(n.ticker), String(n.name));
    const mark = new Map<string, { d: number; m: number }>();
    for (const g of greeksRows) mark.set(String(g.option_trade_id), { d: N(g.delta), m: N(g.last_mark) });
    /* ⚠ ONE SESSION SEVEN DAYS BACK, NOT THE OLDEST OF TWELVE DAYS. This used
       to page a twelve-day window and keep the furthest-back reading per leg,
       because the LEAPs were days old and a true week did not exist yet. They
       are weeks old now, so the honest reading is available — and the window
       was costing 62,432 rows and 63 round trips for a map of sixty numbers.

       `markWeek` says "change this week" and now means exactly that. A leg with
       no reading that day reads 0, which is the same self-healing behaviour the
       window had for anything younger than it: UBER's LEAP was bought today and
       correctly shows no weekly change at all. */
    const weekAgoRead = await time('weekAgo', () =>
      greeksOn(ago(7), 'option_trade_id,last_mark'));
    const weekAgo = new Map<string, number>();
    for (const g of weekAgoRead.rows) {
      const id = String(g.option_trade_id);
      if (!weekAgo.has(id)) weekAgo.set(id, N(g.last_mark));
    }

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

    /* ── ONE START DATE, AND ONLY WHAT IS CLOSED ──────────────────────────
       Nik, 17 Sep 2026, after finding Coverage reading $32.7k collected while
       Programme read $15.4k kept:

         "every number on each card should start from the same date ... what if
          we start everything from 31st august 2026"
         "only the roll check card should calculate what is not closed,
          everywhere else we need to calculate only what's closed ... so this
          week's open calls and puts sold will not be part of the calculation"

       1 · THE DATE IS 31 AUGUST 2026, the stock-replacement shift. Checked
          against the book: every LEAP the page charts was bought on or after
          that day, so the ~$19.6k the cut drops is call premium earned against
          SHARES he no longer owns. Nothing LEAP-era is lost.

       2 · A LEG IS IN OR OUT BY WHEN IT WAS OPENED, never by the date of a
          single trade. Filtering on trade_date alone takes the buy-backs of
          legs sold in August without their opening credits, and every "kept"
          goes negative. This was already true of the Programme card, whose
          PROG_START this rule generalises to the whole page.

       3 · SETTLED MEANS EXPIRED OR BOUGHT BACK TO FLAT. A credit on a leg
          still open is not yours: it can still be bought back for more than it
          was sold for. Every card counts settled credit only.

       4 · THREE EXCEPTIONS, all his: Positions (the card whose whole job is
          what is open), Weekly yield ("it will automatically start adding
          yield for next week as I start rolling"), and Credit & theta, which
          measures the RATE a contract sold at and knows that at the sale. */
    const BOOK_START = '2026-08-31';
    const shortKey = (t: Record<string, unknown>) =>
      `${t.ticker}|${t.option_type}|${N(t.strike)}|${t.expiry}`;
    const shortOpened = new Map<string, string>();
    const shortLeft = new Map<string, number>();
    for (const t of allShorts) {
      const k = shortKey(t), d = String(t.trade_date).slice(0, 10);
      if (String(t.action) === 'open') {
        if (!shortOpened.has(k) || d < shortOpened.get(k)!) shortOpened.set(k, d);
        shortLeft.set(k, (shortLeft.get(k) ?? 0) + N(t.contracts));
      } else {
        shortLeft.set(k, (shortLeft.get(k) ?? 0) - N(t.contracts));
      }
    }
    const inBook = (t: Record<string, unknown>) =>
      (shortOpened.get(shortKey(t)) ?? '9999-99-99') >= BOOK_START;
    /* Every short leg of this book, all-time meaning since 31 Aug. */
    const bookShorts = allShorts.filter(inBook);
    /* Expired, or bought back to flat. Both are closed. */
    const isSettled = (t: Record<string, unknown>) => {
      const k = shortKey(t);
      return String(t.expiry).slice(0, 10) < today || (shortLeft.get(k) ?? 0) <= 0.0001;
    };
    /* And the same question asked of a past date, for the history walks: a leg
       is settled AS AT `cut` when it had expired by then. */
    const settledBy = (t: Record<string, unknown>, cut: string) =>
      String(t.expiry).slice(0, 10) <= cut;

    /* ── every credit ever, bucketed by week ────────────────────────────── */
    const creditByWeek = new Map<string, Map<string, number>>();
    /* The same buckets split by side, for the weekly-yield card's bar and cap. */
    const grossByWeek = new Map<string, Map<string, number>>();
    const boughtByWeek = new Map<string, Map<string, number>>();
    const firstCredit = new Map<string, string>();
    /* The same buckets again, counting only legs that have settled. Every card
       but Weekly yield, Positions and Credit & theta reads these. */
    const settledByWeek = new Map<string, Map<string, number>>();
    const openByWeek = new Map<string, Map<string, number>>();
    for (const t of bookShorts) {
      const tk = String(t.ticker);
      const d = String(t.trade_date).slice(0, 10);
      const c = (String(t.action) === 'open' ? 1 : -1) * N(t.contracts) * N(t.premium) * 100;
      if (!creditByWeek.has(tk)) creditByWeek.set(tk, new Map());
      const m = creditByWeek.get(tk)!;
      /* ⚠ GROSS AND BOUGHT-BACK ARE TWO FACTS, NOT ONE NET. The weekly-yield
         card draws the week's gross credit as the bar and the cost of buying
         legs back as a red cap ON that bar, so a week that sold $7,000 and
         spent $1,500 closing early reads as both, not as $5,500. Netting them
         here would make the two halves unrecoverable. `credit` stays the net,
         because every other card on the page is built on it. */
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
      const done = isSettled(t) ? settledByWeek : openByWeek;
      if (!done.has(tk)) done.set(tk, new Map());
      const dm = done.get(tk)!;
      dm.set(w, (dm.get(w) ?? 0) + c);
      if (!grossByWeek.has(tk)) grossByWeek.set(tk, new Map());
      if (!boughtByWeek.has(tk)) boughtByWeek.set(tk, new Map());
      if (c > 0) {
        const g = grossByWeek.get(tk)!; g.set(w, (g.get(w) ?? 0) + c);
      } else if (c < 0) {
        const b = boughtByWeek.get(tk)!; b.set(w, (b.get(w) ?? 0) - c);
      }
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
              /* ⚠ THE CREDIT PER SHARE THE LEG OPENED AT, which is the number
                 quoted when the trade is placed and the only one comparable
                 against a chain. The roll check reads it two ways: printed
                 under an under-water strike, so the roll can be judged against
                 what the next strike out pays today, and as the basis of the
                 tap that turns a captured percentage into dollars. */
              cr: s.n > 0 ? r2(credit / (s.n * 100)) : 0,
              opened: s.opened,
              /* ⚠ WHAT IS STILL TO DECAY, NOT WHAT THE BUY-BACK COSTS. Nik,
                 14 Sep 2026, replacing "left to capture" on the roll check.
                 `value` is the whole cost of closing the leg; this is the part
                 of it that is time and will come back to him by Friday if he
                 does nothing. The rest is INTRINSIC and is gone — it is the
                 stock having run through the strike, and no amount of waiting
                 returns it.

                 On an out-of-the-money leg the two are the SAME number, and
                 that is the reading rather than a fault: the whole remaining
                 cost is decay he collects. A gap between them is the intrinsic
                 he will not get back, which is the roll signal.

                 ⚠ MONEYNESS INVERTS ON A PUT, the same trap as `itm`: a call
                 has intrinsic ABOVE its strike, a put BELOW it. Hard-coding the
                 call rule would report every sold put as pure time value on the
                 day it most needed rolling.

                 Unpriced means unknown, and `value` falls back to the credit
                 there, so a time value derived from it would be a guess. Zero,
                 and `priced` already tells the card to render it as unknown. */
              tv: priced
                ? Math.max(0, Math.round(value
                    - (s.type === 'put' ? Math.max(0, s.k - S) : Math.max(0, S - s.k))
                      * s.n * 100))
                : 0,
            };
          });

        /* What this name LAST wrote at, per share: the ranking unit of the roll
           check's second view, where a name's room is worth what its own recent
           credit says it is worth. The most recently opened short leg, not the
           book average, because a name's own last print is what the next one
           will look like. */
        const lastShort = [...shorts].sort((a, b) => (a.opened < b.opened ? 1 : -1))[0];
        const lastCr = lastShort ? lastShort.cr : 0;

        const wk = creditByWeek.get(t) ?? new Map();
        /* ⚠ SETTLED ONLY, 17 Sep 2026. `creditByWeek` still carries every leg
           of this book because Weekly yield draws the live week; what a name
           has EARNED is the settled half. */
        const wkDone = settledByWeek.get(t) ?? new Map();
        const collected = [...wkDone.values()].reduce((a, b) => a + b, 0);
        const collectedOpen = [...(openByWeek.get(t) ?? new Map()).values()]
          .reduce((a, b) => a + b, 0);
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
          /* Taken in on legs still open. Not earned, so no card adds it to
             `collected`; Coverage draws it as a lighter cap. */
          collectedOpen: Math.round(collectedOpen),
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
          lastCr,
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
      let g = 0, b = 0;
      for (const p of positions) {
        g += (grossByWeek.get(p.t)?.get(w) ?? 0);
        b += (boughtByWeek.get(p.t)?.get(w) ?? 0);
      }
      return { week: w, credit: Math.round(c), current: w === thisWeek,
               /* Gross sold, and what closing legs cost, charged to the week
                  that paid for it. gross - bought === credit, always. */
               gross: Math.round(g), bought: Math.round(b),
               pct: denom > 0 ? r2(c / denom * 100) : 0,
               /* The denominator this week was measured against, so the card
                  never has to re-derive a dated ledger on the phone. */
               denom: Math.round(denom) };
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

    /* ══ THE FOUR NEW CARDS ══════════════════════════════════════════════
       handoff-final/, 10 Sep 2026. All four derive from the same tables the
       existing cards do, in this one function, because two cards that compute
       the same figure separately will disagree eventually — which is the
       reason this function exists at all. */

    /* ── 01 · Programme, per name ──────────────────────────────────────────
       ⚠ THE PROGRAMME STARTS 31 AUGUST, Nik's ruling 2026-09-10. The handoff
       said "since 20 May", but the credits then ran back to when he still held
       shares while `invested` is the LEAPs and puts he holds now: a May
       numerator over a September denominator. The LEAP shift is the honest
       start for both.

       ⚠ MEMBERSHIP IS THE LEG'S FIRST OPEN, the same rule the put programme
       learned the hard way. Filtering on trade_date alone would take the
       buy-backs of legs sold in August without their opening credits, and
       `kept` would go negative. */
    /* The programme's own start IS the page's start now: one date, set where
       `BOOK_START` is defined. `inProg` survives as the name the rows below
       read. */
    const PROG_START = BOOK_START;
    const inProg = inBook;

    /* Gross credits and buy-backs per name. `kept` is the difference; Nik
       confirmed 2026-09-10 that "Rolled back" is money actually paid out, not
       money still owed on legs that are open. */
    const grossBy = new Map<string, number>(), backBy = new Map<string, number>();
    /* What the open legs have taken in but not yet earned: the lighter cap on
       Coverage's bar, and nothing else. */
    const grossOpenBy = new Map<string, number>(), backOpenBy = new Map<string, number>();
    for (const t of bookShorts) {
      const tk = String(t.ticker), cash = N(t.contracts) * N(t.premium) * 100;
      const isOpen = String(t.action) === 'open';
      const P = isSettled(t) ? (isOpen ? grossBy : backBy) : (isOpen ? grossOpenBy : backOpenBy);
      P.set(tk, (P.get(tk) ?? 0) + cash);
    }

    /* Long put cost and mark per name, so the components split call from put. */
    const putCostByName = new Map<string, number>(), putMarkByName = new Map<string, number>();
    for (const e of open) {
      if (e.dir !== 'long' || e.type !== 'put') continue;
      putCostByName.set(e.ticker, (putCostByName.get(e.ticker) ?? 0) + e.cash);
      const md = e.ids.map((i) => mark.get(i)).filter(Boolean) as { d: number; m: number }[];
      const m = md.length ? md.reduce((a, x) => a + x.m, 0) / md.length : 0;
      putMarkByName.set(e.ticker, (putMarkByName.get(e.ticker) ?? 0) + m * e.n * 100);
    }
    /* What is still owed on the open short legs, always <= 0. */
    const owedBy = new Map<string, number>();
    for (const p of positions) {
      owedBy.set(p.t, -p.shorts.reduce((a, x) => a + (x.priced ? x.value : x.credit), 0));
    }

    const programme = {
      since: PROG_START,
      rows: positions.map((p) => {
        const putCost = putCostByName.get(p.t) ?? 0;
        const putMark = putMarkByName.get(p.t) ?? 0;
        return {
          t: p.t,
          kept: Math.round((grossBy.get(p.t) ?? 0) - (backBy.get(p.t) ?? 0)),
          /* ⚠ OPEN REPLACES OWED, 17 Sep 2026. "Owed" was what it would cost to
             close the open short legs, a figure about legs this page no longer
             counts. `open` is the credit those legs took in and have not
             earned: the same money Coverage draws as its lighter cap. */
          open: Math.round((grossOpenBy.get(p.t) ?? 0) - (backOpenBy.get(p.t) ?? 0)),
          calls: Math.round(p.mark - p.paid),
          puts: Math.round(putMark - putCost),
          owed: Math.round(owedBy.get(p.t) ?? 0),
          invested: p.invested,
        };
      }),
    };

    /* ── 02 · Premium now, per name against its own history ────────────────
       ⚠ NO PERCENTILE. The multiple against the name's own median is the whole
       reading; the rank was what made the earlier version unreadable. */
    const MIN_IV_DAYS = 20;                     // four trading weeks
    const ivBy = new Map<string, number[]>();
    for (const r of ivHist) {
      const t = String(r.ticker), v = N(r.atm_iv) * 100;
      if (v <= 0) continue;
      if (!ivBy.has(t)) ivBy.set(t, []);
      ivBy.get(t)!.push(v);
    }
    const held = new Set(positions.map((p) => p.t));
    const premiumRows = [...ivBy.entries()]
      .filter(([t, v]) => held.has(t) && v.length >= MIN_IV_DAYS)
      .map(([t, v]) => {
        const sorted = [...v].sort((a, b) => a - b);
        const med = sorted.length % 2
          ? sorted[(sorted.length - 1) / 2]
          : (sorted[sorted.length / 2 - 1] + sorted[sorted.length / 2]) / 2;
        return {
          t, now: r2(v[v.length - 1]), usual: r2(med),
          low: r2(sorted[0]), high: r2(sorted[sorted.length - 1]),
          days: v.length,
        };
      })
      .sort((a, b) => (b.now / b.usual) - (a.now / a.usual));
    const premium = {
      /* The card labels itself from this rather than claiming a year. */
      days: premiumRows.length ? Math.max(...premiumRows.map((r) => r.days)) : 0,
      rows: premiumRows,
    };
    /* Filled in below, once spot and the free counts exist: what a 30-delta
       weekly call pays a contract at today's IV and at the name's own usual,
       the name's 1-week move, and how many contracts are still writeable. The
       row is the card's, so the card reads one object rather than four. */
    type PremRow = typeof premiumRows[number] & {
      pay?: number; payU?: number; free?: number; move?: number | null;
    };

    /* ⚠ AVERAGE CREDIT IS GONE, 17 Sep 2026. Credit & theta replaced it, and
       it reads the weekly buckets in `creditTrend` instead of a four-week
       per-share block of its own. */

    /* ── net delta per name ───────────────────────────────────────────────
       What is left of a name's exposure once everything sold against it is
       counted. Prices draws it as the row's `delta`.

       ⚠ DELTA IS SUMMED LEG BY LEG, never averaged per side. Averaging call
       and put deltas into one `dShort` is what produced "FIS 115%", a figure no
       leg in the book supports.

       ⚠ THE UPSIDE LEFT CARD IS GONE, 14 Sep 2026, Nik: "lets remove the upside
       left card dont need it anymore". Its `share` per name, the book's kept
       percentage and the two 10% figures went with it; only this map survives,
       because Prices reads it. */
    const dOf = (e: { ids: string[] }) => {
      const md = e.ids.map((i) => mark.get(i)).filter(Boolean) as { d: number; m: number }[];
      return md.length ? md.reduce((a, x) => a + x.d, 0) / md.length : 0;
    };
    const netD = new Map<string, number>();
    for (const e of open) {
      const d = dOf(e) * e.n * 100 * (e.dir === 'long' ? 1 : -1);
      netD.set(e.ticker, (netD.get(e.ticker) ?? 0) + d);
    }

    /* ── 04 · To roll ──────────────────────────────────────────────────────
       ⚠ NO ASSIGNMENT LANGUAGE. This book rolls.

       ⚠ THE HISTORY IS PER NAME, THE ROW IS PER LEG, and the card labels that
       "ALL TIME" because the scope change is invisible otherwise — Nik read
       "Kept $4,035" as belonging to the $110 put beside it and asked where the
       card said otherwise. It did not. A name with an in-the-money call AND put
       gets two rows carrying the same history, which the label makes read as
       one standing fact rather than a duplicate. */
    const toRollLegs = positions.flatMap((p) =>
      p.shorts.filter((sh) => sh.itm).map((sh) => ({
        t: p.t, side: sh.type, n: sh.n, strike: sh.k,
        sold: sh.credit, now: sh.priced ? sh.value : sh.credit, exp: sh.exp,
      })));
    const toRoll = {
      /* Same figure Weekly yield prints, so the page agrees with itself. */
      week: bookWeekly.find((w) => w.current)?.credit ?? 0,
      legs: toRollLegs,
      names: Object.fromEntries(positions.map((p) => [p.t, {
        collected: Math.round(grossBy.get(p.t) ?? 0),
        given: Math.round(backBy.get(p.t) ?? 0),
        leap: Math.round(p.mark - p.paid),
      }])),
    };

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
    /* ⚠ THE DAY WINDOW IS THE LAST SESSION, NOT ALWAYS TODAY. Nik, 2026-09-14,
       on a Monday morning showing "Friday" against 0.0% on every name: "it
       should show data Friday and post-market... on Monday it will show the
       data for Friday."

       The window used to be spot against the last close, full stop. That is
       today's move WHILE A SESSION IS RUNNING and it is nonsense at every other
       hour, because outside the session the spot IS the last close and the card
       compares a number with itself. Every evening and every morning it read
       0.0% across the book; a Monday just makes it obvious, since the zero sits
       under the word "Friday".

       So the window reports the most recent session there is:

         a session is running   spot against the last close      -> "today"
         otherwise              the last close against the one
                                before it                        -> that day

       ⚠ AND THE TEST IS "HAS TODAY TRADED", NOT "IS THE MARKET OPEN". Bounding
       it at 16:00 ET put the bug back between the close and the next morning:
       daily_closes has no row for today until 17:30, so at 18:00 on a Monday
       the card fell through to Friday's close and announced Friday again. The
       spot holds the day's last print all evening, so from 09:30 until the next
       session opens, today is the session to report.

       ⚠ A HOLIDAY IS A WEEKDAY THAT DID NOT TRADE, and the clock cannot see
       one. Seven names all unchanged to the cent is not a quiet session, it is
       no session, so that reads as "not traded" and the card falls back to the
       last real close. Cheaper and more honest than a holiday calendar. */
    const etNow = new Date(new Date().toLocaleString('en-US', { timeZone: 'America/New_York' }));
    const etWd = etNow.getDay(), etMin = etNow.getHours() * 60 + etNow.getMinutes();
    const openYet = etWd >= 1 && etWd <= 5 && etMin >= 9 * 60 + 30;
    const anyMoved = [...spot.entries()].some(([t, S0]) => {
      const c0 = (closeRows.get(t) ?? [])[0];
      return S0 > 0 && c0 > 0 && Math.abs(S0 - c0) > 0.005;
    });
    const dayLive = openYet && anyMoved;

    const WINDOWS: [string, number][] =
      [['today', 0], ['w1', 5], ['w2', 10], ['w3', 15], ['w4', 20]];
    const moveFor = (t: string): Record<string, number | null> => {
      const S0 = spot.get(t) ?? 0;
      const cs = closeRows.get(t) ?? [];
      const out: Record<string, number | null> = {};
      for (const [key, back] of WINDOWS) {
        /* ⚠ THE WEEK WINDOWS SHIFT WITH THE DAY WINDOW. When the day window is
           reporting Friday rather than a live today, "1 week" has to mean the
           week ending Friday too, or the card draws one row measured to Friday
           beside four measured to now and calls them the same axis. */
        const now = dayLive ? S0 : cs[0];
        const base = cs[dayLive ? back : back + 1];
        out[key] = (base && base > 0 && now && now > 0)
          ? r2((now / base - 1) * 100) : null;
      }
      return out;
    };
    /* ⚠ THE PRICES CARD BORROWS FOUR OTHER CARDS' READINGS, so they ship on the
       row rather than being re-derived on the phone. The design's rule 0.1:
       "price is the input; what the move did to you is the story". A list of
       eight percentages is a quote screen; these four turn each move into a
       statement about the book.

         nearest sold strikes  roll check   -> two ticks on the bar
         free contracts        inventory    -> the ticker's ink
         IV now vs usual       premium now  -> the word under the ticker
         net delta in shares   upside left  -> the move in dollars

       ⚠ AND THE DOLLARS USE NET DELTA, NOT the sheet's `keep x open contracts`.
       That product sizes the move by the SHORT book, which fits a book of small
       covered positions and not this one: NKE carries 15 short puts against 60
       long calls, so the sheet's formula would price a move on 795 shares where
       the position actually moves like 4,400. Net delta is the same question
       asked correctly, and this function already computes it for Upside left.
       Flagged to Nik with the change. */
    const nearestK = (t: string, type: string) => {
      const S0 = spot.get(t) ?? 0;
      const ks = open.filter((e) => e.ticker === t && e.dir === 'short' && e.type === type)
                     .map((e) => e.k);
      if (!ks.length || S0 <= 0) return null;
      return ks.reduce((a, k) => (Math.abs(k - S0) < Math.abs(a - S0) ? k : a));
    };
    const ivByT = new Map(premiumRows.map((r) => [r.t, { now: r.now, usual: r.usual }]));
    const priceRows = positions.map((p) => {
      const r = inv.get(p.t);
      return {
        ticker: p.t, weight: p.paid, pct: moveFor(p.t),
        /* The card swaps its value column to this on a tap. Nik, 2026-09-09:
           "When I tap on % can we show the stock price for each ticker". */
        spot: r2(spot.get(p.t) ?? 0),
        /* calls + puts still writeable. 0 mutes the ticker. */
        free: r ? Math.max(0, r.ch - r.cs) + Math.max(0, r.ph - r.ps) : 0,
        /* share equivalents, signed. A short put in the money is LONG delta, so
           this can exceed the long calls' own exposure. */
        delta: Math.round(netD.get(p.t) ?? 0),
        callK: nearestK(p.t, 'call'),
        putK: nearestK(p.t, 'put'),
        /* null when the name has too little IV history for a median to mean
           anything: the word is absent rather than invented. */
        iv: ivByT.get(p.t) ?? null,
      };
    });
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

    /* ── theta, a day ─────────────────────────────────────────────────────
       handoff `export 8/credit-theta`, 14 Sep 2026. The long legs (the LEAPs
       and the protective puts) PAY decay every day; the short legs COLLECT it.
       The card is one against the other, four weeks of shape behind each.

       ⚠ TWO CORRECTIONS THE SHEET DOES NOT KNOW ABOUT, both forced by the data
       and both flagged to Nik.

       1 · A DAY'S DECAY CANNOT EXCEED WHAT THE OPTION IS WORTH. Black-Scholes
       theta goes to infinity as expiry approaches, and the vendor ships it raw:
       a KR 59 call marked at $0.76 on its expiry day reported theta −2.20 a
       share, which says it will lose three times its own value by tomorrow.
       Summed, that read $5,533 a DAY of collect on a book that takes about
       $7,000 a WEEK in credit. Capping each leg at its own remaining mark is
       the arithmetic floor: an option cannot decay past zero.

       2 · EVERY WEEK IS MEASURED ON THE SAME WEEKDAY. A weekly's theta on its
       expiry Friday is most of its value; on the Monday it is a fraction of
       that. Taking "the last reading of the week" put the live week's Monday
       beside four past Fridays and called them a series. Each week is read at
       the same offset into the week that today sits at, so the four bars are
       the same measurement four times, and the live figure is always today's.

       ⚠ ONE PAGE PER DAY IS ENOUGH, and that is why this does not page the
       whole table. `mp-refresh` writes every leg every minute, so 1,000 rows
       ordered newest-first covers roughly ten minutes and therefore every leg
       many times over. Paging five weeks of `option_greeks` would be 55,000
       rows and 55 round trips for four numbers. */
    /* ⚠ TWELVE WEEKS, 17 Sep 2026: Credit & theta draws the trend, so the
       weekly lens needs twelve readings. Theta and Coverage still read the
       last one only. */
    const TH_WEEKS = 12;
    /* ⚠ AND NO WEEK BEFORE THE BOOK. Nik, 17 Sep 2026, asked for 31 August on
       this card too: the weeks before it are the NVDA book, a different
       position answering a different question. Three points today, twelve by
       December. */
    const TH_FLOOR = weekStart(BOOK_START);
    const thWeeks: string[] = [];
    for (let i = TH_WEEKS - 1; i >= 0; i--) {
      const w = new Date(Date.parse(thisWeek + 'T00:00:00Z') - i * 7 * 86_400_000)
        .toISOString().slice(0, 10);
      if (w >= TH_FLOOR) thWeeks.push(w);
    }
    /* How far into the week today is. Capped at Friday: there are no readings
       at the weekend and a Sunday would ask every past week for a Sunday. */
    const thOffset = Math.min(4, Math.max(0, Math.round(
      (Date.parse(today + 'T00:00:00Z') - Date.parse(thisWeek + 'T00:00:00Z')) / 86_400_000)));
    const dayShift = (d: string, n: number) =>
      new Date(Date.parse(d + 'T00:00:00Z') + n * 86_400_000).toISOString().slice(0, 10);

    /* The direction and size of every leg alive in the window, including the
       ones that have since expired — a week's theta is what the book carried
       THAT week, not what survives today. */
    const thLegs = new Map<string, {
      dir: string; type: string; n: number; exp: string; ticker: string;
    }>();
    for (const t of await time('thetaLegs', () =>
      P(`option_trades?voided_at=is.null&expiry=gte.${thWeeks[0]}`
        + '&select=id,ticker,direction,option_type,contracts,expiry&order=id.asc'))) {
      thLegs.set(String(t.id), {
        dir: String(t.direction), type: String(t.option_type),
        n: N(t.contracts), exp: String(t.expiry).slice(0, 10), ticker: String(t.ticker),
      });
    }

    /* The newest reading per leg on one day. Walks back up to four days so a
       holiday or a short week still answers rather than shipping a zero. */
    const thetaOn = async (day: string) => {
      const { day: d, rows } = await greeksOn(day, 'option_trade_id,theta,last_mark,iv');
      const seen = new Map<string, number>();
      const ivs = new Map<string, number>();
      for (const g of rows) {
        const id = String(g.option_trade_id);
        if (seen.has(id) || g.theta === null) continue;
        /* THE CAP. Never more than the option is worth. */
        seen.set(id, Math.max(N(g.theta), -Math.abs(N(g.last_mark))));
        if (g.iv !== null && N(g.iv) > 0) ivs.set(id, N(g.iv));
      }
      return { day: d, th: seen, iv: ivs };
    };

    const thRead = await time('thetaDays', () => Promise.all(
      thWeeks.map((w) => thetaOn(dayShift(w, thOffset)))));
    const thetaWeeks = thWeeks.map((w, i) => {
      /* ⚠ EACH SIDE SPLIT BY WHAT IT IS MADE OF, 14 Sep 2026. The long side is
         the LEAPs AND the protective puts, and they cost almost the same to
         hold — $164 against $154 — on a fifth of the capital, so the hedge
         burns roughly four times faster per dollar. Nothing else in the deck
         prices the protection in daily terms. The short side splits the same
         way so the two columns stay twins. */
      let long = 0, short = 0, lc = 0, lp = 0, sc = 0, sp = 0, ivN = 0, ivW = 0;
      for (const [id, th] of thRead[i].th) {
        const leg = thLegs.get(id);
        /* A leg that had already expired before that week was not in the book. */
        if (!leg || leg.exp < w) continue;
        const cash = th * leg.n * 100;
        if (leg.dir === 'long') {
          long += cash;
          if (leg.type === 'put') lp += cash; else lc += cash;
        } else {
          short -= cash;
          if (leg.type === 'put') sp -= cash; else sc -= cash;
          /* The short legs' IV, weighted by contracts. What the sold side is
             being paid on, read at the same close as its theta. */
          const v = thRead[i].iv.get(id);
          if (v) { ivN += v * leg.n; ivW += leg.n; }
        }
      }
      return {
        week: w, on: thRead[i].day, long: Math.round(long), short: Math.round(short),
        lc: Math.round(lc), lp: Math.round(lp), sc: Math.round(sc), sp: Math.round(sp),
        iv: ivW > 0 ? ivN / ivW : null,
      };
    });
    /* ⚠ THE ABSOLUTE MOVE, NOT THE NET ONE. Decay is only free when the book
       sits still, and a book where one name ran 6% up and another 6% down has
       not sat still even though its net move is zero. */
    const absW1 = priceRows.map((r) => r.pct.w1)
      .filter((v): v is number => v !== null).map(Math.abs);
    const theta = {
      /* The retired Theta card drew four. */
      weeks: thetaWeeks.slice(-4).map(({ iv: _iv, ...w }) => w),
      move: absW1.length ? r2(absW1.reduce((a, b) => a + b, 0) / absW1.length) : null,
    };

    /* ── credit & theta, the trend ───────────────────────────────────────
       handoff `export 19/credit-theta`, 17 Sep 2026, with Nik's rulings on
       the same day, which replace the sheet where they differ:

       1 · THE RATIO IS THE THETA READING. Short collects ÷ what the LEAP calls
          AND the long puts pay. 3.5× and above is comfortable, 2× to 3.5× is
          watch, under 2× is danger: "anything less than 2 is not worth".
       2 · CREDIT IS A PERCENT OF STRIKE, never dollars a contract. The book
          turned over from NVDA to eight cheaper names and $/contract fell
          from 422 to 35 while % of strike held 0.5 to 1.7. Dollars measured
          the stock price, not the premium.
       3 · NO RSI. Twelve weeks is too few for a 14-bucket RSI, which pins at
          0 or 100 on this much history. The trend is the last 2 weeks against
          the 6 before, in words: Strengthening · Holding · Turning · Weakening.
       4 · ONE LINE, AND A SECOND WHEN TWO THINGS ARE MOVING. Below 2× the
          line says which side did it, and any single name under 2× is named
          even when the book is fine.

       Credit buckets by the week the leg COVERS and counts opens only, the
       same rules as the retired Average credit card. Weekly only for now;
       Monthly and Quarterly wait until there is history to cut. */
    const TR_PRIOR = 6, TR_RECENT = 2;
    const pctOf = (a: number, b: number) => (b ? (a - b) / Math.abs(b) * 100 : 0);
    const mean = (a: number[]) => (a.length ? a.reduce((x, y) => x + y, 0) / a.length : 0);
    /* The state of a series: recent mean against prior mean, and whether the
       last step agrees. A move under 10% either way is holding. */
    const stateOf = (vals: (number | null)[]) => {
      const v = vals.filter((x): x is number => x !== null);
      if (v.length < TR_RECENT + 2) return 'Holding';
      const recent = mean(v.slice(-TR_RECENT));
      const prior = mean(v.slice(-(TR_RECENT + TR_PRIOR), -TR_RECENT));
      const ch = pctOf(recent, prior);
      const step = pctOf(v[v.length - 1], v[v.length - 2]);
      if (Math.abs(ch) < 10) return 'Holding';
      if (ch > 0) return step < -10 ? 'Turning' : 'Strengthening';
      return step > 10 ? 'Turning' : 'Weakening';
    };

    const trCredit = new Map<string, {
      calls: { n: number; cash: number; notional: number };
      puts: { n: number; cash: number; notional: number };
      back: number; names: Set<string>;
    }>();
    for (const t of bookShorts) {
      const w = weekStart(String(t.expiry).slice(0, 10));
      if (w < thWeeks[0] || w > thisWeek) continue;
      const e = trCredit.get(w) ?? {
        calls: { n: 0, cash: 0, notional: 0 }, puts: { n: 0, cash: 0, notional: 0 },
        back: 0, names: new Set<string>(),
      };
      const n = N(t.contracts), cash = n * N(t.premium) * 100;
      if (String(t.action) === 'open') {
        const side = String(t.option_type) === 'put' ? e.puts : e.calls;
        side.n += n; side.cash += cash; side.notional += n * N(t.strike) * 100;
        e.names.add(String(t.ticker));
      } else {
        e.back += cash;
      }
      trCredit.set(w, e);
    }
    const pctStrike = (s: { cash: number; notional: number }) =>
      s.notional > 0 ? s.cash / s.notional * 100 : null;

    const trWeeks = thetaWeeks.map((tw) => {
      const c = trCredit.get(tw.week);
      const side = (x?: { n: number; cash: number; notional: number }) => ({
        n: Math.round(x?.n ?? 0), cash: Math.round(x?.cash ?? 0),
        notional: Math.round(x?.notional ?? 0),
      });
      return {
        week: tw.week, on: tw.on,
        short: tw.short, long: tw.long, lc: tw.lc, lp: tw.lp, sc: tw.sc, sp: tw.sp,
        /* null before the book held a long leg, not infinity. */
        ratio: tw.long < 0 ? r2(tw.short / -tw.long) : null,
        iv: tw.iv === null ? null : r2(tw.iv * 100),
        calls: side(c?.calls), puts: side(c?.puts),
        back: Math.round(c?.back ?? 0),
      };
    });
    const blendPct = (w: typeof trWeeks[number]) => {
      const nl = w.calls.notional + w.puts.notional;
      return nl > 0 ? r2((w.calls.cash + w.puts.cash) / nl * 100) : null;
    };

    /* Each name's ratio today, from the same live reading. */
    const liveRead = thRead[thRead.length - 1];
    const byName = new Map<string, { short: number; lc: number; lp: number }>();
    for (const [id, th] of liveRead.th) {
      const leg = thLegs.get(id);
      if (!leg || leg.exp < thisWeek) continue;
      const e = byName.get(leg.ticker) ?? { short: 0, lc: 0, lp: 0 };
      const cash = th * leg.n * 100;
      if (leg.dir === 'long') { if (leg.type === 'put') e.lp += cash; else e.lc += cash; }
      else e.short -= cash;
      byName.set(leg.ticker, e);
    }
    const thNames = [...byName.entries()].map(([t, e]) => ({
      t, short: Math.round(e.short), lc: Math.round(e.lc), lp: Math.round(e.lp),
      ratio: (e.lc + e.lp) < 0 ? r2(e.short / -(e.lc + e.lp)) : null,
    })).sort((a, b) => a.t.localeCompare(b.t));

    const usd = (v: number) => '$' + Math.round(Math.abs(v)).toLocaleString('en-US');
    const fx = (v: number) => (v >= 10 ? v.toFixed(0) : v.toFixed(1)) + '×';
    const joinNames = (a: string[]) =>
      a.length <= 1 ? (a[0] ?? '') : a.slice(0, -1).join(', ') + ' and ' + a[a.length - 1];

    /* ── the theta lines ── */
    const thetaLines: string[] = [];
    {
      const nowW = trWeeks[trWeeks.length - 1];
      const thenW = trWeeks[Math.max(0, trWeeks.length - 3)];
      const shortCh = pctOf(nowW.short, thenW.short);
      const longCh = pctOf(-nowW.long, -thenW.long);
      const dayLabel = (iso: string) => {
        const d = new Date(iso + 'T12:00:00Z');
        return `${d.getUTCDate()} ${MON[d.getUTCMonth()]}`;
      };
      /* ⚠ THE PART THAT MOVED THE MOST DOLLARS IS NAMED, AND ITS OWN CHANGE
         IS PRINTED. Printing the whole side's 205% beside "long puts" said the
         puts tripled, when the puts were new and the side grew because of them.
         A part that was zero two weeks ago is a new leg, and says so. */
      const part = (a: number, b: number, a0: number, b0: number, na: string, nb: string) => {
        const useA = Math.abs(a - a0) >= Math.abs(b - b0);
        const now = Math.abs(useA ? a : b), then = Math.abs(useA ? a0 : b0);
        return { who: useA ? na : nb, now, isNew: then === 0 && now > 0, ch: pctOf(now, then) };
      };
      const sPart = part(nowW.sc, nowW.sp, thenW.sc, thenW.sp, 'Short calls', 'Short puts');
      const lPart = part(nowW.lc, nowW.lp, thenW.lc, thenW.lp, 'LEAPs', 'Long puts');
      const since = dayLabel(thenW.week);
      const ivCh = (nowW.iv !== null && thenW.iv !== null) ? pctOf(nowW.iv, thenW.iv) : 0;
      const shortLine = () => {
        if (sPart.isNew) return `${sPart.who} sold since ${since} collect ${usd(sPart.now)} a day`;
        const base = `${sPart.who} collect ${Math.abs(Math.round(sPart.ch))}% ${sPart.ch >= 0 ? 'more' : 'less'}`;
        /* IV named only when it moved the same way, by 10% or more. */
        if (Math.abs(ivCh) >= 10 && Math.sign(ivCh) === Math.sign(sPart.ch)) {
          return `${base} \u00B7 IV ${ivCh > 0 ? 'up' : 'down'} ${Math.abs(Math.round(ivCh))}%`;
        }
        return `${base} than 2 weeks ago`;
      };
      const longLine = () => lPart.isNew
        ? `${lPart.who} bought since ${since} cost ${usd(lPart.now)} a day`
        : `${lPart.who} cost ${Math.abs(Math.round(lPart.ch))}% ${lPart.ch >= 0 ? 'more' : 'less'} a day than 2 weeks ago`;
      const twoBack = trWeeks.length >= 3;
      const low = thNames.filter((x) => x.ratio !== null && x.ratio < 2)
        .sort((a, b) => (a.ratio ?? 0) - (b.ratio ?? 0));
      const lowLine = () => {
        if (low.length === 1) {
          const x = low[0];
          const what = x.lp <= x.lc ? 'puts' : 'LEAPs';
          return `${x.t} below 2× on its own · ${what} cost ${usd(Math.min(x.lp, x.lc))} a day`;
        }
        return `${joinNames(low.slice(0, 3).map((x) => x.t))} below 2× on their own`;
      };
      /* Short shrinking and long growing hurt the ratio equally, so the
         bigger percentage is the cause. */
      const shortCaused = -shortCh >= longCh;
      if (nowW.ratio !== null && nowW.ratio < 2) {
        thetaLines.push(shortCaused
          ? `Below 2\u00D7 \u00B7 ${sPart.who.toLowerCase()} collect ${Math.abs(Math.round(sPart.ch))}% less`
          : lPart.isNew
            ? `Below 2\u00D7 \u00B7 ${lPart.who === 'LEAPs' ? 'LEAPs' : 'long puts'} bought since ${since}`
            : `Below 2\u00D7 \u00B7 ${lPart.who === 'LEAPs' ? 'LEAPs' : 'long puts'} cost ${Math.abs(Math.round(lPart.ch))}% more`);
        if (low.length) thetaLines.push(lowLine());
      } else {
        const movers: { size: number; line: string }[] = [];
        if (twoBack && Math.abs(shortCh) >= 15) movers.push({ size: Math.abs(shortCh), line: shortLine() });
        if (twoBack && Math.abs(longCh) >= 15) movers.push({ size: Math.abs(longCh), line: longLine() });
        movers.sort((a, b) => b.size - a.size);
        if (movers.length) thetaLines.push(movers[0].line);
        else if (twoBack && thenW.ratio !== null && nowW.ratio !== null) {
          thetaLines.push(`Holding near ${fx(thenW.ratio)} from 2 weeks ago`);
        } else if (nowW.ratio !== null) {
          thetaLines.push(`Short covers long ${fx(nowW.ratio)} \u00B7 ${trWeeks.length} `
            + `week${trWeeks.length === 1 ? '' : 's'} of history so far`);
        }
        if (low.length) thetaLines.push(lowLine());
        else if (movers.length > 1) thetaLines.push(movers[1].line);
      }
    }

    /* ── the credit lines ── */
    const creditLines: string[] = [];
    const bl = trWeeks.map(blendPct);
    const hist = [...trCredit.entries()].sort(([a], [b]) => a.localeCompare(b));
    {
      const recentW = trWeeks.slice(-TR_RECENT), priorW = trWeeks.slice(-(TR_RECENT + TR_PRIOR), -TR_RECENT);
      const sum = (ws: typeof trWeeks, k: 'calls' | 'puts') => ws.reduce((a, w) => ({
        cash: a.cash + w[k].cash, notional: a.notional + w[k].notional, n: a.n + w[k].n,
      }), { cash: 0, notional: 0, n: 0 });
      const side = (k: 'calls' | 'puts') => {
        const r = pctStrike(sum(recentW, k)), p = pctStrike(sum(priorW, k));
        return { k, ch: r !== null && p !== null ? pctOf(r, p) : 0 };
      };
      const sides = [side('calls'), side('puts')].sort((a, b) => Math.abs(b.ch) - Math.abs(a.ch));
      const top = sides[0];
      /* ⚠ NO COMPARISON WITHOUT SOMETHING TO COMPARE TO. With the page cut to
         31 Aug the prior window is one week or none, and dividing by it printed
         "Puts sold pay 186% more than the 6 weeks prior" off two data points.
         The card says what it has instead. */
      const priorReal = priorW.filter((w) => blendPct(w) !== null).length;
      if (priorReal < 2) {
        const nowPct = bl[bl.length - 1];
        const runW = trWeeks.filter((w) => blendPct(w) !== null).length;
        creditLines.push(nowPct !== null
          ? `${nowPct.toFixed(2)}% of strike \u00B7 ${runW} week${runW === 1 ? '' : 's'} of history so far`
          : 'No credit yet this week');
      } else if (Math.abs(top.ch) < 10) {
        const nowPct = bl[bl.length - 1];
        creditLines.push(nowPct !== null ? `Credit holding at ${nowPct.toFixed(2)}% of strike` : 'Credit holding');
      } else {
        creditLines.push(`${top.k === 'calls' ? 'Calls' : 'Puts'} sold pay ${Math.abs(Math.round(top.ch))}% ${top.ch > 0 ? 'more' : 'less'} than the 6 weeks prior`);
      }
      /* The second line is the first cause that moved, most telling first. */
      const up = top.ch >= 0;
      const ivR = mean(recentW.map((w) => w.iv).filter((x): x is number => x !== null));
      const ivP = mean(priorW.map((w) => w.iv).filter((x): x is number => x !== null));
      const ivCh = ivR && ivP ? pctOf(ivR, ivP) : 0;
      const nR = mean(recentW.map((w) => w.calls.n + w.puts.n));
      const nP = mean(priorW.map((w) => w.calls.n + w.puts.n));
      const nCh = pctOf(nR, nP);
      const bR = recentW.reduce((a, w) => a + w.back, 0);
      const bP = mean(priorW.map((w) => w.back)) * TR_RECENT;
      const namesR = new Set<string>(), namesP = new Set<string>();
      for (const w of recentW) for (const t of trCredit.get(w.week)?.names ?? []) namesR.add(t);
      for (const w of priorW) for (const t of trCredit.get(w.week)?.names ?? []) namesP.add(t);
      const fresh = [...namesR].filter((t) => !namesP.has(t)).sort();
      const mv2 = bookMove.w2;
      const causes: string[] = [];
      if (Math.abs(ivCh) >= 10) causes.push(`IV on the legs sold ${ivCh > 0 ? 'up' : 'down'} ${Math.abs(Math.round(ivCh))}%`);
      if (mv2 !== null && mv2 !== undefined && Math.abs(mv2) >= 3 && (mv2 > 0) === up) {
        causes.push(`Stocks ${mv2 > 0 ? 'up' : 'down'} ${Math.abs(mv2).toFixed(1)}% in 2 weeks, LEAPs ${mv2 > 0 ? 'rising' : 'falling'}`);
      }
      if (fresh.length) causes.push(`New names sold: ${joinNames(fresh.slice(0, 3))}`);
      if (Math.abs(nCh) >= 25) causes.push(`Writing ${Math.abs(Math.round(nCh))}% ${nCh > 0 ? 'more' : 'fewer'} contracts a week`);
      if (bR >= 200 && bR > bP * 1.5) causes.push(`Buybacks ${usd(bR)} in 2 weeks, up from ${usd(bP)}`);
      if (creditLines.length && causes.length) creditLines.push(causes[0]);
    }
    /* The usual range: the middle half of every week's blend on record. */
    const allBl = hist.map(([, e]) => {
      const nl = e.calls.notional + e.puts.notional;
      return nl > 0 ? (e.calls.cash + e.puts.cash) / nl * 100 : null;
    }).filter((x): x is number => x !== null).sort((a, b) => a - b);
    const q = (p: number) => {
      if (!allBl.length) return null;
      const i = (allBl.length - 1) * p, lo = Math.floor(i), hi = Math.ceil(i);
      return r2(allBl[lo] + (allBl[hi] - allBl[lo]) * (i - lo));
    };
    const creditTrend = {
      asOf: liveRead.day,
      weeks: trWeeks,
      names: thNames,
      theta: {
        state: stateOf(trWeeks.map((w) => (w.ratio === null ? null : Math.min(w.ratio, 6)))),
        lines: thetaLines,
      },
      credit: {
        state: stateOf(bl),
        lines: creditLines,
        usualLo: q(0.25), usualHi: q(0.75), usualWeeks: allBl.length,
      },
    };

    /* ── intrinsic value ──────────────────────────────────────────────────
       handoff `export 9/intrinsic-premium`, 14 Sep 2026. What the long legs
       are worth today, and how much of that is real rather than time.

       ⚠ THE LONG LEGS ONLY. Short legs were on the first design and came off:
       their intrinsic is money OWED, which inverts every colour on the card.
       Short-leg moneyness is the roll check's job.

       ⚠ THE WHOLE IS max(paid, mark), NOT PAID — and that is an amendment to
       the sheet, forced by the book. The sheet says "PAID IS THE WHOLE" and
       cuts it into intrinsic + time + lost, which only works while the leg is
       DOWN. The long puts are UP $1,377 today, and there intrinsic + time
       already exceed paid, so the three shares would sum past 100% and the bar
       would draw off its own track.

       With the whole as max(paid, mark) the down case is unchanged — paid is
       the larger, and the segments are exactly the sheet's 66/30/3 — and the
       up case is defined: mark is the whole, the two real segments fill it,
       and the third figure is a GAIN rather than a loss. `cost` is shipped
       either way so the client can mark where paid falls inside an up bar.
       Flagged to Nik with the build. */
    const longLeg = (type: string, label: string, unit: string) => {
      /* `mk` and not `mark`: the module already has a `mark` map of every
         leg's price, and shadowing it here would read as the same thing. */
      let mk = 0, paid = 0, intr = 0, n = 0;
      for (const e of open) {
        if (e.dir !== 'long' || e.type !== type) continue;
        const S0 = spot.get(e.ticker) ?? 0;
        const md = e.ids.map((i) => mark.get(i)).filter(Boolean) as { d: number; m: number }[];
        /* An unpriced leg is not a worthless one: it marks at what it cost,
           the same fallback Programme uses, so a LEAP bought this morning
           reads 0 rather than a total loss. */
        const m = md.length
          ? md.reduce((a, x) => a + x.m, 0) / md.length
          : (e.n > 0 ? e.cash / (e.n * 100) : 0);
        mk += m * e.n * 100;
        paid += e.cash;
        n += e.n;
        /* ⚠ MONEYNESS INVERTS ON A PUT. A call is real above its strike, a put
           below it; the call rule alone would report every protective put as
           pure time value on the day it is worth most. */
        const iv = type === 'put' ? Math.max(0, e.k - S0) : Math.max(0, S0 - e.k);
        intr += iv * e.n * 100;
      }
      return {
        k: type === 'put' ? 'lp' : 'lc', label,
        sub: `${Math.round(n)} ${unit}${Math.round(n) === 1 ? '' : 's'}`,
        mark: Math.round(mk), paid: Math.round(paid), intr: Math.round(Math.min(intr, mk)),
      };
    };
    const ivLegs = [longLeg('call', 'Long calls', 'LEAP'), longLeg('put', 'Long puts', 'put')]
      .filter((l) => l.paid > 0);

    /* One row a name, one strike a side. Every name in this book holds a
       single long-call strike and at most one long-put strike; if a name is
       ever built in two tranches the LARGEST by contracts is the row, because
       the dot is about where the position sits and the position is the block. */
    const kOf = (t: string, type: string) => {
      const legs = open.filter((e) => e.ticker === t && e.dir === 'long' && e.type === type);
      if (!legs.length) return null;
      const best = legs.reduce((a, b) => (b.n > a.n ? b : a));
      return { k: r2(best.k), exp: best.exp };
    };
    const ivRows = [...new Set(positions.map((p) => p.t))].map((t) => ({
      t, call: kOf(t, 'call'), put: kOf(t, 'put'),
    })).filter((r) => r.call || r.put);

    const intrinsic = { legs: ivLegs, rows: ivRows };

    /* ── what a 30-delta weekly call pays ─────────────────────────────────
       Premium now's figure tap and its whole footer. The same contract priced
       twice — at today's IV and at the name's own usual — so the difference is
       vol and nothing else: same spot, same tenor, same delta.

       ⚠ THE ASSUMPTIONS ARE STATED BECAUSE THEY ARE CHOICES. Seven days,
       because the book sells weeklies; zero rate and no dividend, the same
       simplification the payoff planner makes; delta fixed at 0.30, so the
       strike moves with the vol rather than the delta. None of these is
       measurable from the book — flagged to Nik. */
    const D30 = -0.5244005127080407;          // the d1 at which N(d1) = 0.30
    const PAY_T = 7 / 365;
    function ncdf(x: number): number {
      const a1 = .254829592, a2 = -.284496736, a3 = 1.421413741,
            a4 = -1.453152027, a5 = 1.061405429, p = .3275911;
      const sg = x < 0 ? -1 : 1, z = Math.abs(x) / Math.SQRT2, t = 1 / (1 + p * z);
      const y = 1 - ((((a5 * t + a4) * t + a3) * t + a2) * t + a1) * t * Math.exp(-z * z);
      return .5 * (1 + sg * y);
    }
    /* Delta is fixed, so the strike is derived rather than searched for:
       d1 = (ln(S/K) + v²T/2) / (v√T) at d1 = D30 gives
       K = S · exp(v²T/2 − D30·v√T), and the price collapses to
       0.30·S − K·N(d1 − v√T). */
    const pay30 = (S0: number, ivPct: number) => {
      const v = ivPct / 100;
      if (S0 <= 0 || v <= 0) return 0;
      const sq = v * Math.sqrt(PAY_T);
      const K = S0 * Math.exp(v * v * PAY_T / 2 - D30 * sq);
      return Math.max(0, Math.round((0.30 * S0 - K * ncdf(D30 - sq)) * 100));
    };

    /* ── the two cover rings' borrowed marks ──────────────────────────────
       handoff `export 7/cover-rings`, 14 Sep 2026. Both rings print the SAME
       two figures under the arc, so they are computed once here rather than
       twice on the phone.

       ⚠ THE TICKS ARE CAPACITY, PER SIDE. Prices ships `free` as calls PLUS
       puts in one number because its job is "is this name worked"; a ring may
       only count its own side, or the call ring would wear the put ring's
       room as its own. */
    const freeCalls = [...inv.values()].reduce((a, r) => a + Math.max(0, r.ch - r.cs), 0);
    const freePuts = [...inv.values()].reduce((a, r) => a + Math.max(0, r.ph - r.ps), 0);
    /* ⚠ THE MOVE WORD IS THE ONE PRICES PRINTS ON SCREEN, and that is the
       EQUAL-WEIGHT mean, not `bookMove`. `bookMove` weights by cost basis and
       the Prices CARD averages its rows flat, so the two disagree — −2.2%
       against −1.4% today. Shipping the weighted one would have put a figure
       under both rings that contradicts the card three above them, which is
       the exact defect one shared function exists to prevent. Caught by
       rendering the page, not by reading the payload. */
    const w1s = priceRows.map((r) => r.pct.w1).filter((v): v is number => v !== null);
    const coverMove = w1s.length
      ? r2(w1s.reduce((a, b) => a + b, 0) / w1s.length) : null;

    /* ── call cover ───────────────────────────────────────────────────────
       The twin of the put ring, and the book-level reading of Yield progress:
       what the LEAP calls cost, against the short-call credit banked toward
       paying for them.

       ⚠ AGGREGATED BY NAME, NEVER BY LEG. `positions` is one row per long-call
       LEG — BABA holds two, opened at different strikes — and each row carries
       the NAME's `collected` and `week`. Summing the rows would count BABA's
       credit twice and read the ring 3 points high.

       ⚠ CALL PREMIUM ONLY, the other half of Nik's 2026-09-06 rule. He ruled
       that call premium must not fund the put ring; the same dollar cannot run
       the other way either, so a short PUT credit is the put ring's and is not
       in here. Programme's per-name `collected` is every short credit, so it
       reads above this on the four names that have sold puts. Flagged.

       ⚠ AND THE NAME MUST HOLD A LEAP. META, NVDA and eleven others carry
       short-call history from the share era; NVDA's is −$40,402 of buy-backs.
       Credit with nothing to pay off is not cover. */
    const leapCostBy = new Map<string, number>();
    for (const e of open) {
      if (e.dir !== 'long' || e.type !== 'call') continue;
      leapCostBy.set(e.ticker, (leapCostBy.get(e.ticker) ?? 0) + e.cash);
    }
    const callCrBy = new Map<string, number>(), callWkBy = new Map<string, number>();
    /* Settled and open kept apart: Coverage draws the first as its bar and the
       second as the lighter cap above it. */
    const callCrOpenBy = new Map<string, number>();
    for (const t of bookShorts) {
      if (String(t.option_type) !== 'call') continue;
      const tk = String(t.ticker);
      if (!leapCostBy.has(tk)) continue;
      const c = (String(t.action) === 'open' ? 1 : -1) * N(t.contracts) * N(t.premium) * 100;
      if (isSettled(t)) callCrBy.set(tk, (callCrBy.get(tk) ?? 0) + c);
      else callCrOpenBy.set(tk, (callCrOpenBy.get(tk) ?? 0) + c);
      /* Bucketed by the week the leg COVERS, the rule every card here uses. */
      if (weekStart(String(t.expiry).slice(0, 10)) === thisWeek) {
        callWkBy.set(tk, (callWkBy.get(tk) ?? 0) + c);
      }
    }
    const callNames = [...leapCostBy.entries()].filter(([, v]) => v > 0);
    const callCost = callNames.reduce((a, [, v]) => a + v, 0);
    const callCollected = callNames.reduce((a, [t]) => a + (callCrBy.get(t) ?? 0), 0);
    /* ⚠ THE PACE IS THIS WEEK, NOT AN AVERAGE. The sheet's `week` field, and
       the same figure Weekly yield draws as its live bar. The put ring averages
       its live weeks because short puts are written in tranches and a zero week
       there is silence, not a stop; short calls are written every week. */
    const callPace = callNames.reduce((a, [t]) => a + (callWkBy.get(t) ?? 0), 0);
    const callLeft = Math.round(callCost - callCollected);

    /* Premium now's rows are finished here: `pay30` needs spot and the free
       counts need the inventory, and both are built above this line. */
    for (const r of premiumRows as PremRow[]) {
      const S0 = spot.get(r.t) ?? 0, inv0 = inv.get(r.t);
      r.pay = pay30(S0, r.now);
      r.payU = pay30(S0, r.usual);
      r.free = inv0 ? Math.max(0, inv0.ch - inv0.cs) + Math.max(0, inv0.ph - inv0.ps) : 0;
      r.move = priceRows.find((x) => x.ticker === r.t)?.pct.w1 ?? null;
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
    /* ⚠ ONE DATE FOR THE PAGE, 17 Sep 2026: the put programme starts where
       everything else starts. It ran from 1 Sep because that was when the
       first hedge of this book was read as "the programme"; the FIS puts of
       26 Aug and the NKE puts of 31 Aug are the same hedge and belong in it. */
    const PUT_START = BOOK_START;
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
    const putWeek = new Map<string, number>(), putWeekOpen = new Map<string, number>();
    /* Settled only, the page rule. A short put still open has taken cash in
       that could still be handed back, so it does not pay for the hedge yet;
       it waits in `putWeekOpen` and Coverage draws it as the lighter cap. */
    const putLeft2 = new Map<string, number>();
    for (const t of allPuts) {
      if (String(t.direction) !== 'short') continue;
      const k = putKey(t);
      putLeft2.set(k, (putLeft2.get(k) ?? 0)
        + (String(t.action) === 'open' ? 1 : -1) * N(t.contracts));
    }
    for (const t of allPuts) {
      if (String(t.direction) !== 'short' || !inProgramme(t)) continue;
      const c = (String(t.action) === 'open' ? 1 : -1) * N(t.contracts) * N(t.premium) * 100;
      const w = weekStart(String(t.expiry).slice(0, 10));
      const done = String(t.expiry).slice(0, 10) < today
        || (putLeft2.get(putKey(t)) ?? 0) <= 0.0001;
      const M = done ? putWeek : putWeekOpen;
      M.set(w, (M.get(w) ?? 0) + c);
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

    /* ── cover bars ───────────────────────────────────────────────────────
       handoff `export 12/cover-bars`, 14 Sep 2026. These two REPLACE the rings.

       ⚠ ONLY TIME VALUE HAS TO BE COVERED, and that is the whole change. The
       rings measured credit against the whole COST of the long legs, which is
       the wrong denominator: a long leg's intrinsic is real money — exercising
       returns it — so premium only has to earn back the part that melts. Nik,
       14 Sep 2026: "us saying that the whole thing will go to zero just doesn't
       make any sense." The call side goes from 16% covered of cost to 31% of
       time value on the same book, and the ring was telling him he was behind
       when he was not.

       ⚠ AND IT IS TWO MOVING QUANTITIES, WHICH IS WHY THE RING HAD TO GO. A ring
       shows one fraction against a fixed whole. Here the left side shrinks every
       day and the right grows every week, and the reader needs to see both. */
    const coverDay = async (day: string) => {
      const { day: d, rows } = await greeksOn(day, 'option_trade_id,last_mark');
      const mk = new Map<string, number>();
      for (const g of rows) {
        const id = String(g.option_trade_id);
        if (!mk.has(id)) mk.set(id, N(g.last_mark));
      }
      return { day: d, mk };
    };
    /* ⚠ THE SPOT OF THAT DAY, NOT TODAY'S. Intrinsic is spot against strike, so
       a past day's time value needs that day's close — using today's would
       report the stock's move as decay. */
    const closeAt = new Map<string, number>();
    for (const r of closes) {
      closeAt.set(`${r.ticker}|${String(r.date).slice(0, 10)}`, N(r.close_price));
    }
    const spotOn = (t: string, d: string) => {
      for (let i = 0; i < 7; i++) {
        const k = `${t}|${new Date(Date.parse(d + 'T00:00:00Z') - i * 86_400_000)
          .toISOString().slice(0, 10)}`;
        const v = closeAt.get(k);
        if (v && v > 0) return v;
      }
      return spot.get(t) ?? 0;
    };
    /* Every long leg's id, with what it takes to value it on a past day. */
    type LongLeg = { ticker: string; type: string; k: number; n: number; ids: string[] };
    const longLegs: LongLeg[] = open
      .filter((e) => e.dir === 'long')
      .map((e) => ({ ticker: e.ticker, type: e.type, k: e.k, n: e.n, ids: e.ids }));

    /* ⚠ COMPARE THE SAME LEGS OR THE GHOST IS A LIE. `mp-refresh` covered 27
       legs on 7 September and 66 today, so a naive then-against-now would
       report the widening COVERAGE as time value appearing out of nowhere — and
       a LEAP bought this morning would read as a week's melt in reverse. The
       change is measured over the legs present in BOTH readings, and the ghost's
       level is today's total less that change, so the line sits where it
       honestly sits against the bar beside it. */
    const timeOver = (mk: Map<string, number>, day: string, type: string,
                      only?: Set<string>) => {
      let tv = 0;
      const seen = new Set<string>();
      for (const e of longLegs) {
        if (e.type !== type) continue;
        const md = e.ids.map((i) => mk.get(i)).filter((x) => x !== undefined) as number[];
        if (md.length !== e.ids.length) continue;          // the leg did not exist yet
        if (only && !e.ids.every((i) => only.has(i))) continue;
        for (const i of e.ids) seen.add(i);
        const m = md.reduce((a, b) => a + b, 0) / md.length;
        const S0 = spotOn(e.ticker, day);
        const intr = type === 'put' ? Math.max(0, e.k - S0) : Math.max(0, S0 - e.k);
        tv += Math.max(0, m - intr) * e.n * 100;
      }
      return { tv: Math.round(tv), ids: seen };
    };
    const nowMk = new Map<string, number>();
    for (const [id, v] of mark) nowMk.set(id, v.m);

    /* ⚠ AND CREDIT IS COUNTED THE WAY ITS OWN CARD COUNTS IT. The call side is
       short-call credit on a name that holds a LEAP; the put side is the put
       programme's, which needs `direction` and `strike` to test membership —
       fields the shorts query does not select, so it reads `allPuts`. Getting
       this wrong made the put ghost read zero against a real $2,214. */
    const creditTo = (cut: string, type: string) => {
      let c = 0;
      if (type === 'call') {
        for (const t of bookShorts) {
          if (String(t.option_type) !== 'call') continue;
          if (String(t.trade_date).slice(0, 10) > cut || !settledBy(t, cut)) continue;
          if (!leapCostBy.has(String(t.ticker))) continue;
          c += (String(t.action) === 'open' ? 1 : -1) * N(t.contracts) * N(t.premium) * 100;
        }
      } else {
        for (const t of allPuts) {
          if (String(t.direction) !== 'short' || !inProgramme(t)) continue;
          if (String(t.trade_date).slice(0, 10) > cut) continue;
          c += (String(t.action) === 'open' ? 1 : -1) * N(t.contracts) * N(t.premium) * 100;
        }
      }
      return Math.round(c);
    };

    const ydayDate = closes.map((r) => String(r.date).slice(0, 10))
      .filter((d) => d < today).sort().pop() ?? ago(1);
    const [ydayMk, weekMk] = await time('coverHist', () =>
      Promise.all([coverDay(ydayDate), coverDay(ago(7))]));

    /* This week's realised credit per side, and how many names hold that leg. */
    const putWkTotal = [...putWeek.entries()]
      .filter(([w]) => w === thisWeek).reduce((a, [, v]) => a + v, 0);
    const nameCount = (type: string) =>
      new Set(longLegs.filter((e) => e.type === type).map((e) => e.ticker)).size;

    const ghost = (read: { day: string; mk: Map<string, number> }, type: string) => {
      const then = timeOver(read.mk, read.day, type);
      if (!then.ids.size) return null;
      const nowSame = timeOver(nowMk, today, type, then.ids);
      const l = ivLegs.find((x) => x.k === (type === 'put' ? 'lp' : 'lc'));
      const now = l ? l.mark - l.intr : 0;
      return Math.max(0, Math.round(now - (nowSame.tv - then.tv)));
    };

    const side = (type: string, label: string, scope: string,
                  collected: number, pace: number, melt: number, open: number) => ({
      label, scope, names: nameCount(type),
      /* ⚠ TODAY'S FIGURE IS THE INTRINSIC CARD'S, NOT A SECOND DERIVATION. The
         sheet requires the two cards to read one book, and two computations of
         "time value" would disagree the first time one of them was changed. */
      time: (() => {
        const l = ivLegs.find((x) => x.k === (type === 'put' ? 'lp' : 'lc'));
        return l ? l.mark - l.intr : 0;
      })(),
      /* Null where no leg of this side was being priced that day — the history
         simply does not reach back yet, and a zero would draw the ghost on the
         floor and claim the whole bar melted. */
      hist: { yday: ghost(ydayMk, type), week: ghost(weekMk, type) },
      collected: Math.round(collected),
      /* ⚠ THE LIGHTER CAP, 17 Sep 2026. Credit taken on legs that are still
         open: real cash, not yet earned, and it can still be handed back. Nik
         asked for it drawn above the solid bar rather than inside it. */
      open: Math.round(open),
      chist: { yday: creditTo(ydayMk.day, type), week: creditTo(weekMk.day, type) },
      pace: Math.round(pace),
      /* Positive: the card's word is "melts", so the sign is in the label. */
      melt: Math.abs(melt),
    });

    /* ── yield progress, by name ──────────────────────────────────────────
       handoff `export 13/yield-progress`, 14 Sep 2026. Call cover taken apart:
       one row a name, that name's time value over the premium collected
       against it, on one scale for the whole card.

       ⚠ THE DENOMINATOR IS TIME VALUE, NOT WHAT WAS PAID. The 2 Sep card read
       `collected / paid` and ranked every name against the book's average — a
       card about how far along each name was on a road whose end was the wrong
       place. Intrinsic is real money that exercising returns; only the part
       that melts has to be earned back. Same correction as the cover bars.

       ⚠ AND THE PACE IS CALL CREDIT ONLY, bucketed by the week the leg COVERS.
       That is `callWkBy`, the same map Call cover sums, so the rows' clocks
       roll up to the book's. Put credit is spoken for by the put programme and
       one dollar cannot discharge two debts.

       ⚠ NEGATIVE TIME VALUE IS CLAMPED TO ZERO, per leg. KR's LEAP is $26 deep
       in the money and marks $1.09 a share BELOW intrinsic, which is ordinary
       for something that deep: time value is −$109. Nik, 14 Sep 2026: "yes
       clamp it". A negative bar has no width and a ratio against a negative
       number says nothing, and the truth of the row is that premium has
       nothing left to earn back there. So the name reads covered with no wash
       bar at all.

       ⚠ WHICH IS WHY THIS SUM IS $109 ABOVE CALL COVER'S. That card takes
       today's figure from the Intrinsic value card, which subtracts Σintrinsic
       from Σmark at BOOK level and so lets KR's −$109 net against the rest.
       Both print $106k. Flagged to Nik with the build; if he wants them equal
       to the dollar, the fix is to clamp in `longLeg` too. */
    const ypTime = new Map<string, number>();
    for (const e of open) {
      if (e.dir !== 'long' || e.type !== 'call') continue;
      if (!leapCostBy.has(e.ticker)) continue;
      const S0 = spot.get(e.ticker) ?? 0;
      const md = e.ids.map((i) => mark.get(i)).filter(Boolean) as { d: number; m: number }[];
      /* An unpriced leg marks at what it cost, the deck's fallback: a LEAP
         bought this morning is not a worthless one. */
      const m = md.length
        ? md.reduce((a, x) => a + x.m, 0) / md.length
        : (e.n > 0 ? e.cash / (e.n * 100) : 0);
      const tv = Math.max(0, m - Math.max(0, S0 - e.k)) * e.n * 100;
      ypTime.set(e.ticker, (ypTime.get(e.ticker) ?? 0) + tv);
    }

    /* This week's long-call decay, per name, positive. Same reading Theta's
       last week draws as `lc`, split by ticker rather than by side. */
    const ypMelt = new Map<string, number>();
    for (const [id, th] of thRead[thRead.length - 1].th) {
      const leg = thLegs.get(id);
      if (!leg || leg.dir !== 'long' || leg.type !== 'call') continue;
      if (leg.exp < thisWeek || !leapCostBy.has(leg.ticker)) continue;
      ypMelt.set(leg.ticker, (ypMelt.get(leg.ticker) ?? 0) - th * leg.n * 100);
    }

    /* Roll check's own test, on the name: a short CALL bought back for more
       than it was sold for. It marks the ticker, never the figure — a roll is
       not a loss on the LEAP, it is why that name's bar is lagging. */
    const ypRoll = new Map<string, boolean>();
    for (const p of positions) {
      ypRoll.set(p.t, p.shorts.some((sh) => sh.type === 'call' && sh.priced && sh.captured < 0));
    }

    const ypRows = callNames.map(([t]) => {
      const time0 = Math.round(ypTime.get(t) ?? 0);
      return {
        t,
        time: time0,
        collected: Math.round(callCrBy.get(t) ?? 0),
        open: Math.round(callCrOpenBy.get(t) ?? 0),
        pace: Math.round(callWkBy.get(t) ?? 0),
        melt: Math.round(Math.abs(ypMelt.get(t) ?? 0)),
        rolling: ypRoll.get(t) === true,
        /* ⚠ A DATE FROM THE LEDGER, NOT FROM TODAY'S FIGURES. Filled below,
           and only for a name that is actually covered — walking history for a
           name that has never crossed is a day of reads for a null. */
        coveredOn: null as string | null,
      };
    });

    /* That name's banked call credit as at the close of `cut`. The same sum
       `callCrBy` makes, stopped at a date. */
    const ypCreditOn = (t: string, cut: string) => {
      let c = 0;
      for (const sh of bookShorts) {
        if (String(sh.option_type) !== 'call' || String(sh.ticker) !== t) continue;
        if (String(sh.trade_date).slice(0, 10) > cut || !settledBy(sh, cut)) continue;
        c += (String(sh.action) === 'open' ? 1 : -1) * N(sh.contracts) * N(sh.premium) * 100;
      }
      return c;
    };

    /* ⚠ AND THE WALK ONLY RUNS WHEN SOMETHING CROSSED. `option_greeks` reaches
       back to the day each LEAP was bought (31 Aug at the earliest — the book
       is two weeks old), so a crossing can be dated, but every day costs a
       read. Today nothing is covered and this loop does not execute at all. */
    const ypChasing = ypRows.filter((r) => r.collected < r.time);
    const ypCovered = ypRows.filter((r) => r.collected >= r.time);
    if (ypCovered.length) {
      const want = new Map(ypCovered.map((r) => [r.t, r]));
      for (let back = 1; back <= 20 && want.size; back++) {
        const d = dayShift(today, -back);
        const { day, mk } = await coverDay(d);
        if (day !== d) continue;             // no reading that day: a holiday
        for (const [t, row] of [...want]) {
          let tv = 0, saw = false;
          for (const e of open) {
            if (e.ticker !== t || e.dir !== 'long' || e.type !== 'call') continue;
            const md = e.ids.map((i) => mk.get(i)).filter((x) => x !== undefined) as number[];
            if (md.length !== e.ids.length) continue;    // not held that day
            saw = true;
            const m = md.reduce((a, b) => a + b, 0) / md.length;
            tv += Math.max(0, m - Math.max(0, spotOn(t, day) - e.k)) * e.n * 100;
          }
          /* The day it was NOT yet covered is the day before the crossing, so
             the row keeps the LAST day it was still covered. */
          if (!saw || ypCreditOn(t, day) < tv) want.delete(t);
          else row.coveredOn = day;
        }
      }
    }

    const yieldProgress = ypRows.length
      ? {
        asOf: dayLive ? today : ydayDate,
        /* Covered names first by how far past, then the chasers by how close.
           The one sort; a tap never re-ranks the card. */
        names: [
          ...ypCovered.sort((a, b) =>
            (b.time > 0 ? b.collected / b.time : Infinity)
            - (a.time > 0 ? a.collected / a.time : Infinity)),
          ...ypChasing.sort((a, b) => b.collected / b.time - a.collected / a.time),
        ],
      }
      : null;

    /* ── long legs, by name ───────────────────────────────────────────────
       handoff `export 14/long-legs-programme`, 14 Sep 2026. The long-leg cousin
       of Prices: every long POSITION's move, where Prices shows every held
       stock's. One ledger, two cards — Programme derives its Long calls, Long
       puts and invested from these same legs, so the two can never disagree.

       ⚠ THE WINDOWS COUNT SESSIONS, NOT DAYS, and they are Prices' own offsets:
       5, 10 and 20 closes back from the same anchor. The sheet says "Friday
       closes", but the point it gives for them is that a reader can lay this
       card beside Prices and see whether the LEAP moved with the name — and
       Prices counts sessions, because a week is five trading days and calendar
       arithmetic silently shortens any window that spans a holiday. Counting
       Fridays here would put the two cards on different axes.

       ⚠ AND A LEG YOUNGER THAN A WINDOW CARRIES ITS COST. Every LEAP in this
       book was bought on 31 August or later, so 20 sessions back predates all
       of them: that window reads as the position's whole life, not as a zero.
       An unpriced slot would otherwise draw a bar out of nothing. */
    const sessions = [...new Set(closes
      .map((r) => String(r.date).slice(0, 10))
      .filter((d) => d < today))].sort().reverse();
    /* The same shift Prices applies: while a session is running the anchor is
       today's spot, so the window offsets count from the last close; outside
       one the anchor IS the last close and every offset moves back a day. */
    const llBack = (n: number) => sessions[dayLive ? n - 1 : n] ?? sessions.at(-1) ?? today;
    const llRead = await time('longLegDays', () => Promise.all(
      [5, 10, 20].map((n) => coverDay(llBack(n)))));

    const llLegs = open
      .filter((e) => e.dir === 'long')
      .map((e) => {
        /* Per contract, in dollars: the card multiplies by `n` itself. */
        const cost = e.n > 0 ? e.cash / e.n : 0;
        const md = e.ids.map((i) => mark.get(i)).filter(Boolean) as { d: number; m: number }[];
        const m = md.length ? md.reduce((a, x) => a + x.m, 0) / md.length * 100 : cost;
        const at = (r: { mk: Map<string, number> }) => {
          const w = e.ids.map((i) => r.mk.get(i)).filter((x) => x !== undefined) as number[];
          /* Every id or none: a position half-priced on a past day would report
             the missing half as free. */
          return w.length === e.ids.length && w.length
            ? w.reduce((a, b) => a + b, 0) / w.length * 100
            : cost;
        };
        /* ⚠ TO THE CENT, NOT THE DOLLAR. These are per-contract figures the
           card multiplies by `n`, so rounding here is multiplied too: whole
           dollars put the footer's Paid $14 away from Intrinsic value's, and
           the sheet requires the two to agree. */
        return {
          t: e.ticker,
          k: `${r2(e.k)}${e.type === 'put' ? 'P' : 'C'}`,
          n: Math.round(e.n),
          cost: r2(cost),
          m: r2(m),
          w1: r2(at(llRead[0])),
          w2: r2(at(llRead[1])),
          w4: r2(at(llRead[2])),
        };
      })
      .filter((l) => l.n > 0);

    const longLegsBlock = llLegs.length
      ? { asOf: dayLive ? today : ydayDate, legs: llLegs }
      : null;

    timings.total = Date.now() - T0;
    return json(200, {
      ok: true, build: BUILD, date: today, timings,
      yieldProgress,
      longLegs: longLegsBlock,
      /* ⚠ THE TWO RATES, NOT ONE NET. Programme apportions theta to a name by
         its share of kept (the short side) and of invested (the long side),
         which cannot be done from a single netted figure. Short is positive,
         long negative, both a day, both the whole book. Spread in here because
         `programme` is built before the theta weeks are read. */
      programme: {
        ...programme,
        thetaShortDay: thetaWeeks[thetaWeeks.length - 1]?.short ?? 0,
        thetaLongDay: thetaWeeks[thetaWeeks.length - 1]?.long ?? 0,
      },
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
          /* Borrowed: the ticks outside the ring, and the move word under it. */
          free: freePuts,
          move: coverMove,
        }
        : null,
      /* ⚠ NULL UNTIL A LEAP IS HELD, the same rule as the put ring: a ring at
         0% of $0 is a card with no subject, and the page drops it. */
      callCover: callCost > 0
        ? {
          names: callNames.length,
          cost: Math.round(callCost),
          collected: Math.round(callCollected),
          left: callLeft,
          pace: Math.round(callPace),
          pct: r2(callCollected / callCost * 100),
          weeksToCover: callLeft > 0 && callPace > 0 ? Math.ceil(callLeft / callPace) : 0,
          /* ⚠ THE WEEK IT IS COVERED, NOT A COUNT OF WEEKS. Nik, 14 Sep 2026:
             "add there the apprx date when the investment will be covered". A
             count makes the reader do arithmetic the card has already done, and
             do it wrong — he read 36 weeks as early May and it is the 24th.
             Derived from THIS week's Monday, so it always names a Monday and
             the ring's tap and this line are one division stated twice. */
          by: callLeft > 0 && callPace > 0
            ? new Date(Date.parse(thisWeek + 'T00:00:00Z')
                + Math.ceil(callLeft / callPace) * 7 * 86_400_000)
                .toISOString().slice(0, 10)
            : null,
          free: freeCalls,
          move: coverMove,
        }
        : null,
      /* `asOf` is the close the windows are measured FROM, so the card can
         say what "today" is against without the client guessing. */
      inventory,
      theta,
      creditTrend,
      intrinsic,
      coverBars: {
        asOf: dayLive ? today : ydayDate,
        sides: {
          call: side('call', 'Call cover', 'the long calls',
                     callCollected, callPace, thetaWeeks[thetaWeeks.length - 1]?.lc ?? 0,
                     callNames.reduce((a, [t]) => a + (callCrOpenBy.get(t) ?? 0), 0)),
          put: side('put', 'Put cover', 'the long puts',
                    putCollected, putWkTotal, thetaWeeks[thetaWeeks.length - 1]?.lp ?? 0,
                    [...putWeekOpen.values()].reduce((a, b) => a + b, 0)),
        },
      },
      premium,
      toRoll,
      prices: { rows: priceRows, book: bookMove,
                /* ⚠ THE DATE THE DAY WINDOW DESCRIBES, which is today while a
                   session is running and the last close's date otherwise. The
                   card names the chip from this and never from its own clock,
                   so "Friday" and Friday's figures can never come apart. */
                asOf: dayLive
                  ? today
                  : (closes.map((r) => String(r.date).slice(0, 10))
                      .filter((d) => d < today).sort().pop() ?? today),
                live: dayLive,
                /* ⚠ THE LAST COMPLETED SESSION, WHICH IS NOT `asOf`. While a
                   session is running `asOf` is TODAY — the day window is
                   measuring against a live price — and the last thing that
                   actually closed is the session before it. The pull-to-refresh
                   control prints this on done: "Fri 11 Sep · 4:00 PM close" is
                   an honest answer on a Sunday in a way "just now" is not. */
                lastClose: closes.map((r) => String(r.date).slice(0, 10))
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
