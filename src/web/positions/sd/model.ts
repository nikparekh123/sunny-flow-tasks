// The SD calculator on the web: "What to sell" (handoff 2026-11-11-sd-whatif-totals, README 1; SunnySD.dc.html, `web`).
// The server (sunny-sd) does the engine: every expiry's 1 SD, the strike rows, the suggestion, the signals, the 5-year
// move quantiles, what is sold (with what was got for it) and the cover. The card picks an expiry, a call and a put
// strike and the counts, and works out Held, + New and = Both with the engine's own sale() (README 1.9), here, so the
// three lanes, the side cards and Try in What if all read the same numbers.
// No em dashes in any words this file writes (Nik).
import { cdfOf, sale, type Sale, type SaleLane, type SaleLeg } from '../../../../supabase/functions/_shared/sd-engine.ts';
import { money, price } from '../../lib/format';

export interface SdRow {
  k: number; K: number; pct: number; kA: number; pr: number; be: number; itm: number;
  est: boolean; liq: boolean; won: number | null;
}
export interface SdSig {
  key: string; k: string; v: string; vTone: 'ink' | 'green' | 'red' | 'or'; tag: string; tagTone: 'mu' | 'or';
  s: string; fx: [string, string][];
}
export interface SdExp {
  ex: string; label: string; long: string; td: number; cd: number; T: number; iv: number; m: number; earn: boolean;
  band: [number, number];
  sug: { kc: number; kp: number; mvC: boolean; mvP: boolean; capC: boolean; capP: boolean; C: SdRow; P: SdRow };
  rows: { c: SdRow[]; p: SdRow[] };
  sig: SdSig[];
  /** The 5-year moves over the same trading days: their count, whether the past IV was estimated (HV20 scaled), and
      401 quantiles in SD units (sd-engine won().q), the distribution the chance of profit sums. */
  hist: { n: number; est: boolean; q?: number[] };
}
/** A sold leg still open: `got` is the premium a share received, `iv` the IV of its own expiry. */
export interface SdSold { put: boolean; K: number; n: number; ex: string; be: number | null; got?: number | null; iv?: number | null }
/** What you hold (Nik 11 Nov): one expiry's sold calls and sold puts as a pair, from the server. */
export interface SdHeld {
  ex: string; label: string; calls: { K: number; n: number }[]; puts: { K: number; n: number }[];
  tot: number; up: number; dn: number; sdUp: number; sdDn: number; cop: number;
}
export interface SdReply {
  ok: boolean; v: number; t: string; name: string; S: number; prev: number; move: number; open: boolean; today: string;
  cfg: { cLo: number; cHi: number; pLo: number; pHi: number };
  counts: { calls: number; puts: number };
  sold: SdSold[];
  exps: SdExp[];
  held?: SdHeld[];
  /** The calls a new sale can be covered by: the shares, and the OTM calls bought, by expiry. */
  cover?: { shares: number; otm: { ex: string; n: number }[] };
  /** The rate and the dividend yield the held legs are valued on. */
  r?: number; q?: number;
}

/** The web card is always dark: pal136(true), and the lanes' TH(true). */
export const P = {
  ink: '#F5F5F7', mu: '#98989D', muT: '#AEAEB2', cd: '#1C1C1E', bg: '#0B0B0C', G: '#65C466', RD: '#FF6961', OR: '#F2A93B',
  CL: '#6FA0F6', PT: '#D49A5A', tile: 'rgba(118,118,128,.18)', trk: 'rgba(118,118,128,.24)', rule: 'rgba(255,255,255,.10)',
  ring: 'rgba(235,235,245,.3)', cdMu: 'rgba(0,0,0,.6)',
  zG: '#30D158', zR: '#FF453A', gT: '#30D158', rT: '#FF6961', gB: 'rgba(48,209,88,.14)', rB: 'rgba(255,69,58,.16)', nB: 'rgba(118,118,128,.24)',
} as const;
/** Stripes: where the sale turns profit into loss, or the other way round. */
export const STRIPES = 'repeating-linear-gradient(135deg,rgba(0,0,0,.4) 0 3px,transparent 3px 7px)';

/* ── The design's formats ───────────────────────────────────────────────── */
/** One decimal, two under 0.1% (from a fraction, no sign). */
export const pc = (x: number) => { const a = Math.abs(x) * 100; return (a > 0 && a < 0.1 ? a.toFixed(2) : a.toFixed(1)) + '%'; };
/** ↑ or ↓ and the %: never a minus sign; the arrow never breaks from its number. */
export const dir = (x: number) => (x >= 0 ? '↑ ' : '↓ ') + pc(x);
export const f2 = (x: number) => x.toFixed(2);
/** A strike as listed: 40, 42.5, 40.85. */
export const fk = (x: number) => (x % 1 ? (Math.round(x * 100) % 10 ? x.toFixed(2) : x.toFixed(1)) : String(x));
/** ATM, 0.25 SD, 0.5 SD, 1.0 SD. */
export const sdl = (k: number) => (k < 0 ? 'ITM' : k === 0 ? 'ATM' : (k % 1 ? String(k) : k.toFixed(1)) + ' SD');
/** The design's normal CDF (Abramowitz and Stegun 26.2.17). */
export const N = (x: number) => {
  const t = 1 / (1 + 0.2316419 * Math.abs(x)), d = 0.3989422804014327 * Math.exp(-x * x / 2),
    q = d * t * (0.31938153 + t * (-0.356563782 + t * (1.781477937 + t * (-1.821255978 + t * 1.330274429))));
  return x > 0 ? 1 - q : q;
};
const same = (a: number, b: number) => Math.abs(a - b) < 1e-9;
const steps = (lo: number, hi: number) => { const o: number[] = []; for (let k = lo; k <= hi + 1e-9; k += 0.25) o.push(Math.round(k * 4) / 4); return o; };
/** "0.25 to 1.25 SD", "ATM to 1 SD". */
const range = (lo: number, hi: number) => (lo < 0 ? 'ITM' : lo === 0 ? 'ATM' : String(lo)) + ' to ' + String(hi) + ' SD';
const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const plural = (n: number, one: string, many: string) => `${n} ${n === 1 ? one : many}`;
/** "10 calls and 5 puts", leaving out a side at 0. */
const cnt = (c: number, p: number) => [c ? plural(c, 'call', 'calls') : '', p ? plural(p, 'put', 'puts') : ''].filter(Boolean).join(' and ');
const days = (a: string, b: string) => Math.round((Date.parse(b + 'T12:00:00Z') - Date.parse(a + 'T12:00:00Z')) / 864e5);

/* ── What the user picked ───────────────────────────────────────────────── */
/** The expiry, a call and a put SD (null: that expiry's suggestion), and how many calls and puts to sell (null: 0,
    Nik D3). A new expiry puts the strikes back to its suggestion and keeps the counts; a new name starts over. */
export interface SdPick { t: string; ex: string | null; c: number | null; p: number | null; nc?: number | null; np?: number | null }
export const NO_PICK: SdPick = { t: '', ex: null, c: null, p: null };

/** The row for a picked SD: the suggestion's (with the strike it was moved to), else the plain row. */
const rowAt = (e: SdExp, k: number, put: boolean): SdRow | undefined => {
  if (same(k, put ? e.sug.kp : e.sug.kc)) return put ? e.sug.P : e.sug.C;
  return (put ? e.rows.p : e.rows.c).find((r) => same(r.k, k));
};

/** A What if row for Try in What if (the What if's Trade, less its id and switch). */
export interface SdTrade { side: 's'; ty: 'c' | 'p'; K: number; ex: string; n: number; pr: number; src: 'sd' }
export interface Tile { key: string; sd: string; strike: string; pr: string; won: string; sug: boolean; on: boolean; go: () => void }
export interface Side {
  key: 'c' | 'p'; h: string; c: string; rT: string; o: Tile[];
  n: number; set: (n: number) => void;
  /** The line under the count: cover for calls, the cash if assigned for puts; orange when calls are not covered. */
  hint: string; hc: string;
}
/** A run of the head sentence. */
export interface Run { t: string; w: number; c: string }
/** A strike pill over a bar (x in % of the price scale). */
/** A strike on a lane: its pill and, under it, how far it is from today (Nik 12 Nov 2026: `↓ 9.2% · 1.55 SD`). */
export interface Pill { key: string; xv: number; l: string; s: string; c: string; nw: boolean }
/** A breakeven: the price, `↓ 9.3% · 1.34 SD`, and in Both the change against Held. */
export interface Be { key: string; xv: number; v: string; s: string; ch: { t: string; c: string } | null }
export interface Lane {
  key: 'h' | 'n' | 'b'; name: string; op: string; on: boolean; cop: string; sub: string;
  ch: { t: string; c: string; bg: string } | null;
  zones: { key: number; L: number; W: number; c: string }[];
  diff: { key: number; L: number; W: number }[];
  pills: Pill[];
  /** Held's breakevens over the Both bar. */
  held: Be[];
  bes: Be[];
}
/** A leg in the Calls or Puts card: strike and count, what it took in, `↑ 5.7% · 0.60 SD` from today, its won rate. */
export interface CardLeg { key: string; K: string; pr: string; mv: string; won: string }
export interface CardCol { key: 'h' | 'n'; legs: CardLeg[]; emT: string; be: string; beS: string }
export interface SideCard {
  key: 'c' | 'p'; h: string; col: string; cols: [CardCol, CardCol];
  from: string | null; bV: string; bS: string; ch: { t: string; c: string; bg: string } | null;
}
export interface SdView {
  t: string; name: string; S: number; ei: number; e: SdExp;
  /** `NKE $38.31`, then `Fri Nov 20 · IV 55.9% · 1 SD ±$3.57`. */
  tt: string; sub: string;
  exps: { key: string; t: string; d: string; on: boolean; isE: boolean; go: () => void }[];
  sig: { key: string; k: string; v: string; vc: string; tag: string; tagc: string; s: string; fx: { key: number; t: string; c: string }[] }[];
  /** Sell call, Sell put: the count and its hint, then the strike tiles. */
  rng: [Side, Side];
  /** What the sale does (README 1.6 and 1.7). */
  head: Run[]; gT: string; legend: { key: string; t: string; bg: string; sh: string }[];
  todayX: number; todayT: string; lanes: Lane[]; cards: SideCard[];
  /** The raw sale, for checks. */
  sale: Sale; both: boolean;
  /** Legs sold that end before the chosen expiry, left out. */
  gone: string;
  /** Try in What if: the sale as What if rows, and the caption's words; null with both counts at 0. */
  tryIt: { trades: SdTrade[]; what: string } | null;
  foot: string;
}

/** card136 and SunnySD's sale() and lanes(), web, on the server's reply. */
export function sdView(d: SdReply, pick: SdPick, set: (p: SdPick) => void): SdView | null {
  if (!d?.ok || !d.exps?.length) return null;
  const mine = pick.t === d.t;
  const ei = Math.max(0, mine && pick.ex ? d.exps.findIndex((x) => x.ex === pick.ex) : 0);
  const e = d.exps[ei], S = d.S, m = e.m, cfg = d.cfg, exS = e.label;
  const exL = (iso: string) => d.exps.find((x) => x.ex === iso)?.label ?? (() => { const [, mo, dd] = iso.split('-').map(Number); return `${MON[mo - 1]} ${dd}`; })();
  // A pick outside the rules' range (the reply changed under it) goes back to the suggestion.
  const okC = (k: number | null) => k != null && k >= cfg.cLo - 1e-9 && k <= cfg.cHi + 1e-9;
  const okP = (k: number | null) => k != null && k >= cfg.pLo - 1e-9 && k <= cfg.pHi + 1e-9;
  const samePick = mine && pick.ex === e.ex;
  const selC = samePick && okC(pick.c) ? pick.c! : e.sug.kc, selP = samePick && okP(pick.p) ? pick.p! : e.sug.kp;
  const rc = rowAt(e, selC, false) ?? e.sug.C, rp = rowAt(e, selP, true) ?? e.sug.P;
  // The counts start at 0 (Nik D3) and stay with the name across expiries.
  const nC = Math.max(0, Math.min(999, Math.round(mine ? pick.nc ?? 0 : 0))), nP = Math.max(0, Math.min(999, Math.round(mine ? pick.np ?? 0 : 0)));
  const base = { t: d.t, ex: e.ex, c: selC, p: selP, nc: nC, np: nP };
  const go = (q: Partial<SdPick>) => set({ ...base, ...q });

  const exps = d.exps.map((x, i) => ({
    key: x.ex, t: x.label, d: x.cd === 1 ? '1 day' : x.cd + ' days', on: i === ei, isE: !!x.earn,
    go: () => set({ t: d.t, ex: x.ex, c: null, p: null, nc: nC, np: nP }),
  }));

  const FX: Record<string, string> = { c: P.CL, p: P.PT, b: P.ink, x: P.OR, n: P.mu };
  const VC: Record<string, string> = { ink: P.ink, green: P.G, red: P.RD, or: P.OR };
  const sig = (e.sig ?? []).map((g) => ({
    key: g.key, k: g.k, v: g.v, vc: VC[g.vTone] ?? P.ink, tag: g.tag ?? '', tagc: g.tagTone === 'or' ? P.OR : P.mu, s: g.s ?? '',
    fx: (g.fx ?? []).map(([k, t], i) => ({ key: i, t, c: FX[k] ?? P.mu })),
  }));

  // The 5-year moves (README 1.9), scaled to today's IV; a normal curve when the name has no history.
  const q = e.hist?.q ?? [], cdf = q.length ? cdfOf(q) : N;
  // "won" (A1): ≈ when the past IV behind it was HV20 scaled.
  const wonOf = (w: number | null) => (w == null ? '' : (e.hist?.est ? '≈ ' : '') + pc(w) + ' won');
  const wonK = (K: number, put: boolean) => { const z = Math.log(K / S) / m; return wonOf(put ? 1 - cdf(z) : cdf(z)); };

  // What is sold: Held = sold legs that end on or after the expiry (from what was got for them); earlier ones are left out.
  const sold = d.sold ?? [];
  const hl = sold.filter((l) => l.ex >= e.ex && l.got != null && l.n > 0);
  const held: SaleLeg[] = hl.map((l) => ({ put: l.put, K: l.K, n: l.n, got: l.got!, t: Math.max(0, days(e.ex, l.ex)) / 365, iv: l.iv ?? e.iv }));
  const R = sale({ S, m, r: d.r ?? 0, q: d.q ?? 0, cdf, held, call: nC ? { K: rc.K, n: nC, pr: rc.pr } : null, put: nP ? { K: rp.K, n: nP, pr: rp.pr } : null });
  const hCl = hl.filter((l) => !l.put), hPl = hl.filter((l) => l.put);
  const hC = hCl.reduce((a, l) => a + l.n, 0), hP = hPl.reduce((a, l) => a + l.n, 0);
  const hasN = nC + nP > 0, hasH = hC + hP > 0, both = hasN && hasH;
  const gC = sold.filter((l) => !l.put && l.ex < e.ex), gP = sold.filter((l) => l.put && l.ex < e.ex);
  const gone = gC.length || gP.length
    ? `${cnt(gC.reduce((a, l) => a + l.n, 0), gP.reduce((a, l) => a + l.n, 0))} end ${[...new Set([...gC, ...gP].map((l) => l.ex))].sort().map(exL).join(' and ')}, before ${exS}, so they are left out.`
    : '';

  // How many (README 1.4): the cover hint (Nik 11 Nov) and the cash if the puts are assigned.
  const sh = Math.floor((d.cover?.shares ?? 0) / 100);
  const heldC = sold.filter((l) => !l.put && l.ex >= e.ex).reduce((a, l) => a + l.n, 0);
  const otm = (d.cover?.otm ?? []).filter((o) => o.ex >= e.ex).reduce((a, o) => a + o.n, 0);
  const byS = Math.max(0, sh - heldC), byO = Math.max(0, otm - Math.max(0, heldC - sh)), cov = byS + byO;
  const parts = (a: number, b: number) => [a ? `${a} by shares` : '', b ? `${b} by OTM calls` : ''].filter(Boolean).join(', ');
  const callHint = (n: number): [string, string] => {
    if (!d.cover) return ['', P.mu];
    if (!n) return [cov ? `Up to ${cov} covered: ${parts(byS, byO)}` : 'Nothing left to cover', P.mu];
    if (n <= byS) return ['Covered by your shares', P.mu];
    if (n <= cov) return [`Covered: ${parts(Math.min(n, byS), n - Math.min(n, byS))}`, P.mu];
    return [`${n - cov} not covered · you can cover ${cov}`, P.OR];
  };
  const tiles = (put: boolean): Tile[] => steps(put ? cfg.pLo : cfg.cLo, put ? cfg.pHi : cfg.cHi).map((k) => {
    const r = rowAt(e, k, put), sug = same(k, put ? e.sug.kp : e.sug.kc), on = same(k, put ? selP : selC);
    return { key: (put ? 'p' : 'c') + k, sd: sdl(k), strike: r ? fk(r.K) : '', pr: r ? price(r.pr) : '', won: r ? wonOf(r.won) : '', sug, on, go: () => go(put ? { p: k } : { c: k }) };
  }).filter((o) => o.strike);
  const [ch, chc] = callHint(nC);
  const rng: [Side, Side] = [
    { key: 'c', h: 'Sell call', c: P.CL, rT: range(cfg.cLo, cfg.cHi), o: tiles(false), n: nC, set: (n) => go({ nc: clampN(n) }), hint: ch, hc: chc },
    { key: 'p', h: 'Sell put', c: P.PT, rT: range(cfg.pLo, cfg.pHi), o: tiles(true), n: nP, set: (n) => go({ np: clampN(n) }),
      hint: nP ? `${money(rp.K * 100 * nP)} if assigned at ${fk(rp.K)}` : `${money(rp.K * 100)} a put if assigned`, hc: P.mu },
  ];

  /* ── The lanes (143a): Held, + New, = Both on one price scale ── */
  const A = R.A, B = R.B, xp = (v: number) => ((v - A) / (B - A)) * 100;
  const sdv = (x: number) => Math.abs(Math.log(x / S) / m), mvS = (x: number | null) => (x == null ? '' : `${dir(x / S - 1)} · ${f2(sdv(x))} SD`);
  const sgd = (v: number, put: boolean) => ((put ? -1 : 1) * Math.log(v / S)) / m;
  const L: Record<'h' | 'n' | 'b', SaleLane> = { h: R.h, n: R.n, b: R.b };
  // Each side's breakeven is the engine's: with both sides' premium when the lane has both, else that side's own. The
  // engine searches out from the top of the P&L (11 Nov 2026), so a held leg that ends after the chosen expiry is right.
  const be = (k: 'h' | 'n' | 'b', put: boolean): number | null => {
    const z = L[k][put ? 'p' : 'c'];
    return z ? z.all ?? z.own : null;
  };
  // Each crossing tagged by side: profit into loss going up is the call side, loss into profit the put side.
  const tagged = (k: 'h' | 'n' | 'b') => L[k].cr.map((x, j) => ({ x, put: !(L[k].segs[j]?.pos && !L[k].segs[j + 1]?.pos) }));
  const dP = R.b.cop - R.h.cop, flat = Math.abs(dP) < 0.0005, ptsT = (Math.abs(dP) * 100).toFixed(1) + ' pts';
  type Ch = { k: number; t: string; sh?: string; from?: number };
  const sideCh = (put: boolean): Ch | null => {
    const bB = be('b', put), bH = be('h', put), bN = be('n', put);
    if (bB == null) return null;
    if (!hasN) return { k: 0, t: 'Same as Held until you add calls or puts' };
    if (!hasH) return { k: 0, t: `Same as New: nothing held for ${exS} or later` };
    const ref = bH ?? bN, refT = bH != null ? 'Held' : 'New alone';
    if (ref == null) return { k: 0, t: 'Same as New' };
    const dd = sgd(bB, put) - sgd(ref, put);
    if (Math.abs(dd) < 0.005) return { k: 0, t: `Same as ${refT}, ${f2(ref)}`, from: ref };
    return dd > 0 ? { k: 1, sh: f2(dd) + ' SD further out', t: `${f2(dd)} SD further out than ${refT}`, from: ref }
      : { k: -1, sh: f2(-dd) + ' SD closer', t: `${f2(-dd)} SD closer than ${refT}`, from: ref };
  };
  const chC = sideCh(false), chP = sideCh(true);
  const tone = (k: number) => (k > 0 ? P.gT : k < 0 ? P.rT : P.muT), toneBg = (k: number) => (k > 0 ? P.gB : k < 0 ? P.rB : P.nB);

  const head: Run[] = [];
  const add = (t: string, w: number, c: string) => head.push({ t, w, c });
  if (both) {
    add(`${money(R.n.prem)} more in, chance of profit `, 600, P.ink);
    add(flat ? 'the same' : `${dP >= 0 ? 'up' : 'down'} ${ptsT}`, 600, flat ? P.ink : dP >= 0 ? P.gT : P.rT);
    add('. ', 600, P.ink);
    const xs = ([[false, chC], [true, chP]] as const).filter(([, c]) => c && c.k);
    if (xs.length) {
      add('Breakeven: ', 400, P.muT);
      xs.forEach(([put, c], i) => { add(`${put ? 'puts' : 'calls'} ${/Held$/.test(c!.t) ? c!.sh : c!.t}`, 600, tone(c!.k)); add(i < xs.length - 1 ? ', ' : '.', 400, P.muT); });
    } else add('The breakevens stay where they are.', 400, P.muT);
  } else if (hasN) add(`${money(R.n.prem)} in, ${pc(R.n.cop)} chance of profit.`, 600, P.ink);
  else if (hasH) { add(`What you hold: ${pc(R.h.cop)} chance of profit. `, 600, P.ink); add('Add calls or puts above to see what they change.', 400, P.muT); }
  else { add(`Nothing sold ends on or after ${exS}. `, 600, P.ink); add('Add calls or puts above.', 400, P.muT); }

  const legend = [
    { key: 'p', t: 'Profit', bg: P.zG, sh: 'none' }, { key: 'l', t: 'Loss', bg: P.zR, sh: 'none' },
    ...(both ? [{ key: 'd', t: 'Changed by the sale', bg: `${STRIPES},${P.mu}`, sh: 'none' }] : []),
    { key: 'h', t: 'Held', bg: P.bg, sh: 'inset 0 0 0 1.5px ' + P.muT }, { key: 'n', t: 'New', bg: P.ink, sh: 'none' },
  ];

  // Where the sale changes the sign: Held's and Both's crossings split the scale; a piece is striped when the two differ.
  const posAt = (k: 'h' | 'b', x: number) => L[k].segs.find((s) => x >= s.a && x <= s.b)?.pos ?? false;
  const diff: Lane['diff'] = [];
  if (both) {
    const cuts = [A, ...R.h.cr, ...R.b.cr, B].sort((a, b) => a - b);
    for (let i = 1; i < cuts.length; i++) {
      const a = cuts[i - 1], b = cuts[i];
      if (b - a > 1e-6 && posAt('h', (a + b) / 2) !== posAt('b', (a + b) / 2)) diff.push({ key: diff.length, L: xp(a), W: Math.max(0, xp(b) - xp(a)) });
    }
  }
  // Held's strikes as outlined pills, one per strike and side; New's filled.
  const merge = (ls: { put: boolean; K: number; n: number }[]) => {
    const o = new Map<string, { put: boolean; K: number; n: number }>();
    for (const l of ls) { const k = (l.put ? 'p' : 'c') + l.K, x = o.get(k); if (x) x.n += l.n; else o.set(k, { ...l }); }
    return [...o.values()];
  };
  const pill = (key: string, K: number, n: number, put: boolean, nw: boolean): Pill => ({ key, xv: xp(K), l: `${fk(K)} ×${n}`, s: mvS(K), c: put ? P.PT : P.CL, nw });
  const inAx = (K: number) => K > A && K < B;
  const pillsH = merge(hl).filter((l) => inAx(l.K)).map((l, i) => pill('h' + i, l.K, l.n, l.put, false));
  const pillsN = [...(nC && inAx(rc.K) ? [pill('nc', rc.K, nC, false, true)] : []), ...(nP && inAx(rp.K) ? [pill('np', rp.K, nP, true, true)] : [])];
  const beOf = (k: 'h' | 'n' | 'b') => tagged(k).map(({ x, put }, i): Be => {
    // The change against Held sits under the crossing that is that side's breakeven.
    const c = put ? chP : chC, show = k === 'b' && both && c && c.k !== 0 && x === be('b', put);
    return { key: k + i, xv: xp(x), v: f2(x), s: mvS(x), ch: show ? { t: c!.sh!, c: tone(c!.k) } : null };
  });
  const lane = (k: 'h' | 'n' | 'b'): Lane => {
    const isB = k === 'b', on = k === 'h' ? hasH : k === 'n' ? hasN : hasH || hasN;
    return {
      key: k, name: isB ? 'Both' : k === 'h' ? 'Held' : 'New', op: k === 'n' ? '+' : isB ? '=' : '', on, cop: pc(L[k].cop),
      sub: k === 'h' ? (hasH ? `${money(R.h.prem)} got · ${cnt(hC, hP)}` : `Nothing sold ends on or after ${exS}`)
        : k === 'n' ? (hasN ? `${money(R.n.prem)} · ${cnt(nC, nP)}` : 'Add calls or puts above')
          : both ? `${money(R.b.prem)} in all` : hasN ? 'Same as New' : hasH ? 'Same as Held' : 'Nothing yet',
      ch: isB && both ? { t: flat ? 'Same as Held' : `${dP >= 0 ? '↑' : '↓'} ${ptsT} vs Held`, c: flat ? P.muT : dP >= 0 ? P.gT : P.rT, bg: flat ? P.nB : dP >= 0 ? P.gB : P.rB } : null,
      zones: on ? L[k].segs.map((z, i) => ({ key: i, L: xp(z.a), W: Math.max(0, xp(z.b) - xp(z.a)), c: z.pos ? P.zG : P.zR })) : [],
      diff: isB ? diff : [],
      pills: !on || isB ? [] : k === 'h' ? pillsH : pillsN,
      held: isB && both ? beOf('h') : [],
      bes: on ? beOf(k) : [],
    };
  };

  // The Calls and Puts cards (README 1.7): Held | New, then = Both · breakeven.
  const cards: SideCard[] = ([false, true] as const).flatMap((put): SideCard[] => {
    const nq = put ? nP : nC, r = put ? rp : rc, hs = put ? hPl : hCl, side = put ? 'puts' : 'calls';
    if (!nq && !hs.length) return [];
    const c = put ? chP : chC, bB = be('b', put), hb = be('h', put), nb = be('n', put);
    // No breakeven: past 6 SD, or (a lane that never profits) none at all.
    const beT = (b: number | null, k: 'h' | 'n' | 'b') => (b != null ? f2(b) : L[k].segs.some((z) => z.pos) ? 'Beyond 6 SD' : 'None');
    return [{
      key: put ? 'p' : 'c', h: put ? 'Puts' : 'Calls', col: put ? P.PT : P.CL,
      cols: [
        { key: 'h', emT: `No ${side} held for ${exS} or later`, be: beT(hb, 'h'), beS: mvS(hb),
          legs: hs.map((l, i) => ({ key: 'h' + i, K: `${fk(l.K)} ×${l.n}`, pr: `Got ${price(l.got!)} · ${money(l.got! * l.n * 100)}${l.ex !== e.ex ? ' · ' + exL(l.ex) : ''}`, mv: mvS(l.K), won: wonK(l.K, put) })) },
        { key: 'n', emT: `No new ${side} yet`, be: beT(nb, 'n'), beS: mvS(nb),
          legs: nq ? [{ key: 'n', K: `${fk(r.K)} ×${nq}`, pr: `${price(r.pr)} · ${money(r.pr * nq * 100)}`, mv: mvS(r.K), won: wonOf(r.won) }] : [] },
      ],
      from: c && c.k !== 0 && c.from != null ? f2(c.from) : null, bV: beT(bB, 'b'), bS: mvS(bB),
      ch: c?.t ? { t: c.t, c: tone(c.k), bg: toneBg(c.k) } : null,
    }];
  });

  // Try in What if (README 1.8 and 1.10): the sale as What if rows, at the premium it was priced at.
  const trades: SdTrade[] = [
    ...(nC ? [{ side: 's' as const, ty: 'c' as const, K: rc.K, ex: e.ex, n: nC, pr: rc.pr, src: 'sd' as const }] : []),
    ...(nP ? [{ side: 's' as const, ty: 'p' as const, K: rp.K, ex: e.ex, n: nP, pr: rp.pr, src: 'sd' as const }] : []),
  ];
  const what = [nC ? `${plural(nC, 'call', 'calls')} at ${fk(rc.K)}` : '', nP ? `${plural(nP, 'put', 'puts')} at ${fk(rp.K)}` : ''].filter(Boolean).join(' and ');
  const td = e.td > 0 ? e.td : 1;

  return {
    t: d.t, name: d.name || d.t, S, ei, e,
    tt: `${d.t} $${f2(S)}`, sub: `${e.long} · IV ${pc(e.iv)} · 1 SD ±$${f2(S * m)}`,
    exps, sig, rng,
    head, gT: `Chance of profit and breakeven by ${exS}`, legend,
    todayX: xp(S), todayT: `$${f2(S)} today`, lanes: [lane('h'), lane('n'), lane('b')], cards,
    sale: R, both, gone,
    tryIt: trades.length ? { trades, what: `${what}, ${exS}` } : null,
    foot: (q.length
      ? `Chances from 5 years of ${d.t} moves over the same ${plural(td, 'trading day', 'trading days')}, scaled to today’s IV${e.hist?.est ? ' (the past IV estimated from HV20, so the won rates read ≈)' : ''}.`
      : `Chances from a normal curve at today’s IV: ${d.t} has no 5-year history yet.`)
      + ` Held, New and Both count only what is sold, from what you got for it; legs that end before ${exS} are left out.`,
  };
}
const clampN = (n: number) => Math.max(0, Math.min(999, Math.round(+n || 0)));
