// The SD calculator's numbers on the web (handoff 2026-11-11-sd-calculator, README 1; SunnySD.dc.html `card136`).
// The server (sunny-sd) does the engine (README 1.4 and 1.5): every expiry's 1 SD, the rows at 0 to 2 SD, the
// suggestion and the signals. The card only picks: the expiry, a call SD and a put SD, and works out the pair from
// the rows it was sent, exactly as card136 does.
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
  hist: { n: number; est: boolean };
}
export interface SdSold { put: boolean; K: number; n: number; ex: string; be: number | null }
/** What you hold (Nik 11 Nov): one expiry's sold calls and sold puts as a pair, worked out by the server at the sale
    prices; tot is the premium taken in, in dollars. */
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
}

/** The web card is always dark: pal136(true). */
export const P = {
  ink: '#F5F5F7', mu: '#98989D', muT: '#AEAEB2', cd: '#1C1C1E', G: '#65C466', RD: '#FF6961', OR: '#F2A93B',
  CL: '#6FA0F6', PT: '#D49A5A', tile: 'rgba(118,118,128,.18)', cdMu: 'rgba(0,0,0,.6)',
  czB: 'rgba(111,160,246,.10)', czB2: 'rgba(111,160,246,.22)', czL: 'rgba(111,160,246,.5)',
  pzB: 'rgba(212,154,90,.10)', pzB2: 'rgba(212,154,90,.22)', pzL: 'rgba(212,154,90,.5)',
} as const;

/* ── The design's formats (card136) ─────────────────────────────────────── */
/** One decimal, two under 0.1% (from a fraction, no sign). */
export const pc = (x: number) => { const a = Math.abs(x) * 100; return (a > 0 && a < 0.1 ? a.toFixed(2) : a.toFixed(1)) + '%'; };
/** ↑ or ↓ and the %: never a minus sign. */
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
/** "0.5 to 1.25 SD", "ATM to 1 SD" (Nik, D2: the put row's label reads ATM to 1 SD). */
const range = (lo: number, hi: number) => (lo < 0 ? 'ITM' : lo === 0 ? 'ATM' : String(lo)) + ' to ' + String(hi) + ' SD';

/* ── What the user picked: the expiry, then a call and a put SD (default: that expiry's suggestion) ── */
/** nc and np: how many calls and puts to sell now (Nik, 11 Nov 2026), null = the rest of the counts after what is
    held on that expiry. A new expiry starts them over. */
export interface SdPick { t: string; ex: string | null; c: number | null; p: number | null; nc?: number | null; np?: number | null }
export const NO_PICK: SdPick = { t: '', ex: null, c: null, p: null };

/** The row for a picked SD: the suggestion's (with the strike support or resistance moved it to), else the plain row. */
const rowAt = (e: SdExp, k: number, put: boolean): SdRow | undefined => {
  if (same(k, put ? e.sug.kp : e.sug.kc)) return put ? e.sug.P : e.sug.C;
  return (put ? e.rows.p : e.rows.c).find((r) => same(r.k, k));
};

export interface SdView {
  t: string; S: number; pxT: string; ei: number; e: SdExp;
  ivT: string; sdP: string; sdD: string;
  exps: { key: string; t: string; d: string; on: boolean; isE: boolean; go: () => void }[];
  sig: { key: string; k: string; v: string; vc: string; tag: string; tagc: string; s: string; fx: { key: number; t: string; c: string }[] }[];
  rng: { key: string; h: string; c: string; rT: string; o: { key: string; sd: string; strike: string; pr: string; won: string; sug: boolean; on: boolean; go: () => void }[] }[];
  both: { cop: string; prT: string; tot: number; totN: string };
  /** New's bar; null when both counts are 0. */
  pz: SdZone | null;
  /** How many calls and puts to sell now (Nik, 11 Nov 2026), and their setters. */
  qty: { c: number; p: number; setC: (n: number) => void; setP: (n: number) => void };
  /** The chance tile's three tabs (Nik 11 Nov): New (the picked call and put on the full counts), What you hold (this
      expiry's sold calls and puts at their sale prices), Both (what you hold plus the rest of the counts at the
      picked strikes). Null when the expiry has no held pair: the tile shows New alone. */
  tabs: PairTab[] | null;
  /** Try in What if (Nik, 11 Nov 2026): the picked call and put on the rest of the counts (what you hold on this
      expiry already counts), as What if trades; null when nothing is left to sell on it. */
  tryIt: { label: string; trades: { side: 's'; ty: 'c' | 'p'; K: number; ex: string; n: number }[] } | null;
  ladC: LadRow[]; ladP: LadRow[];
  /** What the payoff chart draws (README 1.9). */
  chart: {
    band: [number, number]; C: { K: number; label: string }; P: { K: number; label: string }; sold: { K: number; be: number | null; label: string }[];
    /** Each held pair's two breakevens (Nik 11 Nov, option 3). */
    pair: { K: number; label: string }[];
  };
}
/** The profit zone's drawing, in % of its width. */
export interface SdZone {
  zL: string; zW: string; mL: string; mW: string; today: string;
  top: { key: string; x: string; l: string; c: string }[];
  dist: { key: string; l: string; x: string; L: string; W: string; c: string }[];
  bot: { key: string; x: string; l: string; s: string }[];
}

/** The profit zone from the lower breakeven (or the put) to the upper (or the call), 12% padding each side; under the
    bar each breakeven in two lines, `36.54 (BE)` over `4.3% (1.2 SD)` (Nik 11 Nov). */
function zoneOf(S: number, pK: number | null, cK: number | null, dn: number | null, up: number | null, sdDn: number | null, sdUp: number | null): SdZone {
  // Today is always on the bar, even when it has moved past a strike or a breakeven. A missing side (a calls-only
  // or puts-only sale) gets room to match the other, and its end of the bar stays green: no breakeven there.
  const nums = (xs: (number | null)[]) => xs.filter((x): x is number => x != null);
  let a0 = Math.min(...nums([dn, pK, S])), b0 = Math.max(...nums([up, cK, S]));
  if (dn == null && pK == null) a0 = S - Math.max(b0 - S, S * 0.02) * 0.6;
  if (up == null && cK == null) b0 = S + Math.max(S - a0, S * 0.02) * 0.6;
  const pad = (b0 - a0) * 0.12, A = a0 - pad, B = b0 + pad;
  const X2 = (v: number) => ((v - A) / (B - A) * 100).toFixed(2) + '%', W2 = (u: number, v: number) => ((v - u) / (B - A) * 100).toFixed(2) + '%';
  const zl = dn ?? A, zr = up ?? B, ml = pK ?? A, mr = cK ?? B;
  return {
    zL: X2(zl), zW: W2(zl, zr), mL: X2(ml), mW: W2(ml, mr), today: X2(S),
    top: [...(pK != null ? [{ key: 'p', x: X2(pK), l: 'Put ' + fk(pK), c: P.PT }] : []), ...(cK != null ? [{ key: 'c', x: X2(cK), l: 'Call ' + fk(cK), c: P.CL }] : [])],
    bot: [
      ...(dn != null ? [{ key: 'd', x: X2(dn), l: f2(dn) + ' (BE)', s: `${pc(dn / S - 1)} (${(sdDn ?? 0).toFixed(1)} SD)` }] : []),
      { key: 't', x: X2(S), l: '$' + f2(S), s: 'today' },
      ...(up != null ? [{ key: 'u', x: X2(up), l: f2(up) + ' (BE)', s: `${pc(up / S - 1)} (${(sdUp ?? 0).toFixed(1)} SD)` }] : []),
    ],
    // A side already in the money draws no distance: its line would lie over the other side's.
    dist: [
      // With the other side in the money between today and this strike, the label sits between the two strikes.
      ...(pK != null && pK < S ? [{ key: 'p', l: dir(pK / S - 1), x: X2((pK + (cK != null && cK < S && cK > pK ? cK : S)) / 2), L: X2(pK), W: W2(pK, S), c: P.PT }] : []),
      ...(cK != null && cK > S ? [{ key: 'c', l: dir(cK / S - 1), x: X2((cK + (pK != null && pK > S && pK < cK ? pK : S)) / 2), L: X2(S), W: W2(S, cK), c: P.CL }] : []),
    ],
  };
}
const legsOf = (ls: { K: number; n: number }[], one: string, many: string) => ls.map((l) => `${l.n} ${l.n === 1 ? one : many} ${fk(l.K)}`).join(', ');

export interface PairTab { key: 'new' | 'hold' | 'both'; label: string; cop: string; tot: number; lead: string; tail: string; pz: SdZone }
type PL = { K: number; n: number; at: number };
/** A pair of sold calls and sold puts on one expiry, any number of strikes (Nik 11 Nov): only one side can end in the
    money, so all the premium cushions it. The same sums as heldPair in _shared/sd-engine.ts. Null when a side is
    empty, it never makes money, or the puts' premium covers a fall to zero. */
export function pairOf(calls: PL[], puts: PL[], S: number, m: number) {
  if ((!calls.length && !puts.length) || !(S > 0) || !(m > 0)) return null;
  const all = [...calls, ...puts], T = all.reduce((a, l) => a + l.n * l.at, 0);
  const pl = (X: number) => T - calls.reduce((a, l) => a + l.n * Math.max(0, X - l.K), 0) - puts.reduce((a, l) => a + l.n * Math.max(0, l.K - X), 0);
  const top = all.map((l) => l.K).reduce((b, K) => (pl(K) > pl(b) ? K : b));
  if (!(pl(top) > 0)) return null;
  const root = (lo: number, hi: number, up: boolean) => {
    for (let i = 0; i < 200; i++) { const md = (lo + hi) / 2; if ((pl(md) > 0) === up) lo = md; else hi = md; }
    return (lo + hi) / 2;
  };
  let up: number | null = null, dn: number | null = null;
  if (calls.length) { let hi = top * 2; while (pl(hi) > 0) hi *= 2; up = root(top, hi, true); }
  if (puts.length) { if (pl(0) > 0) return null; dn = root(0, top, false); }
  return {
    up, dn, tot: T * 100,
    sdUp: up != null ? Math.log(up / S) / m : null, sdDn: dn != null ? Math.log(S / dn) / m : null,
    cop: (up != null ? N(Math.log(up / S) / m) : 1) - (dn != null ? N(Math.log(dn / S) / m) : 0),
  };
}
export interface LadRow { key: string; sdL: string; K: string; pct: string; prT: string; be: string; itm: string; bg: string; ring: string; rad: string; fw: number; sug: boolean; dc: string }

/** card136, web mode, on the server's reply. */
export function sdView(d: SdReply, pick: SdPick, set: (p: SdPick) => void): SdView | null {
  if (!d?.ok || !d.exps?.length) return null;
  const mine = pick.t === d.t;
  const ei = Math.max(0, mine && pick.ex ? d.exps.findIndex((x) => x.ex === pick.ex) : 0);
  const e = d.exps[ei], S = d.S, m = e.m, cfg = d.cfg;
  // A pick outside the rules' range (the reply changed under it) goes back to the suggestion.
  const okC = (k: number | null) => k != null && k >= cfg.cLo - 1e-9 && k <= cfg.cHi + 1e-9;
  const okP = (k: number | null) => k != null && k >= cfg.pLo - 1e-9 && k <= cfg.pHi + 1e-9;
  const samePick = mine && pick.ex === e.ex;
  const selC = samePick && okC(pick.c) ? pick.c! : e.sug.kc, selP = samePick && okP(pick.p) ? pick.p! : e.sug.kp;
  const rc = rowAt(e, selC, false) ?? e.sug.C, rp = rowAt(e, selP, true) ?? e.sug.P;
  // What you hold on this expiry, from the sold legs (premium = the breakeven's distance from the strike).
  const sideOf = (put: boolean) => (d.sold ?? []).filter((x) => x.put === put && x.ex === e.ex && x.be != null).map((x) => ({ K: x.K, n: x.n, at: Math.abs(x.be! - x.K) }));
  const hc = sideOf(false), hp = sideOf(true);
  const { calls: nC, puts: nP } = d.counts ?? { calls: 0, puts: 0 };
  const restC = Math.max(0, nC - hc.reduce((a, l) => a + l.n, 0)), restP = Math.max(0, nP - hp.reduce((a, l) => a + l.n, 0));
  // How many to sell now (Nik, 11 Nov 2026): his count, else the rest of the counts. Only one side can end in the
  // money, so all the premium cushions it, spread over that side's count.
  const qC = Math.max(0, Math.round(samePick && pick.nc != null ? pick.nc : restC)), qP = Math.max(0, Math.round(samePick && pick.np != null ? pick.np : restP));
  const nw = pairOf(qC ? [{ K: rc.K, n: qC, at: rc.pr }] : [], qP ? [{ K: rp.K, n: qP, at: rp.pr }] : [], S, m);
  const tot = (qC ? rc.pr : 0) + (qP ? rp.pr : 0), cop = nw?.cop ?? 0;
  const go = (q: Partial<SdPick>) => set({ t: d.t, ex: e.ex, c: selC, p: selP, nc: samePick ? pick.nc : null, np: samePick ? pick.np : null, ...q });

  const exps = d.exps.map((x, i) => ({
    key: x.ex, t: x.label, d: x.cd === 1 ? '1 day' : x.cd + ' days', on: i === ei, isE: !!x.earn,
    go: () => set({ t: d.t, ex: x.ex, c: null, p: null }),
  }));

  const FX: Record<string, string> = { c: P.CL, p: P.PT, b: P.ink, x: P.OR, n: P.mu };
  const VC: Record<string, string> = { ink: P.ink, green: P.G, red: P.RD, or: P.OR };
  const sig = (e.sig ?? []).map((g) => ({
    key: g.key, k: g.k, v: g.v, vc: VC[g.vTone] ?? P.ink, tag: g.tag ?? '', tagc: g.tagTone === 'or' ? P.OR : P.mu, s: g.s ?? '',
    fx: (g.fx ?? []).map(([k, t], i) => ({ key: i, t, c: FX[k] ?? P.mu })),
  }));

  // A1: the won rates read as estimated (≈) when the history behind them was scaled from HV20.
  const wonT = (r: SdRow) => (r.won == null ? '' : (e.hist?.est ? '≈ ' : '') + pc(r.won) + ' won');
  const opts = (put: boolean) => steps(put ? cfg.pLo : cfg.cLo, put ? cfg.pHi : cfg.cHi).map((k) => {
    const r = rowAt(e, k, put), sug = same(k, put ? e.sug.kp : e.sug.kc), on = same(k, put ? selP : selC);
    return {
      key: (put ? 'p' : 'c') + k, sd: sdl(k), strike: r ? fk(r.K) : '', pr: r ? '$' + f2(r.pr) : '', won: r ? wonT(r) : '', sug, on,
      go: () => go(put ? { p: k } : { c: k }),
    };
  }).filter((o) => o.strike);
  const rng = [
    { key: 'c', h: 'Sell call', c: P.CL, rT: range(cfg.cLo, cfg.cHi), o: opts(false) },
    { key: 'p', h: 'Sell put', c: P.PT, rT: range(cfg.pLo, cfg.pHi), o: opts(true) },
  ];

  const pz = nw ? zoneOf(S, qP ? rp.K : null, qC ? rc.K : null, nw.dn, nw.up, nw.sdDn, nw.sdUp) : null;
  // The tabs: What you hold, and Both = what you hold plus the count at the picked strikes.
  const hold = pairOf(hc, hp, S, m);
  const mix = hold ? pairOf([...hc, ...(qC ? [{ K: rc.K, n: qC, at: rc.pr }] : [])], [...hp, ...(qP ? [{ K: rp.K, n: qP, at: rp.pr }] : [])], S, m) : null;
  const restT = [qC ? legsOf([{ K: rc.K, n: qC }], 'call', 'calls') : '', qP ? legsOf([{ K: rp.K, n: qP }], 'put', 'puts') : ''].filter(Boolean).join(' and ');
  const lowK = (ls: { K: number }[]) => (ls.length ? Math.min(...ls.map((l) => l.K)) : null), highK = (ls: { K: number }[]) => (ls.length ? Math.max(...ls.map((l) => l.K)) : null);
  const tryTrades = [
    ...(qC > 0 ? [{ side: 's' as const, ty: 'c' as const, K: rc.K, ex: e.ex, n: qC }] : []),
    ...(qP > 0 ? [{ side: 's' as const, ty: 'p' as const, K: rp.K, ex: e.ex, n: qP }] : []),
  ];
  const newN = [qC ? `${qC} ${qC === 1 ? 'call' : 'calls'}` : '', qP ? `${qP} ${qP === 1 ? 'put' : 'puts'}` : ''].filter(Boolean).join(' and ');
  const tryIt = tryTrades.length ? {
    label: 'Sell ' + tryTrades.map((x) => `${x.n} ${e.label} ${fk(x.K)} ${x.ty === 'c' ? (x.n === 1 ? 'call' : 'calls') : (x.n === 1 ? 'put' : 'puts')}`).join(' and '),
    trades: tryTrades,
  } : null;
  const tabs: PairTab[] | null = hold && mix && nw && pz ? [
    { key: 'new', label: 'New', cop: pc(cop), tot: nw.tot, lead: 'Total', tail: `for ${newN} · $${f2(tot)} a share`, pz },
    { key: 'hold', label: 'What you hold', cop: pc(hold.cop), tot: hold.tot, lead: 'Taken in', tail: `for ${legsOf(hc, 'call', 'calls')} and ${legsOf(hp, 'put', 'puts')}`,
      pz: zoneOf(S, highK(hp), lowK(hc), hold.dn, hold.up, hold.sdDn, hold.sdUp) },
    { key: 'both', label: 'Both', cop: pc(mix.cop), tot: mix.tot, lead: 'In all', tail: restT ? `for what you hold plus ${restT}` : 'for what you hold, nothing new',
      pz: zoneOf(S, highK(qP ? [...hp, { K: rp.K }] : hp), lowK(qC ? [...hc, { K: rc.K }] : hc), mix.dn, mix.up, mix.sdDn, mix.sdUp) },
  ] : null;

  // Every SD: the boxed range the rules allow, the picked row ringed, the suggestion's dot.
  const zone = (k: number, lo: number, hi: number, on: boolean, put: boolean, flip: boolean) => {
    const inZ = k >= lo - 1e-9 && k <= hi + 1e-9, zl = put ? P.pzL : P.czL;
    const sh = (t: boolean, b: boolean) => ['inset 1px 0 0 ' + zl, 'inset -1px 0 0 ' + zl].concat(t ? ['inset 0 1px 0 ' + zl] : [], b ? ['inset 0 -1px 0 ' + zl] : []).join(',');
    const rd = (a: boolean, b: boolean) => (a && b ? '10px' : a ? '10px 10px 0 0' : b ? '0 0 10px 10px' : '0');
    const isLo = same(k, lo), isHi = same(k, hi), t = flip ? isHi : isLo, b = flip ? isLo : isHi;
    return {
      bg: inZ ? (on ? (put ? P.pzB2 : P.czB2) : (put ? P.pzB : P.czB)) : 'transparent',
      ring: on ? 'inset 0 0 0 1.5px ' + (put ? P.PT : P.CL) : inZ ? sh(t, b) : 'none',
      rad: inZ ? rd(t, b) : '10px',
    };
  };
  const lad = (put: boolean): LadRow[] => {
    // The table's rows start at ATM: one strike in the money (k below 0) is a tile only.
    const lo = Math.max(0, put ? cfg.pLo : cfg.cLo), hi = put ? cfg.pHi : cfg.cHi, Kf = put ? e.sug.P.K : e.sug.C.K;
    const rows = (put ? e.rows.p : e.rows.c).map((r) => {
      const sug = same(r.k, put ? e.sug.kp : e.sug.kc), on = same(r.k, put ? selP : selC);
      return {
        key: (put ? 'p' : 'c') + r.k, sdL: sdl(r.k), K: fk(r.K) + (sug && Kf !== r.K ? ' → ' + fk(Kf) : ''), pct: dir(r.pct),
        prT: (r.est ? '≈ ' : '') + f2(r.pr) + (r.liq && !r.est ? ' !' : ''), be: f2(r.be), itm: pc(r.itm),
        ...zone(r.k, lo, hi, on, put, !put), fw: on ? 700 : 500, sug, dc: put ? P.PT : P.CL,
      };
    });
    // Calls run from 2.0 SD down to ATM, so the price runs top to bottom through the TODAY line.
    return put ? rows : rows.slice().reverse();
  };

  return {
    t: d.t, S, pxT: '$' + f2(S), ei, e,
    ivT: pc(e.iv), sdP: '±' + pc(m), sdD: '±$' + f2(S * m),
    exps, sig, rng,
    both: { cop: nw ? pc(cop) : 'None', prT: '$' + f2(tot), tot: nw?.tot ?? 0, totN: newN || 'nothing to sell' },
    qty: { c: qC, p: qP, setC: (n: number) => go({ nc: Math.max(0, Math.round(n || 0)) }), setP: (n: number) => go({ np: Math.max(0, Math.round(n || 0)) }) },
    pz, tabs, tryIt, ladC: lad(false), ladP: lad(true),
    chart: {
      band: e.band,
      C: { K: rc.K, label: `${fk(rc.K)} call · ${e.label}` },
      P: { K: rp.K, label: `${fk(rp.K)} put · ${e.label}` },
      sold: (d.sold ?? []).map((s) => ({ K: s.K, be: s.be, label: `Sold ${fk(s.K)} ${s.put ? 'put' : 'call'}` + (s.be != null ? ` · BE ${f2(s.be)}` : '') })),
      pair: (d.held ?? []).flatMap((h) => [h.dn, h.up].map((K) => ({ K, label: `${h.label} pair · BE ${f2(K)}` }))),
    },
  };
}
