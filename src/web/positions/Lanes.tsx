// Intelligence's lanes (handoff 2026-11-13-positions §3.9.3, §3.9.5, §3.9.6): one price scale, today's line through all
// of them, each lane a faint band with three outlined boxes on the right. An empty lane is one quiet line.
//   IV (violet)          the chain's mid IV per strike, brighter is richer, a 1 SD bracket · IV now, IV rank, vs HV20
//   SD (indigo)          bands at 0.25 to 2 SD; the picked put and call colour the room between them
//   Gamma Exposure       ceiling ⇥, floor ⇤, accelerator «, flip ◐, sized by gamma; your sold strikes ringed
//   Technicals (teal)    support and resistance zones; the 20/50/100/200-day as thresholds (filled holds, hatched caps)
//   Move                 last week, this week so far, the 5-day pace to the expiry (capped at 1.5 SD)
//   Held / + New / = Both the profit zone, breakevens with % and SD, strikes ringed; the cross solid, each side alone dashed
// Walls and technicals stay faint (.38) until today's session reaches them: touched = yellow, closed through = a white
// capsule with ↑ or ↓ (positions-engine levelState, on the server's `day`).
import { useLayoutEffect, useRef, useState, type ReactNode } from 'react';
import { atSd, crossAdds, levelState, priceScale, sdColour, sdK, LV, SD_RAMP, zOf, type Lane as LaneM, type LevelState } from '../../../supabase/functions/_shared/positions-engine.ts';
import { money } from '../lib/format';
import { stateWords, type IntelModel, type SdReply } from './intel';
import { Box, CEIL, FLOOR, G, Hover, IVL, K, MT, MU, O, QU, R, TEAL, TEAL2, WallIcon, Y, tnum, type BoxQ, type Pop } from './ui';

const LANE_H = 96, TRACK = 'minmax(0,1fr)', COLS = `110px ${TRACK} 416px`;
const TINT = { iv: 'rgba(150,124,232,.06)', sd: 'rgba(128,128,220,.06)', w: 'rgba(134,168,240,.06)', t: 'rgba(76,201,208,.06)', mv: 'rgba(255,255,255,.035)', h: 'rgba(101,196,102,.06)' };
const p2 = (x: number) => `${(x * 100).toFixed(2)}%`;
const f2 = (x: number) => '$' + x.toFixed(2);
const pc1 = (x: number) => (Math.abs(x) * 100).toFixed(1) + '%';
const arw = (r: number) => (r < 0 ? '↓' : '↑') + pc1(r);
const dots = (c: 1 | 2 | 3 | null) => (c ? '●'.repeat(c) + '○'.repeat(3 - c) : '');
const conf = (c: 1 | 2 | 3 | null) => (c ? ['', 'low', 'medium', 'high'][c] : 'not sent');

interface LaneRowProps { name: string; sub: string; tint: string; track: ReactNode; boxes: BoxQ[] | null; empty?: string; trackH?: number }
function LaneRow({ name, sub, tint, track, boxes, empty, trackH = 84 }: LaneRowProps) {
  return (
    <div style={{ display: 'grid', gridTemplateColumns: COLS, columnGap: 12, alignItems: 'center', height: LANE_H, borderTop: '1px solid rgba(255,255,255,.08)', background: tint }}>
      <span style={{ display: 'flex', flexDirection: 'column', paddingLeft: 12 }}>
        <span style={{ fontSize: 15, lineHeight: '20px', fontWeight: 600 }}>{name}</span>
        <span style={{ fontSize: 12, lineHeight: '16px', color: MU }}>{sub}</span>
      </span>
      <span style={{ position: 'relative', display: 'block', height: trackH }}>{track}</span>
      <div style={{ paddingLeft: 24, paddingRight: 12, display: 'grid', gridTemplateColumns: 'repeat(3,minmax(0,1fr))', gap: 8, alignItems: 'center', ...tnum }}>
        {boxes ? boxes.map((q) => <Box key={q.k} q={q} />) : <span style={{ gridColumn: '1 / -1', fontSize: 13, lineHeight: '18px', color: QU }}>{empty}</span>}
      </div>
    </div>
  );
}
const Quiet = ({ t }: { t: string }) => <span style={{ position: 'absolute', left: 0, top: '50%', transform: 'translateY(-50%)', fontSize: 13, lineHeight: '18px', color: MU, whiteSpace: 'nowrap' }}>{t}</span>;

export function Lanes({ d, M, t, mask }: { d: SdReply; M: IntelModel; t: string; mask: (s: string) => string }) {
  const [hv, setHv] = useState<string | null>(null);
  // The track's width in px (the lanes' width less the label and box columns), so every label keeps inside it.
  const box = useRef<HTMLDivElement>(null);
  const [cw, setCw] = useState(900);
  useLayoutEffect(() => {
    const el = box.current;
    if (!el) return;
    setCw(el.clientWidth);
    const ro = new ResizeObserver(() => setCw(el.clientWidth));
    ro.observe(el);
    return () => ro.disconnect();
  }, []);
  const tw = Math.max(120, cw - 550);
  /** About how wide a 12 px (or 11 px) label is. */
  const tx = (str: string, size = 12) => str.length * (size === 11 ? 6.2 : 7) + 2;
  /** A label's left edge in px: centred on f ('c'), just right of it ('r'), just left of it ('l'), or a share of its
      width left of f; always inside the track (and not left of `lo`). */
  const at = (f: number, w: number, mode: 'c' | 'r' | 'l' | number = 'c', lo = 0) => {
    const a = f * tw, l = mode === 'c' ? a - w / 2 : mode === 'r' ? a + 8 : mode === 'l' ? a - 8 - w : a - mode * w;
    return Math.max(lo, Math.min(tw - w, l));
  };
  const { e, S, m, lv } = M, day = d.day;
  const Kc = M.rc.K, Kp = M.rp.K;
  const sc = priceScale(S, m, [lv.ceiling, lv.floor, lv.accelerator, lv.flip, lv.support, lv.resistance, lv.sma20, lv.sma50, lv.sma100, lv.sma200, Kc, Kp,
    ...M.held.map((l) => l.K), M.LB.dn, M.LB.up]);
  const fr = (x: number) => sc.fr(x), cl01 = (x: number) => Math.max(0, Math.min(1, fr(x)));
  const inSc = (x: number | null | undefined): x is number => x != null && fr(x) >= 0 && fr(x) <= 1;
  const sdz = (x: number) => Math.abs(zOf(x, S, m)).toFixed(1) + ' SD';
  const dist = (x: number) => `${x >= S ? '↑' : '↓'}${pc1(x / S - 1)} · ${sdz(x)}`;
  const st = (L: number | null | undefined): LevelState => levelState(L, day);
  const look = (s: LevelState, base: string) => ({ c: s === 'touch' ? Y : base, o: s === 'idle' ? 0.38 : 1, closed: s === 'up' || s === 'dn', ar: s === 'up' ? '↑ ' : s === 'dn' ? '↓ ' : '' });
  const hoverOf = (id: string, x: number, pop: Pop, w?: number) => (
    <Hover key={id} id={id} x={fr(x)} w={w} pop={pop} on={hv === id} set={setHv} aria={`${pop.t} ${pop.v}`} />
  );
  const todayRow = (s: LevelState) => ({ l: 'Today', v: stateWords[s].replace(' today', ''), c: s === 'touch' ? Y : s === 'idle' ? MT : K });
  const alertLine = (k: string, x: number, s: LevelState) => s === 'idle' ? null : (
    <span key={'al' + k} aria-hidden="true" style={{ pointerEvents: 'none' }}>
      {s === 'touch' && <span style={{ position: 'absolute', top: '50%', left: p2(fr(x)), width: 56, height: 56, margin: '-28px 0 0 -28px', borderRadius: '50%', background: 'radial-gradient(circle,rgba(255,214,10,.32),rgba(255,214,10,0) 70%)' }} />}
      <span style={{ position: 'absolute', top: -6, bottom: -6, left: p2(fr(x)), borderLeft: s === 'touch' ? '1.5px solid rgba(255,214,10,.8)' : '1.5px solid rgba(245,245,247,.9)' }} />
    </span>
  );

  /* ── IV ── */
  const ivK = (e.ivK ?? []).filter(([k, v]) => k > 0 && v > 0).sort((a, b) => a[0] - b[0]);
  const ivAt = (k: number): number | null => {
    if (ivK.length < 2 || k < ivK[0][0] || k > ivK[ivK.length - 1][0]) return null;
    let i = 1; while (i < ivK.length - 1 && ivK[i][0] < k) i++;
    const [k0, v0] = ivK[i - 1], [k1, v1] = ivK[i];
    return k1 > k0 ? v0 + (v1 - v0) * (k - k0) / (k1 - k0) : v0;
  };
  const stp = S < 50 ? 0.5 : S < 200 ? 1 : 5, SP = stp * (sc.W / stp > 60 ? Math.ceil(sc.W / stp / 60) : 1);
  const cells: { k: number; v: number }[] = [];
  for (let k = Math.ceil(sc.X0 / SP) * SP; k <= sc.X0 + sc.W + 1e-9; k += SP) { const v = ivAt(+k.toFixed(2)); if (v != null) cells.push({ k: +k.toFixed(2), v }); }
  const vmn = Math.min(...cells.map((c) => c.v)), vmx = Math.max(...cells.map((c) => c.v)), rr = (v: number) => (vmx > vmn ? (v - vmn) / (vmx - vmn) : 0.5);
  const ivLabels = cells.length >= 3 ? [0.12, 0.5, 0.88].map((f) => cells.reduce((a, c) => (Math.abs(fr(c.k) - f) < Math.abs(fr(a.k) - f) ? c : a), cells[0])) : [];
  const lo1 = atSd(S, -1, m), hi1 = atSd(S, 1, m);
  const ivTrack = cells.length >= 2 ? <>
    {ivLabels.map((c, i) => <span key={i} style={{ position: 'absolute', top: 0, left: at(fr(c.k), tx(pc1(c.v))), fontSize: 12, lineHeight: '16px', color: MT, whiteSpace: 'nowrap' }}>{pc1(c.v)}</span>)}
    <span style={{ position: 'absolute', top: 20, height: 28, left: 0, right: 0, overflow: 'hidden', borderRadius: 8 }}>
      {cells.map((c) => (
        <span key={c.k} title={`${c.k} strike · IV ${pc1(c.v)}`} style={{ position: 'absolute', top: 0, bottom: 0, left: p2(fr(c.k - SP / 2)), width: p2(SP / sc.W),
          background: `oklch(${(0.3 + 0.42 * rr(c.v)).toFixed(3)} ${(0.05 + 0.12 * rr(c.v)).toFixed(3)} 282)`, borderRight: '1px solid #0B0C10' }} />
      ))}
    </span>
    <span style={{ position: 'absolute', top: 52, height: 6, left: p2(cl01(lo1)), width: p2(cl01(hi1) - cl01(lo1)), border: '1.5px solid rgba(190,180,255,.7)', borderTop: 'none', borderRadius: '0 0 4px 4px' }} />
    <span style={{ position: 'absolute', top: 62, left: at(cl01(lo1), tx(`1 SD · ${f2(lo1)} to ${f2(hi1)}`), 0.1), fontSize: 12, lineHeight: '16px', fontWeight: 600, color: IVL, whiteSpace: 'nowrap' }}>1 SD · {f2(lo1)} to {f2(hi1)}</span>
  </> : <Quiet t={`No IV by strike for ${e.label} yet.`} />;
  const ivTone = M.iv.tone;
  const ivBoxes: BoxQ[] = [
    { k: 'ivn', l: 'IV now', v: pc1(e.iv), s: M.earnIn ? `earnings ${d.events?.earnings ? md(d.events.earnings) : 'before expiry'}` : 'at the money', sc: M.earnIn ? O : undefined },
    { k: 'ivr', l: 'IV rank', v: M.iv.rank != null ? String(M.iv.rank) : '-', s: M.iv.rank != null ? 'of 100, past year' : 'not sent yet' },
    { k: 'ivh', l: 'vs HV20', v: ivTone === 'rich' ? 'Rich' : ivTone === 'cheap' ? 'Cheap' : ivTone === 'fair' ? 'Fair' : '-', s: d.tech?.hv20 ? `HV20 ${pc1(d.tech.hv20)}` : 'not sent yet' },
  ];

  /* ── SD ── */
  const mv = `±${pc1(m)}`;
  const sdTrack = <>
    <span style={{ position: 'absolute', top: 0, left: 0, fontSize: 12, lineHeight: '16px', fontWeight: 700, color: K, whiteSpace: 'nowrap' }}>
      {M.picked ? `Put at ${sdK(M.kp)} SD · call at ${sdK(M.kc)} SD` : `1 SD ${mv}`}
    </span>
    {!M.picked && (() => { const Kx = M.side === 'p' ? Kp : Kc, w = tx(`Sell ${+Kx.toFixed(2)} calls`) + 16; return inSc(Kx) ? (
      <span style={{ position: 'absolute', top: 0, left: at(fr(Kx), w, 'c', tx(`1 SD ${mv}`) + 10), fontSize: 12, lineHeight: '16px', fontWeight: 700, whiteSpace: 'nowrap' }}>
        <span style={{ padding: '1px 7px', borderRadius: 999, background: K, color: '#000000' }}>Sell {+Kx.toFixed(2)} {M.side === 'p' ? 'puts' : 'calls'}</span>
      </span>) : null; })()}
    <span style={{ position: 'absolute', top: 24, height: 34, left: 0, right: 0, overflow: 'hidden' }}>
      {LV.slice().reverse().map((k) => (
        <span key={k} style={{ position: 'absolute', top: 0, bottom: 0, left: p2(cl01(atSd(S, -k, m))), width: p2(cl01(atSd(S, k, m)) - cl01(atSd(S, -k, m))), borderRadius: 8,
          background: M.picked ? 'rgba(255,255,255,.07)' : SD_RAMP[LV.indexOf(k)], transition: 'background .25s' }} />
      ))}
      {M.picked && (() => {
        const a = cl01(Kp), b = cl01(Kc), sp = b > a ? Math.max(0, Math.min(100, ((fr(S) - a) / (b - a)) * 100)) : 50;
        return <span style={{ position: 'absolute', top: 0, bottom: 0, left: p2(a), width: p2(Math.max(0, b - a)), borderRadius: 8, boxShadow: 'inset 0 0 0 1.5px #F5F5F7',
          background: `linear-gradient(90deg,${sdColour(M.kp || 0.25)} 0 ${sp.toFixed(1)}%,${sdColour(M.kc)} ${sp.toFixed(1)}% 100%)` }} />;
      })()}
      {!M.picked && inSc(M.side === 'p' ? Kp : Kc) && <span style={{ position: 'absolute', top: 0, bottom: 0, left: p2(fr(M.side === 'p' ? Kp : Kc)), borderLeft: '2px solid #F5F5F7' }} />}
    </span>
    {M.picked ? (() => {
      const wp = tx(`Put ${+Kp.toFixed(2)}`), wc = tx(`Call ${+Kc.toFixed(2)}`), lp = at(cl01(Kp), wp), lc = Math.min(tw - wc, Math.max(at(cl01(Kc), wc), lp + wp + 6));
      return <>
        <span style={{ position: 'absolute', top: 64, left: lp, fontSize: 12, lineHeight: '16px', fontWeight: 600, whiteSpace: 'nowrap' }}>Put {+Kp.toFixed(2)}</span>
        <span style={{ position: 'absolute', top: 64, left: lc, fontSize: 12, lineHeight: '16px', fontWeight: 600, whiteSpace: 'nowrap' }}>Call {+Kc.toFixed(2)}</span>
      </>;
    })() : (
      <span style={{ position: 'absolute', top: 64, left: 0, right: 0, display: 'flex', gap: 10, fontSize: 12, lineHeight: '16px', color: MT, whiteSpace: 'nowrap', overflow: 'hidden' }}>
        <span style={{ flex: 'none', display: 'flex', alignItems: 'center', gap: 5 }}>0.25<span style={{ display: 'flex', borderRadius: 2, overflow: 'hidden' }}>
          {SD_RAMP.map((c) => <span key={c} style={{ width: 10, height: 8, background: c }} />)}</span>2 SD</span>
      </span>
    )}
  </>;
  const sdBoxes: BoxQ[] = [
    ...(M.picked
      ? [{ k: 'p', l: 'Put', v: String(+Kp.toFixed(2)), s: `${sdK(M.kp)} SD` }, { k: 'c', l: 'Call', v: String(+Kc.toFixed(2)), s: `${sdK(M.kc)} SD` }]
      : [{ k: 'lo', l: '1 SD low', v: f2(lo1), s: `↓${pc1(m)}` }, { k: 'hi', l: '1 SD high', v: f2(hi1), s: `↑${pc1(m)}` }]),
    { k: 'mv', l: `Move by ${e.label}`, v: mv, s: '1 SD' },
  ];

  /* ── Gamma Exposure ── */
  const W = (k: string) => lv.walls.find((w) => w.kind === k) ?? null;
  const ce = W('ceiling'), fl = W('floor'), ac = W('accelerator'), flip = lv.flip;
  const gmx = Math.max(1, ...lv.walls.map((w) => w.gex)), isz = (g: number) => Math.round(16 + 12 * g / gmx);
  const wallMark = (w: { kind: 'ceiling' | 'floor' | 'accelerator'; K: number; gex: number }, base: string) => {
    if (!inSc(w.K)) return null;
    const s = st(w.K), L = look(s, base), lab = `${L.ar}${+w.K.toFixed(2)}`;
    const lw = tx(lab) + (L.closed ? 12 : 0), chip = { fontSize: 12, lineHeight: '16px', whiteSpace: 'nowrap' as const, borderRadius: 999, padding: L.closed ? '0 6px' : 0,
      background: L.closed ? K : 'transparent', color: L.closed ? '#000000' : L.c };
    if (w.kind === 'accelerator') {
      const near = flip != null && Math.abs(fr(w.K) - fr(flip)) < 0.08, top = near ? 66 : 50;
      return (
        <span key="wmac" style={{ opacity: L.o, pointerEvents: 'none' }}>
          <span style={{ position: 'absolute', top, left: p2(fr(w.K)), marginLeft: -9, color: L.c }}><WallIcon kind="accelerator" size={18} color="currentColor" /></span>
          <span style={{ position: 'absolute', top: top + 1, left: at(fr(w.K), lw, 'l'), fontWeight: 600, ...chip }}>{lab}</span>
        </span>
      );
    }
    const sz = isz(w.gex);
    return (
      <span key={'wm' + w.kind} style={{ opacity: L.o, pointerEvents: 'none' }}>
        <span style={{ position: 'absolute', top: 0, left: p2(fr(w.K)), marginLeft: -sz / 2, color: L.c, lineHeight: 0 }}><WallIcon kind={w.kind} size={sz} color="currentColor" /></span>
        <span style={{ position: 'absolute', top: sz + 2, left: at(fr(w.K), lw), fontWeight: 700, ...chip }}>{lab}</span>
      </span>
    );
  };
  const hasW = lv.walls.length > 0 || flip != null;
  const rings = M.held.filter((l) => inSc(l.K));
  const wPop = (kind: string, x: number, g: number | null, c: 1 | 2 | 3 | null, dc: string, say: string): Pop => ({
    t: kind, v: kind === 'Flip' ? f2(x) : String(+x.toFixed(2)), dc,
    rows: [{ l: 'From today', v: dist(x) }, ...(g != null ? [{ l: kind === 'Ceiling' ? 'Call gamma' : kind === 'Floor' ? 'Put gamma' : 'Gamma', v: money(g) }] : []),
      ...(kind !== 'Flip' && kind !== 'Accelerator' ? [{ l: 'How sure', v: c ? `${dots(c)} ${conf(c)}` : conf(c) }] : []),
      ...(kind === 'Flip' ? [{ l: 'Now', v: S >= x ? 'above it, calmer' : 'below it, choppier' }] : []), todayRow(st(x))], say,
  });
  const gTrack = hasW ? <>
    {[ce, fl, ac].map((w) => (w ? alertLine(w.kind, w.K, inSc(w.K) ? st(w.K) : 'idle') : null))}
    {flip != null && inSc(flip) && alertLine('fp', flip, st(flip))}
    {ce && inSc(ce.K) && hoverOf('ce', ce.K, wPop('Ceiling', ce.K, ce.gex, ce.conf, CEIL, `The strike with the most call gamma for ${e.label}. Dealers sell into rallies here, so the price tends to stall under it.`))}
    {fl && inSc(fl.K) && hoverOf('fl', fl.K, wPop('Floor', fl.K, fl.gex, fl.conf, FLOOR, `The strike with the most put gamma for ${e.label}. Dealers buy into dips here, so the price tends to hold above it.`))}
    {flip != null && inSc(flip) && hoverOf('fp', flip, wPop('Flip', flip, null, null, O, 'Where dealer gamma turns over. Above it moves get damped, below it they get bigger.'))}
    {ac && inSc(ac.K) && hoverOf('ac', ac.K, wPop('Accelerator', ac.K, ac.gex, null, FLOOR, 'A put strike where dealer hedging speeds a fall once the price goes through it.'))}
    {ce && wallMark(ce, CEIL)}
    {fl && wallMark(fl, FLOOR)}
    {flip != null && inSc(flip) && (() => { const s = st(flip), L = look(s, O), lab = `${L.ar}${f2(flip)}`, lw = tx(lab) + (L.closed ? 12 : 0), f = fr(flip); return (
      <span style={{ opacity: L.o, pointerEvents: 'none' }}>
        <span style={{ position: 'absolute', top: 50, left: p2(f), marginLeft: -9, color: L.c, lineHeight: 0 }}><WallIcon kind="flip" size={18} color="currentColor" /></span>
        <span style={{ position: 'absolute', top: 51, left: at(f, lw, f * tw + 12 + lw <= tw ? 'r' : 'l'), fontSize: 12, lineHeight: '16px', fontWeight: 600, whiteSpace: 'nowrap', borderRadius: 999,
          padding: L.closed ? '0 6px' : 0, background: L.closed ? K : 'transparent', color: L.closed ? '#000000' : L.c }}>{lab}</span>
      </span>); })()}
    {ac && wallMark(ac, MT)}
    {rings.map((l, i) => <span key={i} style={{ position: 'absolute', top: 71, left: p2(fr(l.K)), width: 12, height: 12, marginLeft: -6, borderRadius: '50%', border: '2px solid #F5F5F7', background: '#0B0D0C' }} />)}
  </> : <Quiet t={`No gamma walls for ${e.label} yet.`} />;
  const wBox = (k: string, l: string, x: { K: number; gex: number; conf: 1 | 2 | 3 | null } | null, icon: ReactNode): BoxQ => {
    if (!x) return { k, l, v: 'none', vc: MT, icon };
    const s = st(x.K);
    return { k, l, v: String(+x.K.toFixed(2)), s: s !== 'idle' ? stateWords[s] : `${money(x.gex)}${x.conf ? ' ' + dots(x.conf) : ''}`, sc: s === 'touch' ? Y : s === 'idle' ? undefined : K, icon };
  };
  const gBoxes: BoxQ[] | null = hasW ? [
    wBox('ce', 'Ceiling', ce, <WallIcon kind="ceiling" size={13} color={CEIL} />),
    wBox('fl', 'Floor', fl, <WallIcon kind="floor" size={13} color={FLOOR} />),
    flip != null ? { k: 'fp', l: 'Flip', v: f2(flip), s: st(flip) !== 'idle' ? stateWords[st(flip)] : 'calmer above', sc: st(flip) === 'touch' ? Y : undefined, icon: <WallIcon kind="flip" size={13} color={O} /> }
      : { k: 'fp', l: 'Flip', v: 'none', vc: MT, icon: <WallIcon kind="flip" size={13} color={O} /> },
  ] : null;

  /* ── Technicals ── */
  const tech = d.tech;
  const zones = (lv.zones ?? []).filter((z) => fr(z.hi) >= 0 && fr(z.lo) <= 1);
  const zmx = Math.max(1, ...zones.map((z) => z.strength));
  // Zone labels, the nearest to today first; one that would run into a placed label is left to its pop-up.
  const zLab = new Map<number, number>();
  {
    const placed: [number, number][] = [];
    zones.map((z, i) => ({ z, i })).sort((p, q) => Math.abs(p.z.mid - S) - Math.abs(q.z.mid - S)).forEach(({ z, i }) => {
      const s = st(z.mid), w = tx((s === 'up' || s === 'dn' ? '↑ ' : '') + f2(z.mid)) + (s === 'up' || s === 'dn' ? 12 : 0), l = at(cl01(z.mid), w);
      if (placed.some(([a, b]) => l < b + 6 && l + w > a - 6)) return;
      placed.push([l, l + w]);
      zLab.set(i, l);
    });
  }
  const MAs: [number, number | null | undefined, number, number][] = [[20, lv.sma20, 0.45, 600], [50, lv.sma50, 0.6, 700], [100, lv.sma100, 0.75, 700], [200, lv.sma200, 0.9, 800]];
  const tTrack = tech ? <>
    {zones.map((z, i) => alertLine('z' + i, z.mid, st(z.mid)))}
    {MAs.map(([n, x]) => (x != null && inSc(x) ? alertLine('m' + n, x, st(x)) : null))}
    {zones.map((z, i) => hoverOf('z' + i, z.mid, {
      t: z.kind === 'support' ? 'Support' : 'Resistance', v: f2(z.mid), dc: TEAL2,
      rows: [{ l: 'Zone', v: `${f2(z.lo)} to ${f2(z.hi)}` }, { l: 'From today', v: dist(z.mid) }, { l: 'Turned there', v: `${z.strength} ${z.strength === 1 ? 'time' : 'times'}` },
        ...(tech.rsi14 != null ? [{ l: 'RSI', v: `${Math.round(tech.rsi14)}, ${rsiWord(tech.rsi14)}` }] : []), todayRow(st(z.mid))],
      say: z.kind === 'support' ? 'Where buying has turned the price up before.' : 'Where selling has turned the price down before.',
    }))}
    {MAs.map(([n, x]) => (x != null && inSc(x) ? hoverOf('m' + n, x, {
      t: `${n}-day average`, v: f2(x), dc: TEAL, rows: [{ l: 'From today', v: dist(x) }, { l: 'Price', v: S >= x ? 'above it, holding' : 'below it, capping' }, todayRow(st(x))],
      say: n === 20 ? 'The average close of the last 20 trading days. The price often comes back to it.' : n === 50 ? 'The average close of the last 50 trading days, the slower trend.'
        : n === 100 ? 'The average close of the last 100 trading days.' : 'The long trend, the heaviest of the four.',
    }, 14) : null))}
    {zones.map((z, i) => {
      const s = st(z.mid), L = look(s, ''), hold = z.kind === 'support', a = (0.35 + 0.5 * (z.strength / zmx)).toFixed(2);
      const col = s === 'touch' ? '255,214,10' : '76,201,208';
      const bg = hold ? `rgba(${col},${a})` : `repeating-linear-gradient(135deg,rgba(${col},${a}) 0 2px,transparent 2px 5px)`;
      return (
        <span key={'zz' + i} style={{ pointerEvents: 'none', opacity: L.o }}>
          <span style={{ position: 'absolute', top: 0, height: 20, left: p2(cl01(z.lo)), width: `max(12px, ${p2(cl01(z.hi) - cl01(z.lo))})`, borderRadius: 5, background: bg, boxShadow: hold ? 'none' : `inset 0 0 0 1.5px rgba(${col},.8)` }} />
          {zLab.has(i) && <span style={{ position: 'absolute', top: 22, left: zLab.get(i), fontSize: 12, lineHeight: '16px', fontWeight: 600, whiteSpace: 'nowrap', borderRadius: 999,
            padding: L.closed ? '0 6px' : 0, background: L.closed ? K : 'transparent', color: L.closed ? '#000000' : s === 'touch' ? Y : K }}>{L.ar}{f2(z.mid)}</span>}
        </span>
      );
    })}
    <span style={{ position: 'absolute', top: 40, left: 0, right: 0, borderTop: '1px solid rgba(255,255,255,.06)', pointerEvents: 'none' }} />
    {MAs.map(([n, x, w, fw], i) => {
      if (x == null) return null;
      const s = st(x), L = look(s, ''), hold = x < S, f = cl01(x), inL = f < 0.1, col = s === 'touch' ? '255,214,10' : '76,201,208';
      return (
        <span key={n} style={{ pointerEvents: 'none', opacity: L.o }}>
          <span style={{ position: 'absolute', top: 44 + i * 10, height: 6, left: p2(f), right: 0, borderRadius: '3px 0 0 3px',
            background: hold ? `rgba(${col},${w})` : `repeating-linear-gradient(135deg,rgba(${col},${w}) 0 2px,transparent 2px 5px)`, boxShadow: hold ? 'none' : `inset 0 0 0 1px rgba(${col},${w})` }} />
          <span style={{ position: 'absolute', top: 42 + i * 10, left: inL ? f * tw + 4 : Math.max(0, f * tw - 5 - tx(L.ar + n, 11)), height: 10, display: 'inline-flex', alignItems: 'center',
            padding: L.closed ? '0 4px' : 0, borderRadius: 999, background: L.closed ? K : 'transparent', fontSize: 11, lineHeight: '10px', fontWeight: fw, whiteSpace: 'nowrap',
            color: L.closed ? '#000000' : s === 'touch' ? (inL && hold ? '#2A2200' : Y) : inL && hold ? '#04201F' : '#7FE0E5' }}>{L.ar}{n}</span>
        </span>
      );
    })}
  </> : <Quiet t={`No technicals for ${t} yet.`} />;
  const zBox = (k: string, l: string, x: number | null | undefined): BoxQ => {
    if (x == null) return { k, l, v: 'none', vc: MT, dot: TEAL2 };
    const s = st(x);
    return { k, l, v: f2(x), s: s !== 'idle' ? stateWords[s] : sdz(x), sc: s === 'touch' ? Y : s === 'idle' ? undefined : K, dot: TEAL2 };
  };
  const tBoxes: BoxQ[] | null = tech ? [
    zBox('su', 'Support', lv.support), zBox('re', 'Resistance', lv.resistance),
    M.exDivIn && d.events?.exDiv ? { k: 'xd', l: 'Ex-dividend', v: md(d.events.exDiv), vc: O, s: 'early assignment' }
      : { k: 'rsi', l: 'RSI', v: tech.rsi14 != null ? String(Math.round(tech.rsi14)) : '-', s: tech.rsi14 != null ? rsiWord(tech.rsi14) : 'not sent yet' },
  ] : null;

  /* ── Move ── */
  const mo = M.move;
  const arrows = mo && (mo.lw || mo.tw || mo.pace) ? [
    ...(mo.lw ? [{ k: 'lw', y: 0, a: mo.lw.from, b: mo.lw.to, c: MT, dash: false, t: 'Last week', v: arw(mo.lw.r), vc: mo.lw.r < 0 ? R : G, rg: [mo.lw.lo, mo.lw.hi] as [number, number],
      pop: { t: 'Last week', v: arw(mo.lw.r), dc: mo.lw.r < 0 ? R : G, rows: [{ l: shortD(mo.lw.fromD), v: f2(mo.lw.from) }, { l: shortD(mo.lw.toD), v: f2(mo.lw.to) },
        { l: 'Move', v: arw(mo.lw.r), c: mo.lw.r < 0 ? R : G }, { l: 'In SD', v: wkSd(mo.lw.to / mo.lw.from, e.iv) }, { l: 'Range of closes', v: `${f2(mo.lw.lo)} to ${f2(mo.lw.hi)}` }],
        say: 'Close to close, against a one-week SD at today’s IV.' } }] : []),
    ...(mo.tw ? [{ k: 'tw', y: 28, a: mo.tw.from, b: S, c: K, dash: false, t: 'This week', v: arw(mo.tw.r), vc: mo.tw.r < 0 ? R : G, rg: null,
      pop: { t: 'This week', v: arw(mo.tw.r), dc: mo.tw.r < 0 ? R : G, rows: [{ l: 'Fri close', v: f2(mo.tw.from) }, { l: 'Today', v: f2(S) }, { l: 'Move', v: arw(mo.tw.r), c: mo.tw.r < 0 ? R : G },
        { l: 'In SD', v: mo.tw.sd.toFixed(1) + ' SD' }], say: 'Friday’s close to today.' } }] : []),
    ...(mo.pace ? [{ k: 'mo', y: 56, a: S, b: mo.pace.to, c: mo.pace.flat ? MT : mo.pace.r5 < 0 ? R : G, dash: true, t: mo.pace.flat ? `Flat to ${e.label}` : `Pace to ${e.label}`, v: f2(mo.pace.to), vc: K, rg: null,
      pop: { t: 'Momentum', v: mo.pace.flat ? 'Flat' : mo.pace.r5 < 0 ? 'Falling' : 'Rising', dc: mo.pace.flat ? MT : mo.pace.r5 < 0 ? R : G,
        rows: [{ l: '5-day', v: arw(mo.pace.r5), c: mo.pace.r5 < 0 ? R : G }, ...(mo.pace.r20 != null ? [{ l: '20-day', v: arw(mo.pace.r20), c: mo.pace.r20 < 0 ? R : G }] : []),
          ...(tech?.rsi14 != null ? [{ l: 'RSI', v: `${Math.round(tech.rsi14)}, ${rsiWord(tech.rsi14)}` }] : []), { l: `By ${e.label}`, v: f2(mo.pace.to) + (mo.pace.capped ? ', capped' : '') }],
        say: `Where the price lands by ${e.label} if the last 5 days’ pace holds. A guide, not a forecast.` } }] : []),
  ] : null;
  const mvTrack = arrows ? <>{arrows.map((a) => {
    const x1 = cl01(a.a), x2 = cl01(a.b), up = a.b >= a.a, mid = (Math.min(x1, x2) + Math.abs(x2 - x1) / 2);
    // The words sit past the arrow head; if there is no room there, before its tail; else wherever they fit.
    // In a narrow track the words drop to the number alone (the box beside the lane names it).
    const head = x2 * tw, tail = x1 * tw, a0 = Math.min(head, tail), b0 = Math.max(head, tail);
    const fits = (w: number) => (up ? b0 + 8 + w <= tw || a0 - 8 - w >= 0 : a0 - 8 - w >= 0 || b0 + 8 + w <= tw);
    const full = fits(tx(a.t) + 5 + tx(a.v)), lw = full ? tx(a.t) + 5 + tx(a.v) : tx(a.v);
    const ll = up ? (b0 + 8 + lw <= tw ? b0 + 8 : a0 - 8 - lw >= 0 ? a0 - 8 - lw : tw - b0 > a0 ? Math.min(tw - lw, b0 + 8) : Math.max(0, a0 - 8 - lw))
      : (a0 - 8 - lw >= 0 ? a0 - 8 - lw : b0 + 8 + lw <= tw ? b0 + 8 : a0 > tw - b0 ? Math.max(0, a0 - 8 - lw) : Math.min(tw - lw, b0 + 8));
    const id = 'mv' + a.k, on = hv === id;
    return (
      <span key={a.k} style={{ position: 'absolute', left: 0, right: 0, top: a.y, height: 28 }}>
        <span tabIndex={0} role="button" aria-label={`${a.pop.t} ${a.pop.v}`} className="swp-hv" onMouseEnter={() => setHv(id)} onMouseLeave={() => setHv(null)} onFocus={() => setHv(id)} onBlur={() => setHv(null)}
          style={{ position: 'absolute', top: 0, bottom: 0, left: `calc(${p2(Math.min(x1, x2))} - 11px)`, width: `calc(${p2(Math.abs(x2 - x1))} + 22px)`, zIndex: on ? 6 : 3, outline: 'none' }}>
          {on && <PopBox pop={a.pop} tx={mid < 0.2 ? 'translateX(-24px)' : mid > 0.8 ? 'translateX(calc(-100% + 24px))' : 'translateX(-50%)'} />}
        </span>
        {a.rg && <span style={{ position: 'absolute', top: 11, height: 6, left: p2(cl01(a.rg[0])), width: p2(cl01(a.rg[1]) - cl01(a.rg[0])), borderRadius: 3, background: 'rgba(255,255,255,.10)' }} />}
        <span style={{ position: 'absolute', top: 13, left: p2(Math.min(x1, x2)), width: p2(Math.abs(x2 - x1)), borderTop: `2px ${a.dash ? 'dashed' : 'solid'} ${a.c}` }} />
        <span style={{ position: 'absolute', top: 9, left: p2(x2), width: 0, height: 0, marginLeft: up ? -7 : 0, borderTop: '5px solid transparent', borderBottom: '5px solid transparent',
          borderLeft: up ? `7px solid ${a.c}` : '0 solid transparent', borderRight: up ? '0 solid transparent' : `7px solid ${a.c}` }} />
        <span style={{ position: 'absolute', top: 6, left: ll, display: 'flex', gap: 5,
          fontSize: 12, lineHeight: '16px', whiteSpace: 'nowrap', pointerEvents: 'none' }}>
          {full && <span style={{ color: MU }}>{a.t}</span>}<span style={{ fontWeight: 600, color: a.vc }}>{a.v}</span>
        </span>
      </span>
    );
  })}</> : <Quiet t={`No recent closes for ${t} yet.`} />;
  const mvBoxes: BoxQ[] | null = mo ? [
    mo.lw ? { k: 'lw', l: 'Last week', v: arw(mo.lw.r), vc: mo.lw.r < 0 ? R : G, s: `closed ${f2(mo.lw.to)}` } : { k: 'lw', l: 'Last week', v: '-', vc: MT },
    mo.tw ? { k: 'tw', l: 'This week', v: arw(mo.tw.r), vc: mo.tw.r < 0 ? R : G, s: `since Fri · ${mo.tw.sd.toFixed(1)} SD` } : { k: 'tw', l: 'This week', v: '-', vc: MT },
    mo.pace ? { k: 'mo', l: 'Momentum', v: mo.pace.flat ? 'Flat' : mo.pace.r5 < 0 ? 'Falling' : 'Rising', vc: mo.pace.flat ? K : mo.pace.r5 < 0 ? R : G, s: `5-day ${arw(mo.pace.r5)}` }
      : { k: 'mo', l: 'Momentum', v: '-', vc: MT },
  ] : null;

  /* ── Held, + New, = Both ── */
  const zbg = (L: LaneM) => {
    const zl = L.dn == null ? 0 : cl01(L.dn), zr = L.up == null ? 1 : cl01(L.up), sp = zr > zl ? Math.max(0, Math.min(100, ((fr(S) - zl) / (zr - zl)) * 100)) : 50;
    return { zl, zr, bg: `linear-gradient(90deg,${sdColour(L.dn == null ? 2 : Math.abs(zOf(L.dn, S, m)))} 0 ${sp.toFixed(1)}%,${sdColour(L.up == null ? 2 : Math.abs(zOf(L.up, S, m)))} ${sp.toFixed(1)}% 100%)` };
  };
  const beT = (x: number) => `${x >= S ? '↑' : '↓'}${pc1(x / S - 1)} · ${Math.abs(zOf(x, S, m)).toFixed(2)} SD`;
  const sdd = (a1: number, a0: number) => `+${Math.abs(crossAdds(a1, a0, S, m)).toFixed(2)} SD`;
  const sidesOf = (L: LaneM) => [L.calls ? `${L.calls} calls` : '', L.puts ? `${L.puts} puts` : ''].filter(Boolean).join(' · ');
  const hnb = (k: 'h' | 'n' | 'b', L: LaneM, name: string) => {
    if (!L.has) return null;
    const z = zbg(L), ab = L.callsAlone != null && L.putsAlone != null;
    const base = [{ l: 'Sold', v: sidesOf(L) }, { l: 'Premium', v: mask(money(L.inc)) }, { l: 'Chance of profit', v: pc1(L.cp) }];
    return <>
      <span style={{ position: 'absolute', left: 0, right: 0, top: 39, height: 2, borderRadius: 1, background: 'rgba(255,105,97,.45)' }} />
      {!L.none && <span style={{ position: 'absolute', top: 33, height: 14, left: p2(z.zl), width: p2(Math.max(0.004, z.zr - z.zl)), borderRadius: 7, background: z.bg, boxShadow: 'inset 0 0 0 1.5px rgba(245,245,247,.85)' }} />}
      {ab && [L.callsAlone!, L.putsAlone!].filter(inSc).map((x, i) => <span key={'al' + i} style={{ position: 'absolute', top: 27, height: 26, left: p2(fr(x)), borderLeft: '1.5px dashed rgba(245,245,247,.6)' }} />)}
      {L.strikes.filter(inSc).map((x) => <span key={'K' + x} style={{ position: 'absolute', top: 40, left: p2(fr(x)), width: 10, height: 10, margin: '-5px 0 0 -5px', borderRadius: '50%', border: '2px solid #F5F5F7', background: '#0B0D0C' }} />)}
      {(() => {
        // The two breakevens' words: the price over the tick, how far under it; the down side leans left, the up side
        // right, never past the track or into each other.
        const dn = L.dn != null && inSc(L.dn) ? L.dn : null, up = L.up != null && inSc(L.up) ? L.up : null;
        const pw = (x: number) => tx(f2(x)), sw = (x: number) => tx(beT(x), 11);
        const pd = dn != null ? at(fr(dn), pw(dn), 0.7) : 0, sd = dn != null ? at(fr(dn), sw(dn), 0.85) : 0;
        const pu = up != null ? Math.min(tw - pw(up), Math.max(at(fr(up), pw(up), 0.3), dn != null ? pd + pw(dn) + 6 : 0)) : 0;
        const su = up != null ? Math.min(tw - sw(up), Math.max(at(fr(up), sw(up), 0.15), dn != null ? sd + sw(dn) + 6 : 0)) : 0;
        return [[dn, pd, sd], [up, pu, su]].map(([x, lp, ls], i) => (x != null ? (
          <span key={'be' + i}>
            <span style={{ position: 'absolute', top: 28, height: 24, left: p2(fr(x)), marginLeft: -1, borderLeft: '2px solid #F5F5F7' }} />
            <span style={{ position: 'absolute', top: 6, left: lp!, fontSize: 12, lineHeight: '16px', fontWeight: 700, whiteSpace: 'nowrap' }}>{f2(x)}</span>
            <span style={{ position: 'absolute', bottom: 4, left: ls!, fontSize: 11, lineHeight: '14px', fontWeight: 500, color: MT, whiteSpace: 'nowrap' }}>{beT(x)}</span>
          </span>) : null));
      })()}
      {L.dn != null && inSc(L.dn) && hoverOf(k + 'lo', L.dn, { t: `${name} · breakeven down`, v: f2(L.dn), dc: sdColour(Math.abs(zOf(L.dn, S, m))),
        rows: [{ l: 'From today', v: beT(L.dn) }, ...(ab ? [{ l: 'Puts alone', v: `${f2(L.putsAlone!)} · ${sdz(L.putsAlone!)}` }, { l: 'The cross adds', v: sdd(L.dn, L.putsAlone!) }] : []), ...base],
        say: ab ? `The puts break even here with the calls’ premium on top. Alone they would at ${f2(L.putsAlone!)}.` : 'One side only, so no cross.' })}
      {L.up != null && inSc(L.up) && hoverOf(k + 'hi', L.up, { t: `${name} · breakeven up`, v: f2(L.up), dc: sdColour(Math.abs(zOf(L.up, S, m))),
        rows: [{ l: 'From today', v: beT(L.up) }, ...(ab ? [{ l: 'Calls alone', v: `${f2(L.callsAlone!)} · ${sdz(L.callsAlone!)}` }, { l: 'The cross adds', v: sdd(L.up, L.callsAlone!) }] : []), ...base],
        say: ab ? `The calls break even here with the puts’ premium on top. Alone they would at ${f2(L.callsAlone!)}.` : 'One side only, so no cross.' })}
    </>;
  };
  const beBox = (k: string, x: number | null, dn: boolean, none: boolean): BoxQ =>
    none ? { k, l: `Breakeven ${dn ? 'down' : 'up'}`, v: 'none', vc: MT } : x == null ? { k, l: `Breakeven ${dn ? 'down' : 'up'}`, v: 'past 4 SD', vc: MT }
      : { k, l: `Breakeven ${dn ? 'down' : 'up'}`, v: f2(x), s: dist(x) };
  const lxBoxes = (L: LaneM, ref: LaneM | null): BoxQ[] | null => {
    if (!L.has) return null;
    const d0 = ref && ref.has ? (L.cp - ref.cp) * 100 : null;
    return [beBox('lo', L.dn, true, L.none),
      { k: 'cp', l: 'Chance of profit', v: L.none ? '0.0%' : pc1(L.cp), s: d0 != null ? (Math.abs(d0) < 0.05 ? 'same as Held' : `${d0 > 0 ? 'up' : 'down'} ${Math.abs(d0).toFixed(1)} pts`) : `${mask(money(L.inc))} premium`,
        sc: d0 != null ? (d0 > 0.05 ? G : d0 < -0.05 ? R : QU) : undefined },
      beBox('hi', L.up, false, L.none)];
  };

  return (
    <div ref={box} style={{ display: 'flex', flexDirection: 'column' }}>
      <div style={{ display: 'grid', gridTemplateColumns: COLS, columnGap: 12, height: 26 }}>
        <span />
        <span style={{ position: 'relative' }}>
          <span className="tnum" style={{ position: 'absolute', left: at(fr(S), tx(`Today ${f2(S)}`) + 16), bottom: 4, padding: '2px 8px', borderRadius: 999, background: K, color: '#000000',
            fontSize: 12, lineHeight: '16px', fontWeight: 700, whiteSpace: 'nowrap' }}>Today {f2(S)}</span>
        </span>
        <span />
      </div>
      <div style={{ position: 'relative', display: 'flex', flexDirection: 'column' }}>
        <LaneRow name="IV" sub="by strike · brighter is richer" tint={TINT.iv} track={ivTrack} boxes={ivBoxes} />
        <LaneRow name="SD" sub="the base · 0.25 to 2" tint={TINT.sd} track={sdTrack} boxes={sdBoxes} />
        <LaneRow name="Gamma Exposure" sub="walls · size is gamma" tint={TINT.w} track={gTrack} boxes={gBoxes} empty={`No gamma walls for ${e.label} yet.`} />
        <LaneRow name="Technicals" sub="averages · filled holds, hatched caps" tint={TINT.t} track={tTrack} boxes={tBoxes} empty="Support, resistance and RSI come with the technicals." />
        <LaneRow name="Move" sub="last week, this week, pace" tint={TINT.mv} track={mvTrack} boxes={mvBoxes} empty="The week’s moves come with the closes." />
        <LaneRow name="Held" sub={M.LH.has ? `sold for ${e.label}` : `nothing for ${e.label}`} tint={TINT.h} track={M.LH.has ? hnb('h', M.LH, 'Held') : <Quiet t={`Nothing sold for ${e.long} yet.`} />}
          boxes={lxBoxes(M.LH, null)} empty={`Nothing sold for ${e.label}.`} trackH={80} />
        <LaneRow name="+ New" sub="the sale above" tint={TINT.h} track={M.LN.has ? hnb('n', M.LN, 'New') : <Quiet t="Set a count above to try a sale." />}
          boxes={lxBoxes(M.LN, null)} empty="Nothing to sell yet. Set a count in the calculator." trackH={80} />
        <LaneRow name="= Both" sub="Held and New" tint={TINT.h} track={M.LB.has ? hnb('b', M.LB, 'Both') : <Quiet t="Nothing held or new." />}
          boxes={lxBoxes(M.LB, M.LH)} empty="Nothing yet." trackH={80} />
        <span aria-hidden="true" style={{ position: 'absolute', top: 0, bottom: 0, left: `calc(122px + (100% - 550px) * ${fr(S).toFixed(4)})`, borderLeft: '1.5px solid rgba(245,245,247,.85)', pointerEvents: 'none' }} />
      </div>
      <div style={{ display: 'grid', gridTemplateColumns: COLS, columnGap: 12, height: 22, borderTop: '1px solid rgba(255,255,255,.14)' }}>
        <span />
        <span className="tnum" style={{ position: 'relative' }}>
          {sc.ticks.map((v) => <span key={v} style={{ position: 'absolute', top: 4, left: at(fr(v), tx('$' + (+v.toFixed(2)))), fontSize: 12, lineHeight: '14px', color: MU }}>${+v.toFixed(2)}</span>)}
        </span>
        <span />
      </div>
      {rings.length > 0 && (
        <span style={{ display: 'flex', alignItems: 'center', gap: 6, paddingLeft: 122, paddingTop: 8, fontSize: 12, lineHeight: '16px', color: MT }}>
          <span style={{ width: 12, height: 12, borderRadius: '50%', border: '2px solid #F5F5F7' }} />
          Your {M.held.map((l) => `${l.n} ${l.put ? 'puts' : 'calls'} at ${+l.K.toFixed(2)}`).join(' and ')}, sold for {e.label}
        </span>
      )}
    </div>
  );
}

function PopBox({ pop, tx }: { pop: Pop; tx: string }) {
  return (
    <span role="tooltip" style={{ position: 'absolute', bottom: 'calc(100% + 6px)', left: '50%', transform: tx, width: 252, padding: '12px 14px', borderRadius: 14, background: 'rgba(28,28,30,.97)',
      boxShadow: 'inset 0 0 0 1px rgba(255,255,255,.12),0 12px 32px rgba(0,0,0,.55)', display: 'flex', flexDirection: 'column', gap: 8, pointerEvents: 'none', textAlign: 'left', whiteSpace: 'normal' }}>
      <span style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
        <span style={{ flex: 'none', width: 8, height: 8, borderRadius: '50%', background: pop.dc }} />
        <span style={{ fontSize: 13, lineHeight: '18px', color: MT }}>{pop.t}</span>
        <span style={{ marginLeft: 'auto', fontSize: 17, lineHeight: '22px', fontWeight: 600, color: K }}>{pop.v}</span>
      </span>
      <span style={{ display: 'flex', flexDirection: 'column', gap: 4, paddingTop: 8, borderTop: '1px solid rgba(255,255,255,.10)' }}>
        {pop.rows.map((r, i) => (
          <span key={i} style={{ display: 'flex', justifyContent: 'space-between', gap: 12, fontSize: 13, lineHeight: '18px' }}>
            <span style={{ color: MU }}>{r.l}</span><span style={{ fontWeight: 500, color: r.c ?? K, whiteSpace: 'nowrap' }}>{r.v}</span>
          </span>
        ))}
      </span>
      <span style={{ fontSize: 13, lineHeight: '18px', color: '#C7C7CC' }}>{pop.say}</span>
    </span>
  );
}

const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const md = (iso: string) => `${MON[+iso.slice(5, 7) - 1]} ${+iso.slice(8, 10)}`;
const shortD = (iso: string) => { const d = new Date(iso + 'T12:00:00Z'); return `${['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'][d.getUTCDay()]} ${md(iso)}`; };
const rsiWord = (r: number) => (r <= 30 ? 'oversold' : r >= 70 ? 'overbought' : 'neutral');
const wkSd = (r: number, iv: number) => (iv > 0 ? (Math.abs(Math.log(r)) / (iv * Math.sqrt(5 / 252))).toFixed(1) + ' SD' : '-');
