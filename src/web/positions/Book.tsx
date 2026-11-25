// Every leg (handoff 2026-11-24 §4, round 196 shipped): SunnyBook on the picked name, tone calm, fed from the live
// legs. It replaces the old Every leg table and its Whole book row, and Sold, in SD lives in it now.
//   Header: Every leg and how many legs (no how-to line: Nik, 24 Nov 2026); Rows | List (kept per computer in localStorage sunny.book196w)
//   and the name's price. The whole book on one line: So far, Theta a day, Delta, the nearest call and put sold, To
//   roll. The chips (Expiry · Shares, Calls sold, Puts sold, Calls bought, Puts bought), each its own switch; Switch off all (Switch on all when nothing counts);
//   Reset when a chip is off. The status legend.
//   Rows: a group an expiry (its switch, a fold, So far, Delta and Theta of what counts), each a ladder: calls above
//   today's price, puts below, the highest strike first. Shares last.
//   List: a group by what each leg needs (In the money, Danger, Roll, Watch, Safe, Bought, Shares), nearest first.
// Each leg: its switch, SD sold → now (sunny-sd sold[].z0 when sold; now from the leg's own IV over the trading days
// left, positions-engine), the breakeven under 0.5 SD, the status (Danger under 0.5 SD, Watch to 1 SD, Safe past it,
// Roll at 90% kept, In the money, Bought), sold at → now with kept, So far, Delta, Theta a day.
// Each leg by what it is (Nik, 24 Nov 2026): Shares, Calls bought, Calls sold, Puts bought, Puts sold; never Long, Hedge
// or Income (Long and Short stay only as a delta's direction).
// Calm: colour only on Danger, In the money, Roll and losses; legs with nothing to do read grey. A leg counts when
// its own switch and each of its chips are on; off legs fade and leave Payoff and the Greeks (the page's sets).
// No em dashes, no minus signs on money.
import { useMemo, useState, type CSSProperties } from 'react';
import { count, money } from '../lib/format';
import { fk, type PLeg, type Pricer } from './model';
import { sideOf } from './totals';

const W = '#F5F5F7', MU = '#98989D', TX = '#AEAEB2', QG = '#8E8E93', RED = '#FF6961', GRN = '#65C466';
const VKEY = 'sunny.book196w';
type View = 'rows' | 'list';
const readView = (): View => { try { return localStorage.getItem(VKEY) === 'list' ? 'list' : 'rows'; } catch { return 'rows'; } };
const writeView = (v: View) => { try { localStorage.setItem(VKEY, v); } catch { /* private window */ } };

/** One leg as the page hands it over: the leg, its own switch, whether it counts, and its SD. */
export interface BookItem {
  l: PLeg;
  /** Its own switch. */
  on: boolean;
  /** Its own switch and each of its chips on: it is in Payoff and the Greeks. */
  eff: boolean;
  /** A What if trade or a strike tried from Intelligence (not held). */
  added: boolean;
  tried: boolean;
  tg: () => void;
  /** Room to the strike in SD, signed (under 0 in the money): when sold (null: not saved) and now. */
  s0: number | null;
  sN: number;
  /** The labels of the chips that switch it off ("Calls", "Nov 27"). */
  offBy: string[];
}
export interface BookChip { k: string; l: string; on: boolean; go: () => void }

type St = '' | 'itm' | 'dan' | 'wat' | 'safe' | 'roll' | 'hed';
const ST: Record<Exclude<St, ''>, [string, string, string, string]> = {
  itm: ['In the money', RED, '#000000', 'none'], dan: ['Danger', 'rgba(255,105,97,.18)', RED, 'none'],
  wat: ['Watch', 'transparent', QG, 'none'], safe: ['Safe', 'transparent', QG, 'none'],
  roll: ['Roll', GRN, '#000000', 'none'], hed: ['Bought', 'transparent', MU, 'inset 0 0 0 1px rgba(255,255,255,.22)'],
};
const WD = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'], MO = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
/** "Nov 27", or "Mar 19 ’27" past six months (chips name a day, never only a month). */
export const exShort = (iso: string, days: number) => { const [y, m, d] = iso.split('-').map(Number); return `${MO[m - 1]} ${d}` + (days > 183 ? ` ’${String(y).slice(2)}` : ''); };
const exLong = (iso: string, days: number) => { const [y, m, d] = iso.split('-').map(Number); return `${WD[new Date(Date.UTC(y, m - 1, d)).getUTCDay()]} ${exShort(iso, days)}`; };
const f2 = (x: number) => x.toFixed(2);
const dTx = (v: number) => (v < 0 ? 'short ' : 'long ') + count(v);
const sw = (on: boolean | 'mixed') => ({ bg: on === true ? GRN : on === 'mixed' ? 'rgba(101,196,102,.45)' : 'rgba(120,120,128,.32)', kl: on === true ? 18 : on === 'mixed' ? 10 : 2 });

function Sw({ on, label, go }: { on: boolean | 'mixed'; label: string; go: () => void }) {
  const s = sw(on);
  return (
    <button type="button" role="switch" aria-checked={on === 'mixed' ? 'mixed' : on} aria-label={label} onClick={go} className="bare"
      style={{ position: 'relative', flex: 'none', width: 40, height: 24, borderRadius: 12, background: s.bg, transition: 'background .2s' }}>
      <span style={{ position: 'absolute', top: 2, left: s.kl, width: 20, height: 20, borderRadius: '50%', background: '#FFFFFF', boxShadow: '0 2px 4px rgba(0,0,0,.35)', transition: 'left .2s cubic-bezier(.22,1,.36,1)' }} />
    </button>
  );
}

interface Row {
  it: BookItem; k: string; st: St; sold: boolean; sh: boolean; hd: boolean;
  sf: number; dl: number; th: number; kp: number | null; be: number; days: number;
}

export function Book({ t, S0, P0, pr, items, chips, mL, mGo, reset, setL, mask }: {
  t: string; S0: number; P0: number; pr: Pricer; items: BookItem[]; chips: BookChip[][];
  mL: string; mGo: () => void; reset: (() => void) | null; setL: (xs: BookItem[], v: boolean) => void; mask: (s: string) => string;
}) {
  const [view, setViewS] = useState<View>(readView);
  const setView = (v: View) => { setViewS(v); writeView(v); };
  const [col, setCol] = useState<Record<string, boolean>>({});
  const m = pr.m, D = m.today;
  const km = (x: number) => mask(money(x));

  const rows: Row[] = useMemo(() => items.map((it) => {
    const l = it.l, sh = l.ty === 'S', sold = !sh && l.q < 0, hd = !sh && l.q > 0;
    const sf = sh ? l.q * (S0 - l.K) : l.at != null && !it.added ? (l.now - l.at) * l.q * 100 : 0;
    const dl = pr.dL(l, S0, D), th = sh ? 0 : pr.thL(l, S0, D);
    const kp = sold && l.at != null && l.at > 0 ? Math.round((1 - l.now / l.at) * 100) : null;
    const st: St = sh ? '' : hd ? 'hed' : it.sN < 0 ? 'itm' : it.sN < 0.5 ? 'dan' : (kp ?? 0) >= 90 ? 'roll' : it.sN < 1 ? 'wat' : 'safe';
    const at = l.at ?? l.now;
    return { it, k: l.k, st, sold, sh, hd, sf, dl, th, kp, be: l.ty === 'C' ? l.K + at : l.K - at, days: sh ? 1e6 : m.wholeDays(l.ex) };
  }), [items, pr, S0, D, m]);

  /* ── One leg's cells (the design's row()) ── */
  const cell = (r: Row) => {
    const { it, st, sold, sh, hd } = r, l = it.l;
    const q = st !== 'itm' && st !== 'dan' && st !== 'roll', tx = q ? TX : W;
    const qc = (x: number) => (x <= -0.5 ? RED : q ? tx : x >= 0.5 ? W : MU);
    const P = st ? ST[st] : null;
    const s0 = it.s0 ?? (it.added ? it.sN : null);
    const dS = sold && s0 != null ? Math.round(it.sN * 100) - Math.round(s0 * 100) : 0;
    const nm = sh ? 'Shares' : `${fk(l.K)} ${l.ty === 'C' ? 'call' : 'put'}`;
    const cnt = sh ? `${count(l.q)} at $${f2(l.K)}` : `${sold ? 'Sold ×' : 'Bought ×'}${count(l.q)}${it.tried ? ' · from Intelligence' : it.added ? ' · a what if' : ''}`;
    const sdN = sh ? '' : it.sN < 0 ? 'In the money' : `${f2(it.sN)} SD`;
    const gn = hd && l.at ? Math.round((l.now / l.at - 1) * 100) : 0;
    const px2 = sold && r.kp != null ? (r.kp >= 0 ? `${r.kp}% kept` : `${Math.abs(r.kp)}% lost`) : hd && l.at ? `${gn >= 0 ? 'Up' : 'Down'} ${Math.abs(gn)}%` : '';
    const px1 = sh ? `$${f2(l.K)} → $${f2(S0)}` : `${l.at != null ? f2(l.at) : '-'} → ${f2(l.now)}`;
    const ex0 = sh ? '' : l.exL;
    return {
      nm, cnt, ex0, tx, q, P, op: it.eff ? 1 : 0.4,
      sd0: sold && s0 != null ? (s0 < 0 ? 'In the money' : f2(s0)) : '', arr: sold && s0 != null ? '→' : '',
      arc: q ? MU : dS < 0 ? RED : dS > 0 ? GRN : MU, sdN, sdc: sold && it.sN < 0.5 ? RED : tx,
      be: sold && it.sN < 0.5 ? `Breakeven ${f2(r.be)}` : '', px1, px2, px2c: (sold && (r.kp ?? 0) < 0) || (hd && gn < 0) ? RED : MU,
      sf: it.added ? 'new' : km(r.sf), sfc: it.added ? MU : qc(r.sf), dl: dTx(r.dl), th: sh ? '$0' : km(r.th), thc: sh ? MU : qc(r.th),
      kw: `${Math.max(0, Math.min(100, r.kp ?? 0))}%`, kbg: (r.kp ?? 0) >= 90 ? GRN : '#636366',
      ftL: sh ? 'Delta' : 'Theta a day', ftV: sh ? dTx(r.dl) : km(r.th), ftc: sh ? tx : qc(r.th),
      aria: [nm, ex0, cnt, P ? P[0] : '', sold ? `sold at ${s0 == null ? 'an SD not saved' : s0 < 0 ? 'in the money' : f2(s0) + ' SD'}, now ${sdN}${dS < 0 ? ', closer' : dS > 0 ? ', farther' : ''}` : sdN, px2,
        it.added ? 'new' : `${r.sf < 0 ? 'down ' : 'up '}${km(r.sf)} so far`, it.eff ? '' : 'off'].filter(Boolean).join(', '),
      swL: `${it.on ? 'Switch off' : 'Switch on'} ${nm}${sh ? '' : ' ' + l.exL}`,
    };
  };

  const sums = (rs: Row[]) => {
    const on = rs.filter((r) => r.it.eff), s = on.reduce((a, r) => ({ sf: a.sf + (r.it.added ? 0 : r.sf), dl: a.dl + r.dl, th: a.th + r.th }), { sf: 0, dl: 0, th: 0 });
    const own = rs.filter((r) => r.it.on).length;
    return { ...s, none: !on.length, ac: (own === rs.length ? true : !own ? false : 'mixed') as boolean | 'mixed', own };
  };
  const cl = (x: number) => (x >= 0.5 ? W : x <= -0.5 ? RED : MU);
  const mTog = (rs: Row[]) => () => setL(rs.map((r) => r.it), !rs.some((r) => r.it.on));

  /* ── The whole book on one line ── */
  const all = sums(rows), soldOn = rows.filter((r) => r.it.eff && r.sold);
  const nC = soldOn.filter((r) => r.it.l.ty === 'C').sort((a, b) => a.it.sN - b.it.sN)[0], nP = soldOn.filter((r) => r.it.l.ty === 'P').sort((a, b) => a.it.sN - b.it.sN)[0];
  const nR = soldOn.filter((r) => r.st === 'roll').length;
  const nTx = (r: Row) => `${fk(r.it.l.K)} ${r.it.l.exL} · ${r.it.sN < 0 ? 'in the money' : f2(r.it.sN) + ' SD'}`;
  const top: { k: string; l: string; v: string; c: string }[] = [
    { k: 'sf', l: 'So far', v: km(all.sf), c: cl(all.sf) }, { k: 'th', l: 'Theta a day', v: km(all.th), c: cl(all.th) },
    { k: 'dl', l: 'Delta', v: all.none ? 'off' : dTx(all.dl), c: all.none ? MU : all.dl < 0 ? RED : W },
    ...(nC ? [{ k: 'nc', l: 'Nearest call sold', v: nTx(nC), c: nC.it.sN < 0.5 ? RED : W }] : []),
    ...(nP ? [{ k: 'np', l: 'Nearest put sold', v: nTx(nP), c: nP.it.sN < 0.5 ? RED : W }] : []),
    ...(nR ? [{ k: 'nr', l: 'To roll', v: `${nR} at 90% kept`, c: GRN }] : []),
  ];
  const nS = rows.filter((r) => r.sold).length, nH = rows.filter((r) => r.hd).length, hasSh = rows.some((r) => r.sh), nOff = rows.filter((r) => !r.it.eff).length;
  const cnt = `${rows.length} ${rows.length === 1 ? 'leg' : 'legs'} · ` + [nS ? `${nS} sold` : '', nH ? `${nH} bought` : '', hasSh ? 'shares' : ''].filter(Boolean).join(', ') + (nOff ? ` · ${nOff} off` : '');
  const ch = P0 > 0 ? (S0 / P0 - 1) * 100 : 0, mvA = Math.abs(ch) < 0.05 ? '' : ch > 0 ? '↑' : '↓', mvT = Math.abs(ch) < 0.05 ? 'Flat today' : `${Math.abs(ch).toFixed(1)}% today`;

  /* ── Rows: a group an expiry ── */
  const exKeys = [...new Set(rows.filter((r) => !r.sh).map((r) => r.it.l.ex))].sort();
  const groups = [...exKeys, ...(hasSh ? ['none'] : [])].map((gk) => {
    const rs = rows.filter((r) => (gk === 'none' ? r.sh : !r.sh && r.it.l.ex === gk));
    const s = sums(rs), open = col[gk] != null ? !col[gk] : !s.none;
    const days = gk === 'none' ? 0 : m.wholeDays(gk);
    const cs = rs.filter((r) => r.it.l.ty === 'C').sort((a, b) => b.it.l.K - a.it.l.K), ps = rs.filter((r) => r.it.l.ty === 'P').sort((a, b) => b.it.l.K - a.it.l.K);
    // What a chip from another row switched off in this group ("2 off with Calls"); its own chip says "switched off".
    const by = rs.filter((r) => r.it.offBy.length), ownL = gk === 'none' ? 'Shares' : exShort(gk, days);
    const own = by.length === rs.length && rs.every((r) => r.it.offBy.includes(ownL));
    const labs = [...new Set(by.flatMap((r) => r.it.offBy.filter((x) => x !== ownL)))];
    const offT = own ? 'switched off' : by.length ? `${by.length} off with ${labs.length > 2 ? labs.slice(0, 2).join(', ') + ' and more' : labs.join(' and ')}` : '';
    return {
      k: gk, rs, s, open, cs, ps,
      t: gk === 'none' ? 'Shares' : exLong(gk, days),
      sub: [gk === 'none' ? 'no expiry' : days <= 0 ? 'today' : days === 1 ? '1 day' : `${days} days`, `${rs.length} ${rs.length === 1 ? 'leg' : 'legs'}`, offT].filter(Boolean).join(' · '),
    };
  }).filter((g) => g.rs.length);

  /* ── List: a group by what each leg needs ── */
  const SG: [St, string, string, string][] = [['itm', 'In the money', 'past the strike', RED], ['dan', 'Danger', 'under 0.5 SD from the strike', RED], ['roll', 'Roll', '90% or more kept, ready to roll', GRN],
    ['wat', 'Watch', '0.5 to 1 SD from the strike', W], ['safe', 'Safe', 'over 1 SD from the strike', W], ['hed', 'Bought', 'nearest first', W], ['', 'Shares', 'no expiry', W]];
  const lst = view !== 'list' ? [] : SG.map(([sk, tt, sub, tc]) => {
    const rs = rows.filter((r) => r.st === sk).sort((a, b) => (sk === 'roll' ? (b.kp ?? 0) - (a.kp ?? 0) : a.it.sN - b.it.sN));
    return { k: 'L' + sk, rs, s: sums(rs), t: `${tt} · ${rs.length}`, sub, tc, tt };
  }).filter((g) => g.rs.length);

  const COLS = '44px minmax(112px,1fr) 170px 116px 150px 88px 100px 88px', MINW = 980;
  const head: CSSProperties = { fontSize: 12, lineHeight: '16px', fontWeight: 600, letterSpacing: '.05em', textTransform: 'uppercase', color: MU };
  const pill = (P: [string, string, string, string] | null, h = 24, pad = '0 9px', fs = 12) => P && (
    <span style={{ height: h, padding: pad, borderRadius: 6, background: P[1], boxShadow: P[3], display: 'inline-flex', alignItems: 'center', fontSize: fs, lineHeight: 1, fontWeight: 700, color: P[2], whiteSpace: 'nowrap' }}>{P[0]}</span>
  );
  const sdCell = (c: ReturnType<typeof cell>) => (
    <span style={{ display: 'flex', flexDirection: 'column', gap: 1, opacity: c.op }}>
      <span style={{ fontSize: 14, lineHeight: '20px', whiteSpace: 'nowrap' }}>
        {c.sd0 && <><span style={{ color: MU }}>{c.sd0}</span> <span style={{ fontWeight: 700, color: c.arc }}>{c.arr}</span> </>}
        <span style={{ fontWeight: 600, color: c.sdc }}>{c.sdN}</span>
      </span>
      {c.be && <span style={{ fontSize: 12, lineHeight: '16px', color: MU, whiteSpace: 'nowrap' }}>{c.be}</span>}
    </span>
  );
  const today = (k: string, pad: string) => (
    <div key={k} style={{ display: 'flex', alignItems: 'center', gap: 10, minWidth: MINW, padding: pad }}>
      <span style={{ fontSize: 12, lineHeight: '16px', fontWeight: 700, whiteSpace: 'nowrap' }}>{f2(S0)} today</span>
      <span aria-hidden="true" style={{ flex: 1, height: 1, background: 'rgba(245,245,247,.4)' }} />
    </div>
  );
  const rowEl = (r: Row) => {
    const c = cell(r);
    return (
      <div key={r.k} role="row" aria-label={mask(c.aria)} style={{ display: 'grid', gridTemplateColumns: COLS, minWidth: MINW, gap: 16, alignItems: 'center', minHeight: 54, color: c.tx, borderTop: '1px solid rgba(255,255,255,.07)' }}>
        <Sw on={r.it.on} label={c.swL} go={r.it.tg} />
        <span style={{ display: 'flex', flexDirection: 'column', gap: 1, minWidth: 0, opacity: c.op }}>
          <span style={{ fontSize: 15, lineHeight: '20px', fontWeight: 600, whiteSpace: 'nowrap' }}>{c.nm}</span>
          <span style={{ fontSize: 12, lineHeight: '16px', color: MU, whiteSpace: 'nowrap' }}>{c.cnt}</span>
        </span>
        {sdCell(c)}
        <span style={{ display: 'flex', opacity: c.op }}>{pill(c.P)}</span>
        <span style={{ display: 'flex', flexDirection: 'column', gap: 1, opacity: c.op }}>
          <span style={{ fontSize: 14, lineHeight: '20px', whiteSpace: 'nowrap' }}>{c.px1}</span>
          {c.px2 && <span style={{ fontSize: 12, lineHeight: '16px', color: c.px2c, whiteSpace: 'nowrap' }}>{c.px2}</span>}
        </span>
        <span style={{ fontSize: 14, fontWeight: 600, color: c.sfc, opacity: c.op }}>{c.sf}</span>
        <span style={{ fontSize: 14, whiteSpace: 'nowrap', opacity: c.op }}>{c.dl}</span>
        <span style={{ fontSize: 14, color: c.thc, opacity: c.op }}>{c.th}</span>
      </div>
    );
  };
  const listRow = (r: Row) => {
    const c = cell(r);
    return (
      <div key={r.k} role="listitem" aria-label={mask(c.aria)} style={{ color: c.tx, display: 'grid', gridTemplateColumns: '40px minmax(170px,1.3fr) minmax(170px,1fr) minmax(200px,1fr) 96px 112px', gap: 16, alignItems: 'center',
        minHeight: 62, padding: '9px 18px', borderTop: '1px solid rgba(255,255,255,.06)', marginTop: -1 }}>
        <Sw on={r.it.on} label={c.swL} go={r.it.tg} />
        <span style={{ display: 'flex', flexDirection: 'column', gap: 2, minWidth: 0, opacity: c.op }}>
          <span style={{ display: 'flex', alignItems: 'baseline', gap: 8, whiteSpace: 'nowrap' }}>
            <span style={{ fontSize: 15, lineHeight: '20px', fontWeight: 600 }}>{c.nm}</span>
            {c.ex0 && <span style={{ fontSize: 13, lineHeight: '18px', color: MU }}>{c.ex0}</span>}
          </span>
          <span style={{ fontSize: 12, lineHeight: '16px', color: MU, whiteSpace: 'nowrap' }}>{c.cnt}</span>
        </span>
        {sdCell(c)}
        <span style={{ display: 'flex', flexDirection: 'column', gap: 6, minWidth: 0, opacity: c.op }}>
          <span style={{ fontSize: 14, lineHeight: '20px', whiteSpace: 'nowrap' }}>{c.px1}{c.px2 && <span style={{ color: c.px2c }}> · {c.px2}</span>}</span>
          {r.sold && (
            <span aria-hidden="true" style={{ position: 'relative', display: 'block', height: 4, maxWidth: 180, borderRadius: 2, background: '#2C2C2E', overflow: 'hidden' }}>
              <span style={{ position: 'absolute', left: 0, top: 0, bottom: 0, width: c.kw, borderRadius: 2, background: c.kbg }} />
            </span>
          )}
        </span>
        <span style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-end', gap: 2, opacity: c.op }}>
          <span style={{ fontSize: 14, lineHeight: '20px', fontWeight: 700, color: c.sfc, whiteSpace: 'nowrap' }}>{c.sf}</span>
          <span style={{ fontSize: 12, lineHeight: '16px', color: MU }}>So far</span>
        </span>
        <span style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-end', gap: 2, opacity: c.op }}>
          <span style={{ fontSize: 14, lineHeight: '20px', fontWeight: 600, color: c.ftc, whiteSpace: 'nowrap' }}>{c.ftV}</span>
          <span style={{ fontSize: 12, lineHeight: '16px', color: MU, whiteSpace: 'nowrap' }}>{c.ftL}</span>
        </span>
      </div>
    );
  };
  const tri = (s: ReturnType<typeof sums>) => ({
    sf: km(s.sf), sfc: s.none ? MU : cl(s.sf), dl: s.none ? 'off' : dTx(s.dl), dlc: s.none ? MU : s.dl < 0 ? RED : W, th: km(s.th), thc: s.none ? MU : cl(s.th),
  });
  const legend: [Exclude<St, ''>, string][] = [['dan', 'under 0.5 SD'], ['wat', '0.5 to 1 SD'], ['safe', 'over 1 SD'], ['roll', '90% kept'], ['itm', ''], ['hed', '']];

  return (
    <div role="region" aria-label="Every leg" className="tnum" style={{ display: 'flex', flexDirection: 'column', gap: 14, minWidth: 0 }}>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', gap: '12px 24px', flexWrap: 'wrap' }}>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 3, flex: '1 1 420px', minWidth: 0 }}>
            <span style={{ display: 'flex', alignItems: 'baseline', gap: 10, flexWrap: 'wrap' }}>
              <span style={{ fontSize: 20, lineHeight: '26px', fontWeight: 700, letterSpacing: '-.01em' }}>Every leg</span>
              <span style={{ fontSize: 13, lineHeight: '18px', color: MU }}>{cnt}</span>
            </span>
          </div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 20, flexWrap: 'wrap', justifyContent: 'flex-end' }}>
            <div role="radiogroup" aria-label="View" style={{ display: 'flex', gap: 2, padding: 2, borderRadius: 999, background: 'rgba(255,255,255,.06)', boxShadow: 'inset 0 0 0 1px rgba(255,255,255,.08)' }}>
              {([['rows', 'Rows'], ['list', 'List']] as [View, string][]).map(([k, l]) => (
                <button key={k} type="button" role="radio" aria-checked={view === k} className="bare" onClick={() => setView(k)}
                  style={{ height: 30, padding: '0 18px', borderRadius: 999, background: view === k ? W : 'transparent', fontSize: 13, lineHeight: '30px', fontWeight: 600,
                    color: view === k ? '#000000' : W, whiteSpace: 'nowrap', transition: 'background .2s,color .2s' }}>{l}</button>
              ))}
            </div>
            <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-end', gap: 2 }}>
              <span style={{ fontSize: 20, lineHeight: '26px', fontWeight: 700, whiteSpace: 'nowrap' }}>{t} {f2(S0)}</span>
              <span style={{ fontSize: 13, lineHeight: '18px', fontWeight: 600, whiteSpace: 'nowrap' }}><span style={{ color: ch > 0 ? GRN : RED }}>{mvA}</span> {mvT}</span>
            </div>
          </div>
        </div>
        <div role="list" aria-label="The whole book" style={{ display: 'flex', flexWrap: 'wrap', gap: '10px 32px', padding: '12px 0', borderTop: '1px solid rgba(255,255,255,.08)', borderBottom: '1px solid rgba(255,255,255,.08)' }}>
          {top.map((x) => (
            <span key={x.k} role="listitem" style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
              <span style={head}>{x.l}</span>
              <span style={{ fontSize: 15, lineHeight: '20px', fontWeight: 700, color: x.c, whiteSpace: 'nowrap' }}>{x.v}</span>
            </span>
          ))}
        </div>
        <div role="group" aria-label="Switch legs on and off" style={{ display: 'flex', flexWrap: 'wrap', alignItems: 'center', gap: 6 }}>
          {chips.map((row, i) => (
            <span key={i} style={{ display: 'contents' }}>
              {i > 0 && <span aria-hidden="true" style={{ width: 1, height: 20, margin: '0 6px', background: 'rgba(255,255,255,.14)' }} />}
              {row.map((c) => (
                <button key={c.k} type="button" aria-pressed={c.on} aria-label={`${c.on ? 'Switch off' : 'Switch on'} ${c.l}`} onClick={c.go} className="bare"
                  style={{ height: 32, padding: '0 12px', borderRadius: 999, background: c.on ? W : 'transparent', boxShadow: c.on ? 'none' : 'inset 0 0 0 1px rgba(255,255,255,.16)',
                    fontSize: 13, lineHeight: '32px', fontWeight: 600, color: c.on ? '#000000' : QG, whiteSpace: 'nowrap', transition: 'background .2s,color .2s' }}>{c.l}</button>
              ))}
            </span>
          ))}
          <span style={{ marginLeft: 'auto', display: 'flex', gap: 6 }}>
            {reset && (
              <button type="button" className="bare swb-out" onClick={reset} aria-label="Reset the chips, every chip on"
                style={{ height: 32, padding: '0 14px', borderRadius: 999, boxShadow: 'inset 0 0 0 1px rgba(255,255,255,.16)', fontSize: 13, lineHeight: '32px', fontWeight: 600, color: W, whiteSpace: 'nowrap' }}>Reset</button>
            )}
            <button type="button" className="bare swb-out" onClick={mGo}
              style={{ height: 32, padding: '0 14px', borderRadius: 999, boxShadow: 'inset 0 0 0 1px rgba(255,255,255,.16)', fontSize: 13, lineHeight: '32px', fontWeight: 600, color: W, whiteSpace: 'nowrap' }}>{mL}</button>
          </span>
        </div>
        <div style={{ display: 'flex', flexWrap: 'wrap', alignItems: 'center', gap: '6px 14px' }}>
          {legend.map(([k, s]) => (
            <span key={k} style={{ display: 'inline-flex', alignItems: 'center', gap: 6, fontSize: 12, lineHeight: '16px', color: MU, whiteSpace: 'nowrap' }}>{pill(ST[k], 22, '0 8px', 12)}{s}</span>
          ))}
        </div>
      </div>

      {view === 'rows' ? (
        <div role="table" aria-label="Every leg by expiry" style={{ display: 'flex', flexDirection: 'column', overflowX: 'auto', paddingBottom: 4 }}>
          <div role="row" style={{ display: 'grid', gridTemplateColumns: COLS, minWidth: MINW, gap: 16, padding: '4px 0 8px', ...head }}>
            <span role="columnheader">On</span><span role="columnheader">Leg</span><span role="columnheader">SD sold → now</span><span role="columnheader">Status</span>
            <span role="columnheader">Sold at → now</span><span role="columnheader">So far</span><span role="columnheader">Delta</span><span role="columnheader">Theta a day</span>
          </div>
          {groups.map((g) => {
            const v = tri(g.s);
            return (
              <div key={g.k} role="rowgroup" style={{ display: 'flex', flexDirection: 'column' }}>
                <div style={{ display: 'grid', gridTemplateColumns: COLS, minWidth: MINW, gap: 16, alignItems: 'center', padding: '14px 0 10px', borderTop: '1px solid rgba(255,255,255,.16)', opacity: g.s.none ? 0.45 : 1, transition: 'opacity .2s' }}>
                  <Sw on={g.s.ac} label={`${g.s.own ? 'Switch off every leg in' : 'Switch on every leg in'} ${g.t}`} go={mTog(g.rs)} />
                  <button type="button" className="bare" onClick={() => setCol((c) => ({ ...c, [g.k]: g.open }))} aria-expanded={g.open}
                    style={{ gridColumn: '2 / 6', display: 'flex', alignItems: 'center', gap: 10, minWidth: 0 }}>
                    <svg width="12" height="12" viewBox="0 0 12 12" aria-hidden="true" style={{ flex: 'none', display: 'block', transform: g.open ? 'none' : 'rotate(-90deg)', transition: 'transform .25s ease' }}>
                      <path d="M3 4.5 6 7.5 9 4.5" style={{ fill: 'none', stroke: TX, strokeWidth: 1.6, strokeLinecap: 'round', strokeLinejoin: 'round' }} />
                    </svg>
                    <span style={{ fontSize: 15, lineHeight: '20px', fontWeight: 700, whiteSpace: 'nowrap' }}>{g.t}</span>
                    <span style={{ fontSize: 13, lineHeight: '18px', color: MU, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{g.sub}</span>
                  </button>
                  <span style={{ fontSize: 14, fontWeight: 700, color: v.sfc }}>{v.sf}</span>
                  <span style={{ fontSize: 14, fontWeight: 700, color: v.dlc, whiteSpace: 'nowrap' }}>{v.dl}</span>
                  <span style={{ fontSize: 14, fontWeight: 700, color: v.thc }}>{v.th}</span>
                </div>
                {g.open && (g.k === 'none' ? g.rs.map(rowEl) : [...g.cs.map(rowEl), today('td' + g.k, '5px 0 5px 60px'), ...g.ps.map(rowEl)])}
              </div>
            );
          })}
        </div>
      ) : (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 22, overflowX: 'auto', padding: '4px 0' }}>
          {lst.map((g) => {
            const v = tri(g.s);
            return (
              <section key={g.k} aria-label={g.tt} style={{ display: 'flex', flexDirection: 'column', gap: 10, minWidth: 900 }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
                  <Sw on={g.s.ac} label={`${g.s.own ? 'Switch off every leg in' : 'Switch on every leg in'} ${g.tt}`} go={mTog(g.rs)} />
                  <span style={{ display: 'flex', alignItems: 'baseline', gap: 10, flex: 1, minWidth: 0, opacity: g.s.none ? 0.45 : 1, transition: 'opacity .2s' }}>
                    <span style={{ fontSize: 16, lineHeight: '22px', fontWeight: 700, color: g.s.none ? MU : g.tc, whiteSpace: 'nowrap' }}>{g.t}</span>
                    <span style={{ fontSize: 13, lineHeight: '18px', color: MU, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{g.sub}</span>
                  </span>
                  <span style={{ display: 'flex', gap: 20, fontSize: 13, lineHeight: '18px', color: MU, whiteSpace: 'nowrap', opacity: g.s.none ? 0.45 : 1 }}>
                    <span>So far <span style={{ fontWeight: 700, color: v.sfc }}>{v.sf}</span></span>
                    <span>Delta <span style={{ fontWeight: 700, color: v.dlc }}>{v.dl}</span></span>
                    <span>Theta a day <span style={{ fontWeight: 700, color: v.thc }}>{v.th}</span></span>
                  </span>
                </div>
                <div role="list" style={{ display: 'flex', flexDirection: 'column', borderRadius: 20, background: 'rgba(255,255,255,.04)', boxShadow: 'inset 0 0 0 1px rgba(255,255,255,.08)', overflow: 'hidden' }}>
                  {g.rs.map(listRow)}
                </div>
              </section>
            );
          })}
        </div>
      )}
      <style>{'.sw .swb-out:hover{background:rgba(255,255,255,.06)}'}</style>
    </div>
  );
}

/** The chip ids a leg answers to: shares "kind:S"; an option its expiry and its kind and side ("leg:C:sold", Calls sold). */
export const chipIds = (l: PLeg) => { const s = sideOf(l); return s ? ['ex:' + l.ex, `leg:${l.ty}:${s}`] : ['kind:' + l.ty]; };
