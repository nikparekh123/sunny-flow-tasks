/**
 * sundial: Sundial 1.0, the selling engine (docs/SUNDIAL.md; the rules live in _shared/sundial.ts). For each name it
 * covers (NVDA and SpaceX in book N, Nik 25 Nov 2026) it reads the book as it stands, the price, the closes, the saved
 * IV and the next expiry's live chain, and answers in the Income board's five columns (Nik, 25 Nov 2026):
 *   toSell   what to sell now: at 3:45 PM on Mon, Wed and Fri the calls (count by the +20% test) and 2 puts on the expiry a
 *            week out; on a big drop the puts up to the cap
 *   close    calls worth half or less of their sale price on trading day 1 or 2 after the sale: buy back
 *   working  every other open sold leg, with the share of its premium kept so far (in the money ones flagged; hold)
 *   expiring legs that expire today and what happens to each at the close
 *   banked   sold legs closed or expired since Monday, with what each kept
 * Nik decides what to buy; nothing here suggests a purchase.
 *
 * POST { mode }:
 *   'view'  (an owner of the book, or the scheduler's key) works it out and returns it, nothing saved or sent.
 *   'tick'  (the scheduler, every minute 13-21 UTC on weekdays): outside the session it returns at once. In the session
 *           it watches each name for the big drop (live price at or under yesterday's close less 2 daily SD) and, the
 *           first time a day, saves a 'drop' run and pushes Nik. From 15 minutes before the close (3:45 PM, 12:45 PM on
 *           an early-close day) it saves the day's 'plan' run once and pushes the To sell list.
 * Runs are saved in sundial_runs (one row per book, name, kind and day; owners of the book may read them).
 * Pushes go to Nik's login only (meta.user_id), not to every member of book N.
 *
 * ⚠ DEPLOY WITH verify_jwt = false: the scheduler sends x-cron-key (vault cron_secret), not a JWT. The function checks
 * it, or a signed-in user who owns the book. Anyone else gets a 401.
 * No em dashes in any words written here (Nik).
 */
import { addDays, bs, callSd, dropLine, isWeekday, ivFrom, putSd, room, RULES, signals, strikeAt, tdays, test20, yrs, type Leg, type Signals } from '../_shared/sundial.ts';

const BUILD = '2026-11-26.1';
const NAMES: { book: string; t: string; label: string }[] = [{ book: 'N', t: 'NVDA', label: 'NVDA' }, { book: 'N', t: 'SPCX', label: 'SpaceX' }];
const NIK = '85dd190f-9381-4acf-b123-7f1f6f778947';   // nik@sunnyfi.co: Sundial's pushes go to his phones only
const URL_ = Deno.env.get('SUPABASE_URL')!;
const ANON = Deno.env.get('SUPABASE_ANON_KEY')!;
const SK = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const THETA_URL = Deno.env.get('THETA_URL') ?? '';
const THETA_KEY = Deno.env.get('THETA_PROXY_KEY') ?? '';
const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-cron-key, x-admin-key' };
const json = (s: number, b: unknown) => new Response(JSON.stringify(b), { status: s, headers: { ...cors, 'Content-Type': 'application/json' } });
type Row = Record<string, any>;
const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const WD = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const md = (d: string) => `${MON[Number(d.slice(5, 7)) - 1]} ${Number(d.slice(8, 10))}`;
const wd = (d: string) => new Date(d + 'T12:00:00Z').getUTCDay();
const r2 = (x: number) => Math.round(x * 100) / 100;
const kfmt = (K: number) => (K % 1 ? K.toFixed(K * 2 % 1 ? 2 : 1) : String(K));

// ── Who may call ──
async function caller(req: Request): Promise<'cron' | 'owner' | null> {
  const cron = Deno.env.get('CRON_SECRET');
  if (cron && (req.headers.get('x-cron-key') === cron || req.headers.get('x-admin-key') === cron)) return 'cron';
  const auth = req.headers.get('authorization') ?? '';
  if (!auth.startsWith('Bearer ')) return null;
  const r = await fetch(`${URL_}/rest/v1/rpc/my_owned_books`, { method: 'POST', headers: { apikey: ANON, Authorization: auth, 'Content-Type': 'application/json' }, body: '{}' });
  if (!r.ok) { await r.body?.cancel(); return null; }
  const books = (await r.json()) as unknown[];
  const ids = books.map((b) => (typeof b === 'string' ? b : (b as Row)?.my_owned_books));
  return NAMES.every((n) => ids.includes(n.book)) ? 'owner' : null;
}
const db = async (path: string): Promise<Row[]> => {
  const r = await fetch(`${URL_}/rest/v1/${path}`, { headers: { apikey: SK, Authorization: `Bearer ${SK}` } });
  if (!r.ok) { await r.body?.cancel(); return []; }
  return await r.json();
};
const dbPage = async (path: string): Promise<Row[]> => {
  const out: Row[] = [];
  for (let from = 0; ; from += 1000) {
    const r = await fetch(`${URL_}/rest/v1/${path}`, { headers: { apikey: SK, Authorization: `Bearer ${SK}`, Range: `${from}-${from + 999}` } });
    if (!r.ok) { await r.body?.cancel(); return out; }
    const rows = await r.json() as Row[]; out.push(...rows);
    if (rows.length < 1000) return out;
  }
};
const send = async (method: string, path: string, body: unknown, prefer = 'return=minimal') => {
  const r = await fetch(`${URL_}/rest/v1/${path}`, { method, headers: { apikey: SK, Authorization: `Bearer ${SK}`, 'Content-Type': 'application/json', Prefer: prefer }, body: JSON.stringify(body) });
  const ok = r.ok; await r.body?.cancel(); return ok;
};

// ── New York's clock and the exchange calendar ──
const nyNow = () => {
  const p = Object.fromEntries(new Intl.DateTimeFormat('en-CA', { timeZone: 'America/New_York', year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', hour12: false })
    .formatToParts(new Date()).map((x) => [x.type, x.value]));
  return { day: `${p.year}-${p.month}-${p.day}`, mins: (Number(p.hour) % 24) * 60 + Number(p.minute) };
};
async function calendar(day: string) {
  const rows = await db(`market_calendar?date=gte.${addDays(day, -10)}&date=lte.${addDays(day, 60)}&select=date,kind,closes`);
  const closed = new Set(rows.filter((r) => r.kind === 'closed').map((r) => String(r.date)));
  const today = rows.find((r) => String(r.date) === day);
  const closeMins = today?.kind === 'early_close' && today.closes ? Number(String(today.closes).slice(0, 2)) * 60 + Number(String(today.closes).slice(3, 5)) : 16 * 60;
  const open = isWeekday(day) && !closed.has(day);
  return { closed, closeMins, open };
}

// ── Theta: expiries and one expiry's live quotes ──
async function theta(path: string): Promise<Row[]> {
  if (!THETA_URL) return [];
  const r = await fetch(`${THETA_URL}${path}&format=json`, { headers: { 'x-proxy-key': THETA_KEY }, signal: AbortSignal.timeout(15_000) }).catch(() => null);
  if (!r || !r.ok) { await r?.body?.cancel(); return []; }
  return ((await r.json())?.response ?? []) as Row[];
}
async function expiries(t: string): Promise<string[]> {
  const rows = await theta(`/v3/option/list/expirations?symbol=${t}`);
  return [...new Set(rows.map((x) => String(x.expiration ?? x.date ?? '')).filter(Boolean).map((e) => (e.includes('-') ? e : `${e.slice(0, 4)}-${e.slice(4, 6)}-${e.slice(6, 8)}`)))].sort();
}
interface Q { K: number; put: boolean; mid: number | null }
async function quotes(t: string, ex: string): Promise<Q[]> {
  const rows = await theta(`/v3/option/snapshot/quote?symbol=${t}&expiration=${ex.replaceAll('-', '')}`);
  return rows.filter((r) => r.data?.[0]).map((r) => {
    const b = Number(r.data[0].bid), a = Number(r.data[0].ask);
    return { K: Number(r.contract.strike), put: String(r.contract.right).toLowerCase() !== 'call', mid: b > 0 && a > 0 ? (a + b) / 2 : null };
  });
}

// ── The book: every open lot of every leg (first in, first out), shares, and what closed since Monday ──
interface Lot { type: 'call' | 'put'; side: 1 | -1; K: number; ex: string; n: number; px: number; day: string }
function lotsOf(trades: Row[], weekStart: string) {
  const open = new Map<string, Lot[]>(); const banked: { type: string; K: number; ex: string; n: number; kept: number; day: string }[] = [];
  for (const t of trades) {
    const type = t.option_type === 'put' ? 'put' : 'call', side = t.direction === 'long' ? 1 : -1;
    const key = `${type}|${side}|${Number(t.strike)}|${t.expiry}`, n = Number(t.contracts), px = Number(t.premium);
    const q = open.get(key) ?? [];
    if (t.action === 'open') { q.push({ type, side, K: Number(t.strike), ex: String(t.expiry), n, px, day: String(t.trade_date) }); open.set(key, q); continue; }
    let left = n;
    while (left > 0 && q.length) {
      const l = q[0], m = Math.min(left, l.n);
      if (side < 0 && String(t.trade_date) >= weekStart) banked.push({ type, K: l.K, ex: l.ex, n: m, kept: (l.px - px) * m * 100, day: String(t.trade_date) });
      l.n -= m; left -= m; if (l.n <= 0) q.shift();
    }
  }
  return { lots: [...open.values()].flat().filter((l) => l.n > 0), banked };
}

// ── One name, worked out ──
interface Ctx { day: string; mins: number; closed: Set<string>; closeMins: number; open: boolean }
async function work(nm: { book: string; t: string; label: string }, c: Ctx) {
  const { t, book } = nm, day = c.day, minsLeft = c.open ? Math.max(0, c.closeMins - c.mins) : 0;
  const monday = addDays(day, -((wd(day) + 6) % 7));
  const [quote, closesR, ivR, earnR, trades, marks, sharesR, exps] = await Promise.all([
    db(`ticker_quotes_live?ticker=eq.${t}&select=spot,captured_at`),
    db(`daily_closes?ticker=eq.${t}&date=lt.${day}&order=date.desc&limit=260&select=date,close_price`),
    db(`ticker_iv_daily?ticker=eq.${t}&atm_iv=gt.0&snapshot_date=gte.${addDays(day, -365)}&order=snapshot_date.asc&select=snapshot_date,atm_iv`),
    db(`earnings_events?ticker=eq.${t}&report_date=gte.${day}&order=report_date.asc&limit=1&select=report_date,report_time`),
    dbPage(`option_trades?book_id=eq.${book}&ticker=eq.${t}&voided_at=is.null&order=executed_at.asc,id.asc&select=id,trade_date,executed_at,action,direction,option_type,strike,expiry,contracts,premium`),
    dbPage(`option_greeks_live?select=option_trade_id,iv,last_mark,captured_at&order=captured_at.desc`),
    db(`share_lots?book_id=eq.${book}&ticker=eq.${t}&voided_at=is.null&qty_remaining=gt.0&select=qty_remaining,cost_per_share,acquired_date`),
    expiries(t),
  ]);
  const closesD = closesR.slice().reverse(), closes = closesD.map((r) => Number(r.close_price));
  const S = Number(quote[0]?.spot) || closes.at(-1)!, prevClose = closes.at(-1)!;
  const ivs = ivR.map((r) => ({ d: String(r.snapshot_date), v: Number(r.atm_iv) }));
  const ivOn = (d: string) => [...ivs].reverse().find((x) => x.d <= d)?.v ?? ivs.at(-1)?.v ?? 0.5;
  const iv30 = ivOn(day), ivPrev = ivs.filter((x) => x.d < day).at(-1)?.v ?? iv30;
  const d5 = String(closesD[closesD.length - 4]?.date ?? closesD[0]?.date);
  const sig: Signals = signals({ S, prevClose, closes, iv30, iv5: ivOn(d5), ivHist: ivs.map((x) => x.v) });

  // The book
  const { lots, banked } = lotsOf(trades, monday);
  const byId = new Map<string, Row>(); for (const m of marks) if (!byId.has(m.option_trade_id)) byId.set(m.option_trade_id, m);
  const markOf = new Map<string, { iv: number; mark: number; at: string }>();
  for (const tr of trades) {
    const m = byId.get(tr.id); if (!m) continue;
    const key = `${tr.option_type}|${tr.direction === 'long' ? 1 : -1}|${Number(tr.strike)}|${tr.expiry}`, prev = markOf.get(key);
    if (!prev || String(m.captured_at) > prev.at) markOf.set(key, { iv: Number(m.iv) || 0, mark: Number(m.last_mark), at: String(m.captured_at) });
  }
  const live = lots.filter((l) => l.ex >= day);
  const shares = sharesR.reduce((a, r) => a + Number(r.qty_remaining), 0);
  const avg = shares ? sharesR.reduce((a, r) => a + Number(r.qty_remaining) * Number(r.cost_per_share), 0) / shares : null;
  const yearOld = sharesR.filter((r) => String(r.acquired_date) <= addDays(day, -365)).reduce((a, r) => a + Number(r.qty_remaining), 0);
  const ivLeg = (l: { type: string; side: number; K: number; ex: string }) => { const m = markOf.get(`${l.type}|${l.side}|${l.K}|${l.ex}`); return m && m.iv > 0.05 ? m.iv : iv30; };
  const valueNow = (l: Lot) => { const m = markOf.get(`${l.type}|${l.side}|${l.K}|${l.ex}`); return m && m.mark >= 0 && m.at.slice(0, 10) === day ? m.mark : bs(S, l.K, yrs(day, l.ex, c.closed, minsLeft), ivLeg(l), l.type === 'put'); };
  // Legs for the test: lots of the same contract added up. Legs expiring today are left out: they settle at today's
  // close, so a rise later in the week cannot reach them.
  const legMap = new Map<string, Leg>();
  for (const l of live.filter((x) => x.ex > day)) {
    const k = `${l.type}|${l.side}|${l.K}|${l.ex}`, e = legMap.get(k);
    if (e) e.n += l.n; else legMap.set(k, { type: l.type, K: l.K, ex: l.ex, n: l.n, side: l.side, iv: ivLeg(l) });
  }
  const legs = [...legMap.values()];
  const soldPutsOpen = live.filter((l) => l.side < 0 && l.type === 'put' && !(l.ex === day && c.mins >= c.closeMins)).reduce((a, l) => a + l.n, 0);

  // The expiry a week out, its live chain and its own IV
  const target = exps.find((e) => e >= addDays(day, 7)) ?? null;
  const er = earnR[0] ? { d: String(earnR[0].report_date), t: String(earnR[0].report_time ?? 'amc') } : null;
  const spans = (ex: string) => !!er && ((er.d > day && er.d < ex) || (er.d === day && er.t !== 'bmo') || (er.d === ex && er.t === 'bmo'));
  let chain: Q[] = [], ivEx = iv30, est = true;
  if (target) {
    chain = await quotes(t, target);
    const T = yrs(day, target, c.closed, minsLeft);
    const near = (put: boolean) => chain.filter((q) => q.put === put && q.mid).sort((a, b) => Math.abs(a.K - S) - Math.abs(b.K - S))[0];
    const v = [near(false), near(true)].map((q) => (q ? ivFrom(q.mid!, S, q.K, T, q.put) : null)).filter((x): x is number => !!x);
    if (v.length) { ivEx = v.reduce((a, b) => a + b, 0) / v.length; est = false; }
  }
  const listed = (put: boolean) => [...new Set(chain.filter((q) => q.put === put).map((q) => q.K))].sort((a, b) => a - b);
  const priceAt = (K: number, put: boolean, T: number) => { const q = chain.find((x) => x.put === put && x.K === K && x.mid); return q ? q.mid! : bs(S, K, T, ivEx, put); };

  // ── Close, Working, Expiring today (lots of one contract grouped; Close only takes the lots in their first 2 days) ──
  type G = { type: 'call' | 'put'; K: number; ex: string; n: number; cash: number; sold: string; now: number };
  const group = (xs: Lot[]): G[] => {
    const m = new Map<string, G>();
    for (const l of xs) {
      const k = `${l.type}|${l.K}|${l.ex}`, e = m.get(k);
      if (e) { e.n += l.n; e.cash += l.n * l.px; if (l.day < e.sold) e.sold = l.day; }
      else m.set(k, { type: l.type, K: l.K, ex: l.ex, n: l.n, cash: l.n * l.px, sold: l.day, now: valueNow(l) });
    }
    return [...m.values()].sort((a, b) => (a.ex === b.ex ? a.K - b.K : a.ex < b.ex ? -1 : 1));
  };
  const rowOf = (g: G) => {
    const at = g.cash / g.n, itm = g.type === 'call' ? S > g.K : S < g.K;
    return { type: g.type, K: g.K, ex: g.ex, n: g.n, sold: g.sold, at: r2(at), now: r2(g.now), kept: at > 0 ? Math.round((1 - g.now / at) * 100) / 100 : 0, itm };
  };
  const sold = live.filter((x) => x.side < 0);
  const isEarly = (l: Lot) => l.type === 'call' && l.ex > day && (() => { const age = tdays(l.day, day, c.closed); return age >= 1 && age <= RULES.earlyDays; })() && l.px > 0 && 1 - valueNow(l) / l.px >= RULES.earlyKept;
  const closeLots = sold.filter(isEarly);
  let close: Row[] = group(closeLots).map((g) => ({ ...rowOf(g), action: 'buy back' }));
  const expiring: Row[] = group(sold.filter((l) => l.ex === day)).map((g) => {
    const r = rowOf(g);
    const action = !r.itm ? 'expires worthless, kept' : g.type === 'call'
      ? (yearOld >= g.n * 100 ? 'in the money: shares held over a year may go' : 'in the money: buy back at the close and sell again')
      : (avg != null && g.K < avg ? 'in the money: take the shares (under your average)' : 'in the money: buy back at the close and sell again');
    return { ...r, action };
  });
  const working: Row[] = group(sold.filter((l) => l.ex > day && !closeLots.includes(l))).map(rowOf);

  // ── To sell ──
  const toSell: Row[] = [];
  const saleDay = c.open && [1, 3, 5].includes(wd(day));
  const earn = target ? spans(target) : false;
  let calls: Row | null = null, puts: Row | null = null, putsDrop: Row | null = null;
  const T = target ? yrs(day, target, c.closed, minsLeft) : 0;
  const kc = callSd(sig, earn), kp = putSd(sig, earn);
  // The sale is sized as if the Close list is bought back first.
  const legsAfter: Leg[] = legs.map((l) => ({ ...l, n: l.n - (l.side < 0 && l.type === 'call' ? closeLots.filter((x) => x.K === l.K && x.ex === l.ex).reduce((a, x) => a + x.n, 0) : 0) })).filter((l) => l.n > 0);
  if (target) {
    // Puts first (2 an expiry, inside the cap), so the calls are sized with them on the book.
    const nP = Math.min(RULES.putsNormal, Math.max(0, RULES.putCap - soldPutsOpen));
    const Kp = strikeAt(S, kp, ivEx, T, true, listed(true));
    puts = { kind: 'put', n: nP, K: Kp, ex: target, sd: kp, mid: r2(priceAt(Kp, true, T)), earnings: earn };
    const legsP: Leg[] = saleDay && nP > 0 ? [...legsAfter, { type: 'put', K: Kp, ex: target, n: nP, side: -1, iv: ivEx }] : legsAfter;
    if (kc != null) {
      const Kc = strikeAt(S, kc, ivEx, T, false, listed(false));
      const r = room(S, shares, legsP, Kc, target, ivEx, day, c.closed, minsLeft);
      // ⚠ THE EXPIRY CAP (data, 25 Nov 2026): at most half of what the test allows a book with no calls sold.
      const empty = room(S, shares, legsP.filter((l) => !(l.side < 0 && l.type === 'call')), Kc, target, ivEx, day, c.closed, minsLeft);
      // The cap is for the whole expiry: calls already sold on it (and staying on) count toward it.
      const onEx = legsAfter.filter((l) => l.side < 0 && l.type === 'call' && l.ex === target).reduce((a, l) => a + l.n, 0);
      const cap = Math.floor(empty.n * RULES.expiryCap), n = Math.min(r.n, Math.max(0, cap - onEx));
      const tst = n === r.n ? r.test : test20(S, shares, [...legsP, { type: 'call', K: Kc, ex: target, n, side: -1, iv: ivEx }], day, c.closed, minsLeft);
      calls = { kind: 'call', n, room: r.n, cap, onEx, K: Kc, ex: target, sd: kc, mid: r2(priceAt(Kc, false, T)), test: { worst: Math.round(tst.worst), at: tst.at, day: tst.day } };
    } else calls = { kind: 'call', n: 0, ex: target, earnings: true, why: `No calls: ${er ? md(er.d) : ''} earnings before ${md(target)}` };
    if (saleDay) {
      // ⚠ NETTED: buying back calls and selling the same contract again in one go only pays the spread twice. The overlap
      // stays on: the Close row and the sale both shrink by it ("keep N").
      let nC = calls.n;
      if (nC > 0) close = close.map((x) => {
        if (x.type !== 'call' || x.K !== calls!.K || x.ex !== calls!.ex) return x;
        const keep = Math.min(x.n, nC); nC -= keep;
        return { ...x, n: x.n - keep, kept_on: keep };
      }).filter((x) => x.n > 0 || x.kept_on);
      if (nC > 0) toSell.push({ ...calls, n: nC, credit: Math.round(nC * calls.mid * 100), ...(nC !== calls.n ? { of: calls.n } : {}) });
      if (nP > 0) toSell.push({ ...puts, credit: Math.round(nP * puts.mid * 100) });
    }
    // The big drop: live price at or under yesterday's close less 2 daily SD
    const line = dropLine(prevClose, ivPrev);
    const nD = Math.max(0, RULES.putCap - soldPutsOpen);
    if (S <= line && c.open) {
      const Kd = strikeAt(S, kp, ivEx, T, true, listed(true));
      putsDrop = { kind: 'put', drop: true, n: nD, K: Kd, ex: target, sd: kp, mid: r2(priceAt(Kd, true, T)), credit: Math.round(nD * priceAt(Kd, true, T) * 100), line: r2(line) };
      if (nD > 0) toSell.unshift(putsDrop);
    }
  }
  close = close.filter((x) => x.n > 0);
  const bankedTot = banked.reduce((a, b) => a + b.kept, 0);
  const bookTest = test20(S, shares, legs, day, c.closed, minsLeft);
  return {
    t, label: nm.label, book, S: r2(S), prevClose: r2(prevClose), est,
    signals: { z: r2(sig.z), trend: sig.trend, iv30: r2(sig.iv30), hv20: sig.hv20 && r2(sig.hv20), rank: Math.round(sig.rank), rich: sig.rich, cheap: sig.cheap, freak: sig.freak, ivEx: r2(ivEx) },
    earnings: er, target, saleDay,
    plan: { calls, puts },
    drop: { line: r2(dropLine(prevClose, ivPrev)), fired: !!putsDrop, puts: putsDrop },
    toSell, close, working, expiring,
    banked: { total: Math.round(bankedTot), rows: banked.map((b) => ({ ...b, kept: Math.round(b.kept) })) },
    holds: { shares, avg: avg && r2(avg), callsBought: live.filter((l) => l.side > 0 && l.type === 'call').reduce((a, l) => a + l.n, 0), putsBought: live.filter((l) => l.side > 0 && l.type === 'put').reduce((a, l) => a + l.n, 0), soldPutsOpen, putCap: RULES.putCap },
    test: { ok: bookTest.ok, worst: Math.round(bookTest.worst), at: bookTest.at, day: bookTest.day },
  };
}

// ── Pushes (Nik's phones only) ──
async function push(key: string, title: string, body: string, t: string) {
  return send('POST', 'alert_dispatch?on_conflict=dedup_key', [{ category: 'sundial', dedup_key: key, ticker: t, title, body, deep_link: null, book_id: 'N', meta: { user_id: NIK, src: 'sundial' } }], 'resolution=ignore-duplicates,return=minimal');
}
const lineOf = (x: Row, label: string) => `${label} ${x.n} ${md(x.ex)} $${kfmt(x.K)} ${x.kind === 'call' ? 'calls' : 'puts'}`;

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  const who = await caller(req);
  if (!who) return json(401, { error: 'not allowed' });
  const body = await req.json().catch(() => ({})) as Row;
  const mode = String(body.mode ?? 'view');
  const { day, mins } = nyNow();
  const cal = await calendar(day);
  const ctx: Ctx = { day, mins, ...cal };
  try {
    if (mode === 'view' || who === 'owner') {
      const names = [];
      for (const n of NAMES) names.push(await work(n, ctx));
      return json(200, { build: BUILD, at: new Date().toISOString(), day, mins, open: cal.open, closesAt: cal.closeMins, names });
    }
    if (mode !== 'tick') return json(400, { error: 'mode: view or tick' });
    const inSession = cal.open && mins >= 9 * 60 + 30 && mins < cal.closeMins;
    if (!inSession) return json(200, { build: BUILD, skip: 'market closed' });
    const done = await db(`sundial_runs?day=eq.${day}&select=book_id,ticker,kind`);
    const has = (t: string, kind: string) => done.some((r) => r.ticker === t && r.kind === kind);
    const planDue = mins >= cal.closeMins - 15;
    const out: Row[] = [];
    for (const n of NAMES) {
      const needPlan = planDue && !has(n.t, 'plan'), needDrop = !has(n.t, 'drop');
      if (!needPlan && !needDrop) continue;
      if (!needPlan) {
        // The cheap watch first: only work the name out when the live price is at or under the line
        const [q, cl, iv] = await Promise.all([db(`ticker_quotes_live?ticker=eq.${n.t}&select=spot`), db(`daily_closes?ticker=eq.${n.t}&date=lt.${day}&order=date.desc&limit=1&select=close_price`),
          db(`ticker_iv_daily?ticker=eq.${n.t}&atm_iv=gt.0&snapshot_date=lt.${day}&order=snapshot_date.desc&limit=1&select=atm_iv`)]);
        const S = Number(q[0]?.spot), pc = Number(cl[0]?.close_price), v = Number(iv[0]?.atm_iv);
        if (!(S > 0 && pc > 0 && v > 0) || S > dropLine(pc, v)) continue;
      }
      const w = await work(n, ctx);
      if (needDrop && w.drop.fired && w.drop.puts) {
        await send('POST', 'sundial_runs?on_conflict=book_id,ticker,kind,day', [{ book_id: n.book, ticker: n.t, kind: 'drop', day, build: BUILD, payload: w }], 'resolution=merge-duplicates,return=minimal');
        const p = w.drop.puts;
        await push(`sundial:${n.t}:drop:${day}`, `${n.label} big drop`, p.n > 0 ? `Sell ${p.n} ${md(p.ex)} $${kfmt(p.K)} puts, about $${p.credit.toLocaleString('en-US')}. Under $${kfmt(w.drop.line)}.` : `Under $${kfmt(w.drop.line)}. Puts at the cap of ${RULES.putCap}.`, n.t);
        out.push({ t: n.t, drop: true });
      }
      if (needPlan) {
        await send('POST', 'sundial_runs?on_conflict=book_id,ticker,kind,day', [{ book_id: n.book, ticker: n.t, kind: 'plan', day, build: BUILD, payload: w }], 'resolution=merge-duplicates,return=minimal');
        const lines = [...w.toSell.filter((x) => !x.drop).map((x) => lineOf(x, 'Sell')), ...w.close.map((x: Row) => `Buy back ${x.n} ${md(x.ex)} $${kfmt(x.K)} calls`)];
        if (lines.length) await push(`sundial:${n.t}:plan:${day}`, `${n.label} to sell`, lines.join('. ') + '.', n.t);
        out.push({ t: n.t, plan: true, lines: lines.length });
      }
    }
    return json(200, { build: BUILD, day, mins, out });
  } catch (e) {
    return json(500, { build: BUILD, error: String((e as Error)?.message ?? e) });
  }
});
