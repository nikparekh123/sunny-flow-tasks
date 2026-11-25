// Share average (handoff 2026-11-18: CHANGES Nov 16 "Share average · weekend cards and Search", the web part, and
// Nov 18 "Web Home in boxes"; SunnyShareAvg view="grid"). The weekend Home's section after Your book: one box per
// name whose average moved this week, biggest move first, side by side in a grid of columns at least 300 wide, 16
// apart; the server's quiet line for the names that held under them. Never on Positions.
// Each box: the header (logo, ticker, shares, "Down $8.13", "Up" or "Held" grey, this week), the summary
// (ahead of or behind the price, then what sold calls and puts did to what was paid), the Average and price chart (the
// price through the week's closes, the average straight from last Friday to now, the gap shaded grey, Paid dashed,
// Avg · Price · Paid tags), and What moved it · a share · since Sep 1 (two tiles, Calls sold and Puts sold, in the
// Performance legend colours; each figure signed, + pushed the average up). The focus look (handoff
// 2026-11-25-focus §2): no colour on the words, the shading a large fill so neutral grey.
// Data: the brief doc's card {type: 'shareAvg', names, note} (sunny-home doc.ts shareAvgSection, index.ts shareAvg):
// sh, paid, px, days and cl (the week's closes), s1 and s2 (the two steps a share at last Friday and now: calls sold,
// puts sold), w (the average last Friday and now: paid less the premium kept), wk (this week's change).
import { useEffect, useState, type CSSProperties } from 'react';
import type { J } from '../../lib/data';
import { monthDay } from '../../lib/clock';
import { C, clean, price, sgn } from '../../lib/format';
import { useWeb } from '../../lib/state';
import { BOX, BOX_PAD } from './Card';

/** The gap's shading and its legend: a large fill, so neutral grey at its own opacity (focus §2.4). */
const INK = C.ink, SUB = C.ink2, LINE = 'rgba(255,255,255,.08)', PXL = 'rgba(242,242,242,.5)';
const LG = ['Calls sold', 'Puts sold'];
const LC = ['#1C7840', '#3E6AE1'];
const HH = 160;

interface SA { t: string; name: string; sh: number; paid: number; px: number; days: string[]; cl: number[]; s2: number[]; w: [number, number]; wk: number }
const num = (v: unknown) => (Number.isFinite(Number(v)) ? Number(v) : 0);
function readName(x: J): SA | null {
  const w = Array.isArray(x?.w) ? x.w.map(num) : [];
  if (!x?.t || w.length < 2 || !(num(x.paid) > 0)) return null;
  const cl = (Array.isArray(x.cl) ? x.cl : []).map(num), days = (Array.isArray(x.days) ? x.days : []).map(String);
  const s2 = (Array.isArray(x.s2) ? x.s2 : []).map(num);
  return { t: String(x.t), name: String(x.name ?? x.t), sh: num(x.sh), paid: num(x.paid), px: num(x.px) || cl[cl.length - 1] || 0,
    days, cl, s2: LG.map((_, i) => s2[i] ?? 0), w: [w[0], w[1]], wk: num(x.wk) };
}

/** Together (handoff 2026-11-24 §3: "Share average is a grid per account"; Current Web: a header per account, its
    initial in a small disc and its name, then that account's grid). On one account, one grid. */
export default function ShareAvg({ card, payload }: { card: J; payload?: J }) {
  const names = ((card?.names ?? []) as J[]).map(readName).filter((x): x is SA => !!x);
  const note = clean(card?.note);
  if (!names.length && !note) return null;
  const sp: J[] = Array.isArray(payload?.split) ? payload.split : [];
  const groups = sp.length > 1 ? accountGroups(names, sp) : [{ k: 'all', ini: '', nm: '', names }];
  return (
    <div className="tnum" style={{ display: 'flex', flexDirection: 'column', gap: 22, minWidth: 0 }}>
      {groups.filter((g) => g.names.length).map((g) => (
        <div key={g.k} style={{ display: 'flex', flexDirection: 'column', gap: 12, minWidth: 0 }}>
          {g.nm && (
            <span style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 15, lineHeight: '20px', fontWeight: 500 }}>
              <span aria-hidden="true" style={{ flex: 'none', width: 22, height: 22, borderRadius: '50%', background: '#2A2A2A', boxShadow: 'inset 0 0 0 .5px rgba(255,255,255,.22)',
                display: 'inline-flex', alignItems: 'center', justifyContent: 'center', fontSize: 10.5, lineHeight: 1, fontWeight: 400 }}>{g.ini}</span>
              {g.nm}
            </span>
          )}
          <div role="region" aria-label={g.nm ? `Share averages, ${g.nm}` : 'Share averages'} style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill,minmax(300px,1fr))', gap: 16 }}>
            {g.names.map((b) => <Box key={b.t} b={b} />)}
          </div>
        </div>
      ))}
      {note && <span style={{ marginTop: -10, fontSize: 13, lineHeight: '18px', color: SUB, textWrap: 'pretty' } as CSSProperties}>{note}</span>}
    </div>
  );
}

/** Each account's names (payload.split[].names); a name both hold sits under both names together. */
function accountGroups(names: SA[], sp: J[]) {
  const sets = sp.map((s) => ({ id: String(s?.id ?? ''), nm: String(s?.name ?? s?.id ?? ''), ts: new Set<string>((s?.names ?? []).map(String)) }));
  const out = sets.map((x) => ({ k: x.id, ini: x.id, nm: x.nm, names: [] as SA[] }));
  const both = { k: 'both', ini: sets.map((x) => x.id).join(''), nm: sets.map((x) => x.nm).join(' and '), names: [] as SA[] };
  // A name neither holds now (every share sold this week): its own grid, no header.
  const rest = { k: 'rest', ini: '', nm: '', names: [] as SA[] };
  for (const b of names) {
    const at = sets.map((x, i) => (x.ts.has(b.t) ? i : -1)).filter((i) => i >= 0);
    (at.length === 1 ? out[at[0]] : at.length ? both : rest).names.push(b);
  }
  return [...out, both, rest];
}

function Box({ b }: { b: SA }) {
  const { privacy } = useWeb();
  const avg = Math.max(0, b.w[1]), gap = b.px - avg, pd0 = b.w[1] - b.paid, at = Math.abs(gap) < 0.005, ahead = gap > 0;
  const even = Math.abs(pd0) < 0.005, flat = Math.abs(b.wk) < 0.005;
  const wkV = flat ? 'Held' : `${b.wk < 0 ? 'Down' : 'Up'} ${price(b.wk)}`, wkC = flat ? SUB : INK;
  const shares = privacy ? '•,••• shares' : `${b.sh.toLocaleString('en-US')} shares`;
  const aria = `${b.t}, share average ${price(avg)}, ${flat ? 'held' : (b.wk < 0 ? 'down ' : 'up ') + price(b.wk)} this week, paid ${price(b.paid)}, price ${price(b.px)}`;
  return (
    <div role="group" aria-label={aria} style={{ ...BOX, minWidth: 0, padding: BOX_PAD, display: 'flex', flexDirection: 'column', gap: 16 }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
        <Logo t={b.t} />
        <span style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: 1 }}>
          <span style={{ fontSize: 20, lineHeight: '24px', fontWeight: 700, letterSpacing: '-.01em' }}>{b.t}</span>
          <span style={{ fontSize: 13, lineHeight: '16px', color: SUB, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{shares}</span>
        </span>
        <span style={{ flex: 'none', display: 'flex', flexDirection: 'column', alignItems: 'flex-end', gap: 1 }}>
          <span style={{ fontSize: 15, lineHeight: '20px', fontWeight: 500, color: wkC }}>{wkV}</span>
          <span style={{ fontSize: 12, lineHeight: '16px', color: SUB }}>this week</span>
        </span>
      </div>
      <p style={{ margin: 0, fontSize: 17, lineHeight: '24px', textWrap: 'pretty' } as CSSProperties}>
        {at ? <span style={{ fontWeight: 500 }}>At the price.</span>
          : <span style={{ fontWeight: 500 }}>{ahead ? 'Ahead of' : 'Behind'} the price by <span>{price(gap)}</span> a share.</span>}
        {even ? <span> Sold calls and puts left the {price(b.paid)} you paid where it was.</span>
          : <span> Sold calls and puts {pd0 > 0 ? 'added ' : 'took '}<span>{price(pd0)}</span>{pd0 > 0 ? ' to' : ' off'} the {price(b.paid)} you paid.</span>}
      </p>
      {b.cl.length > 0 && <Chart b={b} />}
      <div style={{ display: 'flex', flexDirection: 'column', gap: 12, paddingTop: 14, borderTop: `1px solid ${LINE}` }}>
        <span style={{ fontSize: 12, lineHeight: '14px', fontWeight: 400, color: SUB }}>What moved it · a share · since Sep 1</span>
        <div role="list" style={{ display: 'grid', gridTemplateColumns: 'repeat(2,minmax(0,1fr))', gap: '14px 10px' }}>
          {b.s2.map((v, j) => {
            const z = v === 0, tiny = !z && Math.abs(v) < 0.005;
            const val = z ? '-' : tiny ? 'under 1¢' : sgn(v, price(v));
            const a = `${LG[j]}, ${z ? 'nothing closed yet' : tiny ? 'under a cent' : v > 0 ? `pushed the average up ${price(v)} a share` : `took ${price(v)} a share off the average`}`;
            return (
              <div key={j} role="listitem" aria-label={a} style={{ display: 'flex', gap: 8, minWidth: 0 }}>
                <span style={{ flex: 'none', alignSelf: 'stretch', width: 4, borderRadius: 2, background: LC[j], opacity: z ? 0.35 : 1 }} />
                <span style={{ display: 'flex', flexDirection: 'column', gap: 4, minWidth: 0 }}>
                  <span style={{ fontSize: 13, lineHeight: '16px', color: SUB, textWrap: 'balance' } as CSSProperties}>{LG[j]}</span>
                  <span style={{ fontSize: 15, lineHeight: '18px', fontWeight: 500, color: z || tiny ? SUB : INK }}>{val}</span>
                </span>
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
}

/** The Average and price chart: the price through the week's closes, the average straight from last Friday to now,
    the gap shaded grey, Paid dashed, the tags on the right. */
function Chart({ b }: { b: SA }) {
  const pxs = b.cl, n = pxs.length, avg = b.w[1], vals = [...pxs, b.w[0], b.w[1], b.paid];
  let lo = Math.min(...vals), hi = Math.max(...vals);
  const pd = Math.max((hi - lo) * 0.14, hi * 0.004);
  lo = Math.max(0, lo - pd); hi += pd;
  const X = (i: number) => (n > 1 ? i / (n - 1) : 0.5), Y = (v: number) => (hi - v) / (hi - lo || 1);
  const P = (i: number, v: number) => `${(X(i) * 400).toFixed(1)} ${(Y(v) * 100).toFixed(2)}`, pc = (v: number) => `${(v * 100).toFixed(2)}%`;
  const pxD = pxs.map((v, i) => (i ? 'L' : 'M') + P(i, v)).join(' ');
  const avD = `M${P(0, b.w[0])} L${P(n - 1, b.w[1])}`;
  const aAt = (i: number) => b.w[0] + (b.w[1] - b.w[0]) * (i / ((n - 1) || 1));
  let shG = '', shR = '';
  const quad = (i0: number, A0: number, P0: number, i1: number, A1: number, P1: number, d: number) => {
    const q = `M${P(i0, A0)} L${P(i1, A1)} L${P(i1, P1)} L${P(i0, P0)} Z `;
    if (d > 0) shR += q; else shG += q;
  };
  for (let i = 0; i < n - 1; i++) {
    const a0 = aAt(i), a1 = aAt(i + 1), p0 = pxs[i], p1 = pxs[i + 1], d0 = a0 - p0, d1 = a1 - p1;
    if (d0 * d1 >= 0) quad(i, a0, p0, i + 1, a1, p1, d0 + d1);
    else { const f = d0 / (d0 - d1), im = i + f, vm = a0 + (a1 - a0) * f; quad(i, a0, p0, im, vm, vm, d0); quad(im, vm, vm, i + 1, a1, p1, d1); }
  }
  // Tags beside the chart, nudged apart so none overlap (20 px a tag), each joined to its line.
  const tg = [
    { k: 'a', y: Y(Math.max(0, avg)) * HH, n: Math.max(0, avg).toFixed(2), s: 'Avg', bg: INK, nc: '#171717', sc: '#474747', fw: 400, pad: '0 7px' },
    { k: 'x', y: Y(b.px) * HH, n: b.px.toFixed(2), s: 'Price', bg: 'rgba(255,255,255,.12)', nc: INK, sc: SUB, fw: 400, pad: '0 7px' },
    { k: 'p', y: Y(b.paid) * HH, n: b.paid.toFixed(2), s: 'Paid', bg: 'transparent', nc: SUB, sc: SUB, fw: 500, pad: '0 3px' },
  ].sort((a, z) => a.y - z.y).map((x) => ({ ...x, c: Math.max(9, Math.min(HH - 9, x.y)) }));
  tg.forEach((x, i) => { if (i && x.c < tg[i - 1].c + 20) x.c = tg[i - 1].c + 20; });
  for (let i = tg.length - 1; i >= 0; i--) { const mx = i === tg.length - 1 ? HH - 9 : tg[i + 1].c - 20; if (tg[i].c > mx) tg[i].c = mx; }
  const d0 = b.days[0], d1 = b.days[n - 1];
  const aria = `${b.t} share average by Friday, ${b.w[0].toFixed(2)}${d0 ? ' on ' + monthDay(d0) : ''} to ${Math.max(0, avg).toFixed(2)}${d1 ? ' on ' + monthDay(d1) : ''}; paid ${b.paid.toFixed(2)}, price ${b.px.toFixed(2)}. The average is ${avg < b.px ? 'under' : 'over'} the price.`;
  const dot = (x: number, y: number, s: number, bd: string, bg: string): CSSProperties =>
    ({ position: 'absolute', left: pc(x), top: pc(y), width: s, height: s, transform: 'translate(-50%,-50%)', boxSizing: 'border-box', borderRadius: '50%', border: bd, background: bg });
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
      <div role="img" aria-label={aria} style={{ position: 'relative', height: HH }}>
        <div style={{ position: 'absolute', left: 0, top: 0, bottom: 0, right: 96 }}>
          <svg viewBox="0 0 400 100" preserveAspectRatio="none" aria-hidden="true" style={{ position: 'absolute', inset: 0, width: '100%', height: '100%', overflow: 'visible' }}>
            {shG && <path d={shG} style={{ fill: C.green, fillOpacity: 0.18, stroke: 'none' }} />}
            {shR && <path d={shR} style={{ fill: C.red, fillOpacity: 0.18, stroke: 'none' }} />}
            <path d={pxD} style={{ fill: 'none', stroke: PXL, strokeWidth: 1.5, strokeLinejoin: 'round', strokeLinecap: 'round', vectorEffect: 'non-scaling-stroke' }} />
            <path d={avD} style={{ fill: 'none', stroke: INK, strokeWidth: 2.5, strokeLinejoin: 'round', strokeLinecap: 'round', vectorEffect: 'non-scaling-stroke' }} />
          </svg>
          <span aria-hidden="true" style={{ position: 'absolute', left: 0, right: 0, top: pc(Y(b.paid)), borderTop: `1px dashed ${SUB}`, opacity: 0.6 }} />
          <span aria-hidden="true" style={dot(X(n - 1), Y(b.px), 6, 'none', PXL)} />
          <span aria-hidden="true" style={dot(X(0), Y(b.w[0]), 8, `1.5px solid ${INK}`, '#171717')} />
          <span aria-hidden="true" style={dot(X(n - 1), Y(Math.max(0, avg)), 12, `2.5px solid ${INK}`, '#171717')} />
        </div>
        <div aria-hidden="true" style={{ position: 'absolute', top: 0, bottom: 0, right: 0, width: 96 }}>
          <svg width="8" height="100%" style={{ position: 'absolute', left: 0, top: 0, height: '100%', overflow: 'visible' }}>
            <path d={tg.map((x) => `M0 ${x.y.toFixed(1)} L8 ${x.c.toFixed(1)}`).join(' ')} style={{ fill: 'none', stroke: SUB, strokeWidth: 1 }} />
          </svg>
          {tg.map((x) => (
            <span key={x.k} style={{ position: 'absolute', left: 9, top: x.c - 9, height: 18, boxSizing: 'border-box', display: 'flex', alignItems: 'center', gap: 4,
              padding: x.pad, borderRadius: 999, background: x.bg, whiteSpace: 'nowrap' }}>
              <span style={{ fontSize: 12.5, lineHeight: '16px', fontWeight: x.fw, color: x.nc }}>{x.n}</span>
              <span style={{ fontSize: 10.5, lineHeight: '14px', fontWeight: 500, color: x.sc }}>{x.s}</span>
            </span>
          ))}
        </div>
      </div>
      <div aria-hidden="true" style={{ position: 'relative', height: 16, marginRight: 96 }}>
        {d0 && <span style={{ position: 'absolute', top: 0, left: 0, fontSize: 11, lineHeight: '16px', color: SUB, whiteSpace: 'nowrap' }}>{monthDay(d0)}</span>}
        {n > 1 && d1 && <span style={{ position: 'absolute', top: 0, right: 0, fontSize: 11, lineHeight: '16px', color: SUB, whiteSpace: 'nowrap' }}>{monthDay(d1)}</span>}
      </div>
      <span aria-hidden="true" style={{ display: 'flex', flexWrap: 'wrap', gap: '4px 14px', fontSize: 12, lineHeight: '16px', color: SUB }}>
        <span style={{ display: 'flex', alignItems: 'center', gap: 6 }}><span style={{ width: 10, height: 10, borderRadius: 3, background: C.green, opacity: 0.45 }} />Under the price, ahead</span>
        <span style={{ display: 'flex', alignItems: 'center', gap: 6 }}><span style={{ width: 10, height: 10, borderRadius: 3, background: C.red, opacity: 0.45 }} />Over it, behind</span>
        <span style={{ display: 'flex', alignItems: 'center', gap: 6 }}><span style={{ width: 14, borderTop: `1px dashed ${SUB}` }} />Paid</span>
      </span>
    </div>
  );
}

/** A company logo (public/logos/TICKER.png) at 74% of a 32 px white disc; the ticker when there is no logo. */
function Logo({ t }: { t: string }) {
  const [bad, setBad] = useState(false);
  useEffect(() => setBad(false), [t]);
  return (
    <span aria-hidden="true" style={{ flex: 'none', width: 32, height: 32, borderRadius: '50%', background: '#FAFAFA', boxShadow: 'inset 0 0 0 .5px rgba(0,0,0,.08)',
      display: 'flex', alignItems: 'center', justifyContent: 'center', overflow: 'hidden' }}>
      {bad
        ? <span style={{ fontSize: 9, lineHeight: '10px', fontWeight: 400, color: '#212121' }}>{t.slice(0, 4)}</span>
        : <img src={`/logos/${encodeURIComponent(t)}.png`} alt="" draggable={false} onError={() => setBad(true)}
            style={{ width: '74%', height: '74%', objectFit: 'contain', pointerEvents: 'none' }} />}
    </span>
  );
}
