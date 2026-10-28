/**
 * The search card menu's lookups (Sunny search, Nik 27 Oct 2026): one per card, each returning its card's data
 * on its own as { type, tag, source: { kind, at }, data }. Reads what Sunny already works out (home_snapshot,
 * gamma_view_day) and, for walls on any ticker, asks gex-walls live. Never writes, never trades.
 */
export const SB_URL = Deno.env.get('SUPABASE_URL')!;
export const SB_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
export type Row = Record<string, any>;

export async function db(path: string): Promise<Row[]> {
  const r = await fetch(`${SB_URL}/rest/v1/${path}`, { headers: { apikey: SB_KEY, Authorization: `Bearer ${SB_KEY}` } });
  if (!r.ok) throw new Error(`${path.split('?')[0]}: HTTP ${r.status}`);
  return await r.json();
}

/** Who is asking and which book they may see: the scheduler and the service key read Nik's book (S). */
export async function caller(req: Request): Promise<{ book: string; owner: boolean; system: boolean; user?: string } | null> {
  const cron = Deno.env.get('CRON_SECRET');
  if (cron && (req.headers.get('x-cron-key') === cron || req.headers.get('x-admin-key') === cron)) return { book: 'S', owner: true, system: true };
  const auth = req.headers.get('authorization') ?? '';
  if (auth === `Bearer ${SB_KEY}`) return { book: 'S', owner: true, system: true };
  if (!auth.startsWith('Bearer ')) return null;
  const r = await fetch(`${SB_URL}/auth/v1/user`, { headers: { apikey: Deno.env.get('SUPABASE_ANON_KEY') ?? '', Authorization: auth } });
  if (!r.ok) { await r.body?.cancel(); return null; }
  const u = await r.json();
  const m = await db(`book_members?user_id=eq.${u.id}&select=book_id,role`);
  const own = m.find((x) => x.role === 'owner') ?? m[0];
  return own ? { book: String(own.book_id), owner: own.role === 'owner', system: false, user: String(u.id) } : null;
}

// ── Helpers ────────────────────────────────────────────────────────────────────────────────────────────

export interface Ctx { p: Row; at: string; book: string; today: string }
export async function context(book: string): Promise<Ctx> {
  const [s] = await db(`home_snapshot?book_id=eq.${book}&select=payload&limit=1`);
  if (!s) throw new Error(`no Home data for book ${book}`);
  return { p: s.payload, at: String(s.payload.built_at), book, today: String(s.payload.today) };
}
const r2 = (x: number) => Math.round(x * 100) / 100;
const num = (x: unknown) => (x == null || x === '' || !Number.isFinite(Number(x)) ? null : Number(x));
const T = (t?: unknown) => (t ? String(t).trim().toUpperCase() : undefined);
const daysTo = (iso: string, from: string) => Math.round((Date.parse(iso + 'T12:00:00Z') - Date.parse(from + 'T12:00:00Z')) / 864e5);
const addDays = (iso: string, n: number) => new Date(Date.parse(iso + 'T12:00:00Z') + n * 864e5).toISOString().slice(0, 10);
const tagOf = (t: string | undefined, name: string) => (t ? `${t} · ${name}` : name);
const sunny = (c: Ctx) => ({ kind: 'sunny', at: c.at });
const card = (type: string, tag: string, source: Row, data: unknown) => ({ type, tag, source, data });
const spotOf = (c: Ctx, t: string) =>
  num(c.p.portfolio?.find((x: Row) => x.ticker === t)?.spot) ?? num(c.p.legs?.find((l: Row) => l.ticker === t)?.underlying) ?? NaN;
const nameRow = (c: Ctx, t: string): Row | undefined => c.p.writes?.names?.find((n: Row) => n.ticker === t);
const bookNames = (c: Ctx) => Object.keys(c.p.plan ?? {}).sort();
function need(t: string | undefined, what: string): string {
  if (!t) throw new Error(`${what} needs a ticker`);
  return t;
}

/** Bought legs: a put is insurance, a call marked `up` is a hedge call, any other call is a LEAPS. */
const kindOf = (l: Row) => (l.type === 'put' ? 'insurance' : l.up ? 'hedge' : 'leaps');

function soldRows(c: Ctx, t?: string) {
  return (c.p.legs as Row[]).filter((l) => l.side === 'sold' && l.expiry >= c.today && (!t || l.ticker === t)).map((l) => {
    const s = spotOf(c, l.ticker), call = l.type === 'call', mark = num(l.mark);
    const itm = (call ? Math.max(0, s - l.strike) : Math.max(0, l.strike - s)) * l.n * 100;
    return {
      ticker: l.ticker, type: l.type, n: l.n, strike: l.strike, expiry: l.expiry, days_left: daysTo(l.expiry, c.today),
      sold_at: r2(l.avg), mark: mark == null ? null : r2(mark), price: r2(s),
      captured_pct: mark == null || !l.avg ? null : Math.round((1 - mark / l.avg) * 100),
      in_the_money_usd: Math.round(itm), premium_usd: Math.round(l.avg * l.n * 100),
      left_to_earn_usd: mark == null ? null : Math.round(mark * l.n * 100), delta: num(l.delta) == null ? null : r2(l.delta),
    };
  });
}

function boughtRows(c: Ctx, t?: string) {
  return (c.p.legs as Row[]).filter((l) => l.side === 'bought' && l.expiry >= c.today && (!t || l.ticker === t)).map((l) => {
    const s = spotOf(c, l.ticker), mark = num(l.mark) ?? num(l.avg) ?? 0;
    const intrinsic = l.type === 'call' ? Math.max(0, s - l.strike) : Math.max(0, l.strike - s);
    return {
      ticker: l.ticker, kind: kindOf(l), type: l.type, n: l.n, strike: l.strike, expiry: l.expiry, days_left: daysTo(l.expiry, c.today),
      paid: r2(l.avg), mark: r2(mark), price: r2(s), change_pct: l.avg ? Math.round((mark / l.avg - 1) * 100) : null,
      value_usd: Math.round(mark * l.n * 100), cost_usd: Math.round(l.avg * l.n * 100),
      time_value_usd: Math.round(Math.max(0, mark - intrinsic) * l.n * 100), delta: num(l.delta) == null ? null : r2(l.delta),
    };
  });
}

/** The week's orders for a name, from the same plan To do reads. A sale marked placed on the phone is not
    known here (it lives on the phone until IBKR shows the fill). */
function ordersFor(c: Ctx, t: string): Row[] {
  const p = c.p.plan?.[t];
  if (!p) return [];
  const out: Row[] = [], wk = String(p.week), sell = p.sell ?? {};
  if (p.earnings) out.push({ kind: 'calls', status: 'skipped', title: 'No calls this week', why: 'Earnings land before the expiry.' });
  else if (sell.done && sell.sold < sell.n) out.push({ kind: 'calls', status: 'done', title: `${sell.sold} of ${sell.n} sold`, why: 'Done for this week.' });
  else if (sell.left > 0) out.push({ kind: 'calls', status: 'todo', title: `Sell ${sell.left} ${wk} calls`,
    ways: (sell.ways ?? []).map((w: Row) => ({ way: w.id, legs: w.legs, premium_usd: w.premium, hedge_calls_needed: w.hedge })) });
  else if (sell.sold > 0) out.push({ kind: 'calls', status: 'done', title: `${sell.sold} of ${sell.n} sold` });
  const h = p.hedge;
  if (h) {
    const sizes = new Set((sell.ways ?? []).map((w: Row) => w.hedge).filter((x: unknown) => x != null));
    if (h.add > 0) out.push({ kind: 'hedge', status: sell.left > 0 && !p.earnings && sizes.size > 1 ? 'waiting' : 'todo',
      title: `Buy ${h.add} ${h.exp} ${h.k} calls`, cost_usd: Math.round(h.cost), strike_from: h.pick === 'sd' ? `nearest +${h.target?.sd} SD` : '1st call wall',
      wall_label: h.label ?? null });
    else if (h.held > 0) out.push({ kind: 'hedge', status: 'done', title: `Covered · ${h.held} ${h.exp} calls` });
  }
  const i = p.insurance;
  if (i && i.add > 0) out.push({ kind: 'insurance', status: 'todo', title: `Buy ${i.add} ${i.exp} ${i.k} puts`, cost_usd: i.cost,
    weeks_of_premium: i.weeks, strike_from: i.pick === 'sd' ? 'nearest 1.5 SD down' : '1st put wall' });
  const pu = p.puts ?? {};
  if (pu.n > 0) out.push({ kind: 'puts', status: 'todo', title: `Sell ${pu.n} ${wk} ${pu.k} puts` });
  else if ((pu.why ?? []).length) out.push({ kind: 'puts', status: 'paused', title: 'No puts this week', why: pu.why });
  return out;
}

/* sunny-home's Δ Γ series (ser2): [move %, bought, sold, net] in SHARES of delta, then the cost of the move and the
   P&L of the move in dollars (every leg re-priced at once, plus any shares). The cost column is left out: read
   alone, it was mistaken for the P&L (27 Oct 2026). */
const DG_UNITS = 'Delta figures are in shares: how many shares the position moves like, not dollars. pnl_usd is the ' +
  'dollar P&L if the price moves by move_pct, every option re-priced.';
const rowAt = (rows: Row[], m: number) => rows.reduce((b: Row | null, r) => (!b || Math.abs(r.move_pct - m) < Math.abs(b.move_pct - m) ? r : b), null);
function dgFor(c: Ctx, t: string) {
  const dg = nameRow(c, t)?.dg;
  if (!dg) return null;
  const rows = ((dg.ser2 ?? []) as number[][]).map((r) => ({ move_pct: r[0], bought_delta_shares: r[1], sold_delta_shares: r[2],
    net_delta_shares: r[3], pnl_usd: r[5] }));
  return { units: DG_UNITS, price: dg.px, delta_turns_thin_above_pct: dg.thin25 ?? null, now: rowAt(rows, 0), rows };
}

/** Research Nik saved (research_numbers, checked by him): the latest date per figure, as plain figures. A newer
    report replaces only the figures it has (28 Oct 2026): the Pro Report's fair value does not wipe the model range
    an earlier screenshot gave. */
async function researchFigures(t: string, topics: string[]) {
  const rows = await db(`research_numbers?ticker=eq.${t}&topic=in.(${topics.join(',')})&checked_at=not.is.null` +
    '&select=topic,metric,label,period,value,value_text,unit,source,asof&order=asof.desc,topic.asc,metric.asc,period.desc');
  const latest = new Map<string, string>(), key = (r: Row) => `${r.topic}|${r.metric}`;
  for (const r of rows) if (!latest.has(key(r))) latest.set(key(r), String(r.asof));
  const keep = rows.filter((r) => String(r.asof) === latest.get(key(r)));
  if (!keep.length) throw new Error(`no research saved for ${t} yet (${topics.join(', ')})`);
  const src = { kind: 'research', source: [...new Set(keep.map((r) => String(r.source)))].join(', '),
                asof: [...new Set(keep.map((r) => String(r.asof)))].sort().at(-1) };
  const fig = (r: Row) => ({ label: r.label, ...(r.period ? { period: r.period } : {}), value: r.value == null ? null : Number(r.value),
    text: r.value_text ?? null, unit: r.unit ?? null });
  return { rows: keep, src, fig };
}
const RESEARCH_UNITS = 'Research Nik saved, with its source and date: context only, never for To do, strikes or hedges. ' +
  'unit usd is dollars (revenue and market cap in full dollars), pct is percent, x is a multiple.';

// ── The menu ───────────────────────────────────────────────────────────────────────────────────────────

const TICKER = { ticker: { type: 'string', description: 'A ticker, for example BABA' } };
export const MENU: Row[] = [
  { name: 'account', shows: "Account: value, today's move, realized and unrealized, time value left in what is sold, margin, interest, fees", args: {} },
  { name: 'movers', shows: "Today's moves: each name in the book, SPY, QQQ, IWM and the futures", args: {} },
  { name: 'position', shows: 'Position summary for one name: price, what is sold and bought, the week plan, delta, next earnings, who trades it', args: TICKER, required: ['ticker'] },
  { name: 'sold', shows: 'Sold options with captured %, days left and how far in the money; one name or all', args: { ...TICKER,
      filter: { type: 'string', enum: ['all', 'in_the_money', 'captured'], description: 'in_the_money: only those in the money; captured: only those at or past min_captured' },
      min_captured: { type: 'number', description: 'Captured % threshold for filter captured, default 80' } } },
  { name: 'bought', shows: 'Bought options (LEAPS, hedge calls, insurance puts) with delta, value, time value and days left; one name or all', args: { ...TICKER,
      kind: { type: 'string', enum: ['all', 'leaps', 'hedge', 'insurance'] } } },
  { name: 'todo', shows: "This week's orders: the call sale, hedge calls, insurance puts, weekly puts; one name or all", args: TICKER },
  { name: 'delta_gamma', shows: 'Delta and the P&L of a move from -10% to +10%; one name, or the whole book', args: { ...TICKER,
      move_pct: { type: 'number', description: 'A move to read, for example -10' } } },
  { name: 'gamma', shows: "Gamma ladder for one name: walls with the tape's labels and confidence, the flip, the regime, the priced move. Read this first for walls; it covers the book names and TSLA", args: { ...TICKER,
      view: { type: 'string', description: "'weeklies' (default), 'all', or an expiry date like 2027-01-15" } }, required: ['ticker'] },
  { name: 'walls_live', shows: 'Walls worked out now from live option prices, for any ticker and expiry (open interest only, no tape labels). Only when gamma has no view for that ticker or expiry', args: { ...TICKER,
      expiry: { type: 'string', description: 'An expiry date like 2027-01-15; leave out for the next 45 days' } }, required: ['ticker'] },
  { name: 'roll', shows: "Rolling one name's calls to next Friday, as delta in shares: the calls sold now and what they could be at +1.5 SD by Thursday, what is bought, what insurance takes away, the net, the delta still needed, and each month's call walls (Ceiling, Accelerator) with what one call adds and how many would cover it. Read this for rolling, or how much delta a name needs", args: TICKER, required: ['ticker'] },
  { name: 'hedges', shows: 'Hedge calls and insurance puts: held, needed, strike, cost; one name or a list of the names that need some', args: TICKER },
  { name: 'hedge_rungs', shows: 'Every hedge call and insurance put with days left; rolls are due at 45 days left', args: {} },
  { name: 'put_gates', shows: 'Whether weekly puts can sell: above the 50-day, a Floor below, no Accelerator between; one name or all', args: TICKER },
  { name: 'yield', shows: 'Yield: premium sold, closing cost, hedges and net on the LEAPS base, for a week or a month', args: {
      period: { type: 'string', enum: ['week', 'month'] },
      at: { type: 'string', description: 'A date in the week, or a month like 2026-10; default now' } } },
  { name: 'payback', shows: 'Payback: what the book has made against what the LEAPS cost, and the pace', args: {} },
  { name: 'events', shows: 'Earnings and market holidays coming up; one name or all', args: { ...TICKER,
      days: { type: 'number', description: 'How many days ahead, default 14' } } },
  { name: 'who_is_trading', shows: 'Flow profile for one name: Institution-heavy or Retail-heavy, with the five inputs', args: TICKER, required: ['ticker'] },
  { name: 'what_changed', shows: 'What changed across the names since the first read of the day, most pressing first', args: {} },
  { name: 'labels_held', shows: 'How well the Ceilings, Floors and Accelerators of one name held over the stored sessions', args: TICKER, required: ['ticker'] },
  { name: 'insights', shows: "One name's insights: the verdict and the points that help, need watching or hurt", args: TICKER, required: ['ticker'] },
  { name: 'fundamentals', shows: 'Research Nik saved for one name (Investing Pro and others): P/E, revenue, net income, dividend, payout, and how it compares with peers and its sector', args: TICKER, required: ['ticker'] },
  { name: 'analyst_targets', shows: "Research Nik saved for one name: analysts' target and range, Investing Pro fair value and its models, the 52-week range, and analysts' EPS forecasts for the next three years", args: TICKER, required: ['ticker'] },
  { name: 'earnings_history', shows: 'Research Nik saved for one name: last reported earnings with surprises, and how the price moved the day after each report', args: TICKER, required: ['ticker'] },
  { name: 'research_notes', shows: 'Writing Nik saved for one name: analyst notes, management news, his own notes, latest first', args: TICKER, required: ['ticker'] },
];

// ── The lookups ────────────────────────────────────────────────────────────────────────────────────────

export async function lookup(name: string, a: Row, c: Ctx, owner: boolean): Promise<Row> {
  const t = T(a.ticker);
  switch (name) {
    case 'account': {
      const x = c.p.account ?? {};
      /* Realized, interest and fees always name their period: Home's chart shows them for the range picked
         (1W, 1M, YTD, All), so a bare "realized" would not match the figure Nik sees there. */
      const per = (b: Row | undefined) => (b ? { from: b.from, realized: b.realized, interest: b.interest, fees: b.commission } : null);
      return card('account', 'Account', sunny(c), {
        value: x.value, today: x.today ? { amount: x.today.amount, pct: x.today.pct } : null, unrealized: x.unrealized,
        time_value_sold: x.time_value_sold, margin: x.margin, since_start: per(x.book), this_month: per(x.month),
        note: "Home's chart shows realized for the range picked (1W, 1M, YTD, All); name the period when quoting it." });
    }
    case 'movers':
      return card('movers', 'Movers', sunny(c), {
        names: (c.p.portfolio ?? []).map((x: Row) => ({ ticker: x.ticker, price: r2(x.spot), day_pct: x.ranges?.d ?? null, week_pct: x.ranges?.w1 ?? null })),
        indices: (c.p.indices ?? []).map((x: Row) => ({ symbol: x.symbol, price: x.price, change_pct: x.change_pct, state: x.state })),
        futures: (c.p.futures ?? []).map((x: Row) => ({ symbol: x.symbol, price: x.price, pill: x.pill })) });
    case 'position': {
      const k = need(t, 'position'), n = nameRow(c, k), p = c.p.plan?.[k], pf = c.p.portfolio?.find((x: Row) => x.ticker === k);
      if (!n && !p && !pf) throw new Error(`${k} is not in the book`);
      return card('position', tagOf(k, 'Position'), sunny(c), {
        ticker: k, price: r2(spotOf(c, k)), day_pct: pf?.ranges?.d ?? null, strategy: c.p.strategies?.[k] ?? null,
        next_earnings: n?.next_earnings ?? null, flow: c.p.flow_profile?.[k]?.profile ?? null,
        sold: soldRows(c, k), bought: boughtRows(c, k), orders: ordersFor(c, k),
        delta: c.p.risk?.delta?.by?.find((x: Row) => x.ticker === k) ?? null });
    }
    case 'sold': {
      let rows = soldRows(c, t);
      if (a.filter === 'in_the_money') rows = rows.filter((r) => r.in_the_money_usd > 0);
      if (a.filter === 'captured') rows = rows.filter((r) => (r.captured_pct ?? -1) >= (num(a.min_captured) ?? 80));
      rows.sort((x, y) => (y.captured_pct ?? -999) - (x.captured_pct ?? -999));
      return card('sold', tagOf(t, 'Sold'), sunny(c), { filter: a.filter ?? 'all', rows });
    }
    case 'bought': {
      const rows = boughtRows(c, t).filter((r) => !a.kind || a.kind === 'all' || r.kind === a.kind);
      return card('bought', tagOf(t, 'Bought'), sunny(c), { rows });
    }
    case 'todo': {
      const names = t ? [t] : bookNames(c);
      const by = names.map((k) => ({ ticker: k, week: c.p.plan?.[k]?.week ?? null, orders: ordersFor(c, k) }));
      return card('todo', tagOf(t, 'To do'), sunny(c), {
        names: by, to_do: by.reduce((s, x) => s + x.orders.filter((o) => o.status === 'todo' || o.status === 'waiting').length, 0),
        note: 'A sale marked placed on the phone shows here only once IBKR shows the fill.' });
    }
    case 'delta_gamma': {
      if (t) {
        const d = dgFor(c, t);
        if (!d) throw new Error(`no delta and gamma for ${t}`);
        const m = num(a.move_pct);
        return card('delta_gamma', tagOf(t, 'Δ Γ'), sunny(c), { ...d, at: m == null ? null : rowAt(d.rows, m) });
      }
      // The book: deltas in shares, and the dollar P&L of a move with every name moving by the same %.
      const x = c.p.risk?.delta ?? {};
      const per = bookNames(c).map((k) => ({ ticker: k, dg: dgFor(c, k) })).filter((n) => n.dg);
      const pnl = (m: number) => per.map((n) => ({ ticker: n.ticker, pnl_usd: rowAt(n.dg!.rows, m)?.pnl_usd ?? 0 }));
      const sum = (m: number) => pnl(m).reduce((s, r) => s + Number(r.pnl_usd), 0);
      const m = num(a.move_pct);
      return card('delta_gamma', 'Δ Γ', sunny(c), { units: DG_UNITS,
        net_delta_shares: x.net, long_call_delta_shares: x.long, sold_call_delta_shares: x.sold_calls, sold_put_delta_shares: x.sold_puts,
        insurance_put_delta_shares: x.hedge, net_as_pct_of_leaps_shares: x.pct_now,
        pnl_if_every_name_moves: [-10, -5, -2, 2, 5, 10].map((mv) => ({ move_pct: mv, pnl_usd: Math.round(sum(mv)) })),
        at: m == null ? null : { move_pct: m, pnl_usd: Math.round(sum(m)), by: pnl(m) },
        by: (x.by ?? []).map((r: Row) => ({ ticker: r.ticker, net_delta_shares: r.net, long_delta_shares: r.long, sold_delta_shares: r.sold,
          insurance_delta_shares: r.hedge, alert: r.alert ?? null })) });
    }
    case 'gamma': {
      const k = need(t, 'gamma'), v = String(a.view ?? 'weeklies');
      const [g] = await db(`gamma_view_day?ticker=eq.${k}&view=eq.${encodeURIComponent(v)}&select=day,built_at,data&order=day.desc&limit=1`);
      if (!g) throw new Error(`no ${v} gamma view for ${k}; walls_live works for any ticker`);
      const d = g.data ?? {};
      return card('gamma', tagOf(k, 'Gamma'), { kind: 'sunny', at: g.built_at ?? c.at, day: g.day }, {
        view: v, day: g.day, price: d.spot, regime: d.regime ?? null, flip: d.flip ?? null, coverage: d.coverage ?? null,
        priced: d.priced ?? null, drift: d.drift ?? null, expiries: d.expiries ?? null,
        walls: ((d.walls ?? []) as Row[]).map((w) => ({ k: w.k, side: w.side, rank: w.rank, label: w.label, confidence: w.conf ?? null,
          gex: w.gex ?? null, days_held: w.held ?? null })) });
    }
    case 'walls_live': {
      const k = need(t, 'walls_live');
      const body: Row = { ticker: k, save: false, ...(a.expiry ? { expiries: [String(a.expiry)] } : { days: 45 }) };
      const r = await fetch(`${SB_URL}/functions/v1/gex-walls`, { method: 'POST',
        headers: { Authorization: `Bearer ${SB_KEY}`, 'Content-Type': 'application/json' }, body: JSON.stringify(body),
        signal: AbortSignal.timeout(90_000) });
      const j = await r.json().catch(() => ({ ok: false, error: `HTTP ${r.status}` }));
      if (!j.ok) throw new Error(`walls for ${k}: ${String(j.error ?? 'failed').slice(0, 200)}`);
      return card('walls_live', tagOf(k, 'Walls'), { kind: 'live', at: new Date().toISOString(), note: 'OI only' }, {
        price: j.spot, flip: j.flip, expiries: j.expiries, call_walls: j.call_wall, put_walls: j.put_wall, strikes: j.strikes });
    }
    case 'roll': {
      /* sunny-home's plan.story (28 Oct 2026): the roll to next Friday on the hedge rule's terms. Signed deltas
         in shares; the story words the sign (short, takes away). */
      const k = need(t, 'roll'), s = c.p.plan?.[k]?.story;
      if (!s) throw new Error(`no roll for ${k}`);
      const leg = (g: Row | null) => (g ? { contracts: g.n, delta_now: g.now, delta_at_target: g.at } : null);
      const bought = [s.leaps, s.hedge_calls].filter(Boolean) as Row[];
      const sc = s.sold_calls;
      return card('roll', tagOf(k, 'Roll'), sunny(c), {
        units: 'Delta in shares. Negative takes delta away (calls sold, insurance puts). delta_now is today at the price; ' +
          'delta_at_target is at the target price as of Thursday\'s close.',
        ticker: k, price: s.spot, rolls_to_expiry: s.week, thursday: s.by, earnings_week: s.earnings,
        target: { price: s.target.px, sd: s.target.sd, move_pct: s.target.pct,
          accelerator_above_strike: s.accel ? s.accel.k : null },
        calls_sold: { contracts: sc.n, already_sold: sc.held, to_sell: sc.sale?.n ?? 0, strike: sc.sale?.k ?? null,
          delta_now: sc.now, delta_at_target: sc.at },
        puts_sold: leg(s.sold_puts),
        bought: { leaps: leg(s.leaps), hedge_calls: leg(s.hedge_calls), shares: s.shares,
          delta_now: bought.reduce((a, g) => a + g.now, 0) + (s.shares ?? 0), delta_at_target: bought.reduce((a, g) => a + g.at, 0) + (s.shares ?? 0) },
        insurance_puts: leg(s.insurance),
        net: { delta_now: s.net.now, delta_at_target: s.net.at },
        lowest_on_the_way: { price: s.low.px, delta: s.low.d },
        delta_needed: s.need,
        months: (s.months as Row[]).map((m) => ({ expiry: m.exp, days_left: m.days, open_interest_only: m.oi_only,
          hedge_calls_held_here: m.held.map((h: Row) => ({ strike: h.k, contracts: h.n })),
          walls: (m.walls as Row[]).map((w) => ({ strike: w.k, label: w.label, confidence: w.conf, call_price: w.mid,
            delta_per_call_now: w.d_now, delta_per_call_at_low: w.d_low, delta_per_call_at_target: w.d_at,
            calls_to_cover: w.n, cost_usd: w.cost })) })),
        shares: { to_cover: s.by_shares.n, cost_usd: s.by_shares.cost } });
    }
    case 'hedges': {
      const names = t ? [t] : bookNames(c);
      const rows = names.map((k) => {
        const p = c.p.plan?.[k] ?? {}, h = p.hedge, i = p.insurance;
        // What is held is listed with its own strikes: a held count beside the strike to buy read as "15 held at 40".
        const held = (kind: string) => boughtRows(c, k).filter((r) => r.kind === kind).map((r) => ({ strike: r.strike, expiry: r.expiry, contracts: r.n }));
        return { ticker: k,
          calls: h ? { expiry: h.exp, strike_to_buy: h.k, held: held('hedge'), add: h.add, cost_usd: Math.round(h.cost), label: h.label ?? null,
            strike_from: h.pick === 'sd' ? 'nearest SD' : '1st call wall', target: h.target ?? null, lowest_delta: h.low ?? null,
            lowest_after: h.lowAfter ?? null } : null,
          puts: i ? { expiry: i.exp, strike_to_buy: i.k, held: held('insurance'), add: i.add, ratio: i.ratio, cost_usd: i.cost, weeks_of_premium: i.weeks,
            strike_from: i.pick === 'sd' ? 'nearest SD' : '1st put wall' } : null };
      }).filter((r) => t || (r.calls?.add ?? 0) > 0 || (r.puts?.add ?? 0) > 0);
      return card('hedges', tagOf(t, t ? 'Hedges' : 'Hedge list'), sunny(c), { rows });
    }
    case 'hedge_rungs': {
      const rows = boughtRows(c).filter((r) => r.kind !== 'leaps').map((r) => ({ ...r, roll_due: r.days_left <= 45,
        roll_on: addDays(r.expiry, -45) })).sort((x, y) => x.days_left - y.days_left);
      return card('hedge_rungs', 'Hedge rungs', sunny(c), { roll_at_days_left: 45, rows });
    }
    case 'put_gates': {
      const names = t ? [t] : bookNames(c);
      return card('put_gates', tagOf(t, 'Put gates'), sunny(c), { rows: names.map((k) => {
        const pu = c.p.plan?.[k]?.puts ?? {}, s = spotOf(c, k);
        return { ticker: k, price: r2(s), fifty_day: pu.s50 ?? null, above_fifty_day: pu.s50 != null ? s > pu.s50 : null,
          wall: pu.wall ?? null, can_sell: pu.n ?? 0, strike: pu.k ?? null, cap: pu.cap ?? null, reasons: pu.why ?? [] };
      }) });
    }
    case 'yield': {
      const rows = ((c.p.yield ?? []) as Row[]).slice().sort((x, y) => String(x.week).localeCompare(String(y.week)));
      const net = (r: Row) => r.calls_sold + r.puts_sold - r.calls_back - r.puts_back - (r.hedge ?? 0);
      const shape = (r: Row) => ({ week: r.week, friday: r.fri, calls_sold: r.calls_sold, calls_closing: r.calls_back, puts_sold: r.puts_sold,
        puts_closing: r.puts_back, hedges: r.hedge ?? 0, net: net(r), leaps_base: r.leaps, pct: r.leaps ? r2(net(r) / r.leaps * 100) : null });
      if (a.period === 'month') {
        const m = /^\d{4}-\d{2}$/.test(String(a.at ?? '')) ? String(a.at) : c.today.slice(0, 7);
        const ms = rows.filter((r) => String(r.month) === m);
        const sum = (k: string) => ms.reduce((s, r) => s + Number(r[k] ?? 0), 0);
        const base = ms.at(-1)?.leaps ?? null, n = sum('calls_sold') + sum('puts_sold') - sum('calls_back') - sum('puts_back') - sum('hedge');
        return card('yield', `Yield · ${m}`, sunny(c), { period: 'month', month: m, calls_sold: sum('calls_sold'), calls_closing: sum('calls_back'),
          puts_sold: sum('puts_sold'), puts_closing: sum('puts_back'), hedges: sum('hedge'), net: n, leaps_base: base,
          pct: base ? r2(n / base * 100) : null, weeks: ms.map(shape) });
      }
      const d = /^\d{4}-\d{2}-\d{2}$/.test(String(a.at ?? '')) ? String(a.at) : c.today;
      const w = rows.find((r) => String(r.week) <= d && d <= addDays(String(r.week), 6)) ?? rows.at(-1);
      return card('yield', 'Yield · week', sunny(c), { period: 'week', ...(w ? shape(w) : {}), recent: rows.slice(-6).map(shape) });
    }
    case 'payback': {
      const x = c.p.payback ?? {};
      return card('payback', 'Payback', sunny(c), { leaps_base: x.base, made: x.made, settled: x.settled, open: x.open, closing: x.closing,
        hedges: x.hedges, pace_since_start_per_week: x.pace_start, pace_last_4_weeks_per_week: x.pace_recent, leaps_value: x.leaps_value });
    }
    case 'events': {
      const days = num(a.days) ?? 14, end = addDays(c.today, days);
      const earn = ((c.p.writes?.names ?? []) as Row[]).filter((n) => n.next_earnings?.date && (!t || n.ticker === t))
        .map((n) => ({ kind: 'earnings', ticker: n.ticker, date: n.next_earnings.date, time: n.next_earnings.time ?? null }))
        .filter((e) => t || (e.date >= c.today && e.date <= end));
      const market = t ? [] : ((c.p.calendar ?? []) as Row[]).filter((e) => e.date >= c.today && e.date <= end)
        .map((e) => ({ kind: e.kind, name: e.name, date: e.date, closes: e.closes ?? null }));
      return card('events', tagOf(t, 'Events'), sunny(c), { days, events: [...earn, ...market].sort((x, y) => x.date.localeCompare(y.date)) });
    }
    case 'who_is_trading': {
      const k = need(t, 'who_is_trading'), f = c.p.flow_profile?.[k];
      if (!f) throw new Error(`no flow profile for ${k}`);
      return card('who_is_trading', tagOf(k, 'Who is trading'), { kind: 'sunny', at: c.at, asof: f.asof }, f);
    }
    case 'what_changed':
      return card('what_changed', 'What changed', sunny(c), c.p.insights_all ?? {});
    case 'labels_held': {
      const k = need(t, 'labels_held');
      const [g] = await db(`gamma_view_day?ticker=eq.${k}&view=eq.weeklies&data->track=not.is.null&select=day,built_at,track:data->track&order=day.desc&limit=1`);
      if (!g) throw new Error(`no track record for ${k} yet`);
      return card('labels_held', tagOf(k, 'How labels held'), { kind: 'sunny', at: g.built_at ?? c.at, day: g.day }, g.track);
    }
    case 'fundamentals': {
      const k = need(t, 'fundamentals'), { rows, src, fig } = await researchFigures(k, ['valuation', 'dividend', 'peers']);
      const peers: Row = {};
      for (const r of rows.filter((x) => x.topic === 'peers')) (peers[r.label] ??= {})[r.period] = r.value_text ?? Number(r.value);
      return card('fundamentals', tagOf(k, 'Fundamentals'), src, { units: RESEARCH_UNITS,
        valuation: rows.filter((x) => x.topic === 'valuation').map(fig), dividend: rows.filter((x) => x.topic === 'dividend').map(fig),
        against_peers_and_sector: peers });
    }
    case 'analyst_targets': {
      const k = need(t, 'analyst_targets'), { rows, src, fig } = await researchFigures(k, ['fair_value', 'estimates']);
      return card('analyst_targets', tagOf(k, 'Analyst targets'), src, { units: RESEARCH_UNITS,
        figures: rows.filter((x) => x.topic === 'fair_value').map(fig), eps_forecasts: rows.filter((x) => x.topic === 'estimates').map(fig) });
    }
    case 'earnings_history': {
      const k = need(t, 'earnings_history'), { rows, src, fig } = await researchFigures(k, ['earnings', 'earnings_reactions']);
      const by = new Map<string, Row>();
      for (const r of rows.filter((x) => x.topic === 'earnings_reactions')) (by.get(r.period) ?? by.set(r.period, { report: r.period }).get(r.period)!)[r.metric] = Number(r.value);
      const reactions = [...by.values()].sort((x, y) => String(y.report).localeCompare(String(x.report)));
      const moves = reactions.map((r) => Number(r.change_pct)).filter(Number.isFinite);
      return card('earnings_history', tagOf(k, 'Earnings history'), src, { units: RESEARCH_UNITS,
        last_reported: rows.filter((x) => x.topic === 'earnings').map(fig), reactions,
        summary: moves.length ? { reports: moves.length, up: moves.filter((m) => m > 0).length, down: moves.filter((m) => m < 0).length,
          average_move_pct: Math.round(moves.reduce((s2, m) => s2 + Math.abs(m), 0) / moves.length * 100) / 100,
          biggest_drop_pct: Math.min(...moves), biggest_rise_pct: Math.max(...moves) } : null });
    }
    case 'research_notes': {
      const k = need(t, 'research_notes');
      const notes = await db(`research_notes?ticker=eq.${k}&checked_at=not.is.null&select=asof,source,title,body&order=asof.desc&limit=10`);
      if (!notes.length) throw new Error(`no notes saved for ${k} yet`);
      return card('research_notes', tagOf(k, 'Research notes'), { kind: 'research', source: notes[0].source, asof: notes[0].asof }, { notes });
    }
    case 'insights': {
      const k = need(t, 'insights'), v2 = nameRow(c, k)?.insights?.v2;
      if (!v2) throw new Error(`no insights for ${k}`);
      return card('insights', tagOf(k, 'Insights'), sunny(c), v2);
    }
  }
  throw new Error(`no lookup named ${name}`);
}

