/**
 * income-week — the Monday card. Nik calls it the Awareness Card's weekly
 * sibling; it has no title on screen.
 *
 * Two sections and nothing else:
 *
 *   WHAT CHANGED        analyst moves, guidance and headlines on the held names,
 *                       for the week just gone
 *   WHAT LAST WEEK      premium in on shorts written, minus anything paid to
 *   EARNED              close early. Per name, plus a total.
 *
 * ⚠ NO POSITION DETAIL. Nik: "Dont include position detials just Benzinga
 * detials and what we have earned last week." No shares, no coverage, no floor,
 * no strikes, no assignment. Money and news. The per-position Awareness Cards
 * carry everything else, and repeating it here is what made the old Income card
 * feel like it said the same thing every day.
 *
 * ⚠ EARNED IS PREMIUM, NET OF BUY-BACKS. Not share P&L, not realised gains on
 * assignment. `sum(open) - sum(close)` over short legs. This is also why the
 * card does NOT need to tell an expiry from a buy-back: a leg that expires
 * worthless is closed at zero premium and subtracts nothing, while a leg bought
 * back subtracts what was paid. The distinction that is missing from the data
 * (see below) simply does not arise here.
 *
 * ⚠ AND THAT MISSING DISTINCTION IS REAL, for whatever needs it next.
 * `close_expired_option_legs()` stamps source='expiry' and has NEVER inserted a
 * row — IBKR reports the expiry first and ibkr-flex-sync writes it as an
 * ordinary close with closed_via null. Across the whole book: 288 ibkr closes
 * null, 26 manual null, 8 manual 'assigned', 0 expiry. It is derivable — a
 * close dated on or after expiry at zero premium is an expiry; before expiry
 * with premium paid is a buy-back — but it is not recorded.
 *
 * Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY.
 * Body (all optional): {"asof":"2026-08-24","peek":true}
 */
import { corsHeaders, json, db, ymd, parseISO, addDays, nyToday } from
  'https://raw.githubusercontent.com/nikparekh123/sunny-flow-tasks/dd3c85a56102451ae439016d6a90460c4d41dab0/supabase/functions/_shared/planner.ts';

const BUILD = '2026-08-24.2';

const N = (v: unknown, d = 0) => (v === null || v === undefined || v === '' ? d : Number(v));
const usd = (v: number) => (v < 0 ? '−' : '') + `$${Math.abs(Math.round(v)).toLocaleString('en-US')}`;
const MON = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
/** Cut on a word boundary, and mark that it was cut. */
function clip(t: string, max: number): string {
  const s = t.trim();
  if (s.length <= max) return s;
  const cut = s.slice(0, max);
  const sp = cut.lastIndexOf(' ');
  return (sp > max * 0.6 ? cut.slice(0, sp) : cut).replace(/[,.;:\s]+$/, '') + '\u2026';
}

const day = (iso: string) => {
  const d = parseISO(iso);
  return `${d.getUTCDate()} ${MON[d.getUTCMonth()]}`;
};

/** Monday of the week BEFORE the one `d` falls in. The card looks back. */
function lastWeek(d: Date): { from: string; to: string } {
  const dow = d.getUTCDay();                 // 0 Sun .. 6 Sat
  const backToMonday = dow === 0 ? 6 : dow - 1;
  const thisMonday = addDays(d, -backToMonday);
  return { from: ymd(addDays(thisMonday, -7)), to: ymd(addDays(thisMonday, -1)) };
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  try {
    const url = Deno.env.get('SUPABASE_URL')!;
    const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const D = db(url, key);

    let body: { asof?: string; peek?: boolean } = {};
    try { if (req.method === 'POST') body = await req.json(); } catch { /* no body is normal */ }
    const today = parseISO(body.asof ?? nyToday());
    const todayISO = ymd(today);
    const wk = lastWeek(today);

    const [lots, sleeveRows] = await Promise.all([
      D.get('share_lots?voided_at=is.null&qty_remaining=gt.0&select=ticker,qty_remaining'),
      D.get('income_sleeve_names?active=is.true&select=ticker'),
    ]);
    const sleeve = new Set(sleeveRows.map((r) => String(r.ticker)));
    const names = [...new Set(lots.map((r) => String(r.ticker)))].filter((t) => sleeve.has(t)).sort();
    if (!names.length) return json(200, { ok: true, empty: true, note: 'no held sleeve names' });
    const inList = `(${names.join(',')})`;

    const [trades, acts, guide, news, seen] = await Promise.all([
      D.get(`option_trades?ticker=in.${inList}&voided_at=is.null&direction=eq.short`
        + `&trade_date=gte.${wk.from}&trade_date=lte.${wk.to}`
        + '&select=ticker,action,contracts,premium,trade_date'),
      D.get(`analyst_actions?ticker=in.${inList}&date=gte.${wk.from}&date=lte.${wk.to}`
        + '&select=ticker,date,firm,rating,rating_action,price_target,previous_price_target,price_target_action&order=date.desc'),
      D.get(`guidance_events?ticker=in.${inList}&date=gte.${wk.from}&date=lte.${wk.to}`
        + '&select=ticker,date,direction,fiscal_period&order=date.desc'),
      D.get(`name_news?ticker=in.${inList}&published=gte.${wk.from}&published=lte.${wk.to}T23:59:59`
        + '&select=ticker,published,title,publisher,url&order=published.desc'),
      D.get('income_week_seen?select=week_from,seen_at'),
    ]);

    // ── what last week earned ────────────────────────────────────────────────
    const earned = names.map((t) => {
      const mine = trades.filter((r) => String(r.ticker) === t);
      const net = mine.reduce((s, r) =>
        s + (r.action === 'open' ? 1 : -1) * N(r.contracts) * N(r.premium) * 100, 0);
      return { ticker: t, net, text: `${t} ${usd(net)}` };
    }).filter((x) => x.net !== 0);
    const total = earned.reduce((s, x) => s + x.net, 0);

    // ── what changed ─────────────────────────────────────────────────────────
    type Ev = { date: string; ticker: string; text: string; rank: number };
    const evs: Ev[] = [];

    /* Same-day clusters collapse to ONE line, per ticker. Counting each firm
       separately is what turned a single earnings reaction into "22 cuts" on
       the old Income card. */
    const byKey = new Map<string, Record<string, unknown>[]>();
    for (const r of acts) {
      const k = `${r.ticker}|${String(r.date).slice(0, 10)}`;
      const g = byKey.get(k); if (g) g.push(r); else byKey.set(k, [r]);
    }
    for (const [k, g] of byKey) {
      const [t, d] = k.split('|');
      const cu = g.filter((r) => r.price_target_action === 'lowers').length;
      const ra = g.filter((r) => r.price_target_action === 'raises').length;
      const dn = g.filter((r) => r.rating_action === 'downgrades').length;
      const up = g.filter((r) => r.rating_action === 'upgrades').length;
      let text: string;
      if (g.length === 1) {
        const r = g[0];
        const pt = N(r.price_target), pp = N(r.previous_price_target);
        const tgt = pt && pp && pt !== pp ? `, ${pp} to ${pt}` : '';
        text = r.rating_action === 'downgrades' ? `${t}: ${r.firm} cut it to ${r.rating}${tgt}`
             : r.rating_action === 'upgrades' ? `${t}: ${r.firm} raised it to ${r.rating}${tgt}`
             : pt && pp && pt !== pp ? `${t}: ${r.firm} ${pt < pp ? 'cut' : 'raised'} its target${tgt}`
             : `${t}: ${r.firm} reiterated ${r.rating}`;
      } else {
        const parts: string[] = [];
        if (cu) parts.push(`${cu} target cut${cu > 1 ? 's' : ''}`);
        if (ra) parts.push(`${ra} target raise${ra > 1 ? 's' : ''}`);
        if (dn) parts.push(`${dn} downgrade${dn > 1 ? 's' : ''}`);
        if (up) parts.push(`${up} upgrade${up > 1 ? 's' : ''}`);
        text = `${t}: ${g.length} firms moved`
          + (parts.length ? `, ${parts.join(', ')}` : ', no target or rating changes');
      }
      evs.push({ date: d, ticker: t, text, rank: (dn + up) ? 5 : 3 });
    }
    for (const g of guide) {
      const gd = String(g.direction);
      const w = gd === 'cut' ? 'cut' : gd === 'raised' ? 'raised'
              : gd === 'reaffirmed' ? 'reaffirmed' : gd === 'initiated' ? 'introduced' : gd;
      evs.push({ date: String(g.date).slice(0, 10), ticker: String(g.ticker), rank: 6,
        text: `${g.ticker}: guidance ${w}${g.fiscal_period ? ` for ${g.fiscal_period}` : ''}` });
    }
    /* ⚠ CAP THE WIRE AT TWO PER NAME. Uncapped it wins every week: these names
       carry a steady drip of Motley Fool pieces and nothing else, which is
       exactly how the Income card turned into a news channel once before. */
    const perName = new Map<string, number>();
    for (const n of news) {
      const t = String(n.ticker);
      const c = perName.get(t) ?? 0;
      if (c >= 2) continue;
      perName.set(t, c + 1);
      /* ⚠ NO EM DASH, and never a mid-word cut. slice(0,78) produced
         "He Invested i" and "It's Been My Best St", which reads as corruption
         rather than abbreviation. Cut at the last space before the limit and
         say so with an ellipsis. */
      evs.push({ date: String(n.published).slice(0, 10), ticker: t, rank: 1,
        text: `${t}: ${n.publisher}, ${clip(String(n.title), 76)}` });
    }
    evs.sort((a, b) => b.date.localeCompare(a.date) || b.rank - a.rank);

    const already = (seen as Record<string, unknown>[])
      .some((r) => String(r.week_from).slice(0, 10) === wk.from);

    /* Monday only, and gone once read. The card is written for the week just
       gone, so it is meaningless on a Thursday. */
    const isMonday = today.getUTCDay() === 1;

    if (!body.peek && isMonday && !already) {
      await D.upsert('income_week_seen',
        [{ week_from: wk.from, seen_at: new Date().toISOString() }], 'week_from');
    }

    return json(200, {
      ok: true, build: BUILD, asof: todayISO,
      week: { from: wk.from, to: wk.to, label: `${day(wk.from)} to ${day(wk.to)}` },
      show: isMonday && !already,
      is_monday: isMonday,
      already_read: already,
      changed: evs.map((e) => ({ when: day(e.date), text: e.text })),
      earned: earned.map((e) => ({ ticker: e.ticker, amount: usd(e.net), net: e.net })),
      earned_total: usd(total),
      /* ⚠ NAME A QUIET WEEK RATHER THAN FILLING IT. Five headlines against one
         analyst move is the imbalance Nik rejected on the Awareness Card: the
         wire always has something, so an unqualified list implies a busy week
         when nothing happened. Count the substantive moves and say so. */
      substantive: evs.filter((e) => e.rank >= 3).length,
      quiet: evs.length === 0 ? 'Nothing moved on your names last week.'
        : evs.some((e) => e.rank >= 3) ? null
        : 'No analyst or guidance moves last week. Headlines only.',
    });
  } catch (e) { return json(500, { ok: false, error: String(e) }); }
});
