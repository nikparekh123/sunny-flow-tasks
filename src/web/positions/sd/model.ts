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
export interface SdReply {
  ok: boolean; v: number; t: string; name: string; S: number; prev: number; move: number; open: boolean; today: string;
  cfg: { cLo: number; cHi: number; pLo: number; pHi: number };
  counts: { calls: number; puts: number };
  sold: SdSold[];
  exps: SdExp[];
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
export const sdl = (k: number) => (k === 0 ? 'ATM' : (k % 1 ? String(k) : k.toFixed(1)) + ' SD');
/** The design's normal CDF (Abramowitz and Stegun 26.2.17). */
export const N = (x: number) => {
  const t = 1 / (1 + 0.2316419 * Math.abs(x)), d = 0.3989422804014327 * Math.exp(-x * x / 2),
    q = d * t * (0.31938153 + t * (-0.356563782 + t * (1.781477937 + t * (-1.821255978 + t * 1.330274429))));
  return x > 0 ? 1 - q : q;
};
const same = (a: number, b: number) => Math.abs(a - b) < 1e-9;
const steps = (lo: number, hi: number) => { const o: number[] = []; for (let k = lo; k <= hi + 1e-9; k += 0.25) o.push(Math.round(k * 4) / 4); return o; };
/** "0.5 to 1.25 SD", "ATM to 1 SD" (Nik, D2: the put row's label reads ATM to 1 SD). */
const range = (lo: number, hi: number) => (lo === 0 ? 'ATM' : String(lo)) + ' to ' + String(hi) + ' SD';

/* ── What the user picked: the expiry, then a call and a put SD (default: that expiry's suggestion) ── */
export interface SdPick { t: string; ex: string | null; c: number | null; p: number | null }
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
  pz: {
    zL: string; zW: string; mL: string; mW: string; today: string;
    top: { key: string; x: string; l: string; c: string }[];
    dist: { key: string; l: string; x: string; L: string; W: string; c: string }[];
    bot: { key: string; x: string; l: string; s: string }[];
  };
  ladC: LadRow[]; ladP: LadRow[];
  /** What the payoff chart draws (README 1.9). */
  chart: { band: [number, number]; C: { K: number; label: string }; P: { K: number; label: string }; sold: { K: number; be: number | null; label: string }[] };
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
  const tot = rc.pr + rp.pr, up = rc.K + tot, dn = rp.K - tot, cop = N(Math.log(up / S) / m) - N(Math.log(dn / S) / m);
  const go = (q: Partial<SdPick>) => set({ t: d.t, ex: e.ex, c: selC, p: selP, ...q });

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

  // The timeline: from the lower breakeven (or the put) to the upper breakeven (or the call), 12% padding each side.
  const a0 = Math.min(dn, rp.K), b0 = Math.max(up, rc.K), pad = (b0 - a0) * 0.12, A = a0 - pad, B = b0 + pad;
  const X2 = (v: number) => ((v - A) / (B - A) * 100).toFixed(2) + '%', W2 = (u: number, v: number) => ((v - u) / (B - A) * 100).toFixed(2) + '%';
  const pz = {
    zL: X2(dn), zW: W2(dn, up), mL: X2(rp.K), mW: W2(rp.K, rc.K), today: X2(S),
    top: [{ key: 'p', x: X2(rp.K), l: 'Put ' + fk(rp.K), c: P.PT }, { key: 'c', x: X2(rc.K), l: 'Call ' + fk(rc.K), c: P.CL }],
    bot: [{ key: 'd', x: X2(dn), l: f2(dn), s: 'breakeven' }, { key: 't', x: X2(S), l: '$' + f2(S), s: 'today' }, { key: 'u', x: X2(up), l: f2(up), s: 'breakeven' }],
    dist: [
      { key: 'p', l: dir(rp.K / S - 1), x: X2((rp.K + S) / 2), L: X2(Math.min(rp.K, S)), W: W2(Math.min(rp.K, S), Math.max(rp.K, S)), c: P.PT },
      { key: 'c', l: dir(rc.K / S - 1), x: X2((rc.K + S) / 2), L: X2(Math.min(rc.K, S)), W: W2(Math.min(rc.K, S), Math.max(rc.K, S)), c: P.CL },
    ],
  };

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
    const lo = put ? cfg.pLo : cfg.cLo, hi = put ? cfg.pHi : cfg.cHi, Kf = put ? e.sug.P.K : e.sug.C.K;
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

  const { calls, puts } = d.counts ?? { calls: 0, puts: 0 };
  return {
    t: d.t, S, pxT: '$' + f2(S), ei, e,
    ivT: pc(e.iv), sdP: '±' + pc(m), sdD: '±$' + f2(S * m),
    exps, sig, rng,
    both: { cop: pc(cop), prT: '$' + f2(tot), tot: (rc.pr * calls + rp.pr * puts) * 100, totN: `${calls} ${calls === 1 ? 'call' : 'calls'} and ${puts} ${puts === 1 ? 'put' : 'puts'}` },
    pz, ladC: lad(false), ladP: lad(true),
    chart: {
      band: e.band,
      C: { K: rc.K, label: `${fk(rc.K)} call · ${e.label}` },
      P: { K: rp.K, label: `${fk(rp.K)} put · ${e.label}` },
      sold: (d.sold ?? []).map((s) => ({ K: s.K, be: s.be, label: `Sold ${fk(s.K)} ${s.put ? 'put' : 'call'}` + (s.be != null ? ` · BE ${f2(s.be)}` : '') })),
    },
  };
}
