// ── New Home's page for the current moment (handoff 6 Nov 2026, Pass 2) ──
// sunny-home hands this its reads and the brief; it writes `payload.brief.doc`: the title and date line, the
// day card's caption, the deck's alerts, one lede, then the numbered sections with their cards, in the shapes
// of the design's sample (ios-app Sunny/Brief/Sample/brief-home.json), so the phone only draws.
//
// ⚠ ANYTHING WITHOUT A REAL FEED HIDES (README 9.4): The economy and Out today when econ-sync has nothing, After
// hours (no news feed) and Thesis check (Investing Pro not wired) are left out, with no gap: a section with no cards goes and the ones after it move up a number.
//
// ⚠ ORDERS ARE FOR OWNERS (31 Oct 2026): Tomorrow's orders, the orders line in a lede or headline, the "sales
// Monday" counts and To decide's question say what to trade. buildDoc returns the whole page and a copy without
// them; sunny-home's forOwners puts the whole one in home_todo (owners only) and the copy in home_snapshot.
//
// Words: no em dashes; money lost is red with no minus sign; dividends never go into kept, Made or Payback.

import { company, type Moment } from './brief.ts';
import { fK } from '../_shared/book-engine.ts';

type Row = Record<string, any>;
type Span = { t: string; b?: boolean; c?: string };

export interface NameDay {
  t: string; shares: number; leaps: number; S0: number; P0: number;
  weekBase: number | null;                 // the last close before this week's Monday
  ext: number | null;                      // pre-market or after-hours % since the last close (Yahoo)
  today: { sh: number; lp: number; oc: number; ip: number; sc: number; sp: number };   // $ since the last close
  soldCalls: { K: number; n: number; ex: string }[];
}
export interface DocIn {
  moment: Moment; today: string; mins: number;
  isTrading: (d: string) => boolean; addDays: (d: string, n: number) => string; cal: Row[];
  brief: Row; names: NameDay[];
  market: Row[]; sectors: Row[]; futures: Row[]; watch: Row[];
  chart: Row | null; yieldWeeks: Row[]; payback: Row | null; history: Row | null;
  earnings: Row[]; macro: Row[]; divs: Row[]; trades: Row[]; orders: Row[]; aftershock: Row | null;
  econ?: Row[];                    // econ_cards (econ-sync, FRED): the twelve indicators
  closes?: Row[];                  // daily_closes (ticker, date, close_price), oldest first: the world markets' month lines
  baseNow: number; baseAt: (d: string) => number;
  /** payload.performance (block 20): realized and open as [month, ticker, kind, $] rows; perfFrom = the book's chart start. */
  perf?: { realized: unknown[][]; unrealized: unknown[][] }; perfFrom?: string;
  /* README 9.4 (Audit 7): feeds that have stopped (no run for 50 h, health-monitor's "stopped") hide what they feed
     rather than show an old claim ("None ahead", "3 names still to report"); marketAt = the tape's last capture. */
  feeds?: { stopped?: string[]; marketAt?: string | null };
}

// ── Words and numbers ──
const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const MONTH = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
const DOW = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const DAY = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
const NUM = ['No', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine', 'Ten'];
const ymd = (d: string) => { const [y, m, dd] = d.split('-').map(Number); return { y, m, d: dd, wd: new Date(Date.UTC(y, m - 1, dd)).getUTCDay() }; };
/** An ISO time on the New York clock: its date and minutes since midnight. */
const nyClock = (iso: string) => {
  const p = Object.fromEntries(new Intl.DateTimeFormat('en-CA', { timeZone: 'America/New_York', year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).formatToParts(new Date(iso)).map((x) => [x.type, x.value]));
  return { date: `${p.year}-${p.month}-${p.day}`, mins: Number(p.hour) * 60 + Number(p.minute) };
};
const dayDiff = (a: string, b: string) => Math.round((Date.parse(b + 'T12:00:00Z') - Date.parse(a + 'T12:00:00Z')) / 864e5);
const md = (d: string) => `${MON[ymd(d).m - 1]} ${ymd(d).d}`;
const dmd = (d: string) => `${DOW[ymd(d).wd]} ${md(d)}`;
/* Words and numbers (README 11.5, Nik, 8 Nov 2026). Book money in K and M through the engine's fK, the design's
   money(): $624, $5.9K, $13.7K, $379K, $1.2M. Prices, strikes, index levels and dividends a share stay exact.
   A move in %: one decimal, two only under 0.1% (the design's pct). A yield keeps two decimals, as the design
   writes it (a 0.59% week, the 10y at 4.08%). */
/* Two decimals only while the move rounds under 0.1% (0.04%); 0.0996 reads 0.1%, never 0.10%. */
const p1 = (x: number) => { const q = Math.abs(x); return `${Math.round(q * 100) < 10 ? q.toFixed(2) : q.toFixed(1)}%`; };
const py = (x: number) => `${Math.abs(x).toFixed(2)}%`;
const col = (x: number) => (x < 0 ? 'red' : 'green');
const upDown = (x: number) => (x < 0 ? 'down' : 'up');
const hm = (m: number) => { const h = Math.floor(m / 60), mm = m % 60; const hh = h % 12 || 12; return `${hh}:${String(mm).padStart(2, '0')} ${h < 12 ? 'AM' : 'PM'}`; };
const tm = (t: string | null | undefined) => (t ? hm(Number(t.slice(0, 2)) * 60 + Number(t.slice(3, 5))) : '');
const num = (v: unknown) => (v == null || v === '' || !isFinite(Number(v)) ? null : Number(v));
const sp = (t: string, b = false, c?: string): Span => (c ? { t, b, c } : { t, b });
const word = (n: number) => (n <= 10 ? NUM[n] : String(n));
/** A row's lead for a headline: its bold words only, so the secondary money ($ a share, $ in all) never reaches a
 *  headline that has no privacy copy (README 12, invariant 11). */
const leadOf = (spans: Span[]) => (spans.filter((s) => s.b).map((s) => s.t).join('') || spans.map((s) => s.t).join('')).trim();
const lc = (s: string) => s.charAt(0).toLowerCase() + s.slice(1);

/** Heat-map tile colours by move (the design's eight steps, light; the deepest a shade darker since 8 Nov 2026).
 *  The phone picks the step from the move in both themes; this is only its fallback. */
const tileBg = (m: number) => {
  const a = Math.abs(m);
  if (m >= 0) return a < 0.5 ? '#E2F2E0' : a < 1.5 ? '#C2E4BE' : a < 3 ? '#8FCF89' : '#2B7330';
  return a < 0.5 ? '#FBE3E2' : a < 1.5 ? '#F6C4C2' : a < 3 ? '#EE9B97' : '#B8322D';
};
/** Squarified tiles in a W x H box, biggest first; each rect inset 2 pt so tiles sit 4 apart. */
function squarify(vals: number[], W: number, H: number): number[][] {
  const total = vals.reduce((a, b) => a + b, 0);
  if (!(total > 0)) return vals.map(() => [0, 0, 0, 0]);
  const areas = vals.map((v) => (v / total) * W * H), out: number[][] = [];
  let x = 0, y = 0, w = W, h = H, i = 0;
  while (i < areas.length) {
    const side = Math.min(w, h), row = [areas[i]];
    const worst = (r: number[]) => { const s = r.reduce((a, b) => a + b, 0); return Math.max((side * side * Math.max(...r)) / (s * s), (s * s) / (side * side * Math.min(...r))); };
    let j = i + 1;
    while (j < areas.length && worst([...row, areas[j]]) <= worst(row)) { row.push(areas[j]); j++; }
    const s = row.reduce((a, b) => a + b, 0);
    if (w >= h) { const cw = s / h; let yy = y; for (const a of row) { out.push([x, yy, cw, a / cw]); yy += a / cw; } x += cw; w -= cw; }
    else { const rh = s / w; let xx = x; for (const a of row) { out.push([xx, y, a / rh, rh]); xx += a / rh; } y += rh; h -= rh; }
    i = j;
  }
  return out.map(([a, b, c, d]) => [Math.round(a + 2), Math.round(b + 2), Math.max(0, Math.round(c - 4)), Math.max(0, Math.round(d - 4))]);
}
function heatMap(title: string, items: { ticker: string; name: string; move: number; weight: number }[], extra: Row = {}, period = '') {
  const its = items.filter((x) => x.weight > 0).sort((a, b) => b.weight - a.weight);
  /* Area follows weight, but never so small the ticker cannot fit (the design: every tile big enough for its ticker). */
  const sum = its.reduce((a, x) => a + x.weight, 0), floor = sum / Math.max(1, its.length * 2.2);
  const rects = squarify(its.map((x) => Math.max(x.weight, floor)), 305, 196);
  const tot = its.reduce((a, x) => a + x.weight, 0);
  const move = tot ? its.reduce((a, x) => a + x.move * x.weight, 0) / tot : 0;
  return {
    title, ...(period ? { period } : {}), move: p1(move), moveColor: col(move), moveSigned: +move.toFixed(2), ...extra,
    aria: `${title}${extra.weightOfSP500 ? `, ${extra.weightOfSP500} of the S&P 500` : ''}, ${upDown(move)} ${p1(move)}${period ? ' this week' : ''}. ` + its.map((x) => `${x.name} ${upDown(x.move)} ${p1(x.move)}`).join(', '),
    mapSize: [305, 196],
    tiles: its.map((x, k) => ({ name: x.name, move: +x.move.toFixed(2), bg: tileBg(x.move), rect: rects[k], ticker: x.ticker,
      moveText: p1(x.move), showsMove: rects[k][2] >= 34 && rects[k][3] >= 30, weight: +x.weight.toFixed(1) })),
  };
}

/* ── The economy in plain words: good or bad (Nik, 8 Nov 2026: "I don't know what to read, good or bad") ──
   Each reading's level against bands set for it (ours, not FRED's: change them here), and which way is better.
   `read` says both ("Calm, but getting worse"), `readTone` colours it (green good, red bad, orange mixed, secondary
   plain), `trendTone` colours the trend line by whether its move is good (green) or bad (red). */
type Tone = 'good' | 'okay' | 'bad';
const ECON_READ: Record<string, { better: 'up' | 'down'; bands: [number, string, Tone][] }> = {
  hy_spread:          { better: 'down', bands: [[3.5, 'Calm', 'good'], [5, 'Normal', 'okay'], [7, 'Stressed', 'bad'], [Infinity, 'Panic', 'bad']] },
  consumer_sentiment: { better: 'up',   bands: [[55, 'Very gloomy', 'bad'], [70, 'Gloomy', 'bad'], [85, 'Normal', 'okay'], [Infinity, 'Upbeat', 'good']] },
  auto_delinquency:   { better: 'down', bands: [[2, 'Few behind', 'good'], [2.8, 'Normal', 'okay'], [Infinity, 'Many behind', 'bad']] },
  curve_10y3m:        { better: 'up',   bands: [[0, 'Inverted, a recession warning', 'bad'], [0.5, 'Flat', 'okay'], [Infinity, 'Healthy', 'good']] },
  stress_index:       { better: 'down', bands: [[-0.25, 'Calm', 'good'], [0.5, 'Normal', 'okay'], [1.5, 'Stressed', 'bad'], [Infinity, 'High stress', 'bad']] },
  jobless_claims:     { better: 'down', bands: [[250e3, 'Strong jobs', 'good'], [300e3, 'Softening', 'okay'], [Infinity, 'Weak jobs', 'bad']] },
  bank_credit:        { better: 'up',   bands: [[0, 'Shrinking', 'bad'], [3, 'Slow', 'okay'], [Infinity, 'Healthy', 'good']] },
  sahm:               { better: 'down', bands: [[0.3, 'No recession signal', 'good'], [0.5, 'Near a recession signal', 'okay'], [Infinity, 'Recession signal', 'bad']] },
  lending_standards:  { better: 'down', bands: [[0, 'Easing', 'good'], [10, 'Steady', 'okay'], [Infinity, 'Tightening', 'bad']] },
  chargeoff_rate:     { better: 'down', bands: [[0.5, 'Low losses', 'good'], [1, 'Normal', 'okay'], [Infinity, 'High losses', 'bad']] },
  card_delinquency:   { better: 'down', bands: [[2.5, 'Few behind', 'good'], [3.5, 'Normal', 'okay'], [Infinity, 'Many behind', 'bad']] },
  debt_service:       { better: 'down', bands: [[10.5, 'Light', 'good'], [12, 'Normal', 'okay'], [Infinity, 'Heavy', 'bad']] },
};
export function econRead(id: string, card: Row): { read?: string; readTone?: string; trendTone?: string } {
  const rule = ECON_READ[id];
  const raw = String(card.chart?.points?.at?.(-1)?.value ?? card.value ?? '').trim();
  const m = raw.match(/^([+-]?[0-9.]+)\s*([KM%]?)/i);
  if (!rule || !m) return {};
  const v = Number(m[1]) * (m[2].toUpperCase() === 'K' ? 1e3 : m[2].toUpperCase() === 'M' ? 1e6 : 1);
  if (!Number.isFinite(v)) return {};
  const [, word, level] = rule.bands.find(([hi]) => v < hi) ?? rule.bands[rule.bands.length - 1];
  const dir = card.arrow === '↗' ? 'up' : card.arrow === '↘' ? 'down' : null;
  const better = dir == null ? null : dir === rule.better;
  const read = better == null ? word
    : better ? `${word}, ${level === 'bad' ? 'but' : 'and'} getting better`
    : `${word}, ${level === 'bad' ? 'and' : 'but'} getting worse`;
  const tone = better == null ? (level === 'good' ? 'green' : level === 'bad' ? 'red' : 'secondary')
    : better ? (level === 'bad' ? 'orange' : 'green')
    : (level === 'bad' ? 'red' : 'orange');
  return { read, readTone: tone, trendTone: better == null ? 'secondary' : better ? 'green' : 'red' };
}

export function buildDoc(x: DocIn): { full: Row; open: Row } {
  const stopped = new Set(x.feeds?.stopped ?? []);
  x = { ...x, earnings: stopped.has('earnings') ? [] : x.earnings, macro: stopped.has('macro') ? [] : x.macro,
    divs: stopped.has('dividends') ? [] : x.divs, econ: stopped.has('econ') ? [] : x.econ,
    // No To do orders on Home (Nik, 11 Nov 2026: "Remove To do, we don't need it"), whatever the caller passes.
    orders: [] };
  const { moment, today, mins, addDays, isTrading } = x;
  const B = x.brief, F: string = B.friday, wk = moment === 'weekend';
  const session = ['bell', 'open', 'last20', 'last5'].includes(moment);
  const early = new Map(x.cal.filter((c) => c.kind === 'early_close' && c.closes).map((c) => [String(c.date), Number(String(c.closes).slice(0, 2)) * 60 + Number(String(c.closes).slice(3, 5))]));
  const closeMin = early.get(today) ?? 960;
  const lastTrading = (d: string) => { let y = d; while (!isTrading(y)) y = addDays(y, -1); return y; };
  const nextTrading = (d: string) => { let y = addDays(d, 1); while (!isTrading(y)) y = addDays(y, 1); return y; };
  const mondayOf = (d: string) => addDays(d, -((ymd(d).wd + 6) % 7));
  /* The weekend page reviews the week of the last session: Saturday's is this week, a Monday holiday's the week before.
     On a mid-week holiday (Thanksgiving) the week is still open: "so far", and what comes next starts tomorrow. */
  const monday = mondayOf(wk ? lastTrading(today) : today), weekFri = lastTrading(addDays(monday, 4));
  const weekOpen = wk && weekFri > today, closedDay = !isTrading(today) && ymd(today).wd >= 1 && ymd(today).wd <= 5;
  const salesDay = DAY[ymd(nextTrading(today)).wd];
  const mk = (s: string) => x.market.find((m) => m.symbol === s);
  const weekPct = (m: Row | undefined) => (m && num(m.week_base) && num(m.price) ? (Number(m.price) / Number(m.week_base) - 1) * 100 : null);
  const owner: { key: string; spans?: Span[] }[] = [];   // what the open copy leaves out

  // ── Per name: the move that matters at this moment ──
  type NM = NameDay & { name: string; move: number; dayPL: number; st: number; fp: number | null; sd: number; pricedDay: number };
  const bn = new Map<string, Row>((B.names ?? []).map((n: Row) => [n.t, n]));
  const names: NM[] = x.names.map((n) => {
    const b = bn.get(n.t) ?? {};
    /* Build review item 11 (8 Nov 2026): a name's move reads the same quote as the rest of Home and the ticker chart a
       tile opens: market_live (Yahoo), as the index cards, sectors and Watchlist do. The day is against the last close
       (at the close after 4:00 PM); before the bell the pre-market or after-hours move; on the weekend the week, Friday's
       close against the Friday before, and the map says "Week". The book's own quotes stand in only for a name with no
       Yahoo row. Your names, What's moving and the Your book headline all read this one move. */
    const y = x.market.find((m) => m.symbol === n.t && m.kind === 'name') ?? mk(n.t);
    const day = num(y?.regular_change_pct) ?? (n.P0 > 0 ? (n.S0 / n.P0 - 1) * 100 : 0);
    const move = wk ? (weekPct(y) ?? (n.weekBase ? (n.S0 / n.weekBase - 1) * 100 : day)) : moment === 'pre' || moment === 'futures' ? (n.ext ?? 0) : day;
    const t = n.today, dayPL = t.sh + t.lp + t.oc + t.ip + t.sc + t.sp;
    return { ...n, name: company(n.t), move, dayPL, st: Number(b.st ?? 0), fp: b.fp ?? null, sd: Number(b.sd ?? 0),
      pricedDay: (Number(b.iv ?? 0) / Math.sqrt(252)) * 100 };
  });
  const held = names.length > 0;

  // ── The book's move: the account chart's lines (Sold = calls and puts sold; Long = shares, calls, puts bought) ──
  const G = x.chart?.groups ?? {}, days: string[] = x.chart?.days ?? [];
  const lineAt = (k: string, i: number) => Number(G[k]?.line?.[i] ?? 0);
  const idxOn = (d: string) => { let k = -1; for (let i = 0; i < days.length; i++) if (days[i] <= d) k = i; return k; };
  const split = (i0: number, i1: number) => {
    if (i0 < 0 || i1 < 0 || i1 <= i0) return null;
    const sold = ['cs', 'ps'].reduce((a, k) => a + lineAt(k, i1) - lineAt(k, i0), 0);
    const long = ['cb', 'pb', 'sh'].reduce((a, k) => a + lineAt(k, i1) - lineAt(k, i0), 0);
    return { sold, long, made: sold + long, sh: lineAt('sh', i1) - lineAt('sh', i0), cb: lineAt('cb', i1) - lineAt('cb', i0), pb: lineAt('pb', i1) - lineAt('pb', i0) };
  };
  const last = days.length - 1;
  const todayIdx = days[last] === today || (!isTrading(today) && days[last] === lastTrading(today)) ? last : -1;
  const sums = names.reduce((a, n) => ({ sold: a.sold + n.today.sc + n.today.sp, long: a.long + n.today.sh + n.today.lp + n.today.oc + n.today.ip,
    sh: a.sh + n.today.sh, cb: a.cb + n.today.lp + n.today.oc, pb: a.pb + n.today.ip }), { sold: 0, long: 0, sh: 0, cb: 0, pb: 0 });
  /* Today: the account chart's live point when it has one, else the names' own sums (same legs, marks vs the last close). */
  const bookToday = todayIdx > 0 ? split(todayIdx - 1, todayIdx) : held && (session || moment === 'post') ? { ...sums, made: sums.sold + sums.long } : null;
  const bookWeek = split(idxOn(addDays(monday, -1)), last);
  const pctOfBase = (v: number) => (x.baseNow > 0 ? (v / x.baseNow) * 100 : 0);
  const mostOf = (sign: number) => names.filter((n) => Math.sign(n.dayPL) === sign).sort((a, b) => Math.abs(b.dayPL) - Math.abs(a.dayPL))[0];

  // ── Market pieces ──
  const spy = mk('SPY'), iwm = mk('IWM');
  const spyDay = num(spy?.regular_change_pct) ?? 0, iwmDay = num(iwm?.regular_change_pct) ?? 0;
  const fut = (card: string) => x.futures.find((f) => f.card === card);
  const futPct = (card: string) => { const f = fut(card); return f && num(f.price) && num(f.base) ? (Number(f.price) / Number(f.base) - 1) * 100 : null; };
  const esPct = futPct('SPY');

  const secRows = x.sectors.filter((s) => s.etf), sec = (wkMode: boolean) => secRows.map((s) => ({
    sector: String(s.sector), etf: String(s.symbol),
    move: wkMode ? (num(s.week_base) && num(s.price) ? (Number(s.price) / Number(s.week_base) - 1) * 100 : null) : num(s.day_pct),
  })).filter((s) => s.move != null) as { sector: string; etf: string; move: number }[];
  const SHORT: Record<string, string> = { Technology: 'tech', Communication: 'communication', 'Consumer discretionary': 'consumer names',
    'Consumer staples': 'staples', 'Health care': 'health care', 'Real estate': 'real estate' };
  const short = (s: string) => SHORT[s] ?? lc(s);

  // ════ Cards ════
  const idxCard = (sym: string, label: string, price: number | null, move: number | null, extra: Row = {}, suffix = '') =>
    price == null || move == null ? null : { symbol: label, ...extra, price: label === 'VIX' ? price.toFixed(2) : `$${price.toFixed(2)}`,
      move: p1(move), moveColor: col(move), moveSigned: +move.toFixed(2), aria: `${label} ${upDown(move)} ${p1(move)}${suffix}` };
  const indexCards = () => {
    const pre = moment === 'pre';
    const cards = [['SPY', 'SPY'], ['QQQ', 'QQQ'], ['IWM', 'IWM'], ['^VIX', 'VIX']].map(([s, l]) => {
      const m = mk(s); if (!m) return null;
      if (pre && l !== 'VIX') {
        const f = fut(l), base = num(m.regular_price);
        const r = f && num(f.price) && num(f.base) ? Number(f.price) / Number(f.base) : null;
        return r && base ? idxCard(s, l, base * r, (r - 1) * 100) : null;
      }
      const move = moment === 'post' ? num(m.regular_change_pct) : num(m.regular_change_pct);
      return idxCard(s, l, num(moment === 'post' ? m.regular_price : m.price) ?? num(m.price), move);
    }).filter(Boolean);
    // In session the prices are "Live" only while fresh (Yahoo runs ~10 min behind; Nik allows 20); else their own time.
    const at = x.feeds?.marketAt, atNy = at ? nyClock(at) : null;
    // A price from before today's open counts from 9:30, so the bell's first minutes still read "Live".
    const since = atNy ? (atNy.date === today ? atNy.mins : 570) : 0;
    const late = session && x.feeds != null && (!atNy || mins - since > 20);
    const live = late ? (atNy ? `As of ${atNy.date === today ? '' : `${dmd(atNy.date)}, `}${hm(atNy.mins)}` : null) : 'Live';
    return cards.length ? { type: 'indexCards', cards, footer: pre ? 'Implied by futures · since the 4:00 PM close' : moment === 'post' ? 'At the 4:00 PM close' : live } : null;
  };
  const futuresCards = () => {
    const cards = [['SPY', 'ES'], ['QQQ', 'NQ'], ['IWM', 'RTY']].map(([l, b]) => {
      const f = fut(l), m = mk(l), base = num(m?.regular_price);
      const r = f && num(f.price) && num(f.base) ? Number(f.price) / Number(f.base) : null;
      return r && base ? idxCard(l, l, base * r, (r - 1) * 100, { badge: b, badgeStyle: 'yellow' }) : null;
    }).filter(Boolean);
    return cards.length ? { type: 'futuresCards', cards, footer: 'Implied by futures · since the 4:00 PM close' } : null;
  };
  const weekIndexes = () => {
    const cards = [['SPY', 'SPY'], ['QQQ', 'QQQ'], ['IWM', 'IWM'], ['^VIX', 'VIX']].map(([s, l]) => {
      const m = mk(s), w = weekPct(m);
      return m ? idxCard(s, l, num(m.regular_price) ?? num(m.price), w, {}, ' this week') : null;
    }).filter(Boolean);
    return cards.length ? { type: 'theWeekIndexes', cards, footer: `Week of ${md(monday)} to ${ymd(weekFri).d} · ${weekOpen ? 'so far' : 'at Friday’s close'}` } : null;
  };
  /* The design's overnight list, in its order. */
  const WORLD: [string, string, string][] = [['^N225', 'Nikkei', 'Japan'], ['^HSI', 'Hang Seng', 'Hong Kong'], ['000001.SS', 'Shanghai', 'China'],
    ['^GDAXI', 'DAX', 'Germany'], ['^TNX', '10y yield', 'US Treasury'], ['DX-Y.NYB', 'Dollar', 'Dollar index'], ['CL=F', 'Oil', 'WTI crude'],
    ['GC=F', 'Gold', 'Futures'], ['BTC-USD', 'Bitcoin', 'Trades 24/7']];
  const closedState = (s: string) => /CLOSED|POSTPOST|PREPRE/.test(s ?? '');
  /* Each world market's month line (Nik, 9 Nov 2026: trend lines on Overnight, one month): its daily closes over
     the last 31 days (market-tape keeps them, each dated in the market's own time zone), ending on the quote's own
     price, so today's move is the line's last step. A close for the quote's own session is left out (the quote is
     that day). Colour by the month's direction, as the move's. */
  const TZ: Record<string, string> = { '^N225': 'Asia/Tokyo', '^HSI': 'Asia/Hong_Kong', '000001.SS': 'Asia/Shanghai', '^GDAXI': 'Europe/Berlin', 'BTC-USD': 'UTC' };
  const dayIn = (tz: string, iso: string) => new Intl.DateTimeFormat('en-CA', { timeZone: tz, year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date(iso));
  const monthLine = (s: string, p: number, m: Row) => {
    const from = x.addDays(x.today, -31);
    const live = m.regular_time ? dayIn(TZ[s] ?? 'America/New_York', String(m.regular_time)) : x.today;
    const pts = (x.closes ?? []).filter((c) => c.ticker === s && String(c.date) >= from && String(c.date) < live)
      .map((c) => Number(c.close_price)).filter((v) => v > 0);
    pts.push(p);
    if (pts.length < 5) return null;
    const bp = s === '^TNX', chg = bp ? (p - pts[0]) * 100 : (p / pts[0] - 1) * 100;
    return { pts: pts.map((v) => Number(v.toPrecision(6))), color: col(chg), text: `${upDown(chg)} ${bp ? `${Math.abs(Math.round(chg))} bp` : p1(chg)} in a month` };
  };
  const worldRows = (wkMode: boolean) => WORLD.map(([s, name, sub]) => {
    const m = mk(s); if (!m || num(m.price) == null) return null;
    const p = Number(m.price);
    const yieldRow = s === '^TNX';
    let move: number | null, moveText: string;
    if (yieldRow) {
      const base = wkMode ? num(m.week_base) : num(m.prev_close);
      if (base == null) return null;
      move = (p - base) * 100; moveText = `${Math.abs(Math.round(move))} bp`;
    } else {
      move = wkMode ? weekPct(m) : num(m.regular_change_pct);
      if (move == null) return null;
      moveText = p1(move);
    }
    const value = yieldRow ? `${p.toFixed(2)}%` : ['CL=F', 'GC=F', 'BTC-USD'].includes(s) ? `$${p >= 1000 ? Math.round(p).toLocaleString('en-US') : p.toFixed(2)}`
      : p >= 1000 ? Math.round(p).toLocaleString('en-US') : p.toFixed(2);
    const status = s === 'BTC-USD' || !closedState(String(m.market_state)) ? 'still trading' : 'closed';
    const trend = monthLine(s, p, m);
    // ticker: the market's symbol, so a tap opens its chart (Nik 10 Nov 2026: "I also want charts on all these").
    return { name, sub, ticker: s, value, move: moveText, moveColor: col(move), status, ...(trend ? { trend } : {}),
      aria: `${name} ${value}, ${upDown(move)} ${moveText}, ${status}${trend ? `, ${trend.text}` : ''}` };
  }).filter(Boolean) as Row[];
  const overnight = () => {
    const rows = worldRows(false); if (!rows.length) return null;
    const asia = rows.filter((r) => ['Nikkei', 'Hang Seng', 'Shanghai'].includes(r.name)), eu = rows.find((r) => r.name === 'DAX');
    const subtitle = [asia.length ? (asia.every((r) => r.status === 'closed') ? 'Asia closed' : 'Asia trading') : '',
      eu ? (eu.status === 'closed' ? 'Europe closed' : 'Europe open') : ''].filter(Boolean).join(' · ');
    return { type: 'overnight', title: 'Overnight', subtitle, rows, footer: 'Each market’s last session' };
  };
  const worldThisWeek = () => {
    const rows = worldRows(true); if (!rows.length) return null;
    return { type: 'worldThisWeek', title: 'The world this week', subtitle: 'Mon to Fri', rows, footer: `Week of ${md(monday)} to ${ymd(weekFri).d} · local closes` };
  };
  // ── The economy (FRED, econ-sync): Worth watching by rule, new = landed since yesterday, the rest steady ──
  const nyDay = (iso: string) => new Date(iso).toLocaleDateString('en-CA', { timeZone: 'America/New_York' });
  const econ = [...(x.econ ?? [])].sort((a, b) => Number(a.ord) - Number(b.ord));
  const landed = (r: Row) => (r.landed_at ? nyDay(String(r.landed_at)) : '');
  const isNew = (r: Row) => landed(r) >= addDays(today, -1);
  const tagged = (r: Row): Row => ({ ...r.card, ...econRead(String(r.id), r.card ?? {}),
    ...(r.watch ? { tag: 'Worth watching', tagStyle: 'yellow' } : isNew(r) ? { tag: 'New since yesterday', tagStyle: 'plain' } : {}) });
  const econAll = [...econ.filter((r) => r.watch), ...econ.filter((r) => !r.watch && isNew(r)), ...econ.filter((r) => !r.watch && !isNew(r))].map(tagged);
  const economyCard = () => {
    if (!econ.length) return null;
    const nW = econ.filter((r) => r.watch).length, nN = econ.filter((r) => !r.watch && isNew(r)).length, steady = econ.length - nW - nN;
    const feat = econAll.slice(0, Math.max(3, Math.min(5, nW + nN)));
    return { type: 'economy', label: 'The economy', headline: nW ? `${nW} to watch` : 'Nothing to watch',
      sub: `${nN ? `${nN} new since yesterday · ` : ''}${steady} steady`,
      rows: feat.map((c) => ({ name: c.name, value: c.value, trend: c.trend, read: c.read, readTone: c.readTone, trendTone: c.trendTone })), indicators: feat,
      button: econ.length > feat.length ? `See the other ${econ.length - feat.length}` : null };
  };
  const outToday = () => {
    const rows = econ.filter((r) => landed(r) === today).map((r) => ({ ...r.card, ...econRead(String(r.id), r.card ?? {}), tag: 'Out today', tagStyle: 'plain' }));
    return rows.length ? { type: 'outToday', indicators: rows } : null;
  };

  const sectorsCard = (wkMode: boolean) => {
    const ss = sec(wkMode); if (ss.length < 2) return null;
    const by = [...ss].sort((a, b) => b.move - a.move), lead = by[0], trail = by[by.length - 1];
    const mapOf = (s: { sector: string; move: number }) => {
      const its = x.sectors.filter((r) => !r.etf && r.sector === s.sector && num(r.market_cap)).map((r) => {
        const mv = wkMode ? (num(r.week_base) && num(r.price) ? (Number(r.price) / Number(r.week_base) - 1) * 100 : null) : num(r.day_pct);
        return mv == null ? null : { ticker: String(r.symbol), name: String(r.name), move: mv, weight: Number(r.market_cap) / 1e9 };
      }).filter(Boolean) as { ticker: string; name: string; move: number; weight: number }[];
      /* The sector's share of the S&P 500 (SPY's holdings by sector, market-tape daily); left out when there is none. */
      const spw = num(x.sectors.find((r) => r.etf && r.sector === s.sector)?.sp_weight);
      const m = heatMap(s.sector, its, spw != null ? { weightOfSP500: `${Math.round(spw)}%` } : {}, wkMode ? 'Week' : '');
      return { ...m, move: p1(s.move), moveColor: col(s.move), moveSigned: +s.move.toFixed(2) };
    };
    const why = (s: { sector: string; move: number }) => x.sectors.filter((r) => !r.etf && r.sector === s.sector && num(r.market_cap))
      .map((r) => ({ name: String(r.name), c: Number(r.market_cap) * (wkMode ? (num(r.week_base) ? Number(r.price) / Number(r.week_base) - 1 : 0) : (num(r.day_pct) ?? 0) / 100) }))
      .filter((r) => Math.sign(r.c) === Math.sign(s.move)).sort((a, b) => Math.abs(b.c) - Math.abs(a.c)).slice(0, 2).map((r) => r.name);
    const on = (s: { sector: string; move: number }) => { const w = why(s); return w.length ? ` on ${w.join(' and ')}` : ''; };
    const up = ss.filter((s) => s.move > 0).length;
    const order = [lead, trail, ...by.filter((s) => s !== lead && s !== trail)];
    const past = wkMode || moment === 'post';
    return {
      type: 'sectors', label: 'Sectors', count: `${up} of ${ss.length} up${wkMode ? ' this week' : ''}`,
      writeUp: wkMode ? [`${lead.sector} led the week${on(lead)}.`, `${trail.sector} lagged${on(trail)}.`]
        : past ? [`${lead.sector} led${on(lead)}.`, `${trail.sector} trailed${on(trail)}.`]
        : [`${lead.sector} leads${on(lead)}.`, `${trail.sector} trails${on(trail)}.`],
      leadsTrails: [[wkMode ? 'Led the week' : past ? 'Led' : 'Leads', lead], [wkMode ? 'Lagged' : past ? 'Trailed' : 'Trails', trail]].map(([l, s]) => {
        const v = s as { sector: string; move: number };
        return { label: l, sector: v.sector, move: p1(v.move), moveColor: col(v.move), aria: `${l}: ${v.sector}, ${upDown(v.move)} ${p1(v.move)}. Show its map` };
      }),
      mapOrder: order.map((s) => s.sector), maps: order.map(mapOf),
      source: wkMode ? `Sector funds · week of ${md(monday)}` : 'Sector funds · Yahoo',
    };
  };
  const yourNames = () => {
    if (!held) return null;
    const pages: Row[] = [heatMap('Your names', names.map((n) => ({ ticker: n.t, name: n.name, move: n.move, weight: ((n.shares + n.leaps * 100) * n.S0) / 1000 })),
      { kind: 'yourNames', weightBasis: 'weight = (shares + LEAPS × 100) × price ÷ 1000, the tile area' }, wk ? 'Week' : '')];
    const ws = x.watch.map((w) => {
      const m = mk(String(w.ticker)); const cap = num(m?.market_cap);
      const mv = wk ? weekPct(m) : moment === 'pre' && num(m?.pre_change_pct) != null && String(m?.market_state).startsWith('PRE') ? num(m?.pre_change_pct) : num(w.ranges?.d);
      return cap && mv != null ? { ticker: String(w.ticker), name: company(String(w.ticker)), move: mv, weight: cap / 1e9 } : null;
    }).filter(Boolean) as { ticker: string; name: string; move: number; weight: number }[];
    if (ws.length) pages.push(heatMap('Watchlist', ws, { kind: 'watchlist', weightBasis: 'weight = market cap in $B' }, wk ? 'Week' : ''));
    return { type: 'yourNames', pages };
  };
  const whatsMoving = () => {
    if (!held) return null;
    const rows = names.map((n) => {
      const past = n.pricedDay > 0 && Math.abs(n.move) > n.pricedDay;
      return { ticker: n.t, move: `${n.move < 0 ? '↓' : '↑'} ${p1(n.move)}`, moveColor: past ? col(n.move) : 'ink', pastPricedMove: past,
        movePct: +n.move.toFixed(2), pricedPct: +n.pricedDay.toFixed(2) };
    });
    const lead = [...names].sort((a, b) => (Math.abs(b.move) / (b.pricedDay || 1)) - (Math.abs(a.move) / (a.pricedDay || 1)))[0];
    const past = lead.pricedDay > 0 && Math.abs(lead.move) > lead.pricedDay;
    const sold = lead.soldCalls.filter((c) => c.ex <= F).reduce((a, c) => a + c.n, 0);
    const parts: string[] = [];
    if (lead.today.sh) parts.push(`Your ${lead.shares.toLocaleString('en-US')} shares are ${upDown(lead.today.sh)} ${fK(lead.today.sh)}`);
    if (lead.today.lp) parts.push(`the LEAPS ${upDown(lead.today.lp)} ${fK(lead.today.lp)}`);
    const body = `${lead.move < 0 ? 'Down' : 'Up'} ${p1(lead.move)} so far, priced for ${p1(lead.pricedDay)} today. `
      + (sold ? `${sold} calls sold on it this week.` : 'No calls sold on it this week.') + (parts.length ? ` ${parts.join(', ')} so far.` : '');
    return { type: 'whatsMoving', title: 'What’s moving', subtitle: past ? `${lead.name} is past the move priced for today` : 'Every name is inside the move priced for today',
      body, rows, axis: ['↓ 5%', 'Flat', '↑ 5%'], legend: 'Priced for today by each name’s options' };
  };
  const yourPosition = () => (B.position ? { type: 'yourPosition', subtitle: B.position.subtitle } : { type: 'yourPosition', empty: true, subtitle: 'Nothing held yet' });

  // To decide: the names that turn short by Friday first, then a sold call that needs a look.
  const shorts = [...names].filter((n) => n.st === 2).sort((a, b) => (a.fp ?? 1e9) / a.S0 - (b.fp ?? 1e9) / b.S0);
  const legsTV: Row[] = B.timeValue?.legs ?? [];
  const look = legsTV.filter((l) => !l.put && l.ready && l.ex <= F).sort((a, b) => b.cap - a.cap)[0];
  const toDecide = () => {
    if (!shorts.length && !look) return null;
    const dleft = (ex: string) => Math.max(0, [...Array(Math.max(0, dayDiff(today, ex)) + 1).keys()].filter((k) => isTrading(addDays(today, k)) && (k > 0 || mins < closeMin)).length);
    if (look) {
      const itm = look.itm;
      return { type: 'toDecide', title: 'To decide · needs a look',
        subtitle: itm ? `${company(look.t)}’s ${look.K} calls are in the money with ${dleft(look.ex)} days left` : `${company(look.t)} is ${look.cap}% kept with ${dleft(look.ex)} days left`,
        body: itm ? 'Roll them or let them go?' : 'Close early and sell next week’s calls now?',
        footer: [sp(`${fK(look.left)} left to earn on ${look.q} calls, ${fK(look.kept)} kept.`, true)] };
    }
    const n = shorts[0];
    return { type: 'toDecide', title: 'To decide · near its best', subtitle: `${n.name} makes the most at $${n.fp!.toFixed(2)} by Friday`,
      body: `A priced move is ${p1(n.sd)} by Friday. Roll the calls or add before then?` };
  };

  // Coming up: what is dated ahead, from the calendar, the macro feed, the expiries, earnings and dividends.
  const soldLegs = legsTV;
  type Dated = { d: string; logo?: string; text: Span[]; time?: string; owner?: boolean };
  const dated = (from: string, to: string): Dated[] => {
    const out: Dated[] = [];
    for (const m of x.macro) { const d = String(m.event_date); if (d >= from && d <= to && !/holiday/i.test(String(m.category ?? ''))) out.push({ d, text: [sp(`${String(m.name).replace(/ \(.*\)$/, '')}${m.event_time ? `, ${tm(m.event_time)}` : ''}`, true)] }); }
    for (const c of x.cal) { const d = String(c.date); if (d >= from && d <= to) out.push({ d, text: [sp(c.kind === 'closed' ? `Closed for ${c.name}` : `Closes early, at ${tm(c.closes)}`, true)] }); }
    const exps = new Map<string, number>();
    for (const l of soldLegs) if (l.ex >= from && l.ex <= to) exps.set(l.ex, (exps.get(l.ex) ?? 0) + 1);
    for (const [d, n] of exps) out.push({ d, text: [sp(`${n} ${n === 1 ? 'sale expires' : 'sales expire'}`, true)] });
    for (const e of x.earnings) { const d = String(e.date); if (d >= from && d <= to) out.push({ d, logo: e.ticker, text: [sp(`${company(e.ticker)} reports${e.estimated ? ', date not confirmed' : ''}`, true)] }); }
    for (const v of x.divs) {
      const d = String(v.ex_date), t = String(v.ticker).toUpperCase(), n = names.find((y) => y.t === t);
      if (d >= from && d <= to && n && n.shares > 0) out.push({ d, logo: t, text: [sp(`${n.name} goes ex-dividend `, true), sp(`· $${Number(v.cash_amount).toFixed(2)} a share, ${fK(n.shares * Number(v.cash_amount))}`, false, 'secondary')] });
    }
    return out.sort((a, b) => a.d.localeCompare(b.d));
  };
  const comingRows = (from: string, to: string, max = 8) => dated(from, to).slice(0, max).map((r) => ({ date: dmd(r.d), ...(r.logo ? { logo: r.logo } : {}), text: r.text }));
  const thuAhead = ymd(today).wd >= 1 && ymd(today).wd <= 3 && soldLegs.some((l) => l.ex === F);
  const comingLine = () => {
    const bits: string[] = [];
    if (moment === 'post') {
      const tmw = nextTrading(today), m = x.macro.find((e) => String(e.event_date) === tmw && !/holiday/i.test(String(e.category ?? '')));
      if (m) bits.push(`${String(m.name).replace(/ \(.*\)$/, '')} tomorrow${m.event_time ? ` at ${tm(m.event_time)}` : ''}.`);
    }
    const n = soldLegs.filter((l) => l.ex === F).length;
    if (n) bits.push(`${DAY[ymd(F).wd]} ${n} ${n === 1 ? 'sale expires' : 'sales expire'}.`);
    if (thuAhead) bits.push('Thursday is roll day.');
    return bits.length ? { type: 'comingUp', title: 'Coming up', line: [sp(bits.join(' '))] } : null;
  };

  const nextEarn = x.earnings.filter((e) => String(e.date) >= today).sort((a, b) => String(a.date).localeCompare(String(b.date)))[0];
  const earningsAhead = (within: number) => {
    if (!nextEarn) return null;
    const dd = dayDiff(today, String(nextEarn.date)); if (dd > within || dd < 0) return null;
    const t = String(nextEarn.ticker), n = names.find((y) => y.t === t);
    const when = nextEarn.time === 'bmo' ? 'before the open' : nextEarn.time === 'amc' ? 'after the close' : '';
    const before = (n?.soldCalls ?? []).filter((c) => c.ex < String(nextEarn.date)).reduce((a, c) => a + c.n, 0);
    const span = (n?.soldCalls ?? []).filter((c) => c.ex >= String(nextEarn.date)).reduce((a, c) => a + c.n, 0);
    const you = before ? `Your ${before} calls expire before the report.${span ? ` ${span} more span it.` : ''}` : span ? `Your ${span} calls span the report.` : 'No calls sold across the report yet.';
    return { type: 'earningsAhead', title: `Earnings ahead · ${dd} ${dd === 1 ? 'day' : 'days'} out`,
      subtitle: `${company(t)} reports ${DAY[ymd(String(nextEarn.date)).wd]}${when ? `, ${when}` : ''}`, logo: t, name: company(t),
      when: `${dmd(String(nextEarn.date))}${when ? ` · ${when}` : ''}${nextEarn.estimated ? ' · date not confirmed' : ''}`,
      stats: num(nextEarn.priced_move_pct) ? [{ label: 'Priced move', value: p1(Number(nextEarn.priced_move_pct)) }] : [],
      notes: [{ label: 'You', text: you }], source: 'Earnings dates · Nasdaq' };
  };

  // Results: kept (by expiry week, the yield rule), Long and Made from the account chart's lines.
  const yw = (fri: string) => x.yieldWeeks.find((w) => w.fri === fri || w.week === mondayOf(fri));
  /* Nik 9 Nov: kept counts CLOSED contracts only (expired, assigned or bought back); the credit on ones still open
     is shown apart as "still open" and joins kept as they close. Past weeks have nothing open, so they are unchanged. */
  const openOf = (w: Row | undefined) => (w ? Number(w.calls_open ?? 0) + Number(w.puts_open ?? 0) : 0);
  const keptOf = (w: Row | undefined) => (w ? w.calls_sold - w.calls_back + w.puts_sold - w.puts_back - openOf(w) : 0);
  const soldOf = (w: Row | undefined) => (w ? w.calls_sold + w.puts_sold - openOf(w) : 0);
  const divNext = () => {
    if (stopped.has('dividends')) return null;      // no dividends feed: no line, never "None ahead"
    const v = x.divs.map((d) => ({ d, n: names.find((y) => y.t === String(d.ticker).toUpperCase()) })).filter((r) => r.n && r.n.shares > 0)
      .sort((a, b) => String(a.d.ex_date).localeCompare(String(b.d.ex_date)))[0];
    return v ? [sp(`Next: ${v.n!.name}, ex ${dmd(String(v.d.ex_date))}, ${fK(v.n!.shares * Number(v.d.cash_amount))} · kept out of Made`, false, 'secondary')]
      : [sp('None ahead in the next 45 days · kept out of Made', false, 'secondary')];
  };
  const paidIn = (from: string, to: string) => ((x.chart?.dividends?.paid ?? []) as [string, number][]).filter(([d]) => d >= from && d <= to).reduce((a, [, v]) => a + Number(v), 0);
  const yieldBars = (n = 5) => {
    const fris: string[] = []; let f = weekFri;
    for (let k = 0; k < n; k++) { fris.unshift(f); f = lastTrading(addDays(mondayOf(f), -3)); }
    return fris.map((fr) => { const w = yw(fr), base = x.baseAt(fr), v = base > 0 ? (keptOf(w) / base) * 100 : 0, me = fr === weekFri;
      return { label: me ? 'This week' : md(mondayOf(fr)), value: py(v), signed: +v.toFixed(2), highlight: me, valueColor: v < 0 ? 'red' : me ? 'green' : 'ink' }; });
  };
  const stat = (label: string, v: number, sub: string) => ({ label, value: fK(v), valueColor: col(v), sub });
  const resultsWeek = () => {
    const w = yw(weekFri), kept = keptOf(w), sold = soldOf(w), open = openOf(w), base = x.baseAt(weekFri), long = bookWeek?.long ?? 0;
    return { kept, sold, open, base, long, made: kept + long, yieldPct: base > 0 ? (kept / base) * 100 : 0 };
  };
  const weekFacts = () => {
    const tr = x.trades.filter((t) => String(t.trade_date) >= monday && String(t.trade_date) <= today && t.option_type === 'call' && t.direction === 'short' && t.action === 'close');
    const exp = tr.filter((t) => /Ep lifecycle/.test(String(t.note ?? ''))).length, asg = tr.filter((t) => t.closed_via === 'assigned' || /\bA lifecycle/.test(String(t.note ?? ''))).length;
    const early = [...new Set(tr.filter((t) => !/lifecycle/.test(String(t.note ?? '')) && t.closed_via !== 'assigned').map((t) => company(String(t.ticker).toUpperCase())))];
    const bits: string[] = [];
    if (exp) bits.push(`${word(exp).toLowerCase()} expired`);
    if (asg) bits.push(`${word(asg).toLowerCase()} assigned`);
    if (early.length) bits.push(`${early.join(', ')} closed early`);
    const g = bookWeek;
    const legs = g ? `Shares ${upDown(g.sh)} ${fK(g.sh)}, calls bought ${upDown(g.cb)} ${fK(g.cb)}, insurance ${upDown(g.pb)} ${fK(g.pb)}.` : '';
    return `${bits.length ? `Calls: ${bits.join(', ')}. ` : ''}${legs}`.trim();
  };
  const results = () => {
    const r = resultsWeek(), mStart = `${today.slice(0, 7)}-01`, mName = MONTH[ymd(today).m - 1];
    const fris = x.yieldWeeks.filter((w) => String(w.fri).slice(0, 7) === today.slice(0, 7) && w.fri <= weekFri);
    const mKept = fris.reduce((a, w) => a + keptOf(w), 0), mBase = x.baseAt(weekFri);
    const mSplit = split(idxOn(addDays(mStart, -1)), last), mLong = mSplit?.long ?? 0;
    const groups = fris.map((w) => {
      const s = split(idxOn(addDays(String(w.week), -1)), idxOn(String(w.fri)));
      // `n`: the signed dollars behind each label, so the app draws the bar above or below the zero line (the label stays unsigned).
      return { label: md(String(w.week)), highlight: w.fri === weekFri, values: [{ series: 'Sold, kept', value: fK(keptOf(w)), valueColor: 'ink', n: Math.round(keptOf(w)) },
        { series: 'Long', value: fK(s?.long ?? 0), valueColor: col(s?.long ?? 0), n: Math.round(s?.long ?? 0) }] };
    });
    const last4 = yieldBars(4).map((b) => b.signed), pace = last4.reduce((a, b) => a + b, 0) / Math.max(1, last4.length);
    return { type: 'results', title: 'Results', segments: ['This week', mName], selected: 'This week', bySegment: {
      'This week': { big: fK(r.kept), bigColor: col(r.kept), bigSub: r.kept >= 0 ? `kept of ${fK(r.sold)} ${r.open ? `closed · ${fK(r.open)} still open` : 'sold'} · ${py(r.yieldPct)} yield on ${fK(r.base)} bought`
          : `bought back more than the ${fK(r.sold)} sold · ${py(r.yieldPct)} given back on ${fK(r.base)} bought`,
        stats: [stat('Sold · kept', r.kept, 'realized'), stat('Long', r.long, 'unrealized'), stat('Made', r.made, 'the week')],
        body: weekFacts(), dividends: { title: 'Dividends', line: divNext(), right: paidIn(monday, today) ? fK(paidIn(monday, today)) : 'None this week', rightColor: paidIn(monday, today) ? 'green' : 'secondary' },
        charts: [{ title: 'Yield, week by week', sub: `on ${fK(r.base)} bought`, bars: yieldBars() }] },
      [mName]: { big: p1(mBase > 0 ? (mKept / mBase) * 100 : 0), bigColor: col(mKept), bigSub: `${mKept >= 0 ? 'yield' : 'given back'} in ${mName} on ${fK(mBase)} bought`,
        charts: [{ title: pace >= 0 ? `${Math.round(pace * 52)}% a year at the 4-week pace` : `Giving back ${Math.round(-pace * 52)}% a year at the 4-week pace`, legend: ['Sold, kept', 'Long'], groups }],
        stats: [stat('Sold · kept', mKept, 'realized'), stat('Long', mLong, 'unrealized'), stat('Made', mKept + mLong, mName)],
        dividends: { title: 'Dividends', line: divNext(), right: paidIn(mStart, today) ? fK(paidIn(mStart, today)) : 'None', rightColor: paidIn(mStart, today) ? 'green' : 'secondary' } },
    } };
  };
  const yourResults = () => {
    const t = bookToday; if (!t) return null;
    const r = resultsWeek(), lead = mostOf(Math.sign(t.made) || -1);
    const kind = lead ? (Math.abs(lead.today.sh) >= Math.abs(lead.today.lp) ? 'shares' : 'LEAPS') : '';
    const body = lead ? `${lead.name}’s ${kind} ${t.made < 0 ? 'did most of the damage' : 'did most of the work'}.${t.sold > 0 ? ' Your sales kept working.' : ''}` : '';
    return { type: 'yourResults', title: 'Your results', segments: ['Today', 'This week'], selected: 'Today', bySegment: {
      Today: { stats: [stat('Sold · kept', t.sold, 'today'), stat('Long', t.long, 'unrealized'), stat('Made', t.made, 'today')], body,
        dividends: { title: 'Dividends', line: divNext(), right: paidIn(today, today) ? fK(paidIn(today, today)) : 'None today', rightColor: paidIn(today, today) ? 'green' : 'secondary' } },
      'This week': { stats: [stat('Sold · kept', r.kept, r.open ? `${fK(r.open)} still open` : `of ${fK(r.sold)}`), stat('Long', r.long, 'unrealized'), stat('Made', r.made, 'so far')],
        dividends: { title: 'Dividends', line: divNext(), right: paidIn(monday, today) ? fK(paidIn(monday, today)) : 'None this week', rightColor: paidIn(monday, today) ? 'green' : 'secondary' },
        charts: [{ title: 'Yield, week by week', sub: `on ${fK(r.base)} bought`, bars: yieldBars() }] },
    } };
  };
  const closedRolled = () => {
    const tr = x.trades.filter((t) => String(t.trade_date) === today && !/lifecycle/.test(String(t.note ?? '')));
    const closes = tr.filter((t) => t.action === 'close'); if (!closes.length) return null;
    const T = (t: Row) => String(t.ticker).toUpperCase(), at = (t: Row) => String(t.executed_at ?? t.trade_date ?? '');
    const legKey = (t: Row) => `${T(t)}|${t.option_type}|${t.direction}|${Number(t.strike)}|${t.expiry}`;
    /* Cash in or out of one fill, fees included (IBKR's net_cash): + for a sale, - for a buy. */
    const cash = (t: Row) => num(t.net_cash)
      ?? (((t.action === 'open') === (t.direction === 'short') ? 1 : -1) * Number(t.contracts) * Number(t.premium) * 100 + (num(t.commission) ?? 0));
    /* What each close made: IBKR's realized_pl once its next-morning report has it; until then the same sum IBKR
       makes, the matched opens' cash (FIFO) plus the close's own cash (equal to the cent on 6 Nov's closes). */
    const made = new Map<Row, number>(), legs = new Map<string, Row[]>();
    for (const t of x.trades) { if (t.voided_at) continue; const k = legKey(t); (legs.get(k) ?? legs.set(k, []).get(k)!).push(t); }
    for (const k of new Set(closes.map(legKey))) {
      const all = (legs.get(k) ?? []).slice().sort((u, v) => at(u).localeCompare(at(v)));
      const pool = all.filter((t) => t.action === 'open').map((o) => ({ o, n: Number(o.contracts) }));
      for (const c of all.filter((t) => t.action === 'close')) {
        let need = Number(c.contracts), from = 0;
        for (const s of pool) {
          if (need <= 0) break;
          const take = Math.min(need, s.n);
          if (take > 0) { from += (cash(s.o) * take) / Number(s.o.contracts); s.n -= take; need -= take; }
        }
        made.set(c, num(c.realized_pl) ?? from + cash(c));
      }
    }
    /* Nik 9 Nov: one line per strike, however many pieces IBKR filled it in; "$31 calls" so the strike never
       reads as a count. */
    const byLeg = new Map<string, Row[]>();
    for (const c of closes.slice().sort((u, v) => at(u).localeCompare(at(v)))) { const k = legKey(c); (byLeg.get(k) ?? byLeg.set(k, []).get(k)!).push(c); }
    const usd = (k: number) => `$${Number.isInteger(k) ? k : k.toFixed(2)}`;
    const rows = [...byLeg.values()].map((g) => {
      const c = g[0], t = T(c), n = g.reduce((a, r) => a + Number(r.contracts), 0);
      const opened = tr.find((o) => o.action === 'open' && T(o) === t && o.option_type === c.option_type && o.direction === c.direction);
      const kind = c.direction === 'short' ? (c.option_type === 'call' ? 'calls' : 'puts') : c.option_type === 'call' ? 'calls bought' : 'insurance puts';
      const unit = c.option_type === 'call' ? (n === 1 ? 'call' : 'calls') : n === 1 ? 'put' : 'puts';
      const pl = g.reduce((a, r) => a + (made.get(r) ?? 0), 0), e = c.executed_at ? new Date(String(c.executed_at)) : null;
      const when = e ? hm(Number(e.toLocaleString('en-US', { timeZone: 'America/New_York', hour: 'numeric', hourCycle: 'h23' })) * 60
        + Number(e.toLocaleString('en-US', { timeZone: 'America/New_York', minute: 'numeric' }))) : '';
      return { logo: t, title: `${company(t)} ${usd(Number(c.strike))} ${kind}, ${opened ? 'rolled' : c.direction === 'short' ? 'bought back' : 'sold'}`,
        sub: `${n} ${unit} · ${md(String(c.expiry))} expiry${opened ? ` · for ${md(String(opened.expiry))} ${usd(Number(opened.strike))}s` : ''}${when ? ` · ${when}` : ''}`,
        value: fK(pl), valueColor: col(pl), valueLabel: pl < 0 ? 'lost' : 'made' };
    });
    const rolls = rows.filter((r) => r.title.endsWith('rolled')).length;
    return { type: 'closedRolled', title: 'Closed and rolled today',
      subtitle: `${word(rows.length - rolls)} ${rows.length - rolls === 1 ? 'close' : 'closes'}${rolls ? `, ${word(rolls).toLowerCase()} ${rolls === 1 ? 'roll' : 'rolls'}` : ''}.`.replace(/^No closes, /, ''),
      footer: 'Fills from IBKR', rows };
  };
  const tomorrowOrders = () => {
    if (!x.orders.length) return null;
    const cin = x.orders.filter((o) => o.credit).reduce((a, o) => a + Number(o.cost ?? 0), 0), cout = x.orders.filter((o) => !o.credit).reduce((a, o) => a + Number(o.cost ?? 0), 0);
    return { type: 'tomorrowOrders', title: 'Tomorrow’s orders', count: `${x.orders.length} ${x.orders.length === 1 ? 'order' : 'orders'}`,
      subtitle: `Place at the open · ${fK(cin)} in, ${fK(cout)} out`, footer: 'Each one clears once IBKR shows the fill.',
      rows: x.orders.map((o) => ({ logo: o.t, order: String(o.action ?? o.act), why: String(o.why ?? ''), amount: fK(Number(o.cost ?? 0)), amountLabel: o.credit ? 'credit' : 'cost' })) };
  };
  const thetaMonth = () => {
    const H = x.history?.theta, hd: string[] = x.history?.days ?? [];
    if (!H || !hd.length) return null;
    const weeks: { m: string; c: number; p: number }[] = [];
    hd.forEach((d, i) => { const m = mondayOf(d); let w = weeks.find((y) => y.m === m); if (!w) { w = { m, c: 0, p: 0 }; weeks.push(w); } w.c += Number(H.short?.[i] ?? 0); w.p += Number(H.long?.[i] ?? 0); });
    const ws = weeks.slice(-5).filter((w) => w.p > 0); if (ws.length < 2) return null;
    const r = (w: { c: number; p: number }) => w.c / w.p, a = ws[ws.length - 1], b = ws[ws.length - 2];
    const trend = r(a) > r(b) * 1.05 ? 'stronger' : r(a) < r(b) * 0.95 ? 'weaker' : 'steady';
    return { type: 'thetaMonth', title: `Theta · ${MONTH[ymd(today).m - 1]}`, subtitle: `Collected ${r(a).toFixed(1)}× what you paid, ${trend}`,
      legend: ['Collected', 'Paid in decay'],
      weeks: ws.map((w) => ({ label: w.m === monday ? 'This week' : md(w.m), ratio: `${r(w).toFixed(1)}×`, highlight: w.m === monday })),
      body: `Paying went from ${fK(ws[0].p)} to ${fK(a.p)} a week and collecting ${a.c >= ws[0].c ? 'kept up' : 'fell behind'}.` };
  };
  const payback = () => {
    const P = x.payback; if (!P || !(x.baseNow > 0)) return null;
    const made = Number(P.made ?? 0), base = x.baseNow, pct = (made / base) * 100, left = base - made;
    const when = (pace: number | null) => (pace && pace > 0 ? (() => { const d = new Date(Date.parse(today + 'T12:00:00Z') + (left / pace) * 7 * 864e5); return `${MON[d.getUTCMonth()]} ${d.getUTCFullYear()}`; })() : 'Not at this pace');
    const pr = num(P.pace_recent), ps = num(P.pace_start);
    const months: { m: string; v: number }[] = [];
    for (const [d, , v] of (P.series2 ?? []) as [string, number, number][]) { const m = d.slice(0, 7); const e = months.find((y) => y.m === m); if (e) e.v = v; else months.push({ m, v }); }
    const bars = months.slice(-5).map((e, i, a) => { const prev = i ? a[i - 1].v : (months[months.length - a.length - 1]?.v ?? 0), v = e.v - prev, me = e.m === today.slice(0, 7);
      /* n: the signed amount, so a month that lost draws its bar red (the label stays without a minus sign). */
      return { label: MON[Number(e.m.slice(5)) - 1], value: fK(v), n: Math.round(v), highlight: me, valueColor: me ? col(v) : v < 0 ? 'red' : 'ink', empty: false }; });
    const whenA = when(pr), whenB = when(ps);
    return { type: 'payback', title: 'Payback · month end'.replace('month end', today.slice(8) >= '25' ? 'month end' : 'so far'),
      subtitle: pr && pr > 0 && ps && ps > 0 ? `Paid back between ${[whenA, whenB].sort((u, v) => Date.parse('1 ' + u) - Date.parse('1 ' + v)).join(' and ')}` : 'Not paid back at the recent pace',
      big: p1(pct), bigColor: col(pct), bigSub: `of ${fK(base)} in shares, LEAPS and calls made back, after closing costs and insurance`,
      chart: { title: 'Made each month', bars },
      rows: [{ label: pr != null ? `At the 4-week pace, ${pr < 0 ? 'losing ' : ''}${fK(pr)} a week` : 'At the 4-week pace', value: whenA, valueColor: pr && pr > 0 ? 'ink' : 'red' },
        { label: ps != null ? `Since you started, ${ps < 0 ? 'losing ' : ''}${fK(ps)} a week` : 'Since you started', value: whenB, valueColor: ps && ps > 0 ? 'ink' : 'red' }],
      footer: 'Payback isn’t profit until what you bought holds its value. Dividends stay out of it.' };
  };
  const remember = () => {
    const nw = nextTrading(weekFri), nm = weekOpen ? nextTrading(today) : nw, to = addDays(mondayOf(nw), 4), rows = comingRows(nm, to, 6);
    const sells = x.orders.filter((o) => o.kind === 'sell' || o.kind === 'put').length;
    const later = x.earnings.filter((e) => String(e.date) > to && dayDiff(today, String(e.date)) <= 30)
      .map((e) => ({ date: dmd(String(e.date)), logo: e.ticker, text: [sp(`${company(e.ticker)} reports, inside 30 days`, true)] }));
    const all = [...(sells ? [{ date: dmd(nm), text: [sp(`${word(sells)} ${sells === 1 ? 'sale' : 'sales'} to place`, true)], owner: true }] : []), ...rows, ...later];
    return all.length ? { type: 'remember', title: weekOpen ? 'Coming up' : 'Remember for next week', rows: all } : null;
  };

  // ════ The deck: Aftershock, Earnings season, Holiday ════
  const holiday = (() => {
    const wkStart = wk ? nextTrading(today) : monday, from = mondayOf(wkStart), to = addDays(from, 4);
    // Today's own closure first (Good Friday sits outside next week's range), then this week's.
    const closed = x.cal.find((c) => c.kind === 'closed' && String(c.date) === today)
      ?? x.cal.find((c) => c.kind === 'closed' && String(c.date) >= from && String(c.date) <= to && String(c.date) >= today);
    const ec = x.cal.find((c) => c.kind === 'early_close' && String(c.date) >= from && String(c.date) <= to && String(c.date) >= today);
    if (ec && String(ec.date) === today) return { kind: 'holiday', kicker: `Early close · ${dmd(today)}`, title: `Closes at ${tm(ec.closes)} today`, sub: `Stock options stop at ${tm(ec.closes)} too`, mark: String(ymd(today).d), today: true };
    if (closed) return { kind: 'holiday', kicker: `Holiday · ${dmd(String(closed.date))}`, title: `Closed for ${closed.name}`,
      sub: ec ? `${DAY[ymd(String(ec.date)).wd]} closes early, at ${tm(ec.closes)}` : 'Markets closed all day', mark: String(ymd(String(closed.date)).d),
      ...(String(closed.date) === today ? { today: true } : {}) };
    return null;
  })();
  const season = (() => {
    const ahead = x.earnings.filter((e) => String(e.date) >= today).sort((a, b) => String(a.date).localeCompare(String(b.date)));
    if (!ahead.length || dayDiff(today, String(ahead[0].date)) > 14) return null;
    return { kind: 'earningsSeason', kicker: 'Earnings season', title: `${word(ahead.length)} ${ahead.length === 1 ? 'name' : 'names'} still to report`,
      sub: ahead.slice(0, 3).map((e) => `${company(e.ticker)} ${md(String(e.date))}`).join(' · '), mark: MON[ymd(String(ahead[0].date)).m - 1] };
  })();
  const after = (() => {
    const A = x.aftershock; if (!A) return null;
    const scan = (A.scans ?? [])[0], ev = (A.events ?? []).filter((e: Row) => e.day === scan?.day);
    const d2 = (A.events ?? []).filter((e: Row) => e.day2 === today);
    const list = (es: Row[]) => es.slice(0, 2).map((e) => `${e.ticker} ${p1(Number(e.drop_pct))}`).join(' · ');
    return { kind: 'aftershock', kicker: 'Aftershock', title: null, sub: null, arrow: '→', states: {
      wait: ['Scan at 4:15', d2.length ? `Day 2 · ${d2.slice(0, 2).map((e: Row) => e.ticker).join(', ')}` : `${A.universe ?? 0} names after the close`],
      soon: ['Scan in {mm:ss}', `${A.universe ?? 0} names after the close`],
      scan: [`{n} of ${A.universe ?? 0}`, 'Scanning for drops of 15% or more'],
      done: scan?.day === today && ev.length ? [`${word(ev.length)} ${ev.length === 1 ? 'crash' : 'crashes'}`, list(ev)] : ['All clear', 'No crashes · next scan tomorrow 4:15 PM'],
    } };
  })();
  const deckCards = [holiday, ['pre', 'last20', 'last5', 'post'].includes(moment) ? after : season].filter(Boolean) as Row[];
  if (!['pre', 'last20', 'last5', 'post'].includes(moment) && season && !deckCards.includes(season)) deckCards.push(season);
  const alert = holiday?.today ? holiday : holiday && (wk || moment === 'futures') ? holiday : deckCards.find((c) => c !== holiday) ?? holiday ?? null;

  // ════ Title, date line, day caption ════
  const TITLE: Record<Moment, string> = { futures: 'Overnight Summary', pre: 'Pre-market Summary', bell: 'Market Hours', open: 'Market Hours', last20: 'Market Hours', last5: 'Market Hours', post: 'Post-market Summary', weekend: 'Week in Review' };
  const STATE: Record<Moment, string> = { futures: 'futures trading since 6:00 PM', pre: 'before the bell', bell: 'the market is open', open: 'the market is open', last20: 'the market is open', last5: 'the market is open', post: 'after the close', weekend: 'markets closed' };
  const t = ymd(today);
  const dateLine = `${DAY[t.wd]}, ${MON[t.m - 1]} ${t.d} · ${!isTrading(today) && !wk && t.wd >= 1 && t.wd <= 5 ? 'markets closed' : STATE[moment]}`;
  const left = (to: number) => { const m = Math.max(0, to - mins); return m >= 60 ? `${Math.floor(m / 60)}h ${m % 60}m` : `${m}m`; };
  const cap = moment === 'futures' ? ['Pre-market', 'Futures trading since 6:00 PM'] : moment === 'pre' ? ['Pre-market', `Opens in ${left(570)}`]
    : moment === 'bell' ? ['Market hours', 'The bell just rang'] : session ? ['Market hours', `Closes in ${left(closeMin)}`]
    : moment === 'post' ? ['Post-market', 'After hours until 8:00 PM']
    : closedDay ? ['Markets closed', `Opens ${salesDay} at 9:30 AM`] : ['Week in Review', `The week of ${md(monday)} to ${ymd(weekFri).d}`];
  const dayCaption = { session: cap[0], caption: cap[1], text: `${cap[0]} · ${cap[1]}`, clock: hm(mins), orange: moment === 'last20' || moment === 'last5',
    aria: `Time of day, ${hm(mins)}, ${cap[0]}` };

  // ════ Ledes and headlines (README 5.4) ════
  const orders = x.orders.length;
  const ordersLine = orders ? `${word(orders)} ${orders === 1 ? 'order' : 'orders'} to place at the open.` : 'Nothing to place at the open.';
  const decisions = shorts.length;
  const decLine = decisions ? `${word(decisions)} ${decisions === 1 ? 'call' : 'calls'} to make before Friday.` : 'Nothing to decide before Friday.';
  const money = (v: number, privacy: boolean) => (privacy ? p1(pctOfBase(v)) : fK(v));
  let lede: Span[] = [], ledeP: Span[] = [];
  const both = (f: (p: boolean) => Span[]) => { lede = f(false); ledeP = f(true); };
  if (moment === 'pre') {
    const nDown = names.filter((n) => n.move < 0).length, nUp = names.filter((n) => n.move > 0).length, fu = esPct ?? 0;
    const follow = fu >= 0 ? nUp >= nDown : nDown >= nUp;
    const word2 = follow === (fu >= 0) ? 'up' : 'down', cnt = word2 === 'up' ? nUp : nDown;
    // No orders line (11 Nov 2026: To do removed).
    both(() => [sp('Futures are '), sp(fu >= 0 ? 'up' : 'down', true, col(fu)), sp(held ? `, your names ${follow ? 'are' : 'aren’t'}: ${cnt} of ${names.length} are ${word2} before the bell.` : '.')]);
    if (held) owner.push({ key: 'lede' });
  } else if (moment === 'futures') {
    const asia = ['^N225', '^HSI', '000001.SS'].map((s) => num(mk(s)?.regular_change_pct)).filter((v) => v != null) as number[];
    const a = asia.length ? asia.reduce((u, v) => u + v, 0) / asia.length : null, dax = mk('^GDAXI');
    const daxOpen = dax && !closedState(String(dax.market_state));
    both(() => [sp('Futures point '), sp((esPct ?? 0) >= 0 ? 'higher' : 'lower', true, col(esPct ?? 0)), sp(' overnight'),
      ...(a != null ? [sp(`: Asia ${asia.length && ['^N225', '^HSI', '000001.SS'].every((s) => closedState(String(mk(s)?.market_state))) ? 'closed' : 'is'} ${a >= 0 ? 'higher' : 'lower'}`)] : []),
      ...(daxOpen ? [sp(`, Europe opened ${(num(dax.regular_change_pct) ?? 0) >= 0 ? 'firm' : 'soft'}`)] : []), sp('.'),
      ...(held ? [sp(' Your names trade again at 4:00 AM.')] : [])]);
  } else if (session) {
    const lead = sec(false).sort((u, v) => v.move - u.move)[0], bt = bookToday, m = bt ? mostOf(Math.sign(bt.made) || -1) : null;
    both((p) => [sp('Stocks are '), sp(upDown(spyDay)), sp(` ${p1(spyDay)}`, true, col(spyDay)), sp(lead ? `, ${short(lead.sector)} leading.` : '.'),
      ...(bt && held ? [sp(` Your book is ${upDown(bt.made)} `), sp(money(bt.made, p), true, col(bt.made)), sp(m ? `, most of it ${m.name}.` : '.')] : []),
      ...(held ? [sp(` ${decLine}`)] : [])]);
  } else if (moment === 'post') {
    const bt = bookToday, m = bt ? mostOf(Math.sign(bt.made) || -1) : null;
    const ah = [...names].filter((n) => n.ext != null && Math.abs(n.ext) >= 1).sort((u, v) => Math.abs(v.ext!) - Math.abs(u.ext!))[0];
    const kind = m ? (Math.abs(m.today.sh) >= Math.abs(m.today.lp) ? 'shares' : 'LEAPS') : '';
    both((p) => [sp(`Stocks closed ${upDown(spyDay)} `), sp(p1(spyDay), true, col(spyDay)), sp('.'),
      ...(bt && held ? [sp(` Your book ${bt.made < 0 ? 'lost' : 'made'} `), sp(money(bt.made, p), true, col(bt.made)), sp(m ? `, most of it ${m.name}’s ${kind}.` : '.')] : []),
      ...(ah ? [sp(` ${ah.name} is ${upDown(ah.ext!)} ${p1(ah.ext!)} after hours.`)] : [])]);
  } else {
    const r = resultsWeek(), spw = weekPct(spy) ?? 0, sells = x.orders.filter((o) => o.kind === 'sell' || o.kind === 'put').length;
    const ss = sec(true).sort((u, v) => v.move - u.move), on = spw >= 0 ? ss[0] : ss[ss.length - 1];
    const mkt = `Stocks ${spw >= 0 ? 'rose' : 'fell'}${on && Math.sign(on.move) === Math.sign(spw) ? ` on ${short(on.sector)}` : ''}`;
    both((p) => [
      ...(held && r.sold > 0 ? (r.kept >= 0
        ? [sp(`${weekOpen ? 'So far, a' : 'A'} ${py(r.yieldPct)} week: you kept `), sp(p ? `${Math.round((r.kept / r.sold) * 100)}%` : fK(r.kept), true, 'green'), sp(p ? ` of what you ${r.open ? 'closed' : 'sold'}. ` : ` of ${fK(r.sold)} ${r.open ? 'closed' : 'sold'}. `)]
        : [sp(`${weekOpen ? 'So far, a' : 'A'} losing week: buying back cost `), ...(p ? [sp('more than you sold. ')] : [sp(fK(-r.kept), true, 'red'), sp(` more than the ${fK(r.sold)} sold. `)])])
        : []),
      sp(mkt), ...(held && sells ? [sp(`, and ${word(sells).toLowerCase()} ${sells === 1 ? 'sale comes' : 'sales come'} ${salesDay}.`)] : [sp('.')])]);
    if (held && sells) owner.push({ key: 'lede' });
  }

  /* Performance (Nik 10 Nov 2026, of the old Home's card: "Add this to weekend and post market and search"). The phone
     draws the whole card (filters, months, a bar per name) from payload.performance, realized by month, name and kind;
     these words are what the web, a phone in privacy and an older build draw: this month's realized, a bar per month
     since the book's first, and this month's names. A month before the book's first counts in its first (the LEAPS
     bought on 31 Aug count in September), as on the phone. */
  const performanceCard = () => {
    const rows = (x.perf?.realized ?? []) as unknown[][]; if (!rows.length) return null;
    const from = String(x.perfFrom ?? today).slice(0, 7), mo = today.slice(0, 7), mName = MONTH[ymd(today).m - 1];
    const byM = new Map<string, number>(), byT = new Map<string, number>();
    for (const r of rows) {
      const m = [String(r[0]), from].sort().at(-1)!, v = Number(r[3]) || 0;
      byM.set(m, (byM.get(m) ?? 0) + v);
      if (m === mo) byT.set(String(r[1]), (byT.get(String(r[1])) ?? 0) + v);
    }
    const months = [...byM].filter(([m]) => m <= mo).sort((a, b) => a[0].localeCompare(b[0]));
    const month = byM.get(mo) ?? 0, ytd = months.filter(([m]) => m.slice(0, 4) === mo.slice(0, 4)).reduce((a, [, v]) => a + v, 0);
    const best = [...months].sort((a, b) => b[1] - a[1])[0];
    const bestName = best ? MONTH[Number(best[0].slice(5, 7)) - 1] : null;
    const bars = months.slice(-5).map(([m, v]) => ({ label: MON[Number(m.slice(5, 7)) - 1], value: fK(v), n: Math.round(v), highlight: m === mo,
      valueColor: m === mo ? col(v) : v < 0 ? 'red' : 'ink', empty: false }));
    const named = [...byT].filter(([, v]) => Math.abs(v) >= 1).sort((a, b) => b[1] - a[1]);
    return { type: 'performance', title: 'Performance', subtitle: `Realized in ${mName}, closed trades only`,
      big: fK(month), bigColor: col(month),
      bigSub: `${month < 0 ? 'lost' : 'made'} in ${mName} · ${fK(ytd)} ${ytd < 0 ? 'lost' : 'made'} this year${bestName && best[1] > 0 ? ` · ${bestName} the best month` : ''}`,
      chart: bars.length > 1 ? { title: 'Realized by month', bars } : null,
      rows: named.map(([t, v]) => ({ label: company(t), value: fK(v), valueSub: v < 0 ? 'lost' : 'made', valueColor: col(v) })) };
  };

  // ════ Sections ════
  type Sec ={ kicker: string; headline: Span[]; privacy?: Span[]; cards: (Row | null)[]; ownerCards?: string[]; openHeadline?: Span[] };
  const S: Sec[] = [];
  const marketHead = (): Span[] => {
    const ss = sec(wk).sort((u, v) => v.move - u.move), lead = ss[0], trail = ss[ss.length - 1];
    if (wk) {
      const spw = weekPct(spy) ?? 0;
      const per = weekOpen ? 'so far this week' : 'for the week';
      if (spw >= 0) return [sp(`Stocks rose ${per}${lead && lead.move > 0 ? ` on ${short(lead.sector)}` : ''}.${trail && trail.move < 0 ? ` ${trail.sector} fell the most.` : ''}`, true)];
      return [sp(`Stocks fell ${per}${trail && trail.move < 0 ? `, ${short(trail.sector)} the most` : ''}.${lead && lead.move > 0 ? ` ${lead.sector} rose.` : ''}`, true)];
    }
    const small = iwmDay < spyDay ? 'Small caps lag' : 'Small caps keep up';
    if (moment === 'post') return [sp(`Closed ${spyDay >= 0 ? 'higher' : 'lower'}${lead ? `, ${short(lead.sector)} led` : ''}. ${iwmDay < spyDay ? 'Small caps lagged' : 'Small caps kept up'}.`, true)];
    return [sp(`${lead ? `${lead.sector === 'Technology' ? 'Tech' : lead.sector} leads, ` : ''}${lc(small)}.`.replace(/^s/, 'S'), true)];
  };
  const worldHead = (): Span[] => {
    const fu = esPct ?? 0, soon = x.macro.filter((m) => !/holiday/i.test(String(m.category ?? '')) && dayDiff(today, String(m.event_date)) >= 0 && dayDiff(today, String(m.event_date)) <= 1)[0];
    return [sp(`US futures are ${fu >= 0 ? 'higher' : 'lower'}${soon ? `, ${dayDiff(today, String(soon.event_date)) === 0 ? 'with' : 'a day before'} ${String(soon.name).replace(/ \(.*\)$/, '')}${dayDiff(today, String(soon.event_date)) === 0 && soon.event_time ? ` at ${tm(soon.event_time)}` : ''}` : ''}.`, true)];
  };
  const namesHead = (): Span[] => {
    if (!held) return [sp('Nothing held yet.', true)];
    const big = [...names].sort((u, v) => Math.abs(v.move) - Math.abs(u.move))[0];
    /* The figure in the name's colour (New Home iPhone Preview h2, Nov 8): "Netflix rose 12.7%." with 12.7% green. Every
       run stays bold, so a build before the thick-and-thin headline reads as it did; the app sets the weights. */
    if (wk) { const fell = names.filter((n) => n.move < 0).length; return [sp(`${big.name} ${big.move >= 0 ? 'rose' : 'fell'} `, true), sp(p1(big.move), true, col(big.move)), sp(`. ${word(fell)} of your ${word(names.length).toLowerCase()} names fell.`, true)]; }
    if (moment === 'pre' || moment === 'futures') {
      if (names.every((n) => !n.ext)) return [sp('Your names trade again at 4:00 AM.', true)];
      const fu = esPct ?? 0, nUp = names.filter((n) => n.move > 0).length, follow = fu >= 0 ? nUp >= names.length / 2 : nUp <= names.length / 2;
      return [sp(`Your names ${follow ? 'are' : 'aren’t'} following. ${big.name} is ${upDown(big.move)} `, true), sp(p1(big.move), true, col(big.move)), sp('.', true)];
    }
    const bt = bookToday; if (!bt) return [sp('Your book.', true)];
    if (moment === 'post') {
      const m = mostOf(Math.sign(bt.made) || -1), kind = m ? (Math.abs(m.today.sh) >= Math.abs(m.today.lp) ? 'shares' : 'LEAPS') : '';
      return [sp(`Your sales ${bt.sold >= 0 ? 'kept working' : 'cost you today'}.${m ? ` ${m.name}’s ${kind} ${bt.made < 0 ? 'cost the day' : 'made the day'}.` : ''}`, true)];
    }
    return [];   // session: the money headline below
  };

  if (moment === 'futures' || moment === 'pre') {
    S.push({ kicker: 'World and economy', headline: worldHead(), cards: [moment === 'futures' ? futuresCards() : indexCards(), overnight(), economyCard(), sectorsCard(false)] });
    S.push({ kicker: 'Your book', headline: namesHead(), cards: [yourNames(), yourPosition()] });
    const ne = earningsAhead(14);
    const ch = nextEarn && dayDiff(today, String(nextEarn.date)) <= 14 ? `${company(nextEarn.ticker)} reports in ${dayDiff(today, String(nextEarn.date))} days.` : (comingRows(today, addDays(today, 45))[0] ? `Next: ${leadOf(comingRows(today, addDays(today, 45))[0].text)}, ${comingRows(today, addDays(today, 45))[0].date}.` : 'Nothing dated in the next six weeks.');
    S.push({ kicker: 'Coming up', headline: [sp(ch, true)], cards: [ne, (() => { const rows = comingRows(today, addDays(today, 45)); return rows.length ? { type: 'comingUp', title: 'Coming up', rows } : null; })()] });
  } else if (session) {
    S.push({ kicker: 'The market', headline: marketHead(), cards: [indexCards(), outToday(), sectorsCard(false)] });
    const bt = bookToday, m = bt ? mostOf(Math.sign(bt.made) || -1) : null;
    const h = (p: boolean): Span[] => (bt && held ? [sp(`${bt.made < 0 ? 'Down' : 'Up'} `, true), sp(money(bt.made, p), true, col(bt.made)), sp(m ? `, most of it ${m.name}.` : '.', true)] : namesHead());
    S.push({ kicker: 'Your book', headline: h(false), privacy: h(true), cards: [yourNames(), whatsMoving(), yourPosition()] });
    if (shorts.length || look) {
      const two = shorts.length >= 2, n = shorts[0], k = n?.soldCalls.filter((c) => c.ex <= F).sort((a, b) => a.K - b.K)[0]?.K;
      const head = shorts.length === 0 ? [sp(`Every name still gains from a priced rise by Friday. ${company(look.t)}’s calls are ${look.cap}% kept.`, true)]
        : two ? [sp(`${shorts.length === 2 ? `${shorts[0].name} and ${shorts[1].name}` : `${shorts.slice(0, -1).map((y) => y.name).join(', ')} and ${shorts.at(-1)!.name}`} are past their best at a priced rise by Friday.`, true)]
        : [sp(`${n.name} makes the most at $${n.fp!.toFixed(2)} by Friday.`, true)];
      const full = shorts.length === 0 ? head : [sp(`${head[0].t}${two ? ' Roll the calls or add before then.' : ` Roll the ${k ?? ''} calls or add before then.`.replace('the  calls', 'the calls')}`, true)];
      S.push({ kicker: 'To decide', headline: full, openHeadline: head, cards: [toDecide()], ownerCards: ['toDecide'] });
    }
    const cl = comingLine();
    S.push({ kicker: 'Coming up', headline: [sp(`Post-market takes over at ${hm(closeMin)}.`, true)], cards: [cl] });
  } else if (moment === 'post') {
    S.push({ kicker: 'The market', headline: marketHead(), cards: [indexCards(), sectorsCard(false)] });
    S.push({ kicker: 'Your book', headline: namesHead(), cards: [yourNames(), yourResults(), closedRolled(), held ? performanceCard() : null, yourPosition()] });
    // No Tomorrow's orders (11 Nov 2026: To do removed): the section leads with what is coming.
    const cl = comingLine();
    S.push({ kicker: 'Tomorrow', headline: [sp(cl ? cl.line[0].t : 'Tomorrow.', true)], cards: [cl] });
  } else {
    S.push({ kicker: 'The week', headline: marketHead(), cards: [weekIndexes(), worldThisWeek(), economyCard(), sectorsCard(true)] });
    S.push({ kicker: 'Your book', headline: namesHead(), cards: [yourNames(), held ? results() : null, held ? performanceCard() : null, yourPosition()] });
    const pb = payback(), tm2 = thetaMonth(), mName = MONTH[ymd(today).m - 1], done = ymd(addDays(today, 7)).m !== ymd(today).m && dayDiff(today, `${today.slice(0, 7)}-28`) <= 0;
    const pbPct = x.payback && x.baseNow > 0 ? (Number(x.payback.made ?? 0) / x.baseNow) * 100 : 0;
    /* "October is done: 6.2% of what you bought is paid back." with the figure green (red when given back), as the design. */
    if (held && (pb || tm2)) S.push({ kicker: mName, headline: [sp(`${mName} ${done ? 'is done' : 'so far'}: `, true), sp(p1(pbPct), true, col(pbPct)),
      sp(` of what you bought is ${pbPct >= 0 ? 'paid back' : 'given back'}.`, true)], cards: [tm2, pb] });
    const rem = remember(), sells = x.orders.filter((o) => o.kind === 'sell' || o.kind === 'put').length, ne = earningsAhead(7);
    const first = rem?.rows.find((r: Row) => !r.owner);
    S.push({ kicker: weekOpen ? 'Coming up' : 'Next week', headline: [sp(sells ? `${word(sells)} ${sells === 1 ? 'sale' : 'sales'} ${salesDay}.` : first ? `${leadOf(first.text)}, ${first.date}.` : 'A quiet week ahead.', true)],
      openHeadline: [sp(first ? `${leadOf(first.text)}, ${first.date}.` : 'A quiet week ahead.', true)], cards: [ne, rem] });
  }

  const build = (forOwner: boolean) => {
    let n = 0;
    const sections = S.map((s) => {
      const cards = s.cards.filter(Boolean).map((c) => c as Row).filter((c) => forOwner || !(s.ownerCards ?? []).includes(c.type))
        .map((c) => (c.type === 'remember' && !forOwner ? { ...c, rows: c.rows.filter((r: Row) => !r.owner) } : c))
        .map((c) => (c.type === 'remember' ? { ...c, rows: c.rows.map(({ owner: _o, ...r }: Row) => r) } : c))
        .filter((c) => !(c.type === 'remember' && !c.rows.length));
      if (!cards.length) return null;
      n += 1;
      const headline = !forOwner && s.openHeadline ? s.openHeadline : s.headline;
      return { num: String(n), kicker: s.kicker, headline, ...(s.privacy ? { privacy: { headline: s.privacy } } : {}), cards };
    }).filter(Boolean);
    const strip = (l: Span[]) => (forOwner || !owner.some((o) => o.key === 'lede') ? l
      : l.filter((s) => !/to place at the open/.test(s.t)).map((s) => ({ ...s, t: s.t.replace(/, and \w+ sales? comes? \w+day\./, '.') })));
    return { v: 1, moment, built_for: today, title: TITLE[moment], dateLine, dayCaption, lede: strip(lede), privacy: { lede: strip(ledeP) },
      alert, deckCards, sections, hidden: [...(econ.length ? [] : ['economy', 'outToday']), 'afterHours', 'thesisCheck'],
      // The economy sheet: all twelve, watch first, then new, then steady.
      economy: econ.length ? { title: 'The economy', sub: `${econ.length} indicators · the last four readings`, indicators: econAll } : null };
  };
  return { full: build(true), open: build(false) };
}
