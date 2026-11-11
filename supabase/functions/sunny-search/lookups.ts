/**
 * The search card menu's lookups (Sunny search, Nik 27 Oct 2026): one per card, each returning its card's data
 * on its own as { type, tag, source: { kind, at }, data }. Reads what Sunny already works out (home_snapshot,
 * gamma_view_day) and, for walls on any ticker, asks gex-walls live. Never writes, never trades.
 */
import { money } from './slots.ts';

export const SB_URL = Deno.env.get('SUPABASE_URL')!;
export const SB_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
export type Row = Record<string, any>;

export async function db(path: string): Promise<Row[]> {
  const r = await fetch(`${SB_URL}/rest/v1/${path}`, { headers: { apikey: SB_KEY, Authorization: `Bearer ${SB_KEY}` } });
  if (!r.ok) throw new Error(`${path.split('?')[0]}: HTTP ${r.status}`);
  return await r.json();
}

/** Who is asking and which book they may see: the scheduler and the service key read Nik's book (S). */
export async function caller(req: Request): Promise<{ book: string; owner: boolean; system: boolean; user?: string;
  books?: { book: string; owner: boolean }[] } | null> {
  const cron = Deno.env.get('CRON_SECRET');
  if (cron && (req.headers.get('x-cron-key') === cron || req.headers.get('x-admin-key') === cron)) return { book: 'S', owner: true, system: true };
  const auth = req.headers.get('authorization') ?? '';
  if (auth === `Bearer ${SB_KEY}`) return { book: 'S', owner: true, system: true };
  if (!auth.startsWith('Bearer ')) return null;
  const r = await fetch(`${SB_URL}/auth/v1/user`, { headers: { apikey: Deno.env.get('SUPABASE_ANON_KEY') ?? '', Authorization: auth } });
  if (!r.ok) { await r.body?.cancel(); return null; }
  const u = await r.json();
  const m = await db(`book_members?user_id=eq.${u.id}&select=book_id,role&order=book_id.asc`);
  /* Nik owns his book S and his cousin's N (8 Nov 2026): Search reads S, as the app opens on S, never whichever row
     comes first; a request may name another book the caller belongs to (`body.book`, checked in index.ts). */
  const owned = m.filter((x) => x.role === 'owner');
  const own = owned.find((x) => x.book_id === 'S') ?? owned[0] ?? m[0];
  return own ? { book: String(own.book_id), owner: own.role === 'owner', system: false, user: String(u.id),
    books: m.map((x) => ({ book: String(x.book_id), owner: x.role === 'owner' })) } : null;
}

// ── Helpers ────────────────────────────────────────────────────────────────────────────────────────────

/** draws: the newer cards the phone says it can draw (build 32 on); an older build gets the sentence without them. */
export interface Ctx { p: Row; at: string; book: string; today: string; draws?: string[] }
/* ⚠ TO DO IS FOR OWNERS ONLY (31 Oct 2026). sunny-home keeps what to trade in `home_todo` (forOwners there);
   an owner's Home is home_snapshot with it laid back over, a viewer's is home_snapshot alone. This reads with
   the service key, so `owner` (caller's book_members role) is the gate, not RLS. */
export async function context(book: string, owner = false): Promise<Ctx> {
  const [[s], [o]] = await Promise.all([db(`home_snapshot?book_id=eq.${book}&select=payload&limit=1`),
    owner ? db(`home_todo?book_id=eq.${book}&select=payload&limit=1`) : Promise.resolve([] as Row[])]);
  if (!s) throw new Error(`no Home data for book ${book}`);
  const p = o ? merged(s.payload, o.payload) : s.payload;
  return { p, at: String(p.built_at), book, today: String(p.today) };
}
/* sunny-home's owner part laid over the snapshot: objects merge, anything else replaces, names by ticker
   (the same rule as the app's HomeStore.layOver). */
function layOver(a: unknown, b: unknown): unknown {
  if (!a || !b || typeof a !== 'object' || typeof b !== 'object' || Array.isArray(a) || Array.isArray(b)) return b;
  const out: Row = { ...(a as Row) };
  for (const [k, v] of Object.entries(b as Row)) out[k] = k in out ? layOver(out[k], v) : v;
  return out;
}
function merged(open: Row, owner: Row): Row {
  const p = layOver(open, owner.top ?? {}) as Row, names = (owner.names ?? {}) as Row;
  if (p.writes?.names) p.writes = { ...p.writes, names: (p.writes.names as Row[]).map((n) => (names[n.ticker] ? layOver(n, names[n.ticker]) : n)) };
  return p;
}
/** The lookups that say what to trade: an owner's only (a viewer is never offered them). */
export const OWNER_ONLY = new Set(['todo', 'roll', 'hedges', 'put_gates']);
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
/** The book's names: the plan's for an owner, each open name's strategy for a viewer (the same names). */
/* Every name the book holds. `plan` lists only names with a write planned (NFLX and UBER on 8 Nov), so reading it first
   told the name page and the price chart that NKE, FIS, LULU and BABA were "not in the book" (fixed 8 Nov 2026). */
export const bookNames = (c: Ctx) => [...new Set([...Object.keys(c.p.strategies ?? {}), ...Object.keys(c.p.plan ?? {}),
  ...((c.p.legs ?? []) as Row[]).map((l) => String(l.ticker))])].filter(Boolean).sort();
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
      // Worth more than sold has captured nothing (30 Oct 2026: NKE's 38 calls read "35% captured" in red when they were
      // worth 35% more than they were sold for); that figure goes under its own name.
      captured_pct: mark == null || !l.avg || mark > l.avg ? null : Math.round((1 - mark / l.avg) * 100),
      ...(mark != null && l.avg && mark > l.avg ? { worth_more_than_sold_pct: Math.round((mark / l.avg - 1) * 100) } : {}),
      in_the_money_usd: Math.round(itm), premium_usd: Math.round(l.avg * l.n * 100),
      left_to_earn_usd: mark == null ? null : Math.round(mark * l.n * 100), delta: num(l.delta) == null ? null : r2(l.delta),
      theta_per_day_usd: num(l.theta) == null ? null : Math.round(-Number(l.theta) * l.n * 100),
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
      theta_per_day_usd: num(l.theta) == null ? null : Math.round(Number(l.theta) * l.n * 100),
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

/* What if · Delta and Gamma (block 29, card 3): sunny-home's Δ Γ model widened to 15% either way for the slider
   (Nik, 30 Oct 2026: the slider stays at 15%). Every open leg at its own IV, an instant jump of m% from today's price
   with each leg's time left unchanged, held shares at one delta each; the P&L is every leg re-priced at once. Thin is
   net delta under 25% of TODAY's long delta, short under zero (Nik, 25 Oct 2026: a stable base, as Home reads it).
   The tip is the To do hedge, told as a story: one function sizes the hedge calls for Gamma, To do and Δ Γ (Nik, 25
   Oct 2026), so it is the plan's count, strike and cost, held to zero at the target by Thursday's close. */
const WI_UNITS = 'Delta figures are in shares. Every figure is an instant move from today: each option re-priced at its own IV ' +
  'with its time left unchanged, pnl_usd the P&L of that move. Thin is net delta under 25% of long_delta_today; short is ' +
  'under zero. hedge is the To do hedge: the calls that keep net delta at or above zero from today up to the target by ' +
  "Thursday's close.";
function bsDelta(S: number, K: number, years: number, v: number, cp: 'c' | 'p'): number {
  const d1 = (Math.log(S / K) + (RATE + v * v / 2) * years) / (v * Math.sqrt(years));
  return cp === 'c' ? ncdf(d1) : ncdf(d1) - 1;
}
/* Money in K and M (README 11.5, 8 Nov 2026): the design's money(), shared with the slots. */
const usdK = money;
const stateOf = (d: number, long: number) => (d < 0 ? 'Short' : d < 0.25 * long ? 'Thin' : 'On target');

function whatIf(c: Ctx, t: string, g: Row | undefined, ask: number | null) {
  const dg = nameRow(c, t)?.dg, spot = Number(dg?.px);
  if (!dg || !(spot > 0)) return null;
  const today = c.today, ivA = num(dg.sd) ? Number(dg.sd) / 100 / Math.sqrt(5 / 252) : 0.4;
  const yr = (e: string) => Math.max(0.5 / 365, (Date.parse(e) - Date.parse(today)) / 864e5 / 365);
  const lg = ((c.p.legs ?? []) as Row[]).filter((l) => l.ticker === t && l.expiry >= today && Number(l.n) > 0).map((l) => ({
    sg: l.side === 'sold' ? -1 : 1, cp: (l.type === 'call' ? 'c' : 'p') as 'c' | 'p', K: Number(l.strike), q: Number(l.n),
    T: yr(String(l.expiry)), v: (num(l.iv) ?? 0) > 0 ? Number(l.iv) : ivA }));
  const opt = (S: number, x: typeof lg[number]) => ({ p: bs(S, x.K, x.T * 365, x.v, x.cp), d: bsDelta(S, x.K, x.T, x.v, x.cp) });
  const o0 = lg.map((x) => opt(spot, x));
  // Shares held: the plan's count, or for a viewer (no plan) the share value over the price.
  const pf = c.p.portfolio?.find((x: Row) => x.ticker === t);
  const sh = Number(c.p.plan?.[t]?.story?.shares ?? 0) || (num(pf?.share_value) && spot > 0 ? Math.round(Number(pf.share_value) / spot) : 0);
  const at = (m: number) => {
    const S = spot * (1 + m / 100);
    let b = sh, s = 0, pl = sh * (S - spot);
    lg.forEach((x, i) => { const o1 = opt(S, x), dd = x.sg * x.q * 100 * o1.d; if (x.sg < 0) s += dd; else b += dd; pl += x.sg * x.q * 100 * (o1.p - o0[i].p); });
    return { b, s, d: b + s, pl };
  };
  const long = Math.round(at(0).b);
  if (!(long > 0)) return null;
  // [move %, bought, sold, net, P&L $] every 0.5% from 15% down to 15% up: the slider's steps.
  const rows = Array.from({ length: 61 }, (_, i) => { const m = -15 + i / 2, a = at(m); return [m, Math.round(a.b), Math.round(a.s), Math.round(a.d), Math.round(a.pl)]; });
  const sd = num(dg.sd);
  const mv = Math.max(-15, Math.min(15, Math.round((ask ?? 10) * 2) / 2));
  const read = (r: number[]) => ({ move_pct: r[0], price: r2(spot * (1 + r[0] / 100)), net_delta: r[3], bought_delta: r[1], sold_delta: r[2],
    pct_of_long: Math.round(Math.abs(r[3]) / long * 100), state: stateOf(r[3], long), pnl_usd: tens(r[4]),
    ...(sd && r[0] ? { sd_of_move: r2(Math.abs(r[0]) / sd) } : {}) });
  const first = (st: string, dir: 1 | -1) => rows.filter((r) => r[0] * dir > 0).sort((a, b) => Math.abs(a[0]) - Math.abs(b[0]))
    .find((r) => (st === 'Short' ? r[3] < 0 : r[3] < 0.25 * long))?.[0] ?? null;
  // The tip: the To do hedge, as a story (Nik, 30 Oct 2026, answer 9), never an order.
  const P = c.p.plan?.[t], h = P?.hedge;
  const byWd = P?.by ? new Date(String(P.by) + 'T12:00:00Z').toLocaleString('en-US', { weekday: 'long', timeZone: 'UTC' }) : 'Thursday';
  let tip: { a: string; b: string } | null = null, hedge: Row | null = null;
  if (h?.target?.pct != null) {
    const thru = `through ${h.target.sd} SD up (${Number(h.target.pct).toFixed(1)}%) by ${byWd}`, calls = (n: number) => `${n} ${monDay(String(h.exp))} $${kf(Number(h.k))} call${n === 1 ? '' : 's'}`;
    const need = Math.max(0, -Number(h.low?.d ?? 0));
    hedge = { target_sd: h.target.sd, target_pct: h.target.pct, by: P.by, lowest_net_delta: h.low?.d ?? null, delta_needed: need,
      calls_to_add: h.add, strike: h.k, expiry: h.exp, cost_usd: h.cost, weeks_of_premium: h.weeks, calls_held: h.held };
    tip = h.add > 0
      ? { a: `Needs ${need.toLocaleString('en-US')} shares of delta more to stay above zero ${thru}.`,
          b: `${calls(h.add)} would cover it: ${usdK(Number(h.cost))}` + (h.weeks != null ? `, about ${Number(h.weeks).toFixed(1)} weeks of premium.` : '.') }
      : { a: `Delta stays above zero ${thru}.`, b: h.held > 0 ? `The ${calls(h.held)} held ${h.held === 1 ? 'covers' : 'cover'} it. Nothing to add.` : 'Nothing to add.' };
  }
  const walls = weekWalls(g, spot).filter((w) => Math.abs(w.k / spot - 1) <= 0.15);
  const data = { units: WI_UNITS, ticker: t, price: r2(spot), one_sd_week_pct: sd, long_delta_today: long, thin_line_delta: Math.round(0.25 * long),
    now: read(rows[30]), at: read(rows[(mv + 15) * 2]),
    turns_thin_up_pct: first('Thin', 1), turns_short_up_pct: first('Short', 1), turns_thin_down_pct: first('Thin', -1), turns_short_down_pct: first('Short', -1),
    ...(hedge ? { hedge } : {}),
    walls: walls.map((w) => ({ label: w.label, strike: w.k })),
    rows: rows.filter((r) => Number.isInteger(r[0])).map((r) => ({ move_pct: r[0], net_delta: r[3], bought_delta: r[1], sold_delta: r[2], pnl_usd: tens(r[4]) })) };
  const chart = { t, px: r2(spot), sd, long, mv, rows, tip,
    walls: walls.map((w) => ({ k: w.k, lb: w.label === 'Accelerator' ? 'Accel.' : w.label, side: w.side, dash: !!w.dash })) };
  return { data, chart };
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

/** The analysts as Nasdaq reports them (ticker-technicals saves them each day): the average target, its low and high, and
    how many say buy, hold and sell. Nik, 2 Nov 2026: analysts are Nasdaq's everywhere (the chart's line, the tile, the
    card); Investing Pro keeps fair value. */
async function nasdaqAnalysts(t: string): Promise<Row | null> {
  const [r] = await db(`ticker_fundamentals?ticker=eq.${t}&analyst_target=not.is.null` +
    '&select=day,analyst_target,analyst_low,analyst_high,n_buy,n_hold,n_sell&order=day.desc&limit=1').catch(() => [] as Row[]);
  return r ? { day: String(r.day), target: num(r.analyst_target), low: num(r.analyst_low), high: num(r.analyst_high),
    buy: num(r.n_buy), hold: num(r.n_hold), sell: num(r.n_sell) } : null;
}

// ── Payoff by Friday (block 28, handoff Oct 29 2026) ─────────────────────────────────────────────────────

/* What each price by Friday adds or costs: every leg re-priced with Black-Scholes at its own IV, held where it is
   today, rate 4%, time in days to each close. From today (zero is where the position stands now); what was sold
   alone is from the sale (zero is what was collected). The phone draws the card from card.chart with the same sums
   (SearchPayoff.swift), so the line and the sentence agree. Asked, 29 Oct: each contract's own IV; the book moves
   every name by the same %; the card ends when this week's calls expire; earnings hold IV (the source line names
   the report); open orders stay off; one chip per kind of leg. */
const RATE = 0.04;
function ncdf(x: number): number {
  const t = 1 / (1 + 0.2316419 * Math.abs(x)), d = 0.3989423 * Math.exp(-x * x / 2);
  const p = d * t * (0.3193815 + t * (-0.3565638 + t * (1.781478 + t * (-1.821256 + t * 1.330274))));
  return x > 0 ? 1 - p : p;
}
function bs(S: number, K: number, days: number, v: number, cp: 'c' | 'p'): number {
  if (days <= 0) return cp === 'c' ? Math.max(0, S - K) : Math.max(0, K - S);
  const T = days / 365, sq = v * Math.sqrt(T), d1 = (Math.log(S / K) + (RATE + v * v / 2) * T) / sq, d2 = d1 - sq, df = Math.exp(-RATE * T);
  return cp === 'c' ? S * ncdf(d1) - K * df * ncdf(d2) : K * df * ncdf(-d2) - S * ncdf(-d1);
}
/** A New York wall time on a day, in epoch ms. */
function nyMs(day: string, hm = '16:00'): number {
  const g = Date.parse(`${day}T${hm}:00Z`);
  const p = Object.fromEntries(new Intl.DateTimeFormat('en-US', { timeZone: 'America/New_York', hourCycle: 'h23', year: 'numeric',
    month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit' }).formatToParts(new Date(g)).map((x) => [x.type, x.value]));
  return g + (g - Date.UTC(+p.year, +p.month - 1, +p.day, +p.hour, +p.minute));
}
const fridayFrom = (iso: string) => addDays(iso, (5 - new Date(iso + 'T12:00:00Z').getUTCDay() + 7) % 7);
/** Where the card ends: this week's expiry, the Friday ahead (today on a Friday until its close), then the next; the
    Thursday before when the market is shut that Friday; 1 PM on a half day. Not the plan's week: that moves to next
    Friday on the sale day, and the card skipped a Friday's own close (30 Oct 2026). */
function fridayOf(c: Ctx, now: number): { day: string; close: number } {
  const cal = (c.p.calendar ?? []) as Row[];
  const closeOf = (d: string) => {
    const e = cal.find((x) => x.date === d && x.kind === 'early_close' && x.closes);
    return nyMs(d, e ? String(e.closes).slice(0, 5) : '16:00');
  };
  let fri = fridayFrom(c.today);
  for (let i = 0; i < 6; i++, fri = addDays(fri, 7)) {
    const d = cal.some((e) => e.date === fri && e.kind === 'closed') ? addDays(fri, -1) : fri;
    if (closeOf(d) > now) return { day: d, close: closeOf(d) };
  }
  return { day: fri, close: closeOf(fri) };
}
const KINDS = ['sc', 'sp', 'lp', 'hc', 'ip'] as const;
type Kind = typeof KINDS[number];
interface PLeg { g: Kind; cp: 'c' | 'p'; k: number; exp: string; T: number; n: number; v: number; now: number; paid: number }
const kf = (k: number) => (Number.isInteger(k) ? String(k) : k.toFixed(2));
const chipOf = (g: Kind, ls: PLeg[]) => {
  const ks = [...new Set(ls.map((l) => l.k))].sort((a, b) => a - b).map(kf).join(' · ');
  return g === 'sc' ? `Sold ${ks} calls` : g === 'sp' ? `Sold ${ks} puts` : g === 'lp' ? `LEAPS ${ks}` : g === 'hc' ? `Hedge ${ks}` : `Insurance ${ks}`;
};
const LEG_WORD: Record<Kind, string> = { sc: 'calls sold', sp: 'puts sold', lp: 'LEAPS', hc: 'hedge calls', ip: 'insurance puts' };
/** P&L at a price by Friday: from today, or from the sale. */
function pnlAt(L: PLeg[], S: number, d0: number, fromSale = false): number {
  return L.reduce((s, l) => s + l.n * 100 * (bs(S, l.k, l.T - d0, l.v, l.cp) - (fromSale ? l.paid : l.now)), 0);
}
/** The chart's price range, as the design draws it: at least 5% and 1.9 priced moves either side, every sold strike
    in with 2.5% to spare, never more than 15%. */
const spanOf = (px: number, m: number, L: PLeg[]) =>
  Math.min(0.15, Math.max(0.05, 1.9 * m, ...L.filter((l) => l.n < 0).map((l) => Math.abs(l.k / px - 1) + 0.025)));
function zeros(fn: (s: number) => number, lo: number, hi: number): number[] {
  const out: number[] = [], n = 240;
  let ps = lo, pv = fn(lo);
  for (let i = 1; i <= n; i++) { const s = lo + (hi - lo) * i / n, v = fn(s); if ((pv < 0) !== (v < 0)) out.push(ps + (s - ps) * (pv / (pv - v))); pv = v; ps = s; }
  return out;
}
const tens = (v: number) => Math.round(v / 10) * 10;
/* Every input is cut to 4 places before any sum, and the phone gets exactly these: the sentence and the card then
   work from the same numbers and round to the same $10 (29 Oct 2026: $7,280 in the words, $7,290 on the line). */
const r4 = (x: number) => Math.round(x * 1e4) / 1e4;

/** One name's legs and what the card needs to draw it. The name's IV (the band, and "IV held at") is the one the
    weekly chain prices: the move priced to this week's expiry by the strike nearest the price (gamma's weeklies). */
function payName(c: Ctx, t: string, g: Row | undefined, now: number, d0: number) {
  const px = r4(spotOf(c, t));
  let L: PLeg[] = ((c.p.legs ?? []) as Row[]).filter((l) => l.ticker === t && Number(l.n) > 0).map((l) => {
    const cp: 'c' | 'p' = l.type === 'call' ? 'c' : 'p';
    const kind: Kind = l.side === 'sold' ? (cp === 'c' ? 'sc' : 'sp') : cp === 'p' ? 'ip' : l.up ? 'hc' : 'lp';
    const v = num(l.iv);
    return { g: kind, cp, k: Number(l.strike), exp: String(l.expiry), T: r4((nyMs(String(l.expiry)) - now) / 864e5),
      n: (l.side === 'sold' ? -1 : 1) * Number(l.n), v: v != null && v > 0.02 && v < 5 ? r4(v) : NaN, now: 0, paid: r4(num(l.avg) ?? 0) };
  }).filter((l) => l.T > 0);
  const pr = g?.priced, ty = pr?.exp && g?.built_at ? (nyMs(String(pr.exp)) - Date.parse(String(g.built_at))) / (365 * 864e5) : 0;
  const fromChain = pr?.sd1 && g?.spot && ty > 2 / (24 * 365) ? Number(pr.sd1) / Number(g.spot) / Math.sqrt(ty) : null;
  const near = L.filter((l) => Number.isFinite(l.v)).sort((a, b) => a.T - b.T || Math.abs(a.k - px) - Math.abs(b.k - px))[0];
  const iv = r4(fromChain ?? near?.v ?? 0.35);
  L = L.map((l) => { const v = Number.isFinite(l.v) ? l.v : iv; return { ...l, v, now: r4(bs(px, l.k, l.T, v, l.cp)) }; });
  const m = iv * Math.sqrt(Math.max(0, d0) / 365);
  const ne = nameRow(c, t)?.next_earnings?.date;
  return { t, px, iv, m, L, walls: weekWalls(g, px), reports: ne && ne >= c.today ? String(ne) : null };
}

/** The walls on the price line: the first Ceiling, the first Floor, and the Accelerator nearest the price. */
function weekWalls(g: Row | undefined, px: number): Row[] {
  const ws = ((g?.walls ?? []) as Row[]), lab = (w: Row) => String(w.label ?? '').toLowerCase(), rk = (a: Row, b: Row) => (a.rank ?? 9) - (b.rank ?? 9);
  const ceil = ws.filter((w) => w.side === 'call' && lab(w) === 'ceiling').sort(rk)[0];
  const floor = ws.filter((w) => w.side === 'put' && lab(w) === 'floor').sort(rk)[0];
  const acc = ws.filter((w) => lab(w) === 'accelerator').sort((a, b) => Math.abs(a.k - px) - Math.abs(b.k - px))[0];
  return [ceil && { k: Number(ceil.k), side: 'call', label: 'Ceiling', conf: ceil.conf ?? null, dash: false },
    floor && { k: Number(floor.k), side: 'put', label: 'Floor', conf: floor.conf ?? null, dash: false },
    acc && { k: Number(acc.k), side: acc.side === 'call' ? 'call' : 'put', label: 'Accelerator', conf: null, dash: true }].filter(Boolean) as Row[];
}

/** The phone's copy: every number it needs to draw and redraw the card, rounded. */
const chartName = (x: ReturnType<typeof payName>, fri: string) => ({
  t: x.t, px: x.px, iv: x.iv,
  reports: x.reports && x.reports <= fri ? monDay(x.reports) : null,
  chips: KINDS.filter((g) => x.L.some((l) => l.g === g)).map((g) => ({ g, t: chipOf(g, x.L.filter((l) => l.g === g)) })),
  walls: x.walls,
  legs: x.L.map((l) => ({ g: l.g, cp: l.cp, k: l.k, T: l.T, n: l.n, v: l.v, now: l.now, paid: l.paid })),
});
const monDay = (iso: string) => new Date(iso + 'T12:00:00Z').toLocaleString('en-US', { month: 'short', day: 'numeric', timeZone: 'UTC' });
const dayLabel = (iso: string) => new Date(iso + 'T12:00:00Z').toLocaleString('en-US', { weekday: 'short', month: 'short', day: 'numeric', timeZone: 'UTC' }).replace(',', '');

async function payoff(c: Ctx, t: string | undefined, sold: boolean) {
  const now = Date.now(), fri = fridayOf(c, now), d0 = r4((fri.close - now) / 864e5);
  const names = t ? [t] : bookNames(c);
  const gv = await db(`gamma_view_day?view=eq.weeklies&ticker=in.(${names.join(',')})&select=ticker,day,built_at,spot:data->spot,` +
    `priced:data->priced,walls:data->walls&order=day.desc&limit=${names.length * 3}`).catch(() => [] as Row[]);
  const gOf = (k: string) => gv.find((r) => r.ticker === k);
  const word = new Date(fri.day + 'T12:00:00Z').getUTCDay() === 4 ? 'Thursday' : 'Friday';
  const head = { by: fri.day, by_word: word, days_to_close: Math.round(d0 * 100) / 100 };
  const chart = (mode: string, xs: ReturnType<typeof payName>[]) => ({ mode, by: dayLabel(fri.day), word, d0,
    names: xs.map((x) => chartName(x, fri.day)) });
  const UNITS = `pnl_usd is what each price at ${word}'s close adds (positive) or costs (negative), every leg re-priced with ` +
    'Black-Scholes at its own IV held where it is today, rounded to $10 as the card shows it. ';

  if (!t) {
    // The book: every name moved by the same %, added up.
    const xs = names.map((k) => payName(c, k, gOf(k), now, d0)).filter((x) => x.L.length && Number.isFinite(x.px));
    if (!xs.length) throw new Error('nothing held in the book');
    const at = (x: ReturnType<typeof payName>, mv: number) => pnlAt(x.L, x.px * (1 + mv), d0);
    const tot = (mv: number) => xs.reduce((s, x) => s + at(x, mv), 0);
    return { ...card('payoff', `Book · Payoff by ${word}`, sunny(c), { units: UNITS + 'From today. Every name moves by the same %.', ...head,
      book: Object.fromEntries([[-10, 'down_10_pct'], [-5, 'down_5_pct'], [0, 'flat'], [5, 'up_5_pct'], [10, 'up_10_pct']]
        .map(([mv, k]) => [k, { pnl_usd: tens(tot(Number(mv) / 100)) }])),
      names: xs.map((x) => ({ ticker: x.t, flat_usd: tens(at(x, 0)), down_5_pct_usd: tens(at(x, -0.05)), up_5_pct_usd: tens(at(x, 0.05)) })) }),
      chart: chart('book', xs) };
  }

  const x = payName(c, t, gOf(t), now, d0);
  if (!Number.isFinite(x.px)) throw new Error(`${t} is not in the book`);
  if (!x.L.length) throw new Error(`nothing held on ${t}`);
  const L = sold ? x.L.filter((l) => l.n < 0) : x.L;
  if (!L.length) throw new Error(`nothing sold on ${t} right now`);
  const fn = (s: number) => pnlAt(L, s, d0, sold), r = spanOf(x.px, x.m, L);
  const dn = x.px * (1 - x.m), up = x.px * (1 + x.m);
  const byLeg = (s: number) => KINDS.filter((g) => L.some((l) => l.g === g)).map((g) => ({ leg: LEG_WORD[g],
    pnl_usd: tens(pnlAt(L.filter((l) => l.g === g), s, d0, sold)) }));
  const legs = KINDS.filter((g) => L.some((l) => l.g === g)).map((g) => {
    const ls = L.filter((l) => l.g === g);
    return { leg: LEG_WORD[g], chip: chipOf(g, ls), contracts: ls.reduce((s, l) => s + Math.abs(l.n), 0),
      strikes: [...new Set(ls.map((l) => l.k))].sort((a, b) => a - b), expiries: [...new Set(ls.map((l) => l.exp))].sort(),
      ...(g === 'sc' || g === 'sp' ? { ends_by_then: ls.every((l) => l.exp <= fri.day) } : {}) };
  });
  const premium = sold ? Math.round(L.reduce((s, l) => s + Math.abs(l.n) * 100 * l.paid, 0)) : undefined;
  return { ...card('payoff', tagOf(t, sold ? 'Sold' : `Payoff by ${word}`), sunny(c), {
    units: UNITS + (sold ? 'From the sale: zero is what was collected, so a positive figure is what is kept.' : 'From today: zero is where the position stands now.'),
    ticker: t, price: r2(x.px), ...head, move_priced_pct: r2(x.m * 100), legs,
    ...(sold ? { premium_collected_usd: premium } : {}),
    one_sd_down: { price: r2(dn), pnl_usd: tens(fn(dn)), by_leg: byLeg(dn) },
    flat: { price: r2(x.px), pnl_usd: tens(fn(x.px)), by_leg: byLeg(x.px) },
    one_sd_up: { price: r2(up), pnl_usd: tens(fn(up)), by_leg: byLeg(up) },
    breakevens: zeros(fn, x.px * (1 - r), x.px * (1 + r)).slice(0, 2).map(r2),
    walls: x.walls.map((w) => ({ label: w.label, strike: w.k, ...(w.conf != null ? { confidence: w.conf } : {}) })),
    ...(x.reports && x.reports <= fri.day ? { reports_before_then: x.reports } : {}) }),
    chart: { ...chart(sold ? 'sold' : 'one', [x]) } };
}

// ── The price chart (block 29, handoff Oct 30 2026) ──────────────────────────────────────────────────

/* How a name is doing over a Week, Month, Quarter or Year. The range control changes the card in place, so the phone
   gets every range at once: a year of daily closes with the 50 and 200-day averages, this week's line every 15
   minutes from the stored quotes, the sold strikes and how much is captured, the LEAPS, hedge and insurance strikes,
   this week's Ceiling and Floor, and the saved research. The model gets the same facts worked out here, so the
   sentence and the card agree. Asked, 30 Oct: averages are simple on closes and RSI is 14-day (ticker-technicals'
   maths), the 52-week high and low come from closes, the Week line is the stored quotes, book names only. */
const CO: Record<string, string> = { BABA: 'Alibaba', FIS: 'Fidelity National', KR: 'Kroger', LULU: 'Lululemon', NFLX: 'Netflix',
  NKE: 'Nike', PEP: 'PepsiCo', UBER: 'Uber', TSLA: 'Tesla' };
const nyDate = (ms: number) => new Date(ms).toLocaleDateString('en-CA', { timeZone: 'America/New_York' });
const addMonths = (iso: string, n: number) => { const d = new Date(iso + 'T12:00:00Z'); d.setUTCMonth(d.getUTCMonth() + n); return d.toISOString().slice(0, 10); };
function smaOf(c: number[], n: number): (number | null)[] {
  let s = 0; return c.map((v, i) => { s += v; if (i >= n) s -= c[i - n]; return i >= n - 1 ? s / n : null; });
}
function rsiOf(c: number[], n = 14): number | null {
  let g = 0, l = 0, out: number | null = null;
  for (let i = 1; i < c.length; i++) {
    const ch = c[i] - c[i - 1], up = Math.max(0, ch), dn = Math.max(0, -ch);
    if (i <= n) { g += up / n; l += dn / n; if (i < n) continue; } else { g = (g * (n - 1) + up) / n; l = (l * (n - 1) + dn) / n; }
    out = l === 0 ? 100 : 100 - 100 / (1 + g / l);
  }
  return out;
}
const pct1 = (a: number, b: number) => r2((a / b - 1) * 100);
const dayMon = (iso: string) => { const d = new Date(iso + 'T12:00:00Z'); return `${d.getUTCDate()} ${d.toLocaleString('en-US', { month: 'short', timeZone: 'UTC' })}`; };

/** A name's daily closes, oldest first: Polygon's bars (ticker_bars), less any bar for a day that had not closed when it
    was fetched, then Sunny's own saved close (daily_closes) for a later day the bars do not have yet. 1 Nov 2026:
    Polygon's bar for a day arrives the next morning, so over a weekend the bars stopped at Thursday and the chart's last
    close was a day old. */
async function closesOf(t: string): Promise<{ d: string; c: number }[]> {
  const [[bar], saved] = await Promise.all([db(`ticker_bars?ticker=eq.${t}&select=bars,fetched_at`),
    db(`daily_closes?ticker=eq.${t}&select=date,close_price&order=date.desc&limit=10`).catch(() => [] as Row[])]);
  if (!bar?.bars?.length) throw new Error(`no daily prices for ${t} yet`);
  const got = Date.parse(String(bar.fetched_at));
  const days = (bar.bars as number[][]).map((b) => ({ d: nyDate(b[0]), c: Number(b[4]) })).filter((x) => !(nyMs(x.d, '16:00') > got));
  const last = days.at(-1)?.d ?? '';
  for (const r of [...saved].reverse()) if (String(r.date) > last && Number(r.close_price) > 0) days.push({ d: String(r.date), c: Number(r.close_price) });
  return days;
}

async function priceChart(c: Ctx, t: string, range: string, mark: string | null) {
  const now = Date.now(), today = nyDate(now), spot = spotOf(c, t);
  if (!Number.isFinite(spot) || !bookNames(c).includes(t)) throw new Error(`${t} is not in the book; the price chart covers the book's names for now`);
  const cal = (c.p.calendar ?? []) as Row[];
  // This week, Monday to Friday; on a weekend the week just ended.
  const dow = new Date(today + 'T12:00:00Z').getUTCDay(), mon = addDays(today, dow === 0 ? -6 : dow === 6 ? -5 : 1 - dow);
  const week = [0, 1, 2, 3, 4].map((i) => {
    const d = addDays(mon, i), e = cal.find((x) => x.date === d);
    return { d, closed: e?.kind === 'closed', open: nyMs(d, '09:30'), close: nyMs(d, e?.kind === 'early_close' && e.closes ? String(e.closes).slice(0, 5) : '16:00') };
  });
  const gday = week.findIndex((w) => w.d === today), started = gday >= 0 && !week[gday].closed && now >= week[gday].open;

  const [hist, gv, quotes, res, nq] = await Promise.all([
    closesOf(t),
    db(`gamma_view_day?view=eq.weeklies&ticker=eq.${t}&select=day,walls:data->walls&order=day.desc&limit=1`).catch(() => [] as Row[]),
    // A quote every 15 s or so: each open day in two halves, so no read reaches PostgREST's 1,000 rows.
    Promise.all(week.filter((w) => !w.closed && w.open <= now).flatMap((w) => {
      const mid = (w.open + w.close) / 2;
      return [[w.open, mid], [mid, w.close]].map(([a, b]) => db(`ticker_quotes?ticker=eq.${t}&captured_at=gte.${new Date(a).toISOString()}` +
        `&captured_at=lt.${new Date(b).toISOString()}&select=spot,captured_at&order=captured_at.asc&limit=1000`).catch(() => [] as Row[]));
    })).then((x) => x.flat()),
    researchFigures(t, ['fair_value']).catch(() => null),
    nasdaqAnalysts(t),
  ]);
  // Daily closes, today's price as today's close once the session has started.
  const days = hist.filter((x) => x.d < today);
  if (started) days.push({ d: today, c: spot });
  const cs = days.map((x) => x.c), n = cs.length, px = r4(cs[n - 1]);
  const ma50 = smaOf(cs, 50), ma200 = smaOf(cs, 200), rsi = rsiOf(cs);
  const at = (iso: string) => Math.max(0, days.findIndex((x) => x.d >= iso));
  const lastBefore = (iso: string) => { let i = n - 1; while (i > 0 && days[i].d >= iso) i--; return i; };
  const ix = { w: lastBefore(mon), m: Math.max(0, n - 22), q: at(addMonths(today, -3)), y: at(addMonths(today, -12)) };
  const mv = (k: keyof typeof ix) => pct1(cs[n - 1], cs[ix[k]]);

  // This week's line: the last quote in each 15 minutes, a day's own close where a stretch is missing.
  const pts: number[][] = [[0, r4(cs[ix.w])]];
  week.forEach((w, i) => {
    if (w.closed || w.open > now) return;
    const end = Math.min(now, w.close), span = w.close - w.open, b = new Map<number, number[]>();
    for (const q of quotes) {
      const ms = Date.parse(String(q.captured_at));
      if (ms >= w.open && ms <= end && Number(q.spot) > 0) b.set(Math.floor((ms - w.open) / 9e5), [ms, Number(q.spot)]);
    }
    for (const [, [ms, p]] of [...b.entries()].sort((x, y) => x[0] - y[0])) pts.push([r4((i + (ms - w.open) / span) / 5), r4(p)]);
    const dc = days.find((x) => x.d === w.d)?.c;
    if (w.d !== today && dc != null && pts.at(-1)![0] < (i + 1) / 5 - 1e-6) pts.push([(i + 1) / 5, r4(dc)]);
  });
  if (started) pts.push([r4(Math.min(1, (gday + Math.min(1, (now - week[gday].open) / (week[gday].close - week[gday].open))) / 5)), px]);
  for (let i = 1; i < pts.length; i++) if (pts[i][0] < pts[i - 1][0]) pts[i][0] = pts[i - 1][0];

  // What is held: the week's sold strikes, and the LEAPS, hedge and insurance strikes.
  const legs = ((c.p.legs ?? []) as Row[]).filter((l) => l.ticker === t && Number(l.n) > 0 && l.expiry >= today);
  const expDay = [...week].reverse().find((w) => !w.closed)!.d;
  const sold = legs.filter((l) => l.side === 'sold' && l.expiry <= week[4].d);
  const col = sold.reduce((s, l) => s + Number(l.avg ?? 0) * l.n, 0), left = sold.reduce((s, l) => s + Number(l.mark ?? l.avg ?? 0) * l.n, 0);
  // Pace: 1 less the square root of the share of the week's trading time still ahead.
  const open = week.filter((w) => !w.closed && w.d <= expDay), tot = open.reduce((s, w) => s + w.close - w.open, 0);
  const ahead = open.reduce((s, w) => s + Math.max(0, w.close - Math.max(w.open, now)), 0);
  const cap = sold.length && col > 0 ? Math.round((1 - left / col) * 100) : null, pace = Math.round((1 - Math.sqrt(ahead / tot)) * 100);
  const tag = cap == null ? null : cap >= pace + 5 ? 'ahead of pace' : cap <= pace - 5 ? 'behind pace' : 'on pace';
  const word = { leaps: 'LEAPS', hedge: 'Hedge', insurance: 'Insurance' } as const;
  const bought = [...new Map(legs.filter((l) => l.side === 'bought').map((l) => [`${kindOf(l)}${l.strike}`,
    { g: word[kindOf(l) as keyof typeof word], k: Number(l.strike), n: Number(l.n) }])).values()];
  const leaps = bought.filter((l) => l.g === 'LEAPS').sort((a, b) => b.n - a.n)[0];

  // This week's walls (gamma's weeklies): the first Ceiling and the first Floor within 12% of the price.
  const ws = ((gv[0]?.walls ?? []) as Row[]), lab = (w: Row) => String(w.label ?? '').toLowerCase(), rk = (a: Row, b: Row) => (a.rank ?? 9) - (b.rank ?? 9);
  const walls = [['Ceiling', ws.filter((w) => w.side === 'call' && lab(w) === 'ceiling').sort(rk)[0]],
    ['Floor', ws.filter((w) => w.side === 'put' && lab(w) === 'floor').sort(rk)[0]]]
    .filter(([, w]) => w && Math.abs(Number((w as Row).k) / px - 1) < 0.12).map(([lb, w]) => ({ lb: lb as string, k: Number((w as Row).k) }));

  // The averages, the last cross of the one the range uses, and the 52-week high and low from closes.
  const cross = (k: 50 | 200, from: number) => {
    const A = k === 50 ? ma50 : ma200;
    for (let i = n - 1; i > from; i--) {
      if (A[i - 1] == null || A[i] == null) break;
      if ((cs[i] > A[i]!) !== (cs[i - 1] > A[i - 1]!)) return { date: monDay(days[i].d), crossed: cs[i] > A[i]! ? 'above' : 'below' };
    }
    return null;
  };
  const yr = cs.slice(ix.y), hi = Math.max(...yr), lo = Math.min(...yr);
  // Fair value from Investing Pro, the analysts' target from Nasdaq (2 Nov 2026).
  const fig = (m: string) => res?.rows.find((r) => r.metric === m)?.value, an = nq?.target ?? null, fv = num(fig('fair_value_average'));
  const research = an != null && fv != null && res
    ? { an, fv, src: `${String(res.src.source).split(',')[0]} · ${dayMon(String(res.src.asof))} · analysts Nasdaq · ${dayMon(nq!.day)}` } : null;

  const RNG: Record<string, string> = { w: 'Week', m: 'Month', q: 'Quarter', y: 'Year' };
  const rg = RNG[range] ? range : 'w', m50 = ma50[n - 1]!, m200 = ma200[n - 1];
  const data = {
    units: 'Percent figures are already percents. A move is from the start of the range to today; positive is up.',
    ticker: t, company: CO[t] ?? t, price: r2(px), range: RNG[rg],
    moves_pct: { this_week: mv('w'), over_the_month: mv('m'), over_the_quarter: mv('q'), over_the_year: mv('y') },
    ...(sold.length ? { sold_this_week: sold.map((l) => ({ label: `Your ${kf(Number(l.strike))} ${l.type === 'call' ? 'calls' : 'puts'}`,
      contracts: Number(l.n), strike: Number(l.strike), expiry: l.expiry, price_from_strike_pct: pct1(px, Number(l.strike)) })),
      // Calls worth more than they were sold for have captured nothing: the strike they sit over is the fact then.
      ...(cap != null && cap >= 0 ? { captured_pct: cap, pace: tag } : { worth_more_than_sold: true }) } : {}),
    // Nothing left this week (a Friday after the sale): the open sold strike nearest the price, as the card reads it.
    ...(!sold.length && legs.some((l) => l.side === 'sold') ? { open_sold: legs.filter((l) => l.side === 'sold').map((l) => ({
      label: `Your ${kf(Number(l.strike))} ${l.type === 'call' ? 'calls' : 'puts'}`, expiry: l.expiry, price_from_strike_pct: pct1(px, Number(l.strike)) })) } : {}),
    walls: walls.map((w) => ({ label: w.lb, strike: w.k, price_from_wall_pct: pct1(px, w.k) })),
    ma50: r2(m50), price_from_ma50_pct: pct1(px, m50), ...(m200 != null ? { ma200: r2(m200), price_from_ma200_pct: pct1(px, m200) } : {}),
    rsi14: rsi == null ? null : Math.round(rsi), rsi_reads: rsi == null ? null : rsi > 70 ? 'overbought' : rsi < 30 ? 'oversold' : 'neutral',
    last_cross_of_50day_this_quarter: cross(50, ix.q), last_cross_of_200day_this_year: cross(200, ix.y),
    high_52w: r2(hi), low_52w: r2(lo), under_the_high_pct: Math.round((1 - px / hi) * 100), over_the_low_pct: Math.round((px / lo - 1) * 100),
    ...(leaps ? { leaps_in_the_money_pct: Math.round((px / leaps.k - 1) * 100) } : {}),
    ...(research ? { analysts_average_target: research.an, price_to_analysts_pct: pct1(research.an, px),
      fair_value: research.fv, price_to_fair_value_pct: pct1(research.fv, px), research_source: research.src } : {}),
  };
  const y0 = ix.y, sl = <T,>(a: T[]) => a.slice(y0);
  const chart = {
    t, co: CO[t] ?? t, px, range: rg, mark: mark === 'cross' ? 'cross' : null,
    d: sl(days.map((x) => x.d)), c: sl(cs.map(r4)), ma50: sl(ma50.map((x) => (x == null ? null : r4(x)))),
    ma200: sl(ma200.map((x) => (x == null ? null : r4(x)))), rsi: rsi == null ? null : r4(rsi),
    ix: { w: ix.w - y0, m: ix.m - y0, q: ix.q - y0 },
    week: { days: week.map((w) => ({ lab: `${WDAY[new Date(w.d + 'T12:00:00Z').getUTCDay()]} ${Number(w.d.slice(8))}`, closed: w.closed })),
      today: started ? gday : week.findIndex((w) => w.d === today && !w.closed), exp: week.findIndex((w) => w.d === expDay), pts },
    sold: sold.map((l) => ({ k: Number(l.strike), cp: l.type === 'call' ? 'c' : 'p' })), cap: cap == null ? null : { pct: cap, tag, pace },
    // Every open sold strike, next week's too (a Friday's new sale): the book's status line reads the nearest.
    soldAll: [...new Map(legs.filter((l) => l.side === 'sold').map((l) => [`${l.type}${l.strike}`, { k: Number(l.strike), cp: l.type === 'call' ? 'c' : 'p' }])).values()],
    legs: bought.map(({ g, k }) => ({ g, k })), leapsK: leaps?.k ?? null, walls, res: research,
  };
  return { ...card('chart', tagOf(t, RNG[rg]), sunny(c), data), chart };
}
const WDAY = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

/* Your book (block 29): every name at once, a row each, one range control for all; the list first, small charts when
   asked. Each name's line is the price chart's own (priceChart), cut to what a row draws. The row's status line is the
   nearest thing that needs him: on Week the closest sold strike (else the Ceiling), on Month and Quarter the 50-day, on
   Year the 52-week high; the order follows it, closest first. Worked out here for the sentence, again on the phone for
   the range he switches to. */
async function bookChart(c: Ctx, range: string, view: string) {
  const RNG: Record<string, string> = { w: 'Week', m: 'Month', q: 'Quarter', y: 'Year' }, rg = RNG[range] ? range : 'w';
  const xs = (await Promise.all(bookNames(c).map((t) => priceChart(c, t, rg, null).catch(() => null)))).filter(Boolean) as
    Awaited<ReturnType<typeof priceChart>>[];
  if (!xs.length) throw new Error('no prices for the book yet');
  const pc = (v: number) => Math.abs(v * 100).toFixed(1) + '%';
  const status = (ch: Row) => {
    const n = ch.c.length, px = ch.c[n - 1];
    if (rg === 'w') {
      const near = (ch.soldAll as Row[]).map((s): Row => ({ ...s, d: s.cp === 'c' ? (s.k - px) / px : (px - s.k) / px })).sort((a, b) => a.d - b.d)[0];
      const nm = (s: Row) => `${kf(s.k)} ${s.cp === 'c' ? 'calls' : 'puts'}`;
      if (near) return { ord: near.d, text: near.d < 0 ? `${near.cp === 'c' ? 'Above' : 'Below'} your ${nm(near)}` : `${pc(near.d)} ${near.cp === 'c' ? 'under' : 'over'} ${nm(near)}`,
        tone: near.d < 0 ? 'down' : near.d < 0.015 ? 'thin' : 'muted' };
      const ce = (ch.walls as Row[]).find((w) => w.lb === 'Ceiling');
      if (ce) { const d = (ce.k - px) / px; return { ord: d, text: d < 0 ? 'Above the Ceiling' : `${pc(d)} under the Ceiling`, tone: d < 0.015 ? 'thin' : 'muted' }; }
      return { ord: 1, text: 'Nothing sold', tone: 'muted' };
    }
    if (rg === 'y') {
      const hi = Math.max(...ch.c), dn = 1 - px / hi;
      return { ord: px / ch.c[0] - 1, text: dn < 0.05 ? 'Near the 52-week high' : `${Math.round(dn * 100)}% under 52-week high`, tone: 'muted' };
    }
    const m = ch.ma50[n - 1], d = px / m - 1;
    return { ord: d, text: `${pc(d)} ${d >= 0 ? 'above' : 'below'} the 50-day`, tone: 'muted' };
  };
  const rows = xs.map((x) => ({ x, s: status(x.chart) })).sort((a, b) => a.s.ord - b.s.ord);
  const mvKey = { w: 'this_week', m: 'over_the_month', q: 'over_the_quarter', y: 'over_the_year' }[rg] as 'this_week';
  const data = {
    units: 'Percent figures are already percents; a move is from the start of the range to today, positive is up.',
    range: RNG[rg], view: view === 'grid' ? 'small charts' : 'list', order: { w: 'closest to a strike first', m: 'furthest under the 50-day first',
      q: 'furthest under the 50-day first', y: 'biggest drop first' }[rg],
    names: rows.map(({ x, s }) => { const xd = x.data as Row; return { ticker: xd.ticker, price: xd.price, move_pct: xd.moves_pct[mvKey], status: s.text,
      ...(rg === 'm' || rg === 'q' ? { price_from_ma50_pct: xd.price_from_ma50_pct } : {}),
      ...(rg === 'y' ? { under_the_high_pct: xd.under_the_high_pct } : {}) }; }),
  };
  // The phone's copy: each row's year of closes, the 50-day, this week's line, the sold strikes and the Ceiling.
  const chart = { view: view === 'grid' ? 'grid' : 'list', range: rg, names: rows.map(({ x }) => {
    const ch = x.chart;
    return { t: ch.t, co: ch.co, d: ch.d, c: ch.c, ma50: ch.ma50, ix: ch.ix, week: { today: ch.week.today, pts: ch.week.pts },
      sold: ch.soldAll, ceil: ch.walls.find((w) => w.lb === 'Ceiling')?.k ?? null };
  }) };
  return { ...card('book', tagOf(undefined, `Your book · ${xs.length} names`), sunny(c), data), chart };
}

// ── Technicals, and the payoff's names and Also helps (blocks 29 and 30, handoffs Oct 30 and Oct 31 2026) ──────

/* Technicals: a name's averages, RSI and 52-week range from its daily closes alone (the last close, never the live
   price), so a tile under the payoff and the card it opens show the same number. Simple averages and Wilder's 14-day
   RSI, the price chart's maths. Four widgets, the one asked first: 50-day, 200-day, RSI, 52-week, and the 20-day in the
   50-day's place when it is the one asked. Every percent is cut to one place here, and the phone prints these. */
const TECH = ['ma50', 'ma200', 'rsi', 'range'];
const pctAbs1 = (d: number) => Math.round(Math.abs(d) * 1000) / 10;
async function technicals(t: string, asked: string) {
  const days = await closesOf(t), cs = days.map((x) => x.c), n = cs.length, px = cs[n - 1], last = days[n - 1].d;
  const i0 = Math.max(0, n - 22);
  const avg = (k: number) => {
    const A = smaOf(cs, k), v = A[n - 1];
    return v == null ? null : { v: r2(v), p: pctAbs1(px / v - 1), up: px >= v, c: cs.slice(i0).map(r4), a: A.slice(i0).map((x) => (x == null ? null : r4(x))) };
  };
  const ma: Record<string, ReturnType<typeof avg>> = { ma20: avg(20), ma50: avg(50), ma200: avg(200) }, rsi = rsiOf(cs);
  const y0 = Math.max(0, days.findIndex((x) => x.d >= addMonths(last, -12)));
  const yr = cs.slice(y0), hi = Math.max(...yr), lo = Math.min(...yr), under = Math.round((1 - px / hi) * 100);
  const first = ['ma20', 'ma50', 'ma200', 'rsi', 'range'].includes(asked) ? asked : 'ma50';
  const order = [first, ...TECH.filter((k) => k !== first && !(first === 'ma20' && k === 'ma50'))].slice(0, 4);
  const reads = rsi == null ? null : rsi > 70 ? 'overbought' : rsi < 30 ? 'oversold' : 'neutral';
  const at = `${WDAY[new Date(last + 'T12:00:00Z').getUTCDay()]} close`;
  const data = {
    units: `From daily closes only: the last close (${monDay(last)}), never the live price. Percents are already percents; ` +
      'price_vs says whether the price sits above or below the average.',
    ticker: t, close: r2(px), close_day: last, asked: first,
    ...Object.fromEntries(Object.entries(ma).filter(([, x]) => x).flatMap(([k, x]) => [[k, x!.v], [`price_vs_${k}`, x!.up ? 'above' : 'below'],
      [`price_from_${k}_pct`, x!.p]])),
    rsi14: rsi == null ? null : Math.round(rsi), rsi_reads: reads,
    high_52w: r2(hi), low_52w: r2(lo), under_the_high_pct: under,
  };
  const chart = { t, at, order, n, px: r2(px), ma,
    rsi: rsi == null ? null : { v: Math.round(rsi), x: r2(rsi), reads },
    range: { under, lo: r2(lo), hi: r2(hi), x: hi > lo ? r4((px - lo) / (hi - lo)) : 0.5 } };
  return { ...card('technicals', tagOf(t, 'Technicals'), { kind: 'close', at: last }, data), chart };
}

/** The next monthly expiry after a day: the third Friday of that month or the next, the Thursday before when the
    market is shut that Friday. */
function monthlyAfter(c: Ctx, after: string): string {
  const cal = (c.p.calendar ?? []) as Row[], d = new Date(after + 'T12:00:00Z');
  for (let i = 0; i < 3; i++) {
    const first = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + i, 1, 12)), iso = first.toISOString().slice(0, 10);
    const third = addDays(iso, (5 - first.getUTCDay() + 7) % 7 + 14);
    const e = cal.some((x) => x.date === third && x.kind === 'closed') ? addDays(third, -1) : third;
    if (e > after) return e;
  }
  return addDays(after, 28);
}

/** The first weekly expiry that closes after a report: on or after the day for a report before the open, after it
    otherwise; the Thursday before when the market is shut that Friday. */
function expiryAfter(c: Ctx, day: string, time: string | null): string {
  const cal = (c.p.calendar ?? []) as Row[];
  let f = fridayFrom(day);
  for (let i = 0; i < 4; i++, f = addDays(f, 7)) {
    const e = cal.some((x) => x.date === f && x.kind === 'closed') ? addDays(f, -1) : f;
    if (time === 'bmo' ? e >= day : e > day) return e;
  }
  return f;
}

/** A day so many sessions on (weekdays), for "ready Nov 12". */
const sessionsOn = (iso: string, k: number) => { let d = iso; while (k > 0) { d = addDays(d, 1); const w = new Date(d + 'T12:00:00Z').getUTCDay(); if (w && w < 6) k--; } return d; };
/** How the questions name a company: Nike by name, as the design asks it, every other name by its ticker. */
const said = (t: string) => (t === 'NKE' ? 'Nike' : t);

/* Under a one-name payoff (block 30): every book name as a logo, in book order, each with its delta state (the What if
   model: Thin is net delta under 25% of long, Short under zero), and four tiles with what the payoff cannot show. Each
   tile carries the question it asks and its answer id, so the answer never depends on reading words. Read from the
   same snapshot as the payoff; a tile with no data shows dashed with why. Asked, 1 Nov 2026: the monthly tile is the
   next monthly's own walls (its Ceiling, or the first call wall under its own label when none reads as a Ceiling). */
export async function moreFor(c: Ctx, t: string, weekCeiling: number | null): Promise<Row> {
  const fri = fridayOf(c, Date.now()).day, mo = monthlyAfter(c, fri), md = monDay(mo), n = said(t);
  const [tech, nq, [gm]] = await Promise.all([
    technicals(t, 'ma50').catch(() => null),
    nasdaqAnalysts(t),
    db(`gamma_view_day?ticker=eq.${t}&view=eq.${mo}&select=day,walls:data->walls&order=day.desc&limit=1`).catch(() => [] as Row[]),
  ]);
  const dashed = (k: string, l: string, d: string) => ({ k, l, v: 'Not yet', d, tone: null, pend: true });
  const ch = tech?.chart, last = (tech?.data as Row | undefined)?.close_day as string | undefined;
  const ready = (k: number) => (last && ch ? `Saving closes · ready ${monDay(sessionsOn(last, Math.max(1, k - ch.n)))}` : 'Saving closes');
  const m50 = ch?.ma.ma50;
  const tiles: Row[] = [
    m50 ? { k: 'ma50', l: '50-day', v: m50.v.toFixed(2), d: `Price ${m50.p.toFixed(1)}% ${m50.up ? 'above' : 'below'}`, tone: m50.up ? 'up' : 'down',
      id: `tech:${t}:ma50`, q: `What’s ${n}’s 50-day?` } : dashed('ma50', '50-day', ready(50)),
  ];
  const an = nq?.target ?? null, spot = spotOf(c, t);
  if (an != null && spot > 0) {
    const d = an / spot - 1;
    tiles.push({ k: 'an', l: 'Analysts', v: `$${an.toFixed(2)}`, d: `${pctAbs1(d).toFixed(1)}% ${d >= 0 ? 'above' : 'below'} today`,
      tone: Math.abs(d) < 0.05 ? null : d > 0 ? 'up' : 'down', id: `an:${t}`, q: `What do analysts say about ${n}?` });
  } else tiles.push(dashed('an', 'Analysts', `No analyst targets for ${n} yet`));
  tiles.push(ch && ch.n >= 252 ? { k: 'range', l: '52-week', v: `${ch.range.under}%`, d: `under the high · ${ch.range.lo.toFixed(2)} to ${ch.range.hi.toFixed(2)}`,
    tone: 'muted', id: `tech:${t}:range`, q: `What’s ${n}’s 52-week range?` } : dashed('range', '52-week', ready(252)));
  const ws = ((gm?.walls ?? []) as Row[]).filter((w) => w.side === 'call'), lab = (w: Row) => String(w.label ?? '').toLowerCase();
  const rk = (a: Row, b: Row) => (a.rank ?? 9) - (b.rank ?? 9);
  const top = ws.filter((w) => lab(w) === 'ceiling').sort(rk)[0] ?? ws.sort(rk)[0];
  const word = !top ? 'Ceiling' : lab(top) === 'ceiling' ? 'Ceiling' : lab(top) === 'accelerator' ? 'Accelerator' : 'call wall';
  tiles.push(top ? { k: 'month', l: `${md} ${word}`, v: kf(Number(top.k)),
    d: weekCeiling != null && Number(top.k) === weekCeiling ? 'Same as this Friday' : 'The monthly, past this Friday', tone: 'muted',
    id: `walls:${t}:${mo}`, q: `${t}’s walls on ${md}` } : dashed('month', `${md} Ceiling`, `No ${md} walls saved yet`));
  // A report within 30 days takes the fourth place.
  const e = nameRow(c, t)?.next_earnings, days = e?.date ? daysTo(String(e.date), c.today) : null;
  if (days != null && days >= 0 && days <= 30) tiles[3] = { k: 'earn', l: 'Earnings', v: monDay(String(e.date)),
    d: days === 0 ? 'Today' : `In ${days} day${days === 1 ? '' : 's'}`, tone: null, id: `earn:${t}`, q: `When does ${n} report?` };
  const state = (k: string) => { try { const s = whatIf(c, k, undefined, 0)?.data.now.state; return s === 'Short' || s === 'Thin' ? s : null; } catch { return null; } };
  return { t, names: bookNames(c).map((k) => ({ t: k, co: CO[k] ?? k, st: state(k) })), tiles };
}

// ── The name page (block 31, handoff Nov 2 2026) ───────────────────────────────────────────────────────

/* One page per name, pushed from Search, in three acts. Step 1 is the header and Nike's world: the stock (the year chart
   as the price chart card draws it, and four figures), the sector (Investing Pro's averages and the S&P 500), what's
   being said (Nik's Investing Pro notes: the bull case, the bear case and the latest earnings call) and earnings (the day
   after each of the last four reports, the next report, the move the options price to the first expiry after it). One
   snapshot: the model writes the paragraph and the findings from these figures and the cards draw the same ones. Asked,
   2 Nov 2026: a section with no data is left out, never shown with sample figures; analysts are Nasdaq's; the sector card
   is "Peers and sector"; the earnings stat is the move to that expiry, named by its date. */
const NOTE_ROWS: [string, RegExp][] = [['bull', /^bull case/i], ['bear', /^bear case/i], ['call', /^earnings call/i]];
/** A note's first point: its first bullet, else its first line ("Summary" headings skipped). */
const firstPoint = (body: unknown) => {
  const lines = String(body ?? '').split('\n').map((x) => x.trim()).filter((x) => x && !/^summary:?$/i.test(x));
  return (lines.find((x) => /^[-•*]\s/.test(x)) ?? lines[0] ?? '').replace(/^[-•*]\s+/, '').trim();
};
const monShort = (iso: string) => new Date(iso + 'T12:00:00Z').toLocaleString('en-US', { month: 'short', timeZone: 'UTC' });
const whenOf = (time: unknown) => (time === 'amc' ? 'after the close' : time === 'bmo' ? 'before the open' : null);
const figTxt = (v: number) => (Number.isInteger(v) ? String(v) : v.toFixed(1));
/** A market cap as the research writes it: 55.8B, 840M. */
const capTxt = (v: number) => (v >= 1e9 ? `${(v / 1e9).toFixed(1)}B` : `${Math.round(v / 1e6)}M`);

// ── Your Nike (block 31, step 2) ──────────────────────────────────────────────────────────────────────

/* Asked, 2 Nov 2026: the book is split by each name's value now (the Allocation card's figure); Made = Realized + Open
   as the P&L glossary has them (Realized = everything closed since the book's start, by sunny-home's rules and IBKR's
   figures, so it matches the Performance card; Open = IBKR's unrealized on what is held); You % = Made over the name's
   value on its first day; Week by week grades calls only, a roll counting in the week it was bought back. The money
   comes from IBKR's daily report, so it runs to the last close IBKR has sent. */
const BOOK_FROM: Record<string, string> = { S: '2026-08-31', N: '2026-10-29' };   // demo book D deleted 6 Nov 2026
/** Every row of a read that grows: PostgREST stops at 1,000, so page through it in a fixed order. */
async function dbAll(path: string): Promise<Row[]> {
  const out: Row[] = [];
  for (let off = 0; ; off += 1000) {
    const rows = await db(`${path}&limit=1000&offset=${off}`);
    out.push(...rows);
    if (rows.length < 1000) return out;
  }
}
const yShort = (iso: string) => `${monShort(iso)} ’${iso.slice(2, 4)}`;
const usd0 = money;

async function yourName(c: Ctx, t: string, ch: Row) {
  const from = BOOK_FROM[c.book] ?? BOOK_FROM.S, today = c.today, spot = spotOf(c, t), fri = fridayFrom(today);
  const [trades, sells, lots, pos, closes, po] = await Promise.all([
    dbAll(`option_trades?book_id=eq.${c.book}&ticker=eq.${t}&voided_at=is.null&select=id,trade_date,executed_at,action,direction,` +
      'option_type,strike,expiry,contracts,premium,realized_pl,realized_pl_source,note&order=trade_date.asc,executed_at.asc,id.asc'),
    db(`share_sells?book_id=eq.${c.book}&ticker=eq.${t}&voided_at=is.null&trade_date=gte.${from}&select=trade_date,realized_pl`).catch(() => [] as Row[]),
    db(`share_lots?book_id=eq.${c.book}&ticker=eq.${t}&voided_at=is.null&acquired_date=gte.${from}&select=acquired_date,realized_pl`).catch(() => [] as Row[]),
    dbAll(`account_positions_daily?book_id=eq.${c.book}&underlying=eq.${t}&report_date=gte.${from}` +
      '&select=report_date,position_value,fifo_pnl_unrealized&order=report_date.asc,account_id.asc,conid.asc'),
    db(`daily_closes?ticker=eq.${t}&date=gte.${addDays(from, -7)}&select=date,close_price&order=date.asc`).catch(() => [] as Row[]),
    payoff(c, t, false).catch(() => null),
  ]);

  // Realized, as sunny-home books it: each closing fill at IBKR's figure, what is left open past expiry on that day, and
  // share sales after the start (on the start day only a lot bought that day counts). Calls sold are graded by week too.
  const real: { d: string; amt: number }[] = [];
  const weeks = new Map<string, { sold: number; kept: number; full: boolean }>();
  const wk = (d: string, sold: number, kept: number, full: boolean) => {
    const f = fridayFrom(d), w = weeks.get(f) ?? { sold: 0, kept: 0, full: true };
    w.sold += sold; w.kept += kept; w.full &&= full; weeks.set(f, w);
  };
  const groups = new Map<string, Row[]>();
  for (const x of trades) {
    const k = `${x.option_type}|${x.direction}|${Number(x.strike)}|${x.expiry}`;
    if (!groups.has(k)) groups.set(k, []);
    groups.get(k)!.push(x);
  }
  for (const rows of groups.values()) {
    const fills = [...rows].sort((a, b) => String(a.trade_date).localeCompare(String(b.trade_date))
      || String(a.executed_at ?? '').localeCompare(String(b.executed_at ?? '')) || (a.action === 'open' ? -1 : 1));
    const first = fills.find((f) => f.action === 'open');
    if (!first) continue;
    const pre = String(first.trade_date) < from, f0 = fills[0], short = f0.direction === 'short', exp = String(f0.expiry);
    const calls = short && f0.option_type === 'call' && !pre;
    let qty = 0, cost = 0;
    for (const x of fills) {
      const n = Number(x.contracts), px = Number(x.premium) * 100;
      if (x.action === 'open') { qty += n; cost += n * px; continue; }
      const avg = qty > 0 ? cost / qty : 0;
      const ib = x.realized_pl != null && x.realized_pl_source === 'ibkr' ? Number(x.realized_pl) : null;
      const amt = ib ?? (short ? n * (avg - px) : n * (px - avg));
      if (!pre || String(x.trade_date) > from) real.push({ d: String(x.trade_date), amt });
      // Kept in full: expired, or bought back for 5 cents or less.
      if (calls) wk(String(x.trade_date), n * avg, amt, /IBKR Ep lifecycle/.test(String(x.note ?? '')) || Number(x.premium) <= 0.05);
      cost -= n * avg; qty -= n;
    }
    if (qty > 0.0001 && exp < today) {
      if (!pre || exp > from) real.push({ d: exp, amt: short ? cost : -cost });
      if (calls) wk(exp, cost, cost, true);
    }
  }
  for (const s of sells) {
    const d = String(s.trade_date);
    if (d <= from && !lots.some((l) => String(l.acquired_date) <= d)) continue;
    real.push({ d, amt: Number(s.realized_pl ?? 0) });
  }
  for (const l of lots) if (Number(l.realized_pl)) real.push({ d: String(l.acquired_date), amt: Number(l.realized_pl) });

  // Since you entered: realized to each day plus IBKR's unrealized that day, against the stock from the same day.
  const byDay = new Map<string, { v: number; u: number }>();
  for (const p of pos) {
    const d = String(p.report_date), e = byDay.get(d) ?? { v: 0, u: 0 };
    e.v += Number(p.position_value ?? 0); e.u += Number(p.fifo_pnl_unrealized ?? 0); byDay.set(d, e);
  }
  const days = [...byDay.keys()].sort();
  let since: Row | null = null;
  if (days.length >= 2) {
    const start = days[0], last = days.at(-1)!, base = byDay.get(start)!.v;
    const cum = (d: string) => real.reduce((s, x) => s + (x.d <= d ? x.amt : 0), 0);
    const cl = closes.map((x) => ({ d: String(x.date), c: Number(x.close_price) })).filter((x) => x.c > 0);
    const closeOn = (d: string) => [...cl].reverse().find((x) => x.d <= d)?.c ?? NaN;
    const c0 = closeOn(start);
    const pts = days.map((d) => {
      const made = cum(d) + byDay.get(d)!.u, st = closeOn(d) / c0 - 1;
      return [d, Math.round(made), base > 0 ? r2(made / base * 100) : null, Number.isFinite(st) ? r2(st * 100) : null];
    });
    const made = Math.round(cum(last) + byDay.get(last)!.u), realized = Math.round(cum(last));
    since = { from: start, to: last, fromDay: monDay(start), toDay: monDay(last), base: Math.round(base), made, realized,
      open: made - realized, you: base > 0 ? r2(made / base * 100) : null, stock: pts.at(-1)![3], pts,
      src: `Your trades and IBKR's daily values · to ${monDay(last)} close` };
  }

  // Week by week: every finished week since the start, then this week so far against pace.
  const done = [...weeks.entries()].filter(([f, w]) => f < fri && w.sold > 0).sort((a, b) => a[0].localeCompare(b[0])).slice(-12)
    .map(([f, w]) => ({ fri: f, day: monDay(f), sold: Math.round(w.sold), kept: Math.round(w.kept),
      g: w.kept < 0 ? 'lost' : w.full ? 'full' : 'part' }));
  const legs = ((c.p.legs ?? []) as Row[]).filter((l) => l.ticker === t && Number(l.n) > 0 && String(l.expiry) >= today);
  const wsold = legs.filter((l) => l.side === 'sold' && l.type === 'call' && String(l.expiry) <= fri);
  const col = wsold.reduce((s, l) => s + Number(l.avg ?? 0) * l.n * 100, 0), left = wsold.reduce((s, l) => s + Number(l.mark ?? l.avg ?? 0) * l.n * 100, 0);
  const cap = (ch.chart as Row).cap as Row | null;
  const now = wsold.length && col > 0 ? { fri, day: monDay(fri), sold: Math.round(col), kept: Math.round(col - left),
    pct: Math.round((1 - left / col) * 100), pace: num(cap?.pace), tag: cap?.tag ?? null } : null;
  const weeksOut = done.length || now ? { weeks: done, now, from: monDay(from),
    src: 'Your trades · a roll counts in the week it was bought back' } : null;

  // Nike in your book: each name's value now, this name's share of this week's premium and of the delta in dollars.
  const hs = ((c.p.allocation?.holdings ?? []) as Row[]).filter((h) => Number(h.now) > 0).sort((a, b) => b.now - a.now);
  const tot = hs.reduce((s, h) => s + Number(h.now), 0);
  const prem = new Map<string, number>();
  for (const l of (c.p.legs ?? []) as Row[]) if (l.side === 'sold' && String(l.expiry) >= today && String(l.expiry) <= fri)
    prem.set(l.ticker, (prem.get(l.ticker) ?? 0) + Number(l.avg ?? 0) * l.n * 100);
  const premTot = [...prem.values()].reduce((s, v) => s + v, 0);
  const dd = ((c.p.risk?.delta?.by ?? []) as Row[]).map((x) => ({ t: String(x.ticker), v: Math.max(0, Number(x.net) * spotOf(c, x.ticker)) }))
    .filter((x) => Number.isFinite(x.v));
  const ddTot = dd.reduce((s, x) => s + x.v, 0);
  const book = hs.some((h) => h.ticker === t) && tot > 0 ? {
    total: Math.round(tot), rows: hs.map((h) => ({ t: String(h.ticker), usd: Math.round(h.now), pct: Math.round(h.now / tot * 100) })),
    rank: hs.findIndex((h) => h.ticker === t) + 1,
    premium: premTot > 0 ? Math.round((prem.get(t) ?? 0) / premTot * 100) : null,
    delta: ddTot > 0 ? Math.round((dd.find((x) => x.t === t)?.v ?? 0) / ddTot * 100) : null,
    src: 'Your book · value now, from your positions and live marks' } : null;

  // What you hold: four tiles, each the legs of one kind.
  const sum = (ls: Row[], f: (l: Row) => number) => ls.reduce((s, l) => s + f(l) * l.n, 0) / Math.max(1, ls.reduce((s, l) => s + l.n, 0));
  const nOf = (ls: Row[]) => ls.reduce((s, l) => s + Number(l.n), 0);
  const strikes = (ls: Row[]) => [...new Set(ls.map((l) => Number(l.strike)))].sort((a, b) => a - b);
  const sold = (type: string, label: string) => {
    const ls = legs.filter((l) => l.side === 'sold' && l.type === type);
    if (!ls.length) return { k: type === 'call' ? 'cs' : 'ps', l: label, v: 'None', d: [] as string[], s: null, tone: null };
    const ks = strikes(ls), exps = [...new Set(ls.map((l) => String(l.expiry)))].sort(), avg = sum(ls, (l) => Number(l.avg ?? 0));
    const mark = sum(ls, (l) => Number(l.mark ?? l.avg ?? 0)), kept = avg > 0 ? Math.round((1 - mark / avg) * 100) : null;
    return { k: type === 'call' ? 'cs' : 'ps', l: label, v: ks.length === 1 ? `${nOf(ls)} × ${kf(ks[0])}` : `${nOf(ls)} ${type}s`,
      d: [`${exps.map(monDay).join(', ')} · sold at $${avg.toFixed(2)}`,
        ...(ks.length > 1 ? [ks.map((k) => `${nOf(ls.filter((l) => Number(l.strike) === k))} × ${kf(k)}`).join(', ')] : [])],
      s: kept == null ? null : kept >= 0 ? `${kept}% kept` : `${-kept}% lost`, tone: kept == null ? null : kept >= 0 ? 'up' : 'down' };
  };
  const leaps = legs.filter((l) => l.side === 'bought' && kindOf(l) === 'leaps'), hedge = legs.filter((l) => l.side === 'bought' && kindOf(l) === 'hedge');
  const ins = legs.filter((l) => l.side === 'bought' && kindOf(l) === 'insurance');
  const hedgeLines = [...new Map(hedge.map((l) => [`${l.strike}|${l.expiry}`, l])).values()]
    .sort((a, b) => String(a.expiry).localeCompare(String(b.expiry)))
    .map((l) => `+ ${nOf(hedge.filter((x) => x.strike === l.strike && x.expiry === l.expiry))} × ${kf(Number(l.strike))} hedge, ${monDay(String(l.expiry))}`);
  const lk = strikes(leaps), le = [...new Set(leaps.map((l) => String(l.expiry)))].sort();
  const cb = leaps.length ? { k: 'cb', l: 'Calls bought', v: lk.length === 1 ? `${nOf(leaps)} × ${kf(lk[0])} LEAPS` : `${nOf(leaps)} LEAPS`,
    d: [`${le.map(yShort).join(', ')} · Δ ${sum(leaps, (l) => Number(l.delta ?? 0)).toFixed(2)}`, ...hedgeLines], s: null, tone: null }
    : hedge.length ? { k: 'cb', l: 'Calls bought', v: `${nOf(hedge)} hedge calls`, d: hedgeLines.map((x) => x.slice(2)), s: null, tone: null }
    : { k: 'cb', l: 'Calls bought', v: 'None', d: [], s: null, tone: null };
  const ik = strikes(ins), ie = [...new Set(ins.map((l) => String(l.expiry)))].sort();
  const pb = ins.length ? { k: 'pb', l: 'Puts bought', v: ik.length === 1 ? `${nOf(ins)} × ${kf(ik[0])}` : `${nOf(ins)} puts`,
    d: [`${ie.map(monDay).join(', ')} · insurance`], s: `${Math.abs(Math.round((1 - ik[0] / spot) * 100))}% ${ik[0] > spot ? 'above' : 'below'} today`, tone: 'muted' }
    : { k: 'pb', l: 'Puts bought', v: 'None', d: [], s: null, tone: null };
  const hold = { tiles: [sold('call', 'Calls sold'), sold('put', 'Puts sold'), cb, pb], right: 'Calls left, puts right',
    payoff: po?.chart ? { type: 'payoff', ...po.chart } : null };

  return { book, hold, since, weeks: weeksOut,
    data: {
      ...(book ? { in_your_book: { share_of_book_pct: book.rows.find((r) => r.t === t)?.pct, rank_in_book: book.rank, names_in_book: book.rows.length,
        book_value_usd: book.total, share_of_this_weeks_premium_pct: book.premium, share_of_delta_dollars_pct: book.delta } } : {}),
      what_you_hold: hold.tiles.map((x) => ({ tile: x.l, holds: x.v, detail: x.d.join('; '), status: x.s })),
      ...(since ? { since_you_entered: { from: since.from, to_close_of: since.to, made_usd: since.made, realized_usd: since.realized,
        open_usd: since.open, value_on_first_day_usd: since.base, you_pct: since.you, stock_pct: since.stock } } : {}),
      ...(weeksOut ? { week_by_week_calls: { weeks: done.length, kept_in_full: done.filter((w) => w.g === 'full').length,
        kept_part: done.filter((w) => w.g === 'part').length, lost: done.filter((w) => w.g === 'lost').length,
        kept_usd: done.reduce((s, w) => s + w.kept, 0), sold_usd: done.reduce((s, w) => s + w.sold, 0),
        lost_usd: done.filter((w) => w.kept < 0).reduce((s, w) => s + w.kept, 0),
        ...(now ? { this_week: { expiry: now.fri, sold_usd: now.sold, kept_usd: now.kept, kept_pct: now.pct, pace_pct: now.pace, pace: now.tag } } : {}) } } : {}),
    } };
}

async function namePage(c: Ctx, t: string, ask: string) {
  if (!bookNames(c).includes(t)) throw new Error(`${t} is not in the book; the name page covers the book's names for now`);
  const [ch, val, peers, notes, react] = await Promise.all([
    priceChart(c, t, 'y', null),
    researchFigures(t, ['valuation', 'dividend']).catch(() => null),
    researchFigures(t, ['peers']).catch(() => null),
    db(`research_notes?ticker=eq.${t}&checked_at=not.is.null&select=asof,source,title,body&order=asof.desc&limit=30`).catch(() => [] as Row[]),
    researchFigures(t, ['earnings_reactions']).catch(() => null),
  ]);
  const co = CO[t] ?? t, d = ch.data as Row, spot = spotOf(c, t);
  const dayPct = num(c.p.portfolio?.find((x: Row) => x.ticker === t)?.ranges?.d);
  const dayUsd = dayPct != null && spot > 0 ? r2(Math.abs(spot - spot / (1 + dayPct / 100))) : null;

  // The stock: four figures under the chart, Investing Pro's dated, the 52 weeks from Sunny's closes as the chart has them.
  const vf = (m: string) => val?.rows.find((r) => r.metric === m);
  const mc = vf('market_cap'), pe = vf('pe_ratio'), dy = vf('dividend_yield_pct');
  const stats = [
    mc ? { l: 'Market cap', v: '$' + String(mc.value_text ?? capTxt(Number(mc.value))).replace(/\s+/g, '') } : null,
    pe ? { l: 'P/E, last 12 months', v: figTxt(Number(pe.value)) } : null,
    dy ? { l: 'Dividend yield', v: `${Number(dy.value).toFixed(1)}%` } : null,
    { l: '52 weeks', v: `${Number(d.low_52w).toFixed(2)} to ${Number(d.high_52w).toFixed(2)}` },
  ].filter(Boolean) as Row[];
  const statsSrc = (val ? `${String(val.src.source).split(',')[0]} · ${monDay(String(val.src.asof))} · ` : '') + "52 weeks from Sunny's daily closes";

  // The sector: its peers and its sector (Investing Pro's 1-year total returns, to the research's date), and the name and
  // the S&P 500 over the year to today from Sunny's prices, so the name's row is the stock section's move (Nik, 2 Nov).
  const pr = (k: string) => num(peers?.rows.find((r) => r.metric === 'one_year_total_return_pct' && r.period === k)?.value);
  let sector: Row | null = null;
  if (peers && (pr('Peers') != null || pr('Sector') != null)) {
    const asof = String(peers.src.asof), from = addMonths(c.today, -12);
    const spy = await db(`daily_closes?ticker=eq.SPY&date=gte.${from}&select=date,close_price&order=date.asc&limit=1`).catch(() => [] as Row[]);
    const ix = (c.p.indices ?? []).find((x: Row) => x.symbol === 'SPY'), a = Number(spy[0]?.close_price), b = Number(ix?.regular ?? ix?.price);
    const spx = a > 0 && b > 0 ? pct1(b, a) : null;
    const rows = [{ k: 'me', l: co, pct: num(d.moves_pct?.over_the_year) }, { k: 'peers', l: 'Peers average', pct: pr('Peers') },
      { k: 'sector', l: 'Sector average', pct: pr('Sector') }, { k: 'spx', l: 'S&P 500', pct: spx }]
      .filter((r) => r.pct != null).sort((x, y) => y.pct! - x.pct!);
    sector = { rows, asof, span: '1 year',
      src: `${co} and S&P 500 from Sunny's prices, to today · peers and sector ${String(peers.src.source).split(',')[0]}, to ${monDay(asof)}` };
  }

  // What's being said: the latest bull case, bear case and earnings call notes, each its title and first point.
  const said = NOTE_ROWS.map(([k, re]) => {
    const n = notes.find((x) => re.test(String(x.title ?? '')));
    return n ? { k, title: String(n.title), line: firstPoint(n.body), src: `${n.source} · ${monDay(String(n.asof))}`, asof: String(n.asof) } : null;
  }).filter(Boolean) as Row[];

  // Earnings: the day after each of the last four reports, oldest first; the next report; the move priced to the first
  // expiry after it (that expiry's 1 SD, named by its date).
  const by = new Map<string, number>();
  for (const r of react?.rows ?? []) if (r.metric === 'change_pct' && Number.isFinite(Number(r.value))) by.set(String(r.period), Number(r.value));
  const moves = [...by.entries()].sort((x, y) => y[0].localeCompare(x[0])).slice(0, 4).reverse().map(([rep, pct]) => ({ rep, m: monShort(rep), pct: r2(pct) }));
  const ne = nameRow(c, t)?.next_earnings, nd = ne?.date ? String(ne.date) : null;
  const next = nd && nd >= c.today ? { date: nd, day: monDay(nd), when: whenOf(ne.time), days: daysTo(nd, c.today) } : null;
  let priced: Row | null = null;
  if (next) {
    const exp = expiryAfter(c, next.date, ne.time ?? null);
    const [g] = await db(`gamma_view_day?ticker=eq.${t}&view=eq.${exp}&select=day,priced:data->priced&order=day.desc&limit=1`).catch(() => [] as Row[]);
    const p = num(g?.priced?.sd1_pct);
    if (p != null) priced = { pct: r2(p), exp, by: monDay(exp) };
  }
  const earnings = moves.length || next ? { moves, next, priced,
    src: [react ? `${String(react.src.source).split(',')[0]} · ${monDay(String(react.src.asof))}` : null, next ? 'report date from Nasdaq' : null,
      priced ? "priced move from Sunny's chains" : null].filter(Boolean).join(' · ') } : null;

  // Your Nike (step 2): the money, from the trades and IBKR's daily values.
  const mine = await yourName(c, t, ch).catch((e) => { console.error('yourName', t, String(e)); return null; });
  const order = ask === 'pos' ? ['since', 'book', 'hold', 'weeks'] : ['book', 'hold', 'since', 'weeks'];
  const mineSecs = mine ? order.filter((k) => (mine as Row)[k]) : [];
  // The question folds an act it does not need: what's happening folds Your Nike, the position question folds the
  // world. A folded act is one line, its figures written here so they are exact.
  const tn = (v: number, txt: string) => (v < 0 ? `{r:${txt}}` : `{g:${txt}}`);
  const yr = num(d.moves_pct?.over_the_year), pa = num((sector?.rows as Row[] | undefined)?.find((r) => r.k === 'peers')?.pct);
  const foldWorld = [yr != null ? `Stock ${tn(yr, `${Math.round(Math.abs(yr))}%`)} ${yr < 0 ? 'down' : 'up'} in a year` : null,
    pa != null ? `peers ${tn(pa, `${Math.round(Math.abs(pa))}%`)} ${pa < 0 ? 'down' : 'up'}` : null,
    next ? `earnings ${next.day}` : null].filter(Boolean).join(' · ');
  const sn = mine?.since as Row | null, wn = (mine?.weeks as Row | null)?.now as Row | null;
  const foldMine = [sn ? `${sn.made < 0 ? 'Down' : 'Made'} ${tn(sn.made, usd0(sn.made))} since ${sn.fromDay}` : null,
    wn ? (wn.pct >= 0 ? `calls ${tn(1, `${wn.pct}%`)} kept this week` : `this week's calls ${tn(-1, `${-wn.pct}%`)} lost`) : null]
    .filter(Boolean).join(' · ');
  const fold = ask === 'news' && mineSecs.length ? 'mine' : ask === 'pos' ? 'world' : null;
  const sections = ['stock', ...(sector ? ['sector'] : []), ...(said.length ? ['said'] : []), ...(earnings ? ['earnings'] : []), ...mineSecs];
  const data = {
    units: 'Percents are already percents and moves are signed (negative is down). In the sector, this_name_pct and sp500_pct ' +
      "are the year to today from Sunny's prices (this_name_pct is the stock's year move); the peers and sector averages are " +
      "Investing Pro's 1-year total returns to the sector's as_of date.",
    ticker: t, company: co, ask, price: r2(spot), ...(dayPct != null ? { today_move_pct: dayPct } : {}), sections,
    stock: { year_move_pct: d.moves_pct.over_the_year, over_the_52w_low_pct: d.over_the_low_pct, under_the_52w_high_pct: d.under_the_high_pct,
      high_52w: d.high_52w, low_52w: d.low_52w,
      ...(mc ? { market_cap: mc.value_text ?? capTxt(Number(mc.value)) } : {}), ...(pe ? { pe_last_12_months: Number(pe.value) } : {}),
      ...(dy ? { dividend_yield_pct: Number(dy.value) } : {}),
      ...(d.fair_value != null ? { fair_value: d.fair_value, price_to_fair_value_pct: d.price_to_fair_value_pct } : {}),
      ...(d.analysts_average_target != null ? { analysts_average_target: d.analysts_average_target, price_to_analysts_pct: d.price_to_analysts_pct } : {}) },
    ...(sector ? { sector: { as_of: sector.asof, ...Object.fromEntries((sector.rows as Row[]).map((r) => [
      r.k === 'me' ? 'this_name_pct' : r.k === 'spx' ? 'sp500_pct' : `${r.k}_average_pct`, r.pct])) } } : {}),
    ...(said.length ? { what_is_being_said: said.map((x) => ({ note: x.title, first_point: x.line, date: x.asof })) } : {}),
    ...(earnings ? { earnings: { day_after_moves: moves.map((m) => ({ report: m.rep, move_pct: m.pct })),
      rose_after: moves.filter((m) => m.pct > 0).length, fell_after: moves.filter((m) => m.pct < 0).length,
      ...(next ? { next_report: { date: next.date, when: next.when, days_to_report: next.days } } : {}),
      ...(priced ? { priced_move_pct: priced.pct, priced_to_expiry: priced.exp } : {}) } } : {}),
    ...(mine ? { your_position: mine.data } : {}),
    ...(fold ? { folded_act: fold === 'mine' ? 'your position (one line)' : "the name's world (one line)" } : {}),
  };
  const chart = { t, co, strategy: c.p.strategies?.[t] ?? null, ask, px: r2(spot),
    day: dayPct != null ? { pct: dayPct, usd: dayUsd } : null,
    world: { stock: { chart: ch.chart, stats, src: statsSrc }, sector, said: said.length ? { rows: said, src: said[0].src } : null, earnings },
    mine: mine && mineSecs.length ? { book: mine.book, hold: mine.hold, since: mine.since, weeks: mine.weeks, order: mineSecs } : null,
    fold, folds: { world: foldWorld || null, mine: foldMine || null } };
  return { ...card('name_page', tagOf(t, 'Page'), sunny(c), data), chart };
}

// ── The menu ───────────────────────────────────────────────────────────────────────────────────────────

const TICKER = { ticker: { type: 'string', description: 'A ticker, for example BABA' } };
export const MENU: Row[] = [
  { name: 'account', shows: "Account: value, today's move, realized and unrealized, time value left in what is sold, margin, interest, fees", args: {} },
  { name: 'movers', shows: "Today's moves: each name in the book, SPY, QQQ, IWM and the futures", args: {} },
  { name: 'position', shows: 'Position summary for one name: price, what is sold and bought, the week plan, delta, next earnings, who trades it', args: TICKER, required: ['ticker'] },
  { name: 'sold', shows: 'Sold options with captured %, days left, how far in the money, and theta: what time decay earns a day in dollars; one name or all', args: { ...TICKER,
      filter: { type: 'string', enum: ['all', 'in_the_money', 'captured'], description: 'in_the_money: only those in the money; captured: only those at or past min_captured' },
      min_captured: { type: 'number', description: 'Captured % threshold for filter captured, default 80' } } },
  { name: 'bought', shows: 'Bought options (LEAPS, hedge calls, insurance puts) with delta, value, time value, days left, and theta: what time decay costs a day in dollars (negative); one name or all', args: { ...TICKER,
      kind: { type: 'string', enum: ['all', 'leaps', 'hedge', 'insurance'] } } },
  { name: 'todo', shows: "This week's orders: the call sale, hedge calls, insurance puts, weekly puts; one name or all", args: TICKER },
  { name: 'delta_gamma', shows: 'Delta and the P&L of a move: one name from -15% to +15% (the What if card: net, bought and sold delta in shares, thin or short, and the To do hedge), or the whole book from -10% to +10%', args: { ...TICKER,
      move_pct: { type: 'number', description: 'The move the question names, for example -10 for a 10% drop; 10 when it names none' } } },
  { name: 'gamma', shows: "Gamma ladder for one name: walls with the tape's labels and confidence, the flip, the regime, the priced move. Read this first for walls; it covers the book names and TSLA", args: { ...TICKER,
      view: { type: 'string', description: "'weeklies' (default), 'all', or an expiry date like 2027-01-15" } }, required: ['ticker'] },
  { name: 'walls_live', shows: 'Walls worked out now from live option prices, for any ticker and expiry (open interest only, no tape labels). Only when gamma has no view for that ticker or expiry', args: { ...TICKER,
      expiry: { type: 'string', description: 'An expiry date like 2027-01-15; leave out for the next 45 days' } }, required: ['ticker'] },
  { name: 'roll', shows: "Rolling one name's calls to next Friday, as delta in shares: the calls sold now and what they could be at +1.5 SD by Thursday, what is bought, what insurance takes away, the net, the delta still needed, and each month's call walls (Ceiling, Accelerator) with what one call adds and how many would cover it. Read this for rolling, or how much delta a name needs", args: TICKER, required: ['ticker'] },
  { name: 'payoff', shows: "Payoff by Friday: what each price at this week's expiry adds or costs, every leg re-priced at its own IV: 1 SD down, flat and 1 SD up, with what each leg (calls sold, LEAPS, hedge calls, insurance puts) carries, the breakevens and the walls. legs 'sold' for what is sold alone, from the sale. No ticker for the whole book, every name moving the same %", args: { ...TICKER,
      legs: { type: 'string', enum: ['all', 'sold'], description: "'sold' for what is sold alone (how are my calls doing?); default all" } } },
  { name: 'chart', shows: "Price chart for a name in the book over a Week, Month, Quarter or Year: the move over each range, this week's sold strikes with captured % and pace, this week's Ceiling and Floor, the 50 and 200-day averages and how far the price sits from them, RSI, the last cross of the 50-day this quarter (and of the 200-day this year), the 52-week high and low from closes, how far the LEAPS are in the money, and the analysts' target and fair value where research is saved", args: { ...TICKER,
      range: { type: 'string', enum: ['w', 'm', 'q', 'y'], description: 'The range the question names: w week (the default), m month, q quarter, y year' },
      mark: { type: 'string', enum: ['cross'], description: "'cross' when he asks whether it crossed its 50-day, or for its 50-day chart" } }, required: ['ticker'] },
  { name: 'technicals', shows: "Technicals for a name from its daily closes (the last close, never the live price): the 20, 50 and 200-day averages and whether the price sits above or below each and by how much, RSI (14-day), and the 52-week high and low with how far under the high it is. Read this when he asks for one technical number (What's Nike's 50-day? NKE's RSI? What's Nike's 52-week range?)", args: { ...TICKER,
      asked: { type: 'string', enum: ['ma50', 'ma20', 'ma200', 'rsi', 'range'], description: 'The number asked: ma50 (the default), ma20, ma200, rsi, or range for the 52-week high and low' } }, required: ['ticker'] },
  { name: 'name_page', shows: "A name's page, when he asks about one name as a whole (Tell me about Nike, Show me Nike's world, What's happening with Nike?): the price and today's move, the stock over the year (move, 52-week high and low, market cap, P/E, dividend yield), the sector (1-year moves of the name, its peers average, its sector average and the S&P 500), what's being said (Nik's Investing Pro notes) and earnings (the day after each of the last four reports, the next report, the move priced to the first expiry after it); then his position (How's my Nike position doing? too): its share of the book, what he holds, made since he entered against the stock, and his calls week by week", args: { ...TICKER,
      ask: { type: 'string', enum: ['all', 'news', 'pos'], description: "'news' for what's happening with it; 'pos' for how his position in it is doing; 'all' for tell me about it or show me its world" } }, required: ['ticker'] },
  { name: 'book', shows: "Your book: every name at once, each with its price, its move over the range and the nearest thing that needs him (Week: the closest sold strike or the Ceiling; Month and Quarter: how far from the 50-day; Year: how far under the 52-week high), in that order", args: {
      range: { type: 'string', enum: ['w', 'm', 'q', 'y'], description: 'w week (the default), m month (under their 50-day), q quarter, y year' },
      view: { type: 'string', enum: ['list', 'grid'], description: "'grid' only when he asks for charts (small charts); default list" } } },
  { name: 'hedges', shows: 'Hedge calls and insurance puts: held, needed, strike, cost; one name or a list of the names that need some', args: TICKER },
  { name: 'hedge_rungs', shows: 'Every hedge call and insurance put with days left; rolls are due at 45 days left', args: {} },
  { name: 'put_gates', shows: 'Whether weekly puts can sell: a Floor below and no Accelerator between, and where the price sits against its 50-day (shown only: since 11 Nov 2026 puts never pause below the 50-day); one name or all', args: TICKER },
  { name: 'yield', shows: 'Yield: premium sold, closing cost, hedges and net on the LEAPS base, for a week or a month', args: {
      period: { type: 'string', enum: ['week', 'month'] },
      at: { type: 'string', description: 'A date in the week, or a month like 2026-10; default now' } } },
  { name: 'payback', shows: 'Payback: what the book has made against what the LEAPS cost, and the pace', args: {} },
  { name: 'performance', shows: "Performance: realized P&L (closed trades only) by month since the book's start, by name and by kind (calls sold, puts sold, calls bought, puts bought, shares) for one month, the year so far and the best and worst months; and open P&L by name. Read this for how he did in a month or this year, his best month, or which names made or lost the most", args: {
      month: { type: 'string', description: "'YYYY-MM' when he names a month (October is 2026-10); none for this month" } } },
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
  if (!owner && OWNER_ONLY.has(name)) throw new Error('This login views the book only; it has no To do.');
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
        sold: soldRows(c, k), bought: boughtRows(c, k), ...(owner ? { orders: ordersFor(c, k) } : {}),
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
        // One name: the What if card's figures (15% either way), the card itself for the phone.
        const [g] = await db(`gamma_view_day?view=eq.weeklies&ticker=eq.${t}&select=walls:data->walls&order=day.desc&limit=1`).catch(() => [] as Row[]);
        const w = whatIf(c, t, g, num(a.move_pct));
        if (!w) throw new Error(`no delta and gamma for ${t}`);
        return { ...card('delta_gamma', tagOf(t, 'What if'), sunny(c), w.data), chart: w.chart };
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
    case 'payoff':
      return await payoff(c, t, a.legs === 'sold');
    case 'chart':
      return await priceChart(c, need(t, 'chart'), String(a.range ?? 'w'), a.mark ? String(a.mark) : null);
    case 'book':
      return await bookChart(c, String(a.range ?? 'w'), String(a.view ?? 'list'));
    case 'technicals':
      return await technicals(need(t, 'technicals'), String(a.asked ?? 'ma50'));
    case 'name_page':
      return await namePage(c, need(t, 'name_page'), a.ask === 'news' || a.ask === 'pos' ? a.ask : 'all');
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
    case 'performance': {
      /* The Performance card's figures (sunny-home block 20, payload.performance: [month, ticker, kind, $] rows). A month
         before the book's first counts in its first, as on the card (the LEAPS bought on 31 Aug count in September). */
      const P = c.p.performance ?? {}, from = String(c.p.history?.from ?? BOOK_FROM[c.book] ?? c.today).slice(0, 7);
      const mo = c.today.slice(0, 7), asked = /^\d{4}-\d{2}$/.test(String(a.month ?? '')) ? String(a.month) : mo;
      const byM = new Map<string, number>(), byT = new Map<string, number>(), byK = new Map<string, number>(), open = new Map<string, number>();
      for (const r of (P.realized ?? []) as unknown[][]) {
        const m = [String(r[0]), from].sort().at(-1)!, v = Number(r[3]) || 0;
        byM.set(m, (byM.get(m) ?? 0) + v);
        if (m === asked) { byT.set(String(r[1]), (byT.get(String(r[1])) ?? 0) + v); byK.set(String(r[2]), (byK.get(String(r[2])) ?? 0) + v); }
      }
      for (const r of (P.unrealized ?? []) as unknown[][]) open.set(String(r[1]), (open.get(String(r[1])) ?? 0) + (Number(r[3]) || 0));
      const months = [...byM].filter(([m]) => m <= mo).sort((x, y) => x[0].localeCompare(y[0])).map(([month, made]) => ({ month, made: Math.round(made) }));
      const ranked = [...months].sort((x, y) => y.made - x.made);
      return card('performance', 'Performance', sunny(c), { realized_means: 'closed trades only', month: asked, this_month: mo,
        month_realized: Math.round(byM.get(asked) ?? 0),
        year_so_far: Math.round(months.filter((x) => x.month.slice(0, 4) === mo.slice(0, 4)).reduce((t, x) => t + x.made, 0)),
        best_month: ranked[0] ?? null, worst_month: ranked.at(-1) ?? null, by_month: months,
        by_name: [...byT].map(([ticker, made]) => ({ ticker, made: Math.round(made) })).filter((x) => x.made !== 0).sort((x, y) => y.made - x.made),
        by_kind: [...byK].map(([kind, made]) => ({ kind, made: Math.round(made) })).filter((x) => x.made !== 0).sort((x, y) => Math.abs(y.made) - Math.abs(x.made)),
        open_by_name: [...open].map(([ticker, open_pl]) => ({ ticker, open_pl: Math.round(open_pl) })).sort((x, y) => y.open_pl - x.open_pl) });
    }
    case 'events': {
      const days = num(a.days) ?? 14, end = addDays(c.today, days);
      const earn = ((c.p.writes?.names ?? []) as Row[]).filter((n) => n.next_earnings?.date && (!t || n.ticker === t))
        .map((n) => ({ kind: 'earnings', ticker: n.ticker, date: n.next_earnings.date, time: n.next_earnings.time ?? null,
          // One name (When does BABA report?): how far off it is, and the first expiry whose calls carry the report.
          ...(t ? { days_to_report: daysTo(String(n.next_earnings.date), c.today),
            first_expiry_after: expiryAfter(c, String(n.next_earnings.date), n.next_earnings.time ?? null) } : {}) }))
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
      /* The analysts are Nasdaq's (2 Nov 2026), so the tile, the chart's line and this answer show one target; Investing
         Pro's own analyst figures are left out, its fair value and EPS forecasts stay. */
      const k = need(t, 'analyst_targets');
      const [res, nq] = await Promise.all([researchFigures(k, ['fair_value', 'estimates']).catch(() => null), nasdaqAnalysts(k)]);
      if (!res && !nq) throw new Error(`no analyst targets or research for ${k} yet`);
      // How far the average target sits from today's price, cut as the Analysts tile under the payoff cuts it (block 30).
      const an = nq?.target ?? null, px = spotOf(c, k);
      return card('analyst_targets', tagOf(k, 'Analyst targets'), nq ? { kind: 'research', source: 'Nasdaq', asof: nq.day } : res!.src, { units: RESEARCH_UNITS,
        ...(nq ? { analysts: { source: 'Nasdaq', as_of: nq.day, average_target: nq.target, lowest_target: nq.low, highest_target: nq.high,
          say_buy: nq.buy, say_hold: nq.hold, say_sell: nq.sell } } : {}),
        ...(an != null && px > 0 ? { price_today: r2(px), average_target_vs_price: an >= px ? 'above' : 'below',
          average_target_from_price_pct: pctAbs1(an / px - 1) } : {}),
        ...(res ? { investing_pro: { as_of: res.src.asof, figures: res.rows.filter((x) => x.topic === 'fair_value' && !/^analyst/.test(x.metric)).map(res.fig),
          eps_forecasts: res.rows.filter((x) => x.topic === 'estimates').map(res.fig) } } : {}) });
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

